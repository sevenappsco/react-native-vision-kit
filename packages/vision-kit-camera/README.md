# @sevenapps/vision-kit-camera

Face detector `CameraOutput` for [VisionCamera 5](https://github.com/mrousavy/react-native-vision-camera).
Apple Vision on iOS (no Google pods), ML Kit face detection on Android.
A drop-in replacement for `createFaceDetectorOutput` from
`react-native-vision-camera-face-detector`.

```ts
import { createFaceDetectorOutput, type Face } from "@sevenapps/vision-kit-camera";
```

Peer dependencies: `react-native-vision-camera` >= 5.2, `react-native-nitro-modules` >= 0.37.1.

With Kotlin 2.4, VisionCamera 5.2.4's generated Kotlin needs a small fix
(see `patches/react-native-vision-camera@5.2.4.patch` in the repo).

See the [repo README](https://github.com/sevenappsco/react-native-vision-kit) for the full API and migration notes.

## License

MIT. The Android output is adapted from
[react-native-vision-camera-face-detector](https://github.com/luicfrr/react-native-vision-camera-face-detector) (MIT).
