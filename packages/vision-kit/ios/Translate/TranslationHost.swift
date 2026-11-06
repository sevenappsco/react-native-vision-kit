import ExpoModulesCore
import SwiftUI
import UIKit
#if canImport(Translation)
import Translation

/// iOS 18–25 only hand out a `TranslationSession` through the SwiftUI
/// `.translationTask` modifier, and only a session obtained that way can show
/// the system language-download sheet (`prepareTranslation()`).
///
/// This keeps a tiny, invisible `UIHostingController` attached as a child of the
/// top-most presented view controller. Apple's sheet is presented from there, so
/// the host must follow the app's modals: when it sits under a view controller
/// that is already presenting something (an RN `<Modal>`, a modal route), UIKit
/// silently drops the sheet and `prepareTranslation()` never returns.
///
/// Every request re-attaches if the top-most view controller changed, swaps the
/// modifier's configuration, waits for the closure to hand over a session, runs
/// the job inside the closure (Apple forbids using a session outside of it), and
/// resumes the caller. Jobs are strictly serialized.
///
/// Watchdogs, so a caller never waits forever:
/// - the `.translationTask` closure must fire within `sessionTimeout`;
/// - for jobs that may show the sheet, if the job is still running after
///   `sheetTimeout` and nothing was presented on top of the host, the job is
///   rejected. Once something is presented the job may take as long as the user
///   needs (Apple's sheet is waiting for them).
@available(iOS 18.0, *)
@MainActor
final class TranslationHost {
  static let shared = TranslationHost()

  static let sessionTimeout: Duration = .seconds(8)
  static let sheetTimeout: Duration = .seconds(5)

  /// Example-app diagnostic only: attach under the root view controller like
  /// 0.1.1 did, to reproduce a dropped sheet and exercise the watchdog.
  var debugAttachToRoot = false

  private let model = TranslationHostModel()
  private var hostingController: UIHostingController<TranslationHostView>?
  private var tail: Task<Void, Never>?

  func run<T: Sendable>(
    source: Locale.Language,
    target: Locale.Language,
    mayPresentSheet: Bool = false,
    _ job: @escaping @Sendable (TranslationSession) async throws -> T
  ) async throws -> T {
    let previous = tail
    let task = Task { @MainActor () -> Result<T, Error> in
      await previous?.value
      do {
        return .success(
          try await self.perform(source: source, target: target, mayPresentSheet: mayPresentSheet, job))
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
    mayPresentSheet: Bool,
    _ job: @escaping @Sendable (TranslationSession) async throws -> T
  ) async throws -> T {
    let presenter = try await attach()
    let state = HostJob<T>()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      state.continuation = continuation
      model.pending = { session in
        state.sessionStarted = true
        if mayPresentSheet { self.watchSheet(state, presenter: presenter) }
        do {
          state.finish(.success(try await job(session)))
        } catch {
          state.finish(.failure(error))
        }
      }
      var configuration = TranslationSession.Configuration(source: source, target: target)
      if let current = model.configuration, current.source == source, current.target == target {
        configuration = current
        configuration.invalidate()
      }
      model.configuration = configuration
      log("configuration set \(source.minimalIdentifier)→\(target.minimalIdentifier) under \(type(of: presenter))")

      Task { @MainActor in
        try? await Task.sleep(for: Self.sessionTimeout)
        guard !state.sessionStarted, !state.done else { return }
        log("translationTask did not fire within \(Self.sessionTimeout)")
        self.model.pending = nil
        state.finish(.failure(TranslationSessionTimeoutException()))
      }
    }
  }

  /// Rejects the job if Apple's sheet doesn't appear. The sheet (or anything
  /// else) presented above the host's parent disarms the watchdog.
  private func watchSheet<T>(_ state: HostJob<T>, presenter: UIViewController) {
    // Only a presentation that wasn't there when the job started counts as the
    // sheet: one on the host's parent, or a new top-most view controller anywhere
    // (in case Apple presents it from elsewhere).
    let existing = presenter.presentedViewController
    let topAtStart = try? Self.topViewController()
    Task { @MainActor in
      let deadline = ContinuousClock.now + Self.sheetTimeout
      while !state.done {
        if let presented = presenter.presentedViewController, presented !== existing {
          log("sheet presented: \(type(of: presented))")
          return
        }
        if let top = try? Self.topViewController(), top !== topAtStart, top !== presenter,
           !(top is UIAlertController) {
          log("new top-most view controller: \(type(of: top))")
          return
        }
        if ContinuousClock.now >= deadline {
          log("no sheet within \(Self.sheetTimeout); presenter=\(type(of: presenter)) window=\(presenter.view.window != nil)")
          state.finish(.failure(DownloadSheetNotShownException()))
          return
        }
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  /// Attaches the host under the top-most presented view controller, moving it
  /// when modals have come or gone since the last job.
  private func attach() async throws -> UIViewController {
    var top = try Self.topViewController()
    if debugAttachToRoot, let root = Self.keyWindow()?.rootViewController { top = root }
    // Presenting from a view controller mid-transition fails too; wait it out (≤ 1 s).
    for _ in 0..<20 where top.isBeingPresented || top.isBeingDismissed || top.transitionCoordinator != nil {
      try? await Task.sleep(for: .milliseconds(50))
      top = try Self.topViewController()
      if debugAttachToRoot, let root = Self.keyWindow()?.rootViewController { top = root }
    }

    if let controller = hostingController, controller.parent === top, controller.view.window != nil {
      return top
    }
    if let controller = hostingController {
      controller.willMove(toParent: nil)
      controller.view.removeFromSuperview()
      controller.removeFromParent()
    }
    // A fresh controller and no configuration, so `.translationTask` only fires
    // for the configuration set by the next job.
    model.configuration = nil
    let controller = UIHostingController(rootView: TranslationHostView(model: model))
    controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    controller.view.alpha = 0.011
    controller.view.isUserInteractionEnabled = false
    controller.view.backgroundColor = .clear
    top.addChild(controller)
    top.view.addSubview(controller.view)
    controller.didMove(toParent: top)
    hostingController = controller
    log("host attached to \(type(of: top))")
    return top
  }

  /// The key window's root view controller, followed through
  /// `presentedViewController` (skipping ones being dismissed).
  static func topViewController() throws -> UIViewController {
    guard var top = keyWindow()?.rootViewController else { throw TranslationNoWindowException() }
    while let next = top.presentedViewController, !next.isBeingDismissed {
      top = next
    }
    return top
  }

  static func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    return windows.first(where: \.isKeyWindow) ?? windows.first
  }
}

/// One job's continuation, resumed exactly once (by the job or a watchdog).
@MainActor
private final class HostJob<T> {
  var continuation: CheckedContinuation<T, Error>?
  var sessionStarted = false
  private(set) var done = false

  func finish(_ result: Result<T, Error>) {
    guard !done else { return }
    done = true
    continuation?.resume(with: result)
    continuation = nil
  }
}

func log(_ message: String) {
  #if DEBUG
  NSLog("[VisionKitTranslate] %@", message)
  #endif
}

/// Errors from the host itself (not from Apple's session). `download` rethrows
/// these instead of resolving `false`, so the caller can tell them apart.
protocol TranslationHostFailure: Error {}

final class TranslationNoWindowException: Exception, TranslationHostFailure, @unchecked Sendable {
  override var code: String { "ERR_TRANSLATION_NO_WINDOW" }
  override var reason: String { "No key window to host the Translation session" }
}

final class TranslationSessionTimeoutException: Exception, TranslationHostFailure, @unchecked Sendable {
  override var code: String { "ERR_TRANSLATION_SESSION_TIMEOUT" }
  override var reason: String { "Apple Translation did not provide a session in time" }
}

final class DownloadSheetNotShownException: Exception, TranslationHostFailure, @unchecked Sendable {
  override var code: String { "ERR_DOWNLOAD_SHEET_NOT_SHOWN" }
  override var reason: String {
    "Apple's language download sheet could not be presented. Retry when no other sheet or alert is being presented."
  }
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
