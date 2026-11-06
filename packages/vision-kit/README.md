# @sevenappsco/vision-kit

On-device OCR, offline translation and still-image face detection for Expo apps.
Apple Vision and Translation on iOS (no Google pods), Google ML Kit on Android.

```ts
import { recognizeText } from "@sevenappsco/vision-kit/text";         // replaces @infinitered/react-native-mlkit-text-recognition
import * as Translate from "@sevenappsco/vision-kit/translate";        // replaces fast-mlkit-translate-text
import FaceDetection from "@sevenappsco/vision-kit/face";              // replaces @react-native-ml-kit/face-detection
```

- iOS 16.4+. Offline translation needs iOS 18+ (`isTranslationSupported`).
- iOS translation covers Apple's languages only (19 on iOS 18, 22 on iOS 26);
  check `getPairStatus` and fall back to an online service for the rest.
- iOS downloads show Apple's system sheet; languages can't be deleted from the app.

See the [repo README](https://github.com/sevenappsco/react-native-vision-kit) and
[DESIGN.md](https://github.com/sevenappsco/react-native-vision-kit/blob/main/DESIGN.md)
for the full API, platform differences and migration notes.

## License

MIT
