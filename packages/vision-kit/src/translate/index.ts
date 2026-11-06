import { requireNativeModule } from "expo";

/**
 * - `downloaded`: both languages are on device; `translate` works offline.
 * - `downloadable`: supported, but needs a download (iOS: user-approved system sheet).
 * - `unsupported`: this platform can't translate the pair.
 */
export type PairStatus = "downloaded" | "downloadable" | "unsupported";

export interface TranslateOptions {
  /** BCP-47 language code, e.g. "en", "es", "zh", "zh-TW". */
  source: string;
  target: string;
  /**
   * Download missing models first. On iOS this shows Apple's download sheet.
   * @default false
   */
  downloadIfNeeded?: boolean;
}

interface NativeTranslateModule {
  readonly isSupported: boolean;
  readonly canDeleteLanguageModels: boolean;
  readonly canDownloadSilently: boolean;
  getSupportedLanguages(): Promise<string[]>;
  getPairStatus(source: string, target: string): Promise<PairStatus>;
  getDownloadedLanguageModels(): Promise<string[]>;
  isLanguageDownloaded(code: string): Promise<boolean>;
  downloadLanguagePair(source: string, target: string): Promise<boolean>;
  downloadLanguageModel?(code: string): Promise<boolean>;
  deleteLanguageModel(code: string): Promise<boolean>;
  translateBatch(texts: string[], source: string, target: string, downloadIfNeeded: boolean): Promise<string[]>;
}

const native = requireNativeModule<NativeTranslateModule>("VisionKitTranslate");

/** Error codes thrown by this module (`error.code`). */
export const TranslateErrorCode = {
  /** iOS < 18: Apple Translation isn't available. */
  Unavailable: "ERR_TRANSLATION_UNAVAILABLE",
  LanguageUnsupported: "ERR_LANGUAGE_UNSUPPORTED",
  /** Models missing. Replaces ML Kit's "model files not found" message. */
  ModelNotDownloaded: "ERR_MODEL_NOT_DOWNLOADED",
  /** iOS: deleting languages has no API. */
  Unsupported: "ERR_UNSUPPORTED",
  Failed: "ERR_TRANSLATION_FAILED",
  /**
   * iOS: Apple's download sheet couldn't be presented (for example another
   * sheet or alert was mid-presentation). Nothing was downloaded; retry later.
   */
  DownloadSheetNotShown: "ERR_DOWNLOAD_SHEET_NOT_SHOWN",
  /** iOS: Apple Translation didn't hand out a session in time. Retry later. */
  SessionTimeout: "ERR_TRANSLATION_SESSION_TIMEOUT",
  /** iOS: the app has no key window to host the Translation session. */
  NoWindow: "ERR_TRANSLATION_NO_WINDOW",
} as const;

/** iOS ≥ 18 or Android. When false, use online translation. */
export const isTranslationSupported: boolean = native.isSupported;

/**
 * False on iOS: Apple has no deletion API (users manage languages in
 * Settings → Apps → Translate). Hide "delete language pack" UI when false.
 */
export const canDeleteLanguageModels: boolean = native.canDeleteLanguageModels;

/**
 * False on iOS: downloads go through a system sheet the user must accept.
 * Show your own progress UI only after the promise starts to make progress.
 */
export const canDownloadSilently: boolean = native.canDownloadSilently;

function assertSupported() {
  if (!isTranslationSupported) {
    const error = new Error("Offline translation requires iOS 18 or newer") as Error & { code: string };
    error.code = TranslateErrorCode.Unavailable;
    throw error;
  }
}

/** BCP-47 codes this platform can translate between (iOS: ~20, Android: 59). */
export async function getSupportedLanguages(): Promise<string[]> {
  assertSupported();
  return native.getSupportedLanguages();
}

export async function getPairStatus(source: string, target: string): Promise<PairStatus> {
  assertSupported();
  return native.getPairStatus(source, target);
}

/** iOS: derived from pair status (Apple has no listing API). */
export async function getDownloadedLanguageModels(): Promise<string[]> {
  assertSupported();
  return native.getDownloadedLanguageModels();
}

export async function isLanguageDownloaded(code: string): Promise<boolean> {
  assertSupported();
  return native.isLanguageDownloaded(code);
}

/**
 * Download the models for a pair. iOS shows one system sheet for both languages
 * and resolves `false` if the user dismisses it. Android downloads silently.
 *
 * iOS presents the sheet over the top-most screen, so it works from inside
 * modals. If the sheet can't be presented it rejects with
 * `ERR_DOWNLOAD_SHEET_NOT_SHOWN` (or `ERR_TRANSLATION_SESSION_TIMEOUT`) within
 * a few seconds instead of hanging. Once the sheet is up, the promise waits for
 * the user.
 */
export async function downloadLanguagePair(source: string, target: string): Promise<boolean> {
  assertSupported();
  return native.downloadLanguagePair(source, target);
}

/**
 * Download one language (fast-mlkit-translate-text compatible).
 * iOS can only download pairs, so this downloads `(code, pairedWith)`, with `pairedWith` defaulting to "en".
 */
export async function downloadLanguageModel(
  code: string,
  options: { pairedWith?: string } = {},
): Promise<boolean> {
  assertSupported();
  if (native.downloadLanguageModel) return native.downloadLanguageModel(code);
  const pairedWith = options.pairedWith ?? (code.startsWith("en") ? "es" : "en");
  return native.downloadLanguagePair(code, pairedWith);
}

/** Android only. iOS rejects with `ERR_UNSUPPORTED`; check {@link canDeleteLanguageModels}. */
export async function deleteLanguageModel(code: string): Promise<boolean> {
  assertSupported();
  return native.deleteLanguageModel(code);
}

/** Ensure a pair is ready. Rejects `ERR_MODEL_NOT_DOWNLOADED` if missing and `downloadIfNeeded` is false. */
export async function prepare(options: TranslateOptions): Promise<void> {
  const status = await getPairStatus(options.source, options.target);
  if (status === "downloaded") return;
  if (status === "unsupported") {
    throw Object.assign(new Error(`Unsupported pair ${options.source} → ${options.target}`), {
      code: TranslateErrorCode.LanguageUnsupported,
    });
  }
  if (!options.downloadIfNeeded) {
    throw Object.assign(new Error(`Models for ${options.source} → ${options.target} are not downloaded`), {
      code: TranslateErrorCode.ModelNotDownloaded,
    });
  }
  const ok = await downloadLanguagePair(options.source, options.target);
  if (!ok) {
    throw Object.assign(new Error("Download was declined"), { code: TranslateErrorCode.ModelNotDownloaded });
  }
}

export async function translate(text: string, options: TranslateOptions): Promise<string> {
  const [result] = await translateBatch([text], options);
  return result ?? "";
}

/** Translate many strings in one session (e.g. every OCR block of a photo). */
export async function translateBatch(texts: string[], options: TranslateOptions): Promise<string[]> {
  assertSupported();
  return native.translateBatch(texts, options.source, options.target, options.downloadIfNeeded ?? false);
}
