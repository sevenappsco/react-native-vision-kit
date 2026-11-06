# react-native-vision-kit

On-device OCR, offline translation and face detection for the SevenApps React Native apps.
**Apple frameworks on iOS** (Vision, Translation): zero Google ML Kit pods, arm64-simulator friendly.
**Google ML Kit on Android.**

| Package | Kind | Replaces |
| --- | --- | --- |
| `@sevenappsco/vision-kit/text` | Expo module | `@infinitered/react-native-mlkit-text-recognition` |
| `@sevenappsco/vision-kit/translate` | Expo module | `fast-mlkit-translate-text` |
| `@sevenappsco/vision-kit/face` | Expo module | `@react-native-ml-kit/face-detection` |
| `@sevenappsco/vision-kit-camera` | Nitro module (VisionCamera 5 `CameraOutput`) | `react-native-vision-camera-face-detector` |

See [DESIGN.md](./DESIGN.md) for the design, platform differences and open decisions.

## Layout

```
packages/vision-kit/          Expo module (Swift / Kotlin)
packages/vision-kit-camera/   Nitro module (Swift / Kotlin + nitrogen)
example/                      Expo SDK 58 app (Checks + Face camera screens)
```

## Develop

```sh
pnpm install
pnpm --filter @sevenappsco/vision-kit-camera specs   # re-run nitrogen after editing src/specs/*.nitro.ts
cd example && npx expo prebuild && npx expo run:ios   # or run:android
```

The example mirrors the monorepo build settings: `useFrameworks: "dynamic"`,
`buildReactNativeFromSource: true`, iOS 16.4, compileSdk 37 / minSdk 31.

## Migration cheatsheet

```ts
// aitranslate: OCR
- import { recognizeText, type Block } from "@infinitered/react-native-mlkit-text-recognition";
+ import { recognizeText, isScriptSupported, type Block } from "@sevenappsco/vision-kit/text";
// getOfflineOcrScript(): return null when !isScriptSupported(script)  (iOS has no devanagari; gains cyrillic/arabic/thai)

// aitranslate: offline translation (BCP-47 codes instead of "English"/"Spanish" names)
- await FastTranslator.prepare({ source, target, downloadIfNeeded }); await FastTranslator.translate(text)
+ await translate(text, { source: "en", target: "es", downloadIfNeeded })
// isBuiltInLanguage("en") must be Android-only; hide delete UI when !canDeleteLanguageModels;
// "model files not found" self-heal → catch error.code === "ERR_MODEL_NOT_DOWNLOADED".

// skincare: VisionCamera 5 output (same call)
- import { createFaceDetectorOutput, type Face } from "react-native-vision-camera-face-detector";
+ import { createFaceDetectorOutput, type Face } from "@sevenappsco/vision-kit-camera";
// and drop patches/react-native-vision-camera-face-detector@2.1.0.patch

// faceai
- import FaceDetection from "@react-native-ml-kit/face-detection";
+ import FaceDetection from "@sevenappsco/vision-kit/face";
```

## License

MIT. The Android camera output is adapted from
[react-native-vision-camera-face-detector](https://github.com/luicfrr/react-native-vision-camera-face-detector) (MIT).
The sample portrait is a public-domain NASA photo (Suni Williams, 2018).
