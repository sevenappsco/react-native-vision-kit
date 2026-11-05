import CoreGraphics
import ExpoModulesCore
import Foundation
import ImageIO
import Vision

/// A decoded image plus its EXIF orientation.
///
/// Vision does the rotation itself when it gets the orientation, and reports
/// normalized coordinates in the *upright* image. `uprightSize` is the size of
/// that upright image in pixels, which is the coordinate space every API in
/// this package returns (top-left origin, like ML Kit).
struct VisionImage {
  let cgImage: CGImage
  let orientation: CGImagePropertyOrientation

  var uprightSize: CGSize {
    let w = CGFloat(cgImage.width)
    let h = CGFloat(cgImage.height)
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      return CGSize(width: h, height: w)
    default:
      return CGSize(width: w, height: h)
    }
  }

  func makeHandler() -> VNImageRequestHandler {
    VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
  }

  /// Converts a Vision normalized rect (lower-left origin) to an upright pixel rect (top-left origin).
  func pixelRect(fromNormalized r: CGRect) -> CGRect {
    let size = uprightSize
    return CGRect(
      x: r.minX * size.width,
      y: (1 - r.maxY) * size.height,
      width: r.width * size.width,
      height: r.height * size.height
    )
  }

  /// Converts a Vision image-space point (lower-left origin, pixels) to top-left origin.
  func flip(_ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x, y: uprightSize.height - p.y)
  }

  static func load(_ uri: String) throws -> VisionImage {
    let url = try resolveURL(uri)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw VisionKitError.imageLoad(uri)
    }
    let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
      throw VisionKitError.imageLoad(uri)
    }
    var orientation = CGImagePropertyOrientation.up
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let raw = props[kCGImagePropertyOrientation] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: raw) {
      orientation = parsed
    }
    return VisionImage(cgImage: image, orientation: orientation)
  }

  private static func resolveURL(_ uri: String) throws -> URL {
    if uri.hasPrefix("/") {
      return URL(fileURLWithPath: uri)
    }
    if let url = URL(string: uri), url.isFileURL {
      return url
    }
    // Percent-encoded paths with spaces etc.
    if let encoded = uri.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
       let url = URL(string: encoded), url.isFileURL {
      return url
    }
    throw VisionKitError.unsupportedURI(uri)
  }
}

enum VisionKitError: Error, CustomStringConvertible {
  case imageLoad(String)
  case unsupportedURI(String)

  var description: String {
    switch self {
    case .imageLoad(let uri): return "Could not decode image at \(uri)"
    case .unsupportedURI(let uri): return "Only file:// URIs and absolute paths are supported, got \(uri)"
    }
  }
}

final class ImageLoadException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_IMAGE_LOAD" }
  override var reason: String { param }
}

func loadVisionImage(_ uri: String) throws -> VisionImage {
  do {
    return try VisionImage.load(uri)
  } catch let error as VisionKitError {
    throw ImageLoadException(error.description)
  }
}

extension CGRect {
  var frameDictionary: [String: Double] {
    ["left": Double(minX), "top": Double(minY), "right": Double(maxX), "bottom": Double(maxY)]
  }
}

extension VNRequest {
  /// The iOS simulator has no Neural Engine / Metal path for Vision's face models
  /// ("Could not create inference context"). Run on CPU there; devices are unaffected.
  func useCPUOnSimulator() {
    #if targetEnvironment(simulator)
    if #available(iOS 17.0, *) {
      if let devices = try? supportedComputeStageDevices {
        for stage in devices.keys {
          if let cpu = devices[stage]?.first(where: { if case .cpu = $0 { return true } else { return false } }) {
            setComputeDevice(cpu, for: stage)
          }
        }
      }
    } else {
      usesCPUOnly = true
    }
    #endif
  }
}
