import { requireNativeModule } from "expo";

/** Pixel rect in the upright image (EXIF orientation applied), top-left origin. */
export interface Rect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface TextElement {
  text: string;
  frame: Rect;
  recognizedLanguages: string[];
}

export interface TextLine {
  text: string;
  frame: Rect;
  recognizedLanguages: string[];
  elements: TextElement[];
}

export interface Block {
  text: string;
  frame: Rect;
  recognizedLanguages: string[];
  lines: TextLine[];
}

export interface Text {
  text: string;
  blocks: Block[];
}

/**
 * Script to recognize.
 * - iOS (Apple Vision): latin, chinese, japanese, korean, cyrillic, arabic, thai. **No devanagari.**
 * - Android (ML Kit): latin, chinese, japanese, korean, devanagari.
 *
 * Use {@link isScriptSupported} rather than hardcoding a per-platform table.
 */
export type OcrScript =
  | "latin"
  | "chinese"
  | "japanese"
  | "korean"
  | "devanagari"
  | "cyrillic"
  | "arabic"
  | "thai";

/** @deprecated Alias kept for drop-in compatibility with the patched infinitered module. */
export type TextRecognitionScript = OcrScript;

export interface RecognizeTextOptions {
  /** iOS only: explicit Vision recognition languages (e.g. ["de-DE"]); overrides the script mapping. */
  languages?: string[];
  /** iOS only: "accurate" (default) or "fast" (Latin only). */
  level?: "accurate" | "fast";
  /** iOS only: Vision language correction (default true). */
  languageCorrection?: boolean;
}

interface NativeTextModule {
  recognizeText(uri: string, script: OcrScript, options: RecognizeTextOptions): Promise<Text>;
  getSupportedScripts(): OcrScript[];
  getSupportedRecognitionLanguages(level?: "accurate" | "fast"): string[];
}

const native = requireNativeModule<NativeTextModule>("VisionKitText");

/**
 * Recognize text in a still image. Signature-compatible with
 * `@infinitered/react-native-mlkit-text-recognition`'s (patched) `recognizeText(uri, script)`.
 *
 * Rejects with code `ERR_SCRIPT_UNSUPPORTED` when the platform has no model for `script`.
 */
export async function recognizeText(
  uri: string,
  script: OcrScript = "latin",
  options: RecognizeTextOptions = {},
): Promise<Text> {
  return native.recognizeText(uri, script, options);
}

let supportedScripts: OcrScript[] | undefined;

/** Scripts this platform can recognize on-device. */
export function getSupportedScripts(): OcrScript[] {
  supportedScripts ??= native.getSupportedScripts();
  return supportedScripts;
}

export function isScriptSupported(script: OcrScript): boolean {
  return getSupportedScripts().includes(script);
}

/** iOS: the raw Vision language list (for diagnostics). Android: empty. */
export function getSupportedRecognitionLanguages(level: "accurate" | "fast" = "accurate"): string[] {
  return native.getSupportedRecognitionLanguages(level);
}
