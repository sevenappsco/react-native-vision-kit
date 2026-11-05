import ExpoModulesCore
import NaturalLanguage
import Vision

/// OCR with Apple Vision (`VNRecognizeTextRequest`). Mirrors the shape of
/// `@infinitered/react-native-mlkit-text-recognition` (`Text` → `Block` → `TextLine` → `TextElement`).
public final class VisionKitTextModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VisionKitText")

    Function("getSupportedScripts") { () -> [String] in
      OcrScripts.supported()
    }

    Function("getSupportedRecognitionLanguages") { (level: String?) -> [String] in
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = level == "fast" ? .fast : .accurate
      return (try? request.supportedRecognitionLanguages()) ?? []
    }

    AsyncFunction("recognizeText") { (uri: String, script: String, options: RecognizeTextOptions) -> [String: Any] in
      let languages: [String]
      if let explicit = options.languages, !explicit.isEmpty {
        languages = explicit
      } else if let mapped = OcrScripts.languages(for: script) {
        languages = mapped
      } else {
        throw ScriptUnsupportedException(script)
      }

      let image = try loadVisionImage(uri)
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = options.level == "fast" ? .fast : .accurate
      request.usesLanguageCorrection = options.languageCorrection ?? true
      request.recognitionLanguages = languages
      if #available(iOS 16.0, *) {
        request.automaticallyDetectsLanguage = false
      }

      try image.makeHandler().perform([request])
      let observations = request.results ?? []
      return TextResultBuilder(image: image).build(observations)
    }
  }
}

struct RecognizeTextOptions: Record {
  @Field var languages: [String]?
  @Field var level: String?
  @Field var languageCorrection: Bool?
}

final class ScriptUnsupportedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_SCRIPT_UNSUPPORTED" }
  override var reason: String { "Script '\(param)' is not supported by Apple Vision text recognition on iOS" }
}

enum OcrScripts {
  // Every value here is in `VNRecognizeTextRequest.supportedRecognitionLanguages()`
  // for `.accurate` on iOS 16+ (revision 3).
  static let latin = [
    "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "vi-VT", "tr-TR", "id-ID",
    "cs-CZ", "da-DK", "nl-NL", "nb-NO", "ms-MY", "pl-PL", "ro-RO", "sv-SE",
  ]

  static let table: [String: [String]] = [
    "latin": latin,
    "chinese": ["zh-Hans", "zh-Hant", "en-US"],
    "japanese": ["ja-JP", "en-US"],
    "korean": ["ko-KR", "en-US"],
    "cyrillic": ["ru-RU", "uk-UA", "en-US"],
    "arabic": ["ar-SA", "en-US"],
    "thai": ["th-TH", "en-US"],
    // "devanagari": Apple Vision has no Devanagari model.
  ]

  static func languages(for script: String) -> [String]? {
    guard let wanted = table[script] else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let available = Set((try? request.supportedRecognitionLanguages()) ?? [])
    let filtered = wanted.filter { available.contains($0) }
    return filtered.isEmpty ? nil : filtered
  }

  static func supported() -> [String] {
    ["latin", "chinese", "japanese", "korean", "cyrillic", "arabic", "thai"].filter {
      languages(for: $0) != nil
    }
  }
}

/// Converts Vision line observations into ML Kit's block/line/element tree.
struct TextResultBuilder {
  let image: VisionImage

  private struct Line {
    let text: String
    let rect: CGRect
    let elements: [[String: Any]]
    let language: String?
  }

  func build(_ observations: [VNRecognizedTextObservation]) -> [String: Any] {
    let lines: [Line] = observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      let rect = image.pixelRect(fromNormalized: observation.boundingBox)
      return Line(
        text: text,
        rect: rect,
        elements: elements(of: candidate, lineRect: rect),
        language: dominantLanguage(text)
      )
    }

    let blocks = groupIntoBlocks(lines).map { group -> [String: Any] in
      let rect = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }
      let languages = Array(Set(group.compactMap(\.language))).sorted()
      return [
        "text": group.map(\.text).joined(separator: "\n"),
        "frame": rect.frameDictionary,
        "recognizedLanguages": languages,
        "lines": group.map { line -> [String: Any] in
          [
            "text": line.text,
            "frame": line.rect.frameDictionary,
            "recognizedLanguages": line.language.map { [$0] } ?? [],
            "elements": line.elements,
          ]
        },
      ]
    }

    return [
      "text": blocks.compactMap { $0["text"] as? String }.joined(separator: "\n"),
      "blocks": blocks,
    ]
  }

  private func elements(of candidate: VNRecognizedText, lineRect: CGRect) -> [[String: Any]] {
    let text = candidate.string
    var result: [[String: Any]] = []
    var index = text.startIndex
    while index < text.endIndex {
      guard let wordStart = text[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
      let wordEnd = text[wordStart...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
      let range = wordStart..<wordEnd
      let rect: CGRect
      if let box = try? candidate.boundingBox(for: range) {
        rect = image.pixelRect(fromNormalized: box.boundingBox)
      } else {
        rect = lineRect
      }
      result.append([
        "text": String(text[range]),
        "frame": rect.frameDictionary,
        "recognizedLanguages": [String](),
      ])
      index = wordEnd
    }
    return result
  }

  private func dominantLanguage(_ text: String) -> String? {
    guard text.count >= 4 else { return nil }
    return NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
  }

  /// Vision returns lines; ML Kit returns paragraph blocks. A line joins the
  /// current block when it is directly below it (gap ≤ 0.6 × line height,
  /// close to ML Kit's paragraph splitting),
  /// has a similar height, and overlaps it horizontally.
  private func groupIntoBlocks(_ lines: [Line]) -> [[Line]] {
    let sorted = lines.sorted { $0.rect.minY < $1.rect.minY }
    var blocks: [[Line]] = []
    var blockRects: [CGRect] = []

    for line in sorted {
      var target: Int?
      for (i, block) in blocks.enumerated() {
        guard let last = block.last else { continue }
        let height = max(last.rect.height, 1)
        let gap = line.rect.minY - last.rect.maxY
        let heightRatio = line.rect.height / height
        let blockRect = blockRects[i]
        let overlap = min(line.rect.maxX, blockRect.maxX) - max(line.rect.minX, blockRect.minX)
        if gap <= height * 0.6, gap >= -height * 0.5,
           heightRatio > 0.6, heightRatio < 1.67,
           overlap > min(line.rect.width, blockRect.width) * 0.25 {
          target = i
          break
        }
      }
      if let i = target {
        blocks[i].append(line)
        blockRects[i] = blockRects[i].union(line.rect)
      } else {
        blocks.append([line])
        blockRects.append(line.rect)
      }
    }
    return blocks
  }
}
