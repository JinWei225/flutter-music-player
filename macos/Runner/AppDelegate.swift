import Cocoa
import CoreSpotlight
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    // mewsic:// links reach the app through Flutter's own open-URL hook.
    addApplicationLifecycleDelegate(LinkRouter.shared)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A Spotlight result was picked. Its identifier is the album's
  /// mewsic:// link, so it is opened like any other link.
  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard userActivity.activityType == CSSearchableItemActionType,
      let id = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
      let url = URL(string: id)
    else {
      return super.application(
        application, continue: userActivity, restorationHandler: restorationHandler)
    }
    LinkRouter.shared.open(url)
    return true
  }
}
