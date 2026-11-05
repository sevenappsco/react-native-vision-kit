import SwiftUI
import UIKit
#if canImport(Translation)
import Translation

/// iOS 18–25 only hand out a `TranslationSession` through the SwiftUI
/// `.translationTask` modifier, and only a session obtained that way can show
/// the system language-download sheet (`prepareTranslation()`).
///
/// This keeps a tiny, invisible `UIHostingController` attached to the key
/// window. Every request swaps the modifier's configuration, waits for the
/// closure to hand over a session, runs the job inside the closure (Apple
/// forbids using a session outside of it), and resumes the caller.
/// Jobs are strictly serialized.
@available(iOS 18.0, *)
@MainActor
final class TranslationHost {
  static let shared = TranslationHost()

  private let model = TranslationHostModel()
  private var hostingController: UIHostingController<TranslationHostView>?
  private var tail: Task<Void, Never>?

  func run<T: Sendable>(
    source: Locale.Language,
    target: Locale.Language,
    _ job: @escaping @Sendable (TranslationSession) async throws -> T
  ) async throws -> T {
    let previous = tail
    let task = Task { @MainActor () -> Result<T, Error> in
      await previous?.value
      do {
        return .success(try await self.perform(source: source, target: target, job))
      } catch {
        return .failure(error)
      }
    }
    tail = Task { _ = await task.value }
    return try await task.value.get()
  }

  private func perform<T: Sendable>(
    source: Locale.Language,
    target: Locale.Language,
    _ job: @escaping @Sendable (TranslationSession) async throws -> T
  ) async throws -> T {
    try attachIfNeeded()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      model.pending = { session in
        do {
          continuation.resume(returning: try await job(session))
        } catch {
          continuation.resume(throwing: error)
        }
      }
      var configuration = TranslationSession.Configuration(source: source, target: target)
      if let current = model.configuration, current.source == source, current.target == target {
        configuration = current
        configuration.invalidate()
      }
      model.configuration = configuration
      log("configuration set \(source.minimalIdentifier)→\(target.minimalIdentifier), window=\(hostingController?.view.window != nil)")
    }
  }

  private func attachIfNeeded() throws {
    if let view = hostingController?.view, view.window != nil { return }
    hostingController?.view.removeFromSuperview()
    hostingController?.removeFromParent()

    guard let root = Self.keyWindow()?.rootViewController else {
      throw TranslationHostError.noWindow
    }
    let controller = UIHostingController(rootView: TranslationHostView(model: model))
    controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    controller.view.alpha = 0.011
    controller.view.isUserInteractionEnabled = false
    controller.view.backgroundColor = .clear
    root.addChild(controller)
    root.view.addSubview(controller.view)
    controller.didMove(toParent: root)
    hostingController = controller
    log("host attached to \(type(of: root))")
  }

  private static func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    return windows.first(where: \.isKeyWindow) ?? windows.first
  }
}

func log(_ message: String) {
  #if DEBUG
  NSLog("[VisionKitTranslate] %@", message)
  #endif
}

enum TranslationHostError: Error, CustomStringConvertible {
  case noWindow
  var description: String { "No key window to host the Translation session" }
}

@available(iOS 18.0, *)
@MainActor
final class TranslationHostModel: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?
  var pending: ((TranslationSession) async -> Void)?

  func handle(_ session: TranslationSession) async {
    log("translationTask fired, pending=\(pending != nil)")
    guard let job = pending else { return }
    pending = nil
    await job(session)
  }
}

@available(iOS 18.0, *)
struct TranslationHostView: View {
  @ObservedObject var model: TranslationHostModel

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .translationTask(model.configuration) { session in
        await model.handle(session)
      }
  }
}
#endif
