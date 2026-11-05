import type { HybridObject } from "react-native-nitro-modules";
import type { CameraOutput } from "react-native-vision-camera";

// Every type is prefixed with `VK`. Under `useFrameworks: "dynamic"`, nitrogen's
// quoted includes ("Point.hpp", "CameraPosition.hpp", …) can resolve to
// VisionCamera's headers of the same name. That clash is why the monorepo
// patches react-native-vision-camera-face-detector.

/** Pixel rect in the upright frame, top-left origin. */
export interface VKFaceBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface VKFacePoint {
  x: number;
  y: number;
}

/** Subject's left/right, like ML Kit. iOS provides eyes, nose base and mouth only. */
export interface VKFaceLandmarks {
  leftEye?: VKFacePoint;
  rightEye?: VKFacePoint;
  noseBase?: VKFacePoint;
  mouthLeft?: VKFacePoint;
  mouthRight?: VKFacePoint;
  mouthBottom?: VKFacePoint;
  leftEar?: VKFacePoint;
  rightEar?: VKFacePoint;
  leftCheek?: VKFacePoint;
  rightCheek?: VKFacePoint;
}

export interface VKFace {
  bounds: VKFaceBounds;
  /** Degrees, ML Kit's Euler Z sign convention. */
  rollAngle: number;
  /** Degrees, ML Kit's Euler Y. */
  yawAngle: number;
  /** Degrees, ML Kit's Euler X. */
  pitchAngle: number;
  /** Upright frame size that `bounds` is relative to. */
  frameWidth: number;
  frameHeight: number;
  landmarks?: VKFaceLandmarks;
  /** Android only. */
  trackingId?: number;
  /** Android only. */
  smilingProbability?: number;
  /** Android only. */
  leftEyeOpenProbability?: number;
  /** Android only. */
  rightEyeOpenProbability?: number;
}

export type VKPerformanceMode = "fast" | "accurate";
export type VKCameraFacing = "front" | "back";
export type VKOutputResolution = "preview" | "full";

export interface VKFaceDetectorOutputOptions {
  /** Android: ML Kit performance mode. iOS: "accurate" also runs landmark refinement. @default 'fast' */
  performanceMode?: VKPerformanceMode;
  runLandmarks?: boolean;
  /** Android only. Accepted on iOS for compatibility. */
  runContours?: boolean;
  /** Android only. Accepted on iOS for compatibility. */
  runClassifications?: boolean;
  /** Head width / frame width. @default 0.15 */
  minFaceSize?: number;
  /** Android only. */
  trackingEnabled?: boolean;
  /** Fallback when the connection doesn't report a position. @default 'front' */
  cameraFacing?: VKCameraFacing;
  /** @default 'preview' */
  outputResolution?: VKOutputResolution;
  onFacesDetected: (faces: VKFace[]) => void;
  onError: (error: Error) => void;
}

export interface VKFaceDetectorFactory extends HybridObject<{ ios: "swift"; android: "kotlin" }> {
  createFaceDetectorOutput(options: VKFaceDetectorOutputOptions): CameraOutput;
}
