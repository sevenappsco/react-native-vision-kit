// Adapted from react-native-vision-camera-face-detector (MIT, © luicfrr):
// https://github.com/luicfrr/react-native-vision-camera-face-detector
package com.margelo.nitro.visionkitcamera

import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import com.margelo.nitro.camera.CameraOrientation
import com.margelo.nitro.camera.HybridCameraOutputSpec
import com.margelo.nitro.camera.MediaType
import com.margelo.nitro.camera.MirrorMode
import com.margelo.nitro.camera.extensions.converters.toSize
import com.margelo.nitro.camera.extensions.surfaceRotation
import com.margelo.nitro.camera.public.NativeCameraOutput
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * VisionCamera 5 `CameraOutput`: CameraX `ImageAnalysis` → ML Kit face detection.
 * Coordinates are in the upright (rotated) frame; `frameWidth`/`frameHeight` are that size.
 */
class HybridVKFaceDetectorOutput(
  private val options: VKFaceDetectorOutputOptions,
) : HybridCameraOutputSpec(), ImageAnalysis.Analyzer, NativeCameraOutput {
  override val mediaType: MediaType = MediaType.VIDEO
  override var mirrorMode: MirrorMode = MirrorMode.AUTO
  override var outputOrientation: CameraOrientation = CameraOrientation.UP
    set(value) {
      field = value
      imageAnalysis?.targetRotation = value.surfaceRotation
    }
  override val currentResolution: com.margelo.nitro.camera.Size?
    get() = imageAnalysis?.resolutionInfo?.resolution?.toSize()

  private val detector = FaceDetection.getClient(
    FaceDetectorOptions.Builder()
      .setPerformanceMode(
        if (options.performanceMode == VKPerformanceMode.ACCURATE) FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE
        else FaceDetectorOptions.PERFORMANCE_MODE_FAST
      )
      .setLandmarkMode(
        if (options.runLandmarks == true) FaceDetectorOptions.LANDMARK_MODE_ALL
        else FaceDetectorOptions.LANDMARK_MODE_NONE
      )
      .setContourMode(
        if (options.runContours == true) FaceDetectorOptions.CONTOUR_MODE_ALL
        else FaceDetectorOptions.CONTOUR_MODE_NONE
      )
      .setClassificationMode(
        if (options.runClassifications == true) FaceDetectorOptions.CLASSIFICATION_MODE_ALL
        else FaceDetectorOptions.CLASSIFICATION_MODE_NONE
      )
      .setMinFaceSize((options.minFaceSize ?: 0.15).toFloat())
      .apply { if (options.trackingEnabled == true) enableTracking() }
      .build()
  )
  private val isBusy = AtomicBoolean(false)
  private val executor = Executors.newSingleThreadExecutor()
  private var imageAnalysis: ImageAnalysis? = null

  override fun createUseCase(
    mirrorMode: MirrorMode,
    config: NativeCameraOutput.Config,
  ): NativeCameraOutput.PreparedUseCase {
    val strategy =
      if (options.outputResolution == VKOutputResolution.FULL) ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY
      else ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
    val analysis = ImageAnalysis.Builder()
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
      .setTargetRotation(outputOrientation.surfaceRotation)
      .setOutputImageRotationEnabled(false)
      .setResolutionSelector(
        ResolutionSelector.Builder()
          .setResolutionStrategy(strategy)
          .setAllowedResolutionMode(ResolutionSelector.PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE)
          .build()
      )
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .build()
    return NativeCameraOutput.PreparedUseCase(analysis) {
      imageAnalysis = analysis
      this.mirrorMode = mirrorMode
      analysis.setAnalyzer(executor, this)
    }
  }

  @OptIn(ExperimentalGetImage::class)
  override fun analyze(imageProxy: ImageProxy) {
    if (!isBusy.compareAndSet(false, true)) {
      imageProxy.close()
      return
    }
    try {
      val mediaImage = imageProxy.image ?: throw Error("ImageProxy has no Image")
      val rotation = imageProxy.imageInfo.rotationDegrees
      val input = InputImage.fromMediaImage(mediaImage, rotation)
      val swaps = rotation == 90 || rotation == 270
      val frameWidth = (if (swaps) input.height else input.width).toDouble()
      val frameHeight = (if (swaps) input.width else input.height).toDouble()

      detector.process(input)
        .addOnSuccessListener { faces ->
          options.onFacesDetected(
            faces.sortedByDescending { it.boundingBox.width() * it.boundingBox.height() }
              .map { it.toVKFace(frameWidth, frameHeight) }
              .toTypedArray()
          )
        }
        .addOnFailureListener { options.onError(it) }
        .addOnCompleteListener {
          imageProxy.close()
          isBusy.set(false)
        }
    } catch (error: Throwable) {
      imageProxy.close()
      isBusy.set(false)
      options.onError(error)
    }
  }

  override fun dispose() {
    imageAnalysis?.clearAnalyzer()
    detector.close()
    executor.shutdown()
    super.dispose()
  }
}

private fun Face.point(type: Int): VKFacePoint? =
  getLandmark(type)?.position?.let { VKFacePoint(it.x.toDouble(), it.y.toDouble()) }

private fun Face.toVKFace(frameWidth: Double, frameHeight: Double): VKFace {
  val landmarks = if (allLandmarks.isEmpty()) null else VKFaceLandmarks(
    leftEye = point(FaceLandmark.LEFT_EYE),
    rightEye = point(FaceLandmark.RIGHT_EYE),
    noseBase = point(FaceLandmark.NOSE_BASE),
    mouthLeft = point(FaceLandmark.MOUTH_LEFT),
    mouthRight = point(FaceLandmark.MOUTH_RIGHT),
    mouthBottom = point(FaceLandmark.MOUTH_BOTTOM),
    leftEar = point(FaceLandmark.LEFT_EAR),
    rightEar = point(FaceLandmark.RIGHT_EAR),
    leftCheek = point(FaceLandmark.LEFT_CHEEK),
    rightCheek = point(FaceLandmark.RIGHT_CHEEK),
  )
  return VKFace(
    bounds = VKFaceBounds(
      boundingBox.left.toDouble(),
      boundingBox.top.toDouble(),
      boundingBox.width().toDouble(),
      boundingBox.height().toDouble(),
    ),
    rollAngle = headEulerAngleZ.toDouble(),
    yawAngle = headEulerAngleY.toDouble(),
    pitchAngle = headEulerAngleX.toDouble(),
    frameWidth = frameWidth,
    frameHeight = frameHeight,
    landmarks = landmarks,
    trackingId = trackingId?.toDouble(),
    smilingProbability = smilingProbability?.toDouble(),
    leftEyeOpenProbability = leftEyeOpenProbability?.toDouble(),
    rightEyeOpenProbability = rightEyeOpenProbability?.toDouble(),
  )
}
