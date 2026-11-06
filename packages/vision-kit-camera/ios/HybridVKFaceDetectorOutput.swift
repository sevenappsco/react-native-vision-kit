import AVFoundation
import NitroModules
import Vision
import VisionCamera

/// A VisionCamera 5 `CameraOutput` that runs Apple Vision face detection on
/// camera buffers. No Google ML Kit on iOS.
///
/// Buffers stay unrotated (VisionCamera's default for data outputs). Vision
/// gets the physical orientation as metadata and reports coordinates in the
/// upright image. `frameWidth`/`frameHeight` are that upright size.
final class HybridVKFaceDetectorOutput: HybridCameraOutputSpec, NativeCameraOutput {
  let output = AVCaptureVideoDataOutput()
  let requiresAudioInput = false
  let requiresDepthFormat = false
  let mediaType: MediaType = .video
  let streamType: StreamType = .video
  var outputOrientation: CameraOrientation = .up

  var currentResolution: Size? {
    output.connection(with: .video)?.inputStreamResolution
  }

  var targetResolution: ResolutionRule {
    .closestTo(Size(width: 720.0, height: 1280.0))
  }

  private let queue = DispatchQueue(label: "com.sevenapps.visionkit.faces", qos: .userInitiated)
  private let delegate: SampleBufferDelegate
  private let sequenceHandler = VNSequenceRequestHandler()
  private let onFacesDetected: ([VKFace]) -> Void
  private let onError: (Error) -> Void
  private let runLandmarks: Bool
  private let minFaceSize: Double
  private let cameraFacing: VKCameraFacing

  init(_ options: VKFaceDetectorOutputOptions) {
    onFacesDetected = options.onFacesDetected
    onError = options.onError
    runLandmarks = (options.runLandmarks ?? false) || options.performanceMode == .accurate
    minFaceSize = options.minFaceSize ?? 0.15
    cameraFacing = options.cameraFacing ?? .front
    delegate = SampleBufferDelegate()
    super.init()

    delegate.onSampleBuffer = { [weak self] buffer, connection in
      self?.process(buffer, connection: connection)
    }
    output.setSampleBufferDelegate(delegate, queue: queue)
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    if #available(iOS 17.0, *), options.outputResolution != .full {
      output.automaticallyConfiguresOutputBufferDimensions = false
      output.deliversPreviewSizedOutputBuffers = true
    }
  }

  func configure(config _: OutputConfiguration) {
    output.connection(with: .video)?.preferredVideoStabilizationMode = .off
  }

  // MARK: - Processing (on `queue`; the delegate drops late frames for us)

  private func process(_ buffer: CMSampleBuffer, connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

    let orientation = imageOrientation(for: connection)
    let rawWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
    let rawHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
    let swaps: Bool
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored: swaps = true
    default: swaps = false
    }
    let width = swaps ? rawHeight : rawWidth
    let height = swaps ? rawWidth : rawHeight

    let rectangles = VNDetectFaceRectanglesRequest()
    if #available(iOS 15.0, *) {
      rectangles.revision = VNDetectFaceRectanglesRequestRevision3
    }
    #if targetEnvironment(simulator)
    rectangles.usesCPUOnly = true
    #endif

    do {
      try sequenceHandler.perform([rectangles], on: pixelBuffer, orientation: orientation)
      var observations = (rectangles.results ?? []).filter {
        Double($0.boundingBox.width) >= minFaceSize
      }
      var landmarkObservations: [VNFaceObservation] = []
      if runLandmarks, !observations.isEmpty {
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = observations
        try sequenceHandler.perform([landmarks], on: pixelBuffer, orientation: orientation)
        landmarkObservations = landmarks.results ?? []
      }
      // Largest face first, like ML Kit's typical ordering for selfies.
      observations.sort { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }

      let faces = observations.map { observation -> VKFace in
        let r = observation.boundingBox
        let bounds = VKFaceBounds(
          x: Double(r.minX) * width,
          y: (1 - Double(r.maxY)) * height,
          width: Double(r.width) * width,
          height: Double(r.height) * height
        )
        let landmarkFace = landmarkObservations.first { $0.uuid == observation.uuid }
          ?? landmarkObservations.first { $0.boundingBox == observation.boundingBox }
        return VKFace(
          bounds: bounds,
          rollAngle: FaceAngles.degrees(observation.roll) * FaceAngles.rollSign,
          yawAngle: FaceAngles.degrees(observation.yaw) * FaceAngles.yawSign,
          pitchAngle: FaceAngles.pitch(observation),
          frameWidth: width,
          frameHeight: height,
          landmarks: landmarkFace.flatMap { landmarks(of: $0, width: width, height: height) },
          trackingId: nil,
          smilingProbability: nil,
          leftEyeOpenProbability: nil,
          rightEyeOpenProbability: nil
        )
      }
      onFacesDetected(faces)
    } catch {
      onError(error)
    }
  }

  private func landmarks(of face: VNFaceObservation, width: Double, height: Double) -> VKFaceLandmarks? {
    guard let lm = face.landmarks else { return nil }
    let box = face.boundingBox
    func points(_ region: VNFaceLandmarkRegion2D?) -> [VKFacePoint] {
      (region?.normalizedPoints ?? []).map { p in
        let x = (Double(box.minX) + Double(p.x) * Double(box.width)) * width
        let y = (Double(box.minY) + Double(p.y) * Double(box.height)) * height
        return VKFacePoint(x: x, y: height - y)
      }
    }
    func center(_ ps: [VKFacePoint]) -> VKFacePoint? {
      guard !ps.isEmpty else { return nil }
      let n = Double(ps.count)
      return VKFacePoint(x: ps.map(\.x).reduce(0, +) / n, y: ps.map(\.y).reduce(0, +) / n)
    }
    // Vision names regions from the viewer's side; ML Kit uses the subject's side.
    // Eye-region centroids, like ML Kit's eye-center landmarks. Vision's left/right
    // match ML Kit's (cross-checked on the same image).
    let leftEye = center(points(lm.leftEye)) ?? points(lm.leftPupil).first
    let rightEye = center(points(lm.rightEye)) ?? points(lm.rightPupil).first
    var ax = 1.0, ay = 0.0
    if let l = leftEye, let r = rightEye {
      let len = max(((l.x - r.x) * (l.x - r.x) + (l.y - r.y) * (l.y - r.y)).squareRoot(), 0.0001)
      ax = (l.x - r.x) / len
      ay = (l.y - r.y) / len
    }
    let (dx, dy) = (-ay, ax)
    func extreme(_ ps: [VKFacePoint], _ x: Double, _ y: Double) -> VKFacePoint? {
      ps.max { ($0.x * x + $0.y * y) < ($1.x * x + $1.y * y) }
    }
    let lips = points(lm.outerLips)
    return VKFaceLandmarks(
      leftEye: leftEye,
      rightEye: rightEye,
      noseBase: extreme(points(lm.nose), dx, dy),
      mouthLeft: extreme(lips, ax, ay),
      mouthRight: extreme(lips, -ax, -ay),
      mouthBottom: extreme(lips, dx, dy),
      leftEar: nil,
      rightEar: nil,
      leftCheek: nil,
      rightCheek: nil
    )
  }

  /// Orientation of the unrotated buffer relative to the upright target
  /// orientation, for the camera position in use.
  private func imageOrientation(for connection: AVCaptureConnection) -> CGImagePropertyOrientation {
    let position = connection.inputPorts
      .compactMap { ($0.input as? AVCaptureDeviceInput)?.device.position }
      .first ?? (cameraFacing == .back ? .back : .front)
    // Same table as react-native-vision-camera-face-detector's
    // `toMLKitBufferOrientation`: front-camera results are in the mirrored
    // (selfie) upright image, which is what skincare's guidance was tuned on.
    switch (position, outputOrientation) {
    case (.back, .up): return .right
    case (.back, .left): return .up
    case (.back, .down): return .left
    case (.back, .right): return .down
    case (_, .up): return .leftMirrored
    case (_, .left): return .downMirrored
    case (_, .down): return .rightMirrored
    case (_, .right): return .upMirrored
    }
  }
}

private final class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  var onSampleBuffer: ((CMSampleBuffer, AVCaptureConnection) -> Void)?

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    onSampleBuffer?(sampleBuffer, connection)
  }
}

/// Converts Vision's radians to ML Kit's degrees and sign convention.
/// Must match `FaceAngles` in @sevenappsco/vision-kit (still-image API).
enum FaceAngles {
  static let rollSign: Double = 1
  static let yawSign: Double = 1
  static let pitchSign: Double = 1

  static func degrees(_ value: NSNumber?) -> Double {
    (value?.doubleValue ?? 0) * 180 / .pi
  }

  static func pitch(_ face: VNFaceObservation) -> Double {
    if #available(iOS 15.0, *) {
      return degrees(face.pitch) * pitchSign
    }
    return 0
  }
}
