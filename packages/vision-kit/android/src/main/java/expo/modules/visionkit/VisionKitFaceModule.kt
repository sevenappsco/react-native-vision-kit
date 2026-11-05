package expo.modules.visionkit

import android.graphics.PointF
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class FaceDetectionOptions : Record {
  @Field val performanceMode: String? = null
  @Field val landmarkMode: String? = null
  @Field val contourMode: String? = null
  @Field val classificationMode: String? = null
  @Field val minFaceSize: Double? = null
  @Field val trackingEnabled: Boolean? = null
}

/** Still-image face detection with ML Kit. Same output as `@react-native-ml-kit/face-detection`. */
class VisionKitFaceModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("VisionKitFace")

    AsyncFunction("detect") { uri: String, options: FaceDetectionOptions ->
      val builder = FaceDetectorOptions.Builder()
        .setPerformanceMode(
          if (options.performanceMode == "accurate") FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE
          else FaceDetectorOptions.PERFORMANCE_MODE_FAST
        )
        .setLandmarkMode(
          if (options.landmarkMode == "all") FaceDetectorOptions.LANDMARK_MODE_ALL
          else FaceDetectorOptions.LANDMARK_MODE_NONE
        )
        .setContourMode(
          if (options.contourMode == "all") FaceDetectorOptions.CONTOUR_MODE_ALL
          else FaceDetectorOptions.CONTOUR_MODE_NONE
        )
        .setClassificationMode(
          if (options.classificationMode == "all") FaceDetectorOptions.CLASSIFICATION_MODE_ALL
          else FaceDetectorOptions.CLASSIFICATION_MODE_NONE
        )
        .setMinFaceSize((options.minFaceSize ?: 0.1).toFloat())
      if (options.trackingEnabled == true) builder.enableTracking()

      val detector = FaceDetection.getClient(builder.build())
      try {
        val faces = Tasks.await(detector.process(loadInputImage(appContext, uri)))
        faces.map { it.toRecord() }
      } finally {
        detector.close()
      }
    }
  }
}

private fun PointF.toPoint() = mapOf("x" to x.toDouble(), "y" to y.toDouble())

private val LANDMARKS = mapOf(
  FaceLandmark.LEFT_EAR to "leftEar",
  FaceLandmark.RIGHT_EAR to "rightEar",
  FaceLandmark.LEFT_EYE to "leftEye",
  FaceLandmark.RIGHT_EYE to "rightEye",
  FaceLandmark.NOSE_BASE to "noseBase",
  FaceLandmark.LEFT_CHEEK to "leftCheek",
  FaceLandmark.RIGHT_CHEEK to "rightCheek",
  FaceLandmark.MOUTH_LEFT to "mouthLeft",
  FaceLandmark.MOUTH_RIGHT to "mouthRight",
  FaceLandmark.MOUTH_BOTTOM to "mouthBottom",
)

private val CONTOURS = mapOf(
  FaceContour.FACE to "face",
  FaceContour.LEFT_EYE to "leftEye",
  FaceContour.RIGHT_EYE to "rightEye",
  FaceContour.LEFT_CHEEK to "leftCheek",
  FaceContour.RIGHT_CHEEK to "rightCheek",
  FaceContour.NOSE_BOTTOM to "noseBottom",
  FaceContour.NOSE_BRIDGE to "noseBridge",
  FaceContour.LEFT_EYEBROW_TOP to "leftEyebrowTop",
  FaceContour.RIGHT_EYEBROW_TOP to "rightEyebrowTop",
  FaceContour.LEFT_EYEBROW_BOTTOM to "leftEyebrowBottom",
  FaceContour.RIGHT_EYEBROW_BOTTOM to "rightEyebrowBottom",
  FaceContour.UPPER_LIP_TOP to "upperLipTop",
  FaceContour.UPPER_LIP_BOTTOM to "upperLipBottom",
  FaceContour.LOWER_LIP_TOP to "lowerLipTop",
  FaceContour.LOWER_LIP_BOTTOM to "lowerLipBottom",
)

private fun Face.toRecord(): Map<String, Any?> {
  val out = mutableMapOf<String, Any?>(
    "frame" to mapOf(
      "left" to boundingBox.left.toDouble(),
      "top" to boundingBox.top.toDouble(),
      "width" to boundingBox.width().toDouble(),
      "height" to boundingBox.height().toDouble(),
    ),
    "rotationX" to headEulerAngleX.toDouble(),
    "rotationY" to headEulerAngleY.toDouble(),
    "rotationZ" to headEulerAngleZ.toDouble(),
  )
  if (allLandmarks.isNotEmpty()) {
    out["landmarks"] = allLandmarks.mapNotNull { lm ->
      LANDMARKS[lm.landmarkType]?.let { it to mapOf("position" to lm.position.toPoint()) }
    }.toMap()
  }
  if (allContours.isNotEmpty()) {
    out["contours"] = allContours.mapNotNull { c ->
      CONTOURS[c.faceContourType]?.let { it to mapOf("points" to c.points.map { p -> p.toPoint() }) }
    }.toMap()
  }
  smilingProbability?.let { out["smilingProbability"] = it.toDouble() }
  leftEyeOpenProbability?.let { out["leftEyeOpenProbability"] = it.toDouble() }
  rightEyeOpenProbability?.let { out["rightEyeOpenProbability"] = it.toDouble() }
  trackingId?.let { out["trackingID"] = it }
  return out
}
