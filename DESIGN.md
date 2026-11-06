# react-native-vision-kit — Design

Replace the Google ML Kit libraries used by the SevenApps React Native apps with
packages that use **Apple frameworks on iOS** and keep **ML Kit on Android**.

Goal: zero Google ML Kit pods on iOS. That removes the duplicate Google
libraries (GTMSessionFetcher 3.5 next to Firebase SPM's 5.3, GoogleUtilities,
PromisesObjC, …) and the missing arm64-simulator slice.

| Replaces | App | New import |
| --- | --- | --- |
| `@infinitered/react-native-mlkit-text-recognition` (+ patch) | aitranslate | `@sevenappsco/vision-kit/text` |
| `fast-mlkit-translate-text` | aitranslate | `@sevenappsco/vision-kit/translate` |
| `@react-native-ml-kit/face-detection` | faceai | `@sevenappsco/vision-kit/face` |
| `react-native-vision-camera-face-detector` 2.1.0 (+ patch) | skincare | `@sevenappsco/vision-kit-camera` |

Package names are placeholders (see *Open decisions*).

---

## 1. Packaging: two packages, not one

The preferred design was one package with subpath exports. Text, translation,
and still-image faces follow it: one **Expo module**, `@sevenappsco/vision-kit`,
with `/text`, `/translate` and `/face`.

The **VisionCamera 5 face output has to be a Nitro module**, so it ships as a
second package, `@sevenappsco/vision-kit-camera`. The reasons are concrete:

1. **VisionCamera 5 accepts only Nitro objects as outputs.** `<Camera outputs={[…]}>`
   takes `CameraOutput`, a Nitro `HybridObject` (`HybridCameraOutputSpec`).
   Natively, VisionCamera checks that the object conforms to
   `NativeCameraOutput`:
   - iOS: provide an `AVCaptureOutput`, plus `configure(config:)` and resolution negotiation.
   - Android: `createUseCase(...)` returns a CameraX `UseCase`.

   An Expo module cannot return a Nitro hybrid object. Frame processors don't
   help either: worklets run on another JS runtime where Expo module functions
   don't exist, and skincare deliberately uses a worklet-free output. Only
   nitrogen-generated code can subclass `HybridCameraOutputSpec`, as the
   existing face-detector library does.
2. **Different native dependency graph.** The camera output links
   `VisionCamera` + `NitroModules` on iOS. On Android it also needs CMake and
   prefab against `react-native-vision-camera`. faceai has no VisionCamera, and
   aitranslate doesn't need a face output. One podspec or Gradle module would
   force VisionCamera, Nitro and a C++ build onto every consumer. That could be
   avoided only with conditional sources in the podspec and Gradle file, which
   is fragile.
3. **Different autolinking.** Expo modules are linked through
   `expo-module.config.json`. Nitro modules are linked through
   `nitro.json` → nitrogen `+autolinking.rb`/`.gradle`/`.cmake` and an RN
   `ReactPackage`. Keeping them separate avoids double-linking problems.

Repo layout (pnpm workspace):

```
packages/vision-kit/          Expo module (Swift / Kotlin)
packages/vision-kit-camera/   Nitro module (Swift / Kotlin + nitrogen C++)
example/                      Expo SDK 58 app, mirrors the monorepo build settings
```

## 2. Minimum versions

| | Package minimum | Notes |
| --- | --- | --- |
| iOS | **16.4** (same as aitranslate / skincare) | Translation needs iOS 18; it is gated at runtime (`isTranslationSupported()`), not raised for the whole package. |
| Android | minSdk 26 (apps use 31) | ML Kit. |
| Expo / RN | SDK 58 / RN 0.88.1, New Architecture | |
| Nitro | `react-native-nitro-modules` ^0.37.1, `react-native-vision-camera` ^5.2.4 | camera package only |

## 3. `@sevenappsco/vision-kit/text`: OCR

### API (same shape as infinitered's, plus the monorepo patch's `script` argument)

```ts
type OcrScript = "latin" | "chinese" | "japanese" | "korean" | "devanagari"
               | "cyrillic" | "arabic" | "thai";            // last 3: iOS only
interface Rect { left: number; top: number; right: number; bottom: number }
interface TextElement { text: string; frame: Rect; recognizedLanguages: string[] }
interface TextLine extends TextElement { elements: TextElement[] }
interface Block extends TextElement { lines: TextLine[] }
interface Text { text: string; blocks: Block[] }

recognizeText(uri: string, script?: OcrScript /* = "latin" */,
              options?: { languages?: string[]; level?: "accurate" | "fast" }): Promise<Text>
getSupportedScripts(): OcrScript[]          // per-platform; replaces getOfflineOcrScript's hardcoded table
isScriptSupported(script: OcrScript): boolean
```

Frames are in pixels of the **upright** image (EXIF orientation applied), with
the origin at the top left, as ML Kit reports them. Verified: on the Latin sample the
first-line frame is {72,77,719,132} on iOS 18.6 and {71,79,717,127} on Android. `uri` accepts `file://`,
absolute paths, and on Android also `content://`.

### iOS: Vision `VNRecognizeTextRequest`

- `recognitionLevel = .accurate`, `usesLanguageCorrection = true`, and
  `recognitionLanguages` taken from the script (below), or from
  `options.languages`.
- The `CGImage` and its `CGImagePropertyOrientation` go to
  `VNImageRequestHandler`. Vision's normalized lower-left boxes are converted
  to upright pixel rects.
- **Blocks.** Vision returns *lines*, not paragraphs. aitranslate translates
  blocks, so the module groups lines into blocks. A line joins a block when the
  vertical gap is at most 0.6× the line height, its height is within about 0.6–1.67×
  of the previous line's, and the two overlap horizontally. Words
  (`elements`) come from `VNRecognizedText.boundingBox(for:)` on whitespace
  ranges. CJK lines produce a single element. ML Kit's own blocks aren't
  consistent either (Chinese 2 blocks vs Japanese 3 on identically laid-out
  samples), so expect block boundaries to differ by platform. On iOS 26.5 the
  heuristic merges the first two Latin sample lines; iOS 18.6 and ML Kit don't.
- `VNRecognizeTextRequest` (iOS 13+) is used on every iOS version.
  - iOS 18's Swift `RecognizeTextRequest` uses the same model and the same
    language list (checked on the iOS 26 SDK), so it adds nothing here.
  - iOS 26's `RecognizeDocumentsRequest` returns real paragraphs. It is a
    possible later upgrade for iOS 26+ only. It wasn't adopted because it is
    tuned for documents rather than camera scenes, and results would differ
    across iOS versions.

Script → Vision languages:

| script | `recognitionLanguages` |
| --- | --- |
| latin | en-US, fr-FR, it-IT, de-DE, es-ES, pt-BR, vi-VT, tr-TR, id-ID, cs-CZ, da-DK, nl-NL, nb-NO, ms-MY, pl-PL, ro-RO, sv-SE |
| chinese | zh-Hans, zh-Hant, en-US |
| japanese | ja-JP, en-US |
| korean | ko-KR, en-US |
| cyrillic | ru-RU, uk-UA, en-US |
| arabic | ar-SA, en-US |
| thai | th-TH, en-US |
| devanagari | **not supported**: rejects with `ERR_SCRIPT_UNSUPPORTED` |

### Android: ML Kit Text Recognition v2

The same five recognizers the monorepo patch adds (`text-recognition`,
`-chinese`, `-japanese`, `-korean`, `-devanagari` 16.0.1, bundled models).
`cyrillic`/`arabic`/`thai` reject with `ERR_SCRIPT_UNSUPPORTED`. ML Kit's Latin
model does read Cyrillic and Vietnamese diacritics poorly.

### Accuracy / coverage differences vs ML Kit

The full Vision language list was queried on the macOS 26 SDK (accurate):
`en fr it de es pt zh-Hans zh-Hant yue ko ja ru uk th vi ar ars tr id cs da nl no nn nb ms pl ro sv`.
The `fast` level is Latin-only: en fr it de es pt.

- **Lost on iOS: Devanagari (Hindi, Marathi).** Verified: the iOS 18.6 and 26.5 simulators both report no Devanagari language. Apple Vision has no Devanagari
  model on any iOS version. aitranslate already has an "online OCR only" path
  for scripts without offline OCR, so on iOS `hi`/`mr` should go through the
  backend. `getOfflineOcrScript` should consult `isScriptSupported`.
- **Gained on iOS:** Russian/Ukrainian (Cyrillic), Arabic, Thai, and
  Cantonese, which ML Kit has no on-device model for. aitranslate can enable
  offline camera OCR for `ru`, `uk`, `ar`, `th` on iOS. Belarusian,
  Bulgarian, Macedonian and Persian get reasonable but not language-tuned results.
- Latin languages missing from Vision's list (af, sq, ca, hr, et, …) still
  read well. Vision's Latin model is not language-exclusive, but language
  correction is tuned to the listed languages. Expect slightly worse
  diacritics for hr/sl/sk/lt/lv than ML Kit.
- Vision `accurate` is noticeably better than ML Kit on curved or angled text
  and small print. It is slower: roughly 150–400 ms per photo on an A15
  (Apple's figure; not measured here). The live viewfinder in aitranslate
  already throttles, which is fine.
- Block grouping is heuristic on iOS, so block boundaries differ from ML
  Kit's. Line and word text should be equal or better.

## 4. `@sevenappsco/vision-kit/translate`: offline translation

### Apple Translation constraints (verified against the iOS 26.5 SDK swiftinterface)

| API | Available |
| --- | --- |
| `LanguageAvailability().supportedLanguages`, `.status(from:to:)` → `installed / supported / unsupported` | iOS 18.0 |
| `TranslationSession`, **obtainable only through SwiftUI `.translationTask(...)`** | iOS 18.0 |
| `session.prepareTranslation()`: shows the **system download sheet** and waits for it | iOS 18.0 (SwiftUI-hosted session only) |
| `TranslationSession(installedSource:target:)`: programmatic, no UI, **cannot download** (`canRequestDownloads == false`) | iOS 26.0 |
| `session.isReady`, `cancel()`, `TranslationError.notInstalled` | iOS 26.0 |
| `Strategy.highFidelity / .lowLatency` | iOS 26.4 |
| Delete a language | **no API**. The user does it in *Settings → Apps → Translate → Downloaded Languages*. |
| List downloaded languages | **no API**. It is derived from pair status. |
| Simulator | Not functional: model downloads don't work, and `supportedLanguages` may be empty. Translation needs a device. |

What these constraints mean in practice:

- **Downloads are user-mediated.** The app can't download silently in the
  background; it can only *ask*, which shows a system sheet. The user can
  decline, which resolves `false`.
- **Downloads are per pair.** Apple downloads the languages a pair needs.
  There is no "download Spanish" without a target. The default target is the
  user's preferred language.
- **English is not built in on iOS.** ML Kit ships English inside the SDK.
  Apple's English assets are usually present when the device language is
  English, but that isn't guaranteed. aitranslate's
  `BUILT_IN_LANGUAGE_CODES = {"en"}` must be Android-only.

### Options considered

| Option | iOS min | Translate path | Download path | Verdict |
| --- | --- | --- | --- | --- |
| **A. 16.4 package, translation gated at 18 (chosen)** | 16.4 (feature: 18) | 18–25: hidden SwiftUI host. 26+: `TranslationSession(installedSource:)`, no UI. | Hidden SwiftUI host + `prepareTranslation()` → system sheet (18+) | Works with today's deployment target. iOS 16/17 users keep online (backend) translation, which aitranslate already supports. |
| B. Raise apps to iOS 18 | 18 | as A | as A | Simpler product story, but drops iOS 16.4–17 users (product decision). |
| C. Raise to iOS 26, programmatic only | 26 | programmatic | still needs the SwiftUI host | Unacceptable reach for little gain: downloads still need SwiftUI. |
| D. Keep ML Kit Translate on iOS | 16.4 | ML Kit | ML Kit | Defeats the goal (GoogleMLKit pods). |

**Hidden SwiftUI host.** A 1×1, alpha 0.01 `UIHostingController` is added as
a child of the **top-most presented** view controller (root →
`presentedViewController` chain, skipping ones being dismissed), and moved on
every request when that changes. Apple's sheet is presented from there: under a
view controller that is already presenting something (an RN `<Modal>`, a modal
route) UIKit drops or misplaces the sheet. 0.1.1 attached to the root VC, and
`downloadLanguagePair` from a modal hung forever on device (fixed in 0.1.2). It holds a
`.translationTask(configuration)` modifier. Each request sets a new
`Configuration` (or calls `invalidate()`) and awaits the closure. The closure
runs `prepareTranslation()` or `translations(from:)` and resumes a stored
continuation. Requests are serialized, matching aitranslate's `runSerialized`.
The session is never used outside its closure, as Apple requires.

Watchdogs, so a request never hangs: the `.translationTask` closure must fire
within 8 s (`ERR_TRANSLATION_SESSION_TIMEOUT`), and a download whose sheet
hasn't appeared above the host after 5 s is rejected
(`ERR_DOWNLOAD_SHEET_NOT_SHOWN`). Once the sheet is up there is no timeout: it
waits for the user. Verified on the iOS 18.6 simulator from no modal, an RN
`<Modal>`, a modal over a modal and under an alert (the example's
`ModalSheetRepro`), and the watchdog by forcing 0.1.1's root attach.

### API (close to fast-mlkit-translate-text, but with BCP-47 codes instead of English names)

```ts
type ModelStatus = "downloaded" | "downloadable" | "unsupported";
isTranslationSupported(): boolean                      // iOS ≥ 18, Android always
getSupportedLanguages(): Promise<string[]>             // BCP-47 base codes ("es", "zh", …)
getPairStatus(source, target): Promise<ModelStatus>
isLanguageDownloaded(code): Promise<boolean>
getDownloadedLanguageModels(): Promise<string[]>       // iOS: derived from pair status vs. a pivot
downloadLanguageModel(code, opts?: { pairedWith?: string }): Promise<boolean>
  // Android: silent download (Wi-Fi not required). iOS: system sheet for (code, pairedWith ?? "en"); false if declined.
downloadLanguagePair(source, target): Promise<boolean> // preferred on iOS: one sheet for both languages
deleteLanguageModel(code): Promise<boolean>            // iOS: rejects ERR_UNSUPPORTED (no API)
canDeleteLanguageModels: boolean                       // false on iOS → hide "delete" UI
prepare({ source, target, downloadIfNeeded? }): Promise<void>
translate(text, { source, target }): Promise<string>
translateBatch(texts, { source, target }): Promise<string[]> // one session for N camera blocks
```

Error codes: `ERR_TRANSLATION_UNAVAILABLE` (iOS < 18),
`ERR_LANGUAGE_UNSUPPORTED`, `ERR_MODEL_NOT_DOWNLOADED`, `ERR_UNSUPPORTED`,
`ERR_TRANSLATION_FAILED`. A declined download resolves `false` rather than
throwing: dismissing Apple's sheet throws a generic "Unable to Translate"
error, observed on iOS 18.6. `ERR_MODEL_NOT_DOWNLOADED` replaces
the ML Kit "model files not found" string that aitranslate self-heals.

### Mapping aitranslate's "language pack missing" UX

| Today (ML Kit) | iOS (Apple) | Android |
| --- | --- | --- |
| `downloadModel(code)` with an in-app spinner, silent download | `downloadLanguagePair(src, tgt)` → system sheet "Download languages?" with system progress. The promise resolves after the download, or `false` if dismissed. The in-app spinner should only show *after* the sheet is accepted (the sheet blocks anyway). | unchanged |
| `deleteModel(code)` in the language-pack manager | not possible → hide (`canDeleteLanguageModels`), or show "Manage in Settings" text | unchanged |
| `getDownloadedModels()` list | approximate (pair-derived); shown as is | unchanged |
| `en` treated as built-in | not built in: check `getPairStatus` | unchanged |
| iOS < 18 | `isTranslationSupported() === false` → offline toggle hidden, backend only | n/a |

### Language coverage vs ML Kit's 59

ML Kit Translate: 59 languages, any-to-any via English (verified on the
Android emulator).

Apple Translation, as `LanguageAvailability().supportedLanguages` reports it
(measured in the example app):

| iOS | Base languages |
| --- | --- |
| 18.6 | **19**: ar, de, en, es, fr, hi, id, it, ja, ko, nl, pl, pt, ru, th, tr, uk, vi, zh (+ en-GB, zh-TW) |
| 26.5 | **22**: the iOS 18 set + **da, nb, sv** (+ regional variants: en-AU/CA/IN/…, es-MX/US, fr-CA, de-CH, it-CH, pt-PT, zh-HK/TW) |

So **37 (iOS 26) to 40 (iOS 18) of aitranslate's 59 offline languages have no
Apple model**. Missing on every version: af, be, bg, bn, ca, cs, cy, el, eo, et,
fa, fi, ga, gl, gu, he, hr, ht, hu, is, ka, kn, lt, lv, mk, mr, ms, mt, ro, sk,
sl, sq, sw, ta, te, tl, ur. Also missing on iOS 18–25: da, no, sv.
`isSupportedLanguage` must become a runtime check on iOS, and those languages
fall back to the backend. **This is the largest product regression of the
migration and needs a product decision** (see *Open decisions*).

### Android

`com.google.mlkit:translate:17.0.3` with `RemoteModelManager` for
list/download/delete. No language-id dependency, since aitranslate doesn't use
`identify`. The `Translator` client is cached per pair and closed on change.

## 5. `@sevenappsco/vision-kit/face`: still-image faces (faceai)

```ts
detect(uri: string, options?: {
  performanceMode?: "fast" | "accurate"; landmarkMode?: "none" | "all";
  contourMode?: "none" | "all"; classificationMode?: "none" | "all";
  minFaceSize?: number;
}): Promise<Face[]>
// Face = { frame: {left, top, width, height}, rotationX, rotationY, rotationZ,
//          landmarks?, contours?, smilingProbability?, leftEyeOpenProbability?, rightEyeOpenProbability? }
```

The shape is that of `@react-native-ml-kit/face-detection`, so faceai only
changes the import (`import FaceDetection from "@sevenappsco/vision-kit/face"`;
`FaceDetection.detect(...)`).

- **iOS:** `VNDetectFaceRectanglesRequest` (rev 3: roll, yaw, pitch) and, when
  landmarks or contours are requested, `VNDetectFaceLandmarksRequest`.
  Angles are in degrees with **ML Kit's sign convention**. Verified on the
  same images: a copy rotated 20° counter-clockwise gives roll +18.1° on
  Vision and +20.4° on ML Kit. The clockwise copy gives −21.1° and −20.0°.
  - Landmarks: leftEye/rightEye (pupils), noseBase, mouthLeft/Right/Bottom.
    **Ears and cheeks are not available** from Vision.
  - Contours: face, eyes, eyebrows, nose bridge, lips (Vision regions, with
    point counts different from ML Kit's).
  - Left and right follow ML Kit's convention, which is the same as Vision's
    region names. On the sample portrait both put `leftEye` on the image's
    left (ML Kit x=327, Vision x=331). This was cross-checked because the
    first guess (a swap) was wrong.
  - **Classification (smiling / eyes open) is not available** on iOS; those
    fields are undefined.
- **Android:** ML Kit `face-detection` 16.1.7, unchanged.

## 6. `@sevenappsco/vision-kit-camera`: VisionCamera 5 face output (skincare)

```ts
createFaceDetectorOutput(options: {
  performanceMode?: "fast" | "accurate"; runLandmarks?: boolean;
  runContours?: boolean; runClassifications?: boolean;  // accepted for compat; iOS ignores contours/classification
  minFaceSize?: number; cameraFacing?: "front" | "back";
  outputResolution?: "preview" | "full";
  onFacesDetected: (faces: Face[]) => void; onError: (error: Error) => void;
}): CameraOutput
// Face = { bounds: {x, y, width, height}, rollAngle, yawAngle, pitchAngle,
//          frameWidth, frameHeight, landmarks? }
```

The call is source-compatible with skincare's `createFaceDetectorOutput(...)`.
`Face` is a plain Nitro **struct**, not a HybridObject, so JS gets plain
objects. skincare already copies the fields out.

**Coordinates:** pixels of the upright (rotated) frame. `frameWidth` and
`frameHeight` are the upright dimensions, so `bounds` and the frame size are
self-consistent. That is what skincare's ratio logic needs. Upright coordinates
match the old library's `autoMode: false` on Android.

- **iOS:** a Swift `HybridFaceDetectorOutput: HybridCameraOutputSpec, NativeCameraOutput`.
  - Wraps an `AVCaptureVideoDataOutput` with preview-sized buffers (iOS 17+),
    `alwaysDiscardsLateVideoFrames`, and a busy flag (drop frames while one is
    processing).
  - Each buffer goes through `VNSequenceRequestHandler` with
    `VNDetectFaceRectanglesRequest` (+ landmarks), using an orientation
    derived from VisionCamera's `outputOrientation` and the camera position.
- **Android:** a Kotlin `NativeCameraOutput`, `createUseCase` →
  CameraX `ImageAnalysis` → ML Kit face detection. Adapted from the MIT
  `react-native-vision-camera-face-detector` (attributed).
- **Header-name collisions.** The monorepo patch exists because, with
  `useFrameworks: "dynamic"`, nitrogen's quoted `#include "CameraPosition.hpp"`
  / `"MirrorMode.hpp"` / `"Point.hpp"` resolve to VisionCamera's headers of the
  same name. This package prefixes every Nitro type (`VKFace`,
  `VKFaceBounds`, `VKFaceDetectorOutputOptions`, …) and reuses no
  VisionCamera type names, so it needs no patch.

## 7. Verification (done in this repo)

The example app (`example/`) has a self-checking **Checks** screen and a
**Face camera** screen. It uses bundled sample images: generated multi-script
text images and a public-domain NASA portrait, plus copies rotated ±20°. It
mirrors the monorepo build settings: dynamic frameworks, RN from source, iOS
16.4, compileSdk 37, Kotlin 2.4.0. It was driven through the T3 device tools.

| | iOS 26.5 sim (arm64) | iOS 18.6 sim (arm64) | Android emu (API 36, arm64) |
| --- | --- | --- | --- |
| Builds; no Google pods (`Podfile.lock` has 0 MLKit/Google/GTM/Promises) | ✅ | ✅ same binary | ✅ |
| OCR latin/chinese/japanese/korean/cyrillic text matches | ✅ | ✅ | ✅ (latin, CJK, devanagari) |
| Unsupported script → `ERR_SCRIPT_UNSUPPORTED` | ✅ devanagari | ✅ devanagari | ✅ cyrillic |
| Still-image face: box, roll sign (±20° images) | ✅ | ✅ | ✅ |
| Still-image face: landmark *geometry* | ⚠️ collapsed on the simulator's CPU path; correct with the same API on macOS Vision | ⚠️ same | ✅ |
| Translation: language list | ✅ 22 | ✅ 19 | ✅ 59 |
| Translation: SwiftUI host attaches, `.translationTask` hands out a session, re-triggers | ✅ | ✅ (the iOS 18–25 path) | n/a |
| Translation: system download sheet presented from the host; dismissal resumes the queue | ✅ (call returns) | ✅ sheet shown, Done → resumes | n/a |
| Translation: real download + translate | ❌ simulator says "not supported on simulated devices" | ❌ same | ✅ en→es downloaded; "¡Buenos días \| ¿Dónde está la estación de tren?" |
| Not-downloaded / delete errors | ✅ `ERR_UNSUPPORTED` for delete | ✅ | ✅ `ERR_MODEL_NOT_DOWNLOADED` |
| VisionCamera 5 face `CameraOutput` | ❌ no simulator camera | ❌ | ✅ attaches, ~30 callbacks/s (no face in the emulator feed) |

**Still needs a physical iPhone:** Apple Translation download and translate,
the iOS camera face output, and Vision landmark geometry. **Still needs a face
in front of the camera:** Android face output detection results.

### Build issues found along the way (relevant to the monorepo migration)

1. **`react-native-nitro-modules` 0.37.2 breaks iOS builds** with
   `buildReactNativeFromSource` (`jserrorhandler/ErrorUtils.h` not found while
   building the `cxxreact` module, from the new `cpp/views/ReactNativeCore.hpp`).
   The monorepo resolves 0.37.1 today. Keep its override from floating to 0.37.2
   (`^0.37.1` allows it).
2. **VisionCamera 5.2.4's generated Kotlin doesn't compile with Kotlin 2.4**:
   "Check for instance is always 'false'" in
   `HybridPreviewViewManager.kt`/`HybridFrameRendererViewManager.kt`.
   `patches/react-native-vision-camera@5.2.4.patch` here extends the
   monorepo's (iOS-only) patch with a cast-through-`Any` fix. The monorepo pins
   Kotlin 2.4.0 too, so check whether its Android builds already hit this.
3. The camera package's Android `build.gradle` must not declare its own AGP
   `buildscript` classpath. If it does, it compiles with Kotlin 2.2 against
   Nitro classes built with 2.4.
4. Vision face requests need CPU compute on the simulator ("Could not create
   inference context"). This is handled with `#if targetEnvironment(simulator)`.

## Decisions

- **iOS minimum:** stays 16.4. Offline translation runs on iOS 18+; 16.4–17
  users get online (backend) translation. *(decided 2026-11-06)*
- **Devanagari OCR on iOS:** backend only for hi/mr. *(decided)*
- **iOS language packs:** Apple's system download sheet, no in-app delete;
  aitranslate's language-pack screen gets iOS-specific behaviour. *(decided)*
- **Distribution:** public GitHub repo `sevenappsco/react-native-vision-kit`, published to npm. *(decided)*
- **iOS translation coverage:** languages Apple doesn't support fall back to the
  backend on iOS. ML Kit stays off iOS: it ships only through CocoaPods, which
  conflicts with the Expo 58 + SPM move. *(decided)*
- **Paragraphs on iOS 26:** adopt `RecognizeDocumentsRequest` for block
  grouping on iOS 26+, keeping the heuristic below 26. *(decided, not yet implemented)*
