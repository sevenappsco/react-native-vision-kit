import { NitroModules } from "react-native-nitro-modules";
import type { CameraOutput } from "react-native-vision-camera";
import type {
  VKFace,
  VKFaceDetectorFactory,
  VKFaceDetectorOutputOptions,
} from "./specs/VKFaceDetectorFactory.nitro";

export type {
  VKFace as Face,
  VKFaceBounds as Bounds,
  VKFaceLandmarks as Landmarks,
  VKFacePoint as Point,
  VKFaceDetectorOutputOptions as FaceDetectorOutputOptions,
  VKPerformanceMode as PerformanceMode,
} from "./specs/VKFaceDetectorFactory.nitro";

let factory: VKFaceDetectorFactory | undefined;

function getFactory(): VKFaceDetectorFactory {
  factory ??= NitroModules.createHybridObject<VKFaceDetectorFactory>("VKFaceDetectorFactory");
  return factory;
}

/**
 * Create a VisionCamera 5 `CameraOutput` that detects faces on every frame
 * (it drops frames while one is still processing). Pass it in `<Camera outputs={[...]} />`.
 *
 * Source-compatible with `react-native-vision-camera-face-detector`'s
 * `createFaceDetectorOutput`. `bounds` are in upright frame pixels, relative to
 * `frameWidth`×`frameHeight`.
 */
export function createFaceDetectorOutput(options: VKFaceDetectorOutputOptions): CameraOutput {
  return getFactory().createFaceDetectorOutput(options);
}

export type { VKFace };
