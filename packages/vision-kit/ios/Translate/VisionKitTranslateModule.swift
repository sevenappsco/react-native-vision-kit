import ExpoModulesCore
import Foundation
#if canImport(Translation)
import Translation
#endif

/// Offline translation with Apple's Translation framework (iOS 18+).
///
/// - iOS 26+: translation of installed pairs uses `TranslationSession(installedSource:target:)`, with no UI.
/// - iOS 18–25: everything goes through the hidden SwiftUI host (`TranslationHost`).
/// - Downloads always go through the host and show Apple's system sheet.
/// - Apple has no API to delete languages or list downloads; listing is derived from pair status.
public final class VisionKitTranslateModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VisionKitTranslate")

    Constant("isSupported") { () -> Bool in
      if #available(iOS 18.0, *) { return true }
      return false
    }
    Constant("canDeleteLanguageModels") { false }
    Constant("canDownloadSilently") { false }

    AsyncFunction("getSupportedLanguages") { () async throws -> [String] in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return await AppleTranslation.supportedLanguages().map(\.vkCode).sorted()
    }

    AsyncFunction("getPairStatus") { (source: String, target: String) async throws -> String in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return await AppleTranslation.status(source, target)
    }

    AsyncFunction("getDownloadedLanguageModels") { () async throws -> [String] in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return await AppleTranslation.installedLanguages().sorted()
    }

    AsyncFunction("isLanguageDownloaded") { (code: String) async throws -> Bool in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return await AppleTranslation.isInstalled(code)
    }

    AsyncFunction("downloadLanguagePair") { (source: String, target: String) async throws -> Bool in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return try await AppleTranslation.download(source, target)
    }

    AsyncFunction("deleteLanguageModel") { (_: String) async throws -> Bool in
      throw DeleteUnsupportedException()
    }

    // Example-app diagnostic: proves the hidden SwiftUI host hands out a session
    // (works on the simulator, where real translation is unavailable).
    AsyncFunction("debugHostRoundTrip") { (source: String, target: String, prepare: Bool, attachToRoot: Bool?) async throws -> String in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      await MainActor.run { TranslationHost.shared.debugAttachToRoot = attachToRoot ?? false }
      return try await TranslationHost.shared.run(
        source: Locale.Language(vkCode: source), target: Locale.Language(vkCode: target),
        mayPresentSheet: prepare
      ) { session in
        var report = "session received"
        if #available(iOS 26.0, *) {
          let ready = await session.isReady
          let canDownload = session.canRequestDownloads
          report += ", isReady=\(ready), canRequestDownloads=\(canDownload)"
        }
        guard prepare else { return report }
        do {
          try await session.prepareTranslation()
          report += ", prepareTranslation ok"
        } catch {
          report += ", prepareTranslation threw: \(error.localizedDescription)"
        }
        return report
      }
    }

    AsyncFunction("translateBatch") { (texts: [String], source: String, target: String, downloadIfNeeded: Bool) async throws -> [String] in
      guard #available(iOS 18.0, *) else { throw TranslationUnavailableException() }
      return try await AppleTranslation.translate(texts, source, target, downloadIfNeeded: downloadIfNeeded)
    }
  }
}

final class TranslationUnavailableException: Exception, @unchecked Sendable {
  override var code: String { "ERR_TRANSLATION_UNAVAILABLE" }
  override var reason: String { "Apple Translation requires iOS 18 or newer" }
}

final class DeleteUnsupportedException: Exception, @unchecked Sendable {
  override var code: String { "ERR_UNSUPPORTED" }
  override var reason: String {
    "iOS has no API to delete translation languages. Users manage them in Settings → Apps → Translate."
  }
}

final class LanguageUnsupportedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_LANGUAGE_UNSUPPORTED" }
  override var reason: String { "Apple Translation does not support \(param)" }
}

final class ModelNotDownloadedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_MODEL_NOT_DOWNLOADED" }
  override var reason: String { "Translation languages for \(param) are not downloaded" }
}

final class TranslationFailedException: GenericException<String>, @unchecked Sendable {
  override var code: String { "ERR_TRANSLATION_FAILED" }
  override var reason: String { param }
}

#if canImport(Translation)
extension Locale.Language {
  /// BCP-47 code as used by the JS API: base language plus region or script only when meaningful
  /// ("en", "en-GB", "zh", "zh-TW").
  var vkCode: String { minimalIdentifier }

  init(vkCode code: String) {
    // "zh" alone means Simplified, like ML Kit's "zh".
    switch code.lowercased() {
    case "zh", "zh-cn", "zh-hans": self.init(identifier: "zh-Hans")
    case "zh-tw", "zh-hant": self.init(identifier: "zh-Hant")
    case "no", "nb": self.init(identifier: "nb")
    default: self.init(identifier: code)
    }
  }
}

@available(iOS 18.0, *)
enum AppleTranslation {
  static func supportedLanguages() async -> [Locale.Language] {
    await LanguageAvailability().supportedLanguages
  }

  static func rawStatus(_ source: String, _ target: String) async -> LanguageAvailability.Status {
    await LanguageAvailability().status(
      from: Locale.Language(vkCode: source), to: Locale.Language(vkCode: target))
  }

  static func status(_ source: String, _ target: String) async -> String {
    switch await rawStatus(source, target) {
    case .installed: return "downloaded"
    case .supported: return "downloadable"
    case .unsupported: return "unsupported"
    @unknown default: return "unsupported"
    }
  }

  /// Apple only reports pair status, so a language counts as installed when it
  /// is part of at least one installed pair. Pairwise over ~20 languages ≈ 190 cheap XPC calls.
  static func installedLanguages() async -> [String] {
    let availability = LanguageAvailability()
    let languages = await availability.supportedLanguages
    var installed = Set<String>()
    for i in languages.indices {
      for j in languages.indices where j > i {
        let a = languages[i], b = languages[j]
        if installed.contains(a.vkCode) && installed.contains(b.vkCode) { continue }
        if await availability.status(from: a, to: b) == .installed {
          installed.insert(a.vkCode)
          installed.insert(b.vkCode)
        }
      }
    }
    return Array(installed)
  }

  static func isInstalled(_ code: String) async -> Bool {
    let target = Locale.Language(vkCode: code)
    let availability = LanguageAvailability()
    for other in await availability.supportedLanguages where other != target {
      if await availability.status(from: target, to: other) == .installed { return true }
    }
    return false
  }

  /// Shows Apple's download sheet for the pair. Resolves `false` when the user declines.
  /// Rejects with `ERR_DOWNLOAD_SHEET_NOT_SHOWN` / `ERR_TRANSLATION_SESSION_TIMEOUT`
  /// when the sheet can't be shown, instead of waiting forever.
  static func download(_ source: String, _ target: String) async throws -> Bool {
    switch await rawStatus(source, target) {
    case .installed: return true
    case .unsupported: throw LanguageUnsupportedException("\(source) → \(target)")
    default: break
    }
    do {
      try await TranslationHost.shared.run(
        source: Locale.Language(vkCode: source), target: Locale.Language(vkCode: target),
        mayPresentSheet: true
      ) { session in
        try await session.prepareTranslation()
      }
    } catch let error as TranslationHostFailure {
      // The host couldn't get a session or show the sheet: report it, don't pretend the user declined.
      throw error
    } catch {
      // Dismissing the sheet throws a generic "Unable to Translate" (observed on
      // iOS 18.6), not a CancellationError, so the error can't tell a decline apart
      // from a failed download. Either way the pair isn't installed: resolve `false`.
      if await rawStatus(source, target) == .installed { return true }
      log("prepareTranslation ended without install: \(error)")
      return false
    }
    return await rawStatus(source, target) == .installed
  }

  static func translate(
    _ texts: [String], _ source: String, _ target: String, downloadIfNeeded: Bool
  ) async throws -> [String] {
    if texts.isEmpty { return [] }
    let status = await rawStatus(source, target)
    switch status {
    case .unsupported:
      throw LanguageUnsupportedException("\(source) → \(target)")
    case .supported:
      if !downloadIfNeeded { throw ModelNotDownloadedException("\(source) → \(target)") }
      guard try await download(source, target) else {
        throw ModelNotDownloadedException("\(source) → \(target)")
      }
    default:
      break
    }

    let requests = texts.enumerated().map {
      TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
    }
    let src = Locale.Language(vkCode: source)
    let tgt = Locale.Language(vkCode: target)

    do {
      let responses: [TranslationSession.Response]
      if #available(iOS 26.0, *) {
        let session = TranslationSession(installedSource: src, target: tgt)
        responses = try await session.translations(from: requests)
      } else {
        responses = try await TranslationHost.shared.run(source: src, target: tgt) { session in
          try await session.translations(from: requests)
        }
      }
      var out = texts
      for response in responses {
        if let id = response.clientIdentifier, let i = Int(id), i < out.count {
          out[i] = response.targetText
        }
      }
      return out
    } catch let error as TranslationHostFailure {
      throw error
    } catch {
      if #available(iOS 26.0, *), TranslationError.notInstalled ~= error {
        throw ModelNotDownloadedException("\(source) → \(target)")
      }
      if TranslationError.unsupportedLanguagePairing ~= error {
        throw LanguageUnsupportedException("\(source) → \(target)")
      }
      throw TranslationFailedException(String(describing: error))
    }
  }
}
#endif
