package com.margelo.nitro.visionkitcamera

import com.margelo.nitro.camera.HybridCameraOutputSpec

class HybridVKFaceDetectorFactory : HybridVKFaceDetectorFactorySpec() {
  override fun createFaceDetectorOutput(options: VKFaceDetectorOutputOptions): HybridCameraOutputSpec =
    HybridVKFaceDetectorOutput(options)
}
