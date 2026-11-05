import ExpoModulesCore
import Vision

/// Still-image face detection with Apple Vision. Output shape matches
/// `@react-native-ml-kit/face-detection` (frame, rotationX/Y/Z, landmarks, contours).
public final class VisionKitFaceModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VisionKitFace")

    AsyncFunction("detect") { (uri: String, options: FaceDetectionOptions) -> [[String: Any]] in
      let image = try loadVisionImage(uri)
      let wantsLandmarks = options.landmarkMode == "all" || options.contourMode == "all"

      let rectangles = VNDetectFaceRectanglesRequest()
      if #available(iOS 15.0, *) {
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
      }
      rectangles.useCPUOnSimulator()
      let handler = image.makeHandler()
      try handler.perform([rectangles])
      var faces = rectangles.results ?? []

      let minFaceSize = options.minFaceSize ?? 0.1
      faces = faces.filter { $0.boundingBox.width >= CGFloat(minFaceSize) }

      var landmarkFaces: [VNFaceObservation] = []
      if wantsLandmarks, !faces.isEmpty {
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = faces
        if #available(iOS 15.0, *) {
          landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        }
        landmarks.useCPUOnSimulator()
        try handler.perform([landmarks])
        landmarkFaces = landmarks.results ?? []
      }

      return faces.enumerated().map { index, face in
        let withLandmarks = index < landmarkFaces.count ? landmarkFaces[index] : nil
        return FaceMapper(image: image).map(
          face,
          landmarks: withLandmarks,
          includeLandmarks: options.landmarkMode == "all",
          includeContours: options.contourMode == "all"
        )
      }
    }
  }
}

struct FaceDetectionOptions: Record {
  @Field var performanceMode: String?
  @Field var landmarkMode: String?
  @Field var contourMode: String?
  @Field var classificationMode: String?
  @Field var minFaceSize: Double?
  @Field var trackingEnabled: Bool?
}

struct FaceMapper {
  let image: VisionImage

  func map(
    _ face: VNFaceObservation,
    landmarks landmarkFace: VNFaceObservation?,
    includeLandmarks: Bool,
    includeContours: Bool
  ) -> [String: Any] {
    let rect = image.pixelRect(fromNormalized: face.boundingBox)
    var result: [String: Any] = [
      "frame": [
        "left": Double(rect.minX),
        "top": Double(rect.minY),
        "width": Double(rect.width),
        "height": Double(rect.height),
      ],
      "rotationX": FaceAngles.pitch(face),
      "rotationY": FaceAngles.yaw(face),
      "rotationZ": FaceAngles.roll(face),
    ]

    guard let landmarks = landmarkFace?.landmarks else { return result }
    let size = image.uprightSize

    // Landmark points are normalized to the landmark observation's bounding box.
    // Map them manually: `pointsInImage(imageSize:)` returned collapsed points on
    // the iOS 26.5 simulator.
    let box = landmarkFace?.boundingBox ?? face.boundingBox
    func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
      guard let region else { return [] }
      return region.normalizedPoints.map { p in
        let x = (box.minX + p.x * box.width) * size.width
        let y = (box.minY + p.y * box.height) * size.height
        return image.flip(CGPoint(x: x, y: y))
      }
    }
    func pointDict(_ p: CGPoint) -> [String: Double] { ["x": Double(p.x), "y": Double(p.y)] }
    func centroid(_ ps: [CGPoint]) -> CGPoint? {
      guard !ps.isEmpty else { return nil }
      let sum = ps.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
      return CGPoint(x: sum.x / CGFloat(ps.count), y: sum.y / CGFloat(ps.count))
    }

    // Vision's left/right match ML Kit's on the same image (both put `leftEye` on the
    // image's left for an upright selfie-style photo). Cross-checked against ML Kit
    // on Android with example/assets/samples/face.jpg. ML Kit's eye landmarks are
    // eye centers, so use the eye-region centroid.
    let leftEye = centroid(points(landmarks.leftEye)) ?? points(landmarks.leftPupil).first
    let rightEye = centroid(points(landmarks.rightEye)) ?? points(landmarks.rightPupil).first

    if includeLandmarks {
      var out: [String: Any] = [:]
      if let leftEye { out["leftEye"] = ["position": pointDict(leftEye)] }
      if let rightEye { out["rightEye"] = ["position": pointDict(rightEye)] }

      // Face-relative axes, so corner picks still work on tilted faces.
      var across = CGPoint(x: 1, y: 0)
      if let l = leftEye, let r = rightEye {
        let dx = l.x - r.x, dy = l.y - r.y
        let len = max(sqrt(dx * dx + dy * dy), 0.0001)
        across = CGPoint(x: dx / len, y: dy / len)  // points from rightEye toward leftEye
      } else if rect.width > 0 {
        across = CGPoint(x: 1, y: 0)
      }
      let down = CGPoint(x: -across.y, y: across.x)
      func extreme(_ ps: [CGPoint], along axis: CGPoint, max wantMax: Bool) -> CGPoint? {
        ps.max { a, b in
          let da = a.x * axis.x + a.y * axis.y
          let db = b.x * axis.x + b.y * axis.y
          return wantMax ? da < db : da > db
        }
      }

      let nose = points(landmarks.nose)
      if let base = extreme(nose, along: down, max: true) {
        out["noseBase"] = ["position": pointDict(base)]
      }
      let lips = points(landmarks.outerLips)
      if let p = extreme(lips, along: across, max: true) { out["mouthLeft"] = ["position": pointDict(p)] }
      if let p = extreme(lips, along: across, max: false) { out["mouthRight"] = ["position": pointDict(p)] }
      if let p = extreme(lips, along: down, max: true) { out["mouthBottom"] = ["position": pointDict(p)] }
      // Vision has no ear or cheek landmarks; those keys are left out.
      result["landmarks"] = out
    }

    if includeContours {
      var out: [String: Any] = [:]
      func add(_ key: String, _ region: VNFaceLandmarkRegion2D?) {
        let ps = points(region)
        if !ps.isEmpty { out[key] = ["points": ps.map(pointDict)] }
      }
      add("face", landmarks.faceContour)
      add("leftEye", landmarks.leftEye)
      add("rightEye", landmarks.rightEye)
      add("leftEyebrowTop", landmarks.leftEyebrow)
      add("rightEyebrowTop", landmarks.rightEyebrow)
      add("noseBridge", landmarks.noseCrest)
      add("upperLipTop", landmarks.outerLips)
      add("lowerLipTop", landmarks.innerLips)
      result["contours"] = out
    }
    return result
  }
}

/// Converts Vision's radians to ML Kit's degrees and sign convention.
enum FaceAngles {
  // Vision: rotating the image counter-clockwise gives a positive roll, the same as ML Kit's Euler Z.
  // Checked against ML Kit on the same rotated sample images.
  static let rollSign: Double = 1
  static let yawSign: Double = 1
  static let pitchSign: Double = 1

  static func roll(_ face: VNFaceObservation) -> Double {
    degrees(face.roll) * rollSign
  }
  static func yaw(_ face: VNFaceObservation) -> Double {
    degrees(face.yaw) * yawSign
  }
  static func pitch(_ face: VNFaceObservation) -> Double {
    if #available(iOS 15.0, *) {
      return degrees(face.pitch) * pitchSign
    }
    return 0
  }
  private static func degrees(_ value: NSNumber?) -> Double {
    (value?.doubleValue ?? 0) * 180 / .pi
  }
}
