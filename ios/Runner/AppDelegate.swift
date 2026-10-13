import Flutter
import StoreKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Set before launch finishes so the tap that opened the app is delivered.
    UNUserNotificationCenter.current().delegate = DailyReminders.shared
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DailyReminders") {
      DailyReminders.shared.attach(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppReview") {
      AppReview.attach(messenger: registrar.messenger())
    }
  }
}

/// App Store rating prompt (Dart side: lib/core/app_review.dart). StoreKit decides whether the
/// prompt really appears (at most three times a year per person) and talks only to Apple.
///
/// Channel `cjw/review`: `request` asks StoreKit in the active window scene; answers whether a
/// scene was there to ask in (not whether the prompt showed: StoreKit never says).
enum AppReview {
  private static var channel: FlutterMethodChannel?

  static func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cjw/review", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "request" else { return result(FlutterMethodNotImplemented) }
      let scene = UIApplication.shared.connectedScenes
        .first { $0.activationState == .foregroundActive } as? UIWindowScene
      guard let scene else { return result(false) }
      if #available(iOS 16.0, *) {
        AppStore.requestReview(in: scene)
      } else {
        SKStoreReviewController.requestReview(in: scene)
      }
      result(true)
    }
    self.channel = channel
  }
}

/// Daily reminders (Dart side: lib/core/reminders.dart). Local notifications
/// only: they are scheduled on the device and nothing leaves it.
///
/// Channel `cjw/reminders`: `status`, `request`, `schedule` (replaces every
/// pending reminder), `cancel`, `pending` and `delivered` (read back, for
/// QA), `openSettings`, `ready` (Dart is listening; returns the route of a
/// tap that launched the app). A tap while Dart is listening is sent back
/// as `open` with the reminder's route.
final class DailyReminders: NSObject, UNUserNotificationCenterDelegate {
  static let shared = DailyReminders()
  private static let prefix = "cjw.reminder."

  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pendingRoute: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cjw/reminders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    switch call.method {
    case "status":
      center.getNotificationSettings { settings in
        let status: String
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: status = "granted"
        case .denied: status = "denied"
        default: status = "notDetermined"
        }
        DispatchQueue.main.async { result(status) }
      }
    case "request":
      // QA runs ask quietly (provisional: no prompt, delivered to Notification Center).
      let quiet = (call.arguments as? [String: Any])?["quiet"] as? Bool ?? false
      let options: UNAuthorizationOptions = quiet ? [.alert, .sound, .provisional] : [.alert, .sound]
      center.requestAuthorization(options: options) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "pending":
      center.getPendingNotificationRequests { pending in
        let items: [[String: Any]] = pending.filter { $0.identifier.hasPrefix(Self.prefix) }.map { request in
          let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
          return Self.describe(request, at: next)
        }
        DispatchQueue.main.async { result(items) }
      }
    case "delivered":
      center.getDeliveredNotifications { delivered in
        let items: [[String: Any]] = delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) }.map {
          Self.describe($0.request, at: $0.date)
        }
        DispatchQueue.main.async { result(items) }
      }
    case "schedule":
      let items = call.arguments as? [[String: Any]] ?? []
      schedule(items, center: center) { result(nil) }
    case "cancel":
      schedule([], center: center) { result(nil) }
    case "openSettings":
      let page: String
      if #available(iOS 16.0, *) {
        page = UIApplication.openNotificationSettingsURLString
      } else {
        page = UIApplication.openSettingsURLString
      }
      if let url = URL(string: page) { UIApplication.shared.open(url) }
      result(nil)
    case "ready":
      dartReady = true
      result(pendingRoute)
      pendingRoute = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// A reminder as Dart reads it back (QA checks what is scheduled and delivered).
  private static func describe(_ request: UNNotificationRequest, at date: Date?) -> [String: Any] {
    [
      "id": String(request.identifier.dropFirst(prefix.count)),
      "title": request.content.title,
      "body": request.content.body,
      "route": request.content.userInfo["route"] as? String ?? "",
      "at": (date?.timeIntervalSince1970 ?? 0) * 1000,
    ]
  }

  /// Replaces the pending reminders with [items] ({id, at (ms since epoch),
  /// title, body, route}); ids are days, so a day keeps one reminder.
  private func schedule(_ items: [[String: Any]], center: UNUserNotificationCenter, done: @escaping () -> Void) {
    let ids = Set(items.compactMap { $0["id"] as? String }.map { Self.prefix + $0 })
    center.getPendingNotificationRequests { pending in
      let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && !ids.contains($0) }
      center.removePendingNotificationRequests(withIdentifiers: stale)
      for item in items {
        guard let id = item["id"] as? String, let at = item["at"] as? NSNumber,
              let title = item["title"] as? String, let body = item["body"] as? String else { continue }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "daily"
        content.userInfo = ["route": item["route"] as? String ?? ""]
        let date = Date(timeIntervalSince1970: at.doubleValue / 1000)
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: trigger))
      }
      DispatchQueue.main.async { done() }
    }
  }

  // The player is already in the game: no banner while it is open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let route = response.notification.request.content.userInfo["route"] as? String ?? ""
    if !route.isEmpty {
      if dartReady, let channel {
        channel.invokeMethod("open", arguments: route)
      } else {
        pendingRoute = route
      }
    }
    completionHandler()
  }
}
