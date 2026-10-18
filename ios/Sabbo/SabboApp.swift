import SwiftUI
import UserNotifications

final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    Task {
      let s = await UNUserNotificationCenter.current().notificationSettings()
      if s.authorizationStatus == .authorized {
        await MainActor.run { application.registerForRemoteNotifications() }
      }
    }
    return true
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    UserDefaults.standard.set(
      deviceToken.map { String(format: "%02x", $0) }.joined(), forKey: "apns-token")
    NotificationCenter.default.post(name: Notification.Name("SabboDeviceToken"), object: nil)
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    guard let data = Vault.read(), let session = try? JSONDecoder().decode(Session.self, from: data) else { return [] }
    let recipient = notification.request.content.userInfo["recipient"] as? String
    guard recipient == nil || recipient == session.user_id else { return [] }
    return [.banner, .sound, .list]
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    if let aid = response.notification.request.content.userInfo["assignment_id"] as? String {
      UserDefaults.standard.set(aid, forKey: "notification-assignment")
      let info = response.notification.request.content.userInfo
      UserDefaults.standard.set(info["destination"] as? String, forKey: "notification-destination")
      UserDefaults.standard.set(info["recipient"] as? String, forKey: "notification-recipient")
      await MainActor.run {
        NotificationCenter.default.post(name: Notification.Name("SabboPush"), object: nil)
      }
    }
  }
}
@main struct SabboApp: App {
  @UIApplicationDelegateAdaptor(PushDelegate.self) var delegate
  @StateObject private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      SabboRoot().environmentObject(model).onAppear {
        #if targetEnvironment(macCatalyst)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
          scene.sizeRestrictions?.minimumSize = CGSize(width: 820, height: 640)
        }
        #endif
      }.onReceive(
        NotificationCenter.default.publisher(for: Notification.Name("SabboDeviceToken"))
      ) { _ in Task { await model.registerDevice() } }
    }
  }
}
