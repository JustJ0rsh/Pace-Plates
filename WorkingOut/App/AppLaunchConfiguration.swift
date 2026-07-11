import Foundation

struct AppLaunchConfiguration {
    static let current = AppLaunchConfiguration(processInfo: .processInfo)

    enum UITestStartTab: String {
        case home
        case workouts
        case ai
        case runs
        case weight

        var selectionValue: Int {
            switch self {
            case .home: return 0
            case .workouts: return 1
            case .ai: return 2
            case .runs: return 3
            case .weight: return 4
            }
        }
    }

    let isUITest: Bool
    let fixtureName: String?
    let shouldResetState: Bool
    let startTab: UITestStartTab?

    init(processInfo: ProcessInfo) {
        let environment = processInfo.environment
        let arguments = processInfo.arguments

        let hasUITestFlag = environment["UITEST_MODE"] == "1"
            || arguments.contains("-ui_testing")
            || arguments.contains("-FASTLANE_SNAPSHOT")

        isUITest = hasUITestFlag
        fixtureName = environment["UITEST_FIXTURE"]
        shouldResetState = environment["UITEST_RESET_STATE"] == "1"
        startTab = environment["UITEST_START_TAB"].flatMap(UITestStartTab.init(rawValue:))
    }

    var shouldSkipAutomationSideEffects: Bool {
        isUITest
    }

    var usesIsolatedStore: Bool {
        isUITest
    }

    var usesCoreTabsFixture: Bool {
        fixtureName == "core_tabs"
    }

    var initialTabSelection: Int {
        startTab?.selectionValue ?? UITestStartTab.home.selectionValue
    }

    var stubWeatherSummary: WeatherSummary? {
        guard usesCoreTabsFixture else { return nil }
        return WeatherSummary(
            temperatureC: 18,
            condition: "Clear",
            symbolName: "sun.max.fill"
        )
    }

    func prepareUserDefaults(bundleIdentifier: String?) {
        guard isUITest else { return }

        if shouldResetState, let bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        let defaults: [String: Any] = [
            "didShowTutorial": true,
            "didCompleteProfileSetup": true,
            "didCompleteRunAssistantOnboarding": true,
            "age": 30,
            "heightValue": 70.0,
            "heightUnit": "in",
            "measurementSystem": "imperial",
            "weightUnit": "lbs",
            "distanceUnit": "mi",
            "targetWeight": 180.0,
            "weightGoal": "maintain",
            "sex": "male",
            "experienceLevel": "experienced",
            AppTheme.storageKey: AppThemeOption.appDefault.rawValue,
            "showVitalsOnHome": false,
            WearableDevicePreference.storageKey: WearableDevicePreference.none.rawValue,
            "enableWeeklyWeightReminder": false,
            "enableBackgroundRunTracking": false,
            "runsPendingHealthImport": false,
        ]

        for (key, value) in defaults {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}
