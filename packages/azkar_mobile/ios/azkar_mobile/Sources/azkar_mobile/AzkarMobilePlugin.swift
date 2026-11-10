import Flutter
import UIKit
import WidgetKit

public class AzkarMobilePlugin: NSObject, FlutterPlugin {
  private var widgetChannel: FlutterMethodChannel?
  private let widgetGroup = "group.com.azkar.azkar"
  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = AzkarMobilePlugin()
    plugin.widgetChannel = FlutterMethodChannel(name: "azkar/home_widget", binaryMessenger: registrar.messenger())
    plugin.installHandler()
    registrar.publish(plugin)
  }
  private func installHandler() {
    widgetChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self,
            let defaults = UserDefaults(suiteName: self.widgetGroup) else {
        result(FlutterError(code: "widget_storage", message: "Widget storage is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "selectRemembranceAccount":
        let account = call.arguments as? String
        if let account = account,
           account.range(of: "^[a-f0-9]{24}$", options: .regularExpression) == nil {
          result(FlutterError(code: "invalid_account", message: "Invalid widget account.", details: nil))
          return
        }
        if account == nil || account != defaults.string(forKey: "remembranceAccount") {
          defaults.removeObject(forKey: "remembrance")
          defaults.removeObject(forKey: "remembranceIndex")
          defaults.set(account, forKey: "remembranceAccount")
          WidgetCenter.shared.reloadTimelines(ofKind: "AzkarRemembranceWidget")
        }
        result(nil)
      case "setBackgroundGeneration":
        defaults.set(call.arguments as? String, forKey: "backgroundGeneration")
        result(nil)
      case "updateBackground":
        guard let arguments = call.arguments as? [String: Any],
              let generation = arguments["generation"] as? String,
              generation == defaults.string(forKey: "backgroundGeneration"),
              let calendar = arguments["calendar"] as? String else { result(nil); return }
        defaults.set(calendar, forKey: "calendar")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarPrayerWidget")
        result(nil)
      case "selectLocation":
        guard let selection = call.arguments as? String else {
          result(FlutterError(code: "invalid_selection", message: "A widget location is required.", details: nil))
          return
        }
        if defaults.string(forKey: "selection") != selection {
          defaults.removeObject(forKey: "calendar")
          defaults.set(selection, forKey: "selection")
          WidgetCenter.shared.reloadTimelines(ofKind: "AzkarPrayerWidget")
        }
        result(nil)
      case "update":
        guard let calendar = call.arguments as? String, calendar.utf8.count <= 100000 else {
          result(FlutterError(code: "invalid_calendar", message: "Invalid widget calendar.", details: nil))
          return
        }
        defaults.set(calendar, forKey: "calendar")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarPrayerWidget")
        result(nil)
      case "clearPrayer":
        defaults.removeObject(forKey: "backgroundGeneration")
        defaults.removeObject(forKey: "calendar")
        defaults.removeObject(forKey: "selection")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarPrayerWidget")
        result(nil)
      case "clear":
        defaults.removeObject(forKey: "backgroundGeneration")
        defaults.removeObject(forKey: "calendar")
        defaults.removeObject(forKey: "selection")
        defaults.removeObject(forKey: "remembrance")
        defaults.removeObject(forKey: "remembranceAccount")
        defaults.removeObject(forKey: "remembranceIndex")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarRemembranceWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarPrayerWidget")
        result(nil)
      case "updateRemembrance":
        guard let content = call.arguments as? String, content.utf8.count <= 600000 else {
          result(FlutterError(code: "invalid_content", message: "Invalid widget content.", details: nil))
          return
        }
        guard let data = content.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let payload = decoded as? [String: Any],
              let account = defaults.string(forKey: "remembranceAccount"),
              payload["version"] as? Int == 2,
              payload["accountFingerprint"] as? String == account else { result(nil); return }
        defaults.set(content, forKey: "remembrance")
        WidgetCenter.shared.reloadTimelines(ofKind: "AzkarRemembranceWidget")
        result(nil)
      case "requestPin", "requestPinRemembrance":
        // iOS exposes widget installation through the Home Screen gallery.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
