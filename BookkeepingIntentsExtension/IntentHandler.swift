import Intents

final class IntentHandler: INExtension, OpenRecordLegacyIntentHandling {
    override func handler(for intent: INIntent) -> Any {
        self
    }

    func handle(intent: OpenRecordLegacyIntent, completion: @escaping (OpenRecordLegacyIntentResponse) -> Void) {
        let defaults = UserDefaults(suiteName: "group.com.assetlife.shortcuts")
        defaults?.removeObject(forKey: "pendingRecordParams")
        defaults?.removeObject(forKey: "pendingRecordImagePath")
        defaults?.set("addRecord", forKey: "pendingShortcutAction")
        defaults?.synchronize()

        let response = OpenRecordLegacyIntentResponse(
            code: .continueInApp,
            userActivity: nil
        )
        completion(response)
    }
}
