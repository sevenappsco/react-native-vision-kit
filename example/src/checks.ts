import { Asset } from "expo-asset";
import { Platform } from "react-native";
import FaceDetection from "@sevenapps/vision-kit/face";
import {
  getSupportedRecognitionLanguages,
  getSupportedScripts,
  recognizeText,
  type OcrScript,
} from "@sevenapps/vision-kit/text";
import * as Translate from "@sevenapps/vision-kit/translate";
import { requireNativeModule } from "expo";

export type CheckResult = {
  name: string;
  status: "pass" | "fail" | "info";
  detail: string;
  ms?: number;
};

const SAMPLES = {
  latin: require("../assets/samples/text-latin.png"),
  chinese: require("../assets/samples/text-chinese.png"),
  japanese: require("../assets/samples/text-japanese.png"),
  korean: require("../assets/samples/text-korean.png"),
  devanagari: require("../assets/samples/text-devanagari.png"),
  cyrillic: require("../assets/samples/text-cyrillic.png"),
  face: require("../assets/samples/face.jpg"),
  faceCcw: require("../assets/samples/face-ccw20.jpg"),
  faceCw: require("../assets/samples/face-cw20.jpg"),
} as const;

export async function sampleUri(key: keyof typeof SAMPLES): Promise<string> {
  const asset = Asset.fromModule(SAMPLES[key]);
  await asset.downloadAsync();
  if (!asset.localUri) throw new Error(`No local URI for ${key}`);
  return asset.localUri;
}

const OCR_EXPECTATIONS: { script: OcrScript; sample: keyof typeof SAMPLES; expect: string }[] = [
  { script: "latin", sample: "latin", expect: "Welcome" },
  { script: "chinese", sample: "chinese", expect: "欢迎" },
  { script: "japanese", sample: "japanese", expect: "東京" },
  { script: "korean", sample: "korean", expect: "서울" },
  { script: "devanagari", sample: "devanagari", expect: "नमस्ते" },
  { script: "cyrillic", sample: "cyrillic", expect: "Добро" },
];

async function timed<T>(fn: () => Promise<T>): Promise<[T, number]> {
  const start = Date.now();
  const value = await fn();
  return [value, Date.now() - start];
}

export async function runChecks(onResult: (r: CheckResult) => void): Promise<void> {
  const push = (r: CheckResult) => {
    console.log(`[vision-kit-check] ${r.status.toUpperCase()} ${r.name}: ${r.detail}${r.ms != null ? ` (${r.ms} ms)` : ""}`);
    onResult(r);
  };

  // ---- Text ----
  const scripts = getSupportedScripts();
  push({ name: "text.getSupportedScripts", status: "info", detail: scripts.join(", ") });
  if (Platform.OS === "ios") {
    push({
      name: "text.visionLanguages",
      status: "info",
      detail: getSupportedRecognitionLanguages().join(" "),
    });
  }

  for (const { script, sample, expect } of OCR_EXPECTATIONS) {
    const uri = await sampleUri(sample);
    const supported = scripts.includes(script);
    try {
      const [result, ms] = await timed(() => recognizeText(uri, script));
      const ok = result.text.includes(expect);
      push({
        name: `text.recognize(${script})`,
        status: supported && ok ? "pass" : "fail",
        detail: `${result.blocks.length} blocks, ${result.blocks.reduce((n, b) => n + b.lines.length, 0)} lines: ${JSON.stringify(result.text).slice(0, 90)}`,
        ms,
      });
      if (script === "latin") {
        const b0 = result.blocks[0];
        push({
          name: "text.blockGrouping(latin)",
          status: "info",
          detail: `ML Kit gives 1+1+1 on this sample; got ${result.blocks.map((b) => b.lines.length).join("+")}; frame0=${JSON.stringify(b0?.frame)}; words(line0)=${b0?.lines[0]?.elements.map((e) => e.text).join("|")}`,
        });
      }
    } catch (e: any) {
      push({
        name: `text.recognize(${script})`,
        status: !supported && e?.code === "ERR_SCRIPT_UNSUPPORTED" ? "pass" : "fail",
        detail: `${e?.code}: ${e?.message}`.slice(0, 140),
      });
    }
  }

  // ---- Face (still image) ----
  try {
    const uri = await sampleUri("face");
    const [faces, ms] = await timed(() =>
      FaceDetection.detect(uri, { landmarkMode: "all", contourMode: "all" }),
    );
    const f = faces[0];
    const le = f?.landmarks?.leftEye?.position;
    const re = f?.landmarks?.rightEye?.position;
    push({
      name: "face.detect(face.jpg)",
      status: faces.length === 1 ? "pass" : "fail",
      detail: `${faces.length} face(s); frame=${JSON.stringify(f?.frame && roundObj(f.frame))} rotX/Y/Z=${[f?.rotationX, f?.rotationY, f?.rotationZ].map(round).join("/")} landmarks=${Object.keys(f?.landmarks ?? {}).join(",")} contours=${Object.keys(f?.contours ?? {}).length}`,
      ms,
    });
    push({
      // ML Kit (Android) puts `leftEye` on the image's left for this photo; iOS must match.
      name: "face.leftEyeOnImageLeft (ML Kit convention)",
      status: le && re && le.x < re.x ? "pass" : "fail",
      detail: `leftEye=${pt(le)} rightEye=${pt(re)} nose=${pt(f?.landmarks?.noseBase?.position)} mouthL=${pt(f?.landmarks?.mouthLeft?.position)} mouthR=${pt(f?.landmarks?.mouthRight?.position)} | contour centroids: ${Object.entries(f?.contours ?? {}).map(([k, c]) => `${k}=${pt(centroid(c?.points ?? []))}/${c?.points.length}`).join(" ")}`,
    });
    const [ccw] = await FaceDetection.detect(await sampleUri("faceCcw"));
    const [cw] = await FaceDetection.detect(await sampleUri("faceCw"));
    push({
      name: "face.rollSign (image rotated CCW → +rotationZ)",
      status: ccw && cw && ccw.rotationZ > 5 && cw.rotationZ < -5 ? "pass" : "fail",
      detail: `ccw20 → ${round(ccw?.rotationZ)}°, cw20 → ${round(cw?.rotationZ)}°, upright → ${round(f?.rotationZ)}°`,
    });
  } catch (e: any) {
    push({ name: "face.detect", status: "fail", detail: `${e?.code}: ${e?.message}` });
  }

  // ---- Translate ----
  push({
    name: "translate.flags",
    status: "info",
    detail: `supported=${Translate.isTranslationSupported} canDelete=${Translate.canDeleteLanguageModels} silent=${Translate.canDownloadSilently}`,
  });
  if (!Translate.isTranslationSupported) return;
  try {
    const [languages, ms] = await timed(() => Translate.getSupportedLanguages());
    push({
      name: "translate.getSupportedLanguages",
      status: languages.length > 0 ? "pass" : "fail",
      detail: `${languages.length}: ${languages.join(" ")}`,
      ms,
    });
    const status = await Translate.getPairStatus("en", "es");
    push({ name: "translate.getPairStatus(en→es)", status: "info", detail: status });
    const [downloaded, ms2] = await timed(() => Translate.getDownloadedLanguageModels());
    push({ name: "translate.getDownloadedLanguageModels", status: "info", detail: downloaded.join(" ") || "(none)", ms: ms2 });
    if (Platform.OS === "ios") {
      // Exercises the hidden SwiftUI `.translationTask` host (iOS 18–25 path; downloads on every version).
      const native = requireNativeModule<{ debugHostRoundTrip(s: string, t: string, prepare: boolean): Promise<string> }>("VisionKitTranslate");
      for (const prepare of [false, true]) {
        const name = `translate.swiftUIHost(${prepare ? "session + prepareTranslation" : "session only"})`;
        try {
          const [report, msHost] = await timed(() =>
            Promise.race([
              native.debugHostRoundTrip("en", "es", prepare),
              new Promise<string>((_, reject) => setTimeout(() => reject(new Error("timeout after 15s")), 15000)),
            ]),
          );
          push({ name, status: report.startsWith("session received") ? "pass" : "fail", detail: report, ms: msHost });
        } catch (e: any) {
          push({ name, status: "fail", detail: `${e?.code}: ${e?.message}`.slice(0, 160) });
          break; // host queue is blocked behind the hung job
        }
      }
    }
    if (status === "unsupported") {
      push({ name: "translate.pairUnsupported", status: "info", detail: "Apple reports every pair unsupported on the simulator; translation needs a device." });
    } else if (status === "downloaded") {
      const [out, ms3] = await timed(() =>
        Translate.translateBatch(["Good morning", "Where is the train station?"], { source: "en", target: "es" }),
      );
      push({ name: "translate.translateBatch(en→es)", status: out.every((s) => s.length > 0) ? "pass" : "fail", detail: out.join(" | "), ms: ms3 });
    } else {
      try {
        await Translate.translate("Good morning", { source: "en", target: "es" });
        push({ name: "translate.notDownloadedError", status: "fail", detail: "translate resolved without models" });
      } catch (e: any) {
        push({
          name: "translate.notDownloadedError",
          status: e?.code === Translate.TranslateErrorCode.ModelNotDownloaded ? "pass" : "fail",
          detail: `${e?.code}: ${e?.message}`.slice(0, 140),
        });
      }
    }
    if (!Translate.canDeleteLanguageModels) {
      try {
        await Translate.deleteLanguageModel("es");
        push({ name: "translate.deleteUnsupported", status: "fail", detail: "resolved" });
      } catch (e: any) {
        push({ name: "translate.deleteUnsupported", status: e?.code === "ERR_UNSUPPORTED" ? "pass" : "fail", detail: String(e?.code) });
      }
    }
  } catch (e: any) {
    push({ name: "translate", status: "fail", detail: `${e?.code}: ${e?.message}`.slice(0, 200) });
  }
}

function round(n: number | undefined) {
  return n == null ? "–" : Math.round(n * 10) / 10;
}

function roundObj<T extends object>(o: T) {
  return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === "number" ? Math.round(v) : v]));
}

function pt(p?: { x: number; y: number }) {
  return p ? `(${Math.round(p.x)},${Math.round(p.y)})` : "–";
}

function centroid(points: { x: number; y: number }[]) {
  if (points.length === 0) return undefined;
  return { x: points.reduce((a, p) => a + p.x, 0) / points.length, y: points.reduce((a, p) => a + p.y, 0) / points.length };
}
