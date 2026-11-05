import { requireNativeModule } from "expo";

export interface Point {
  x: number;
  y: number;
}

/** Pixel rect in the upright image, top-left origin. */
export interface Frame {
  width: number;
  height: number;
  top: number;
  left: number;
}

export interface Landmark {
  position: Point;
}

export interface Contour {
  points: Point[];
}

/** iOS (Vision) provides leftEye, rightEye, noseBase, mouthLeft, mouthRight, mouthBottom: no ears or cheeks. */
export type LandmarkType =
  | "leftEar"
  | "rightEar"
  | "leftEye"
  | "rightEye"
  | "noseBase"
  | "leftCheek"
  | "rightCheek"
  | "mouthLeft"
  | "mouthRight"
  | "mouthBottom";

export type ContourType =
  | "face"
  | "leftEye"
  | "rightEye"
  | "leftCheek"
  | "rightCheek"
  | "noseBottom"
  | "noseBridge"
  | "leftEyebrowTop"
  | "rightEyebrowTop"
  | "leftEyebrowBottom"
  | "rightEyebrowBottom"
  | "upperLipTop"
  | "lowerLipTop"
  | "upperLipBottom"
  | "lowerLipBottom";

export interface Face {
  frame: Frame;
  /** Pitch in degrees (ML Kit's Euler X). */
  rotationX: number;
  /** Yaw in degrees (ML Kit's Euler Y). */
  rotationY: number;
  /** Roll in degrees (ML Kit's Euler Z, positive = counter-clockwise in the image). */
  rotationZ: number;
  landmarks?: Partial<Record<LandmarkType, Landmark>>;
  contours?: Partial<Record<ContourType, Contour>>;
  /** Android only. */
  smilingProbability?: number;
  /** Android only. */
  leftEyeOpenProbability?: number;
  /** Android only. */
  rightEyeOpenProbability?: number;
  /** Android only. */
  trackingID?: number;
}

export interface FaceDetectionOptions {
  /** Android: ML Kit performance mode. iOS: ignored (Vision has a single model). @default 'fast' */
  performanceMode?: "fast" | "accurate";
  /** @default 'none' */
  landmarkMode?: "none" | "all";
  /** @default 'none' */
  contourMode?: "none" | "all";
  /** Android only (Vision has no smile / eyes-open classifier). @default 'none' */
  classificationMode?: "none" | "all";
  /** Smallest face, as head width / image width. @default 0.1 */
  minFaceSize?: number;
  /** Android only. @default false */
  trackingEnabled?: boolean;
}

interface NativeFaceModule {
  detect(uri: string, options: FaceDetectionOptions): Promise<Face[]>;
}

const native = requireNativeModule<NativeFaceModule>("VisionKitFace");

/** Detect faces in a still image. Drop-in for `@react-native-ml-kit/face-detection`. */
export function detect(uri: string, options: FaceDetectionOptions = {}): Promise<Face[]> {
  return native.detect(uri, options);
}

const FaceDetection = { detect };
export default FaceDetection;
