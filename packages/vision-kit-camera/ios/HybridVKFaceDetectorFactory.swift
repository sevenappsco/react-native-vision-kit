import NitroModules
import VisionCamera

final class HybridVKFaceDetectorFactory: HybridVKFaceDetectorFactorySpec {
  func createFaceDetectorOutput(options: VKFaceDetectorOutputOptions) throws -> any HybridCameraOutputSpec {
    return HybridVKFaceDetectorOutput(options)
  }
}
