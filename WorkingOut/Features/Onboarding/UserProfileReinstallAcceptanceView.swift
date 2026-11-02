#if DEBUG
import SwiftUI

/// Real Security APIs, restricted to the existing UUID-scoped synthetic service.
/// The caller can uninstall/reinstall the app between seed and verify phases.
struct UserProfileReinstallAcceptanceView: View {
    @State private var result = "Checking synthetic profile…"
    @State private var needsReview = false
    @State private var showingReview = false
    var body: some View {
        #if targetEnvironment(simulator)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(result).textSelection(.enabled).accessibilityIdentifier("profile.lifecycle.result")
                if needsReview { Button("Review Profile") { showingReview = true }.accessibilityIdentifier("profile.units.review") }
            }.padding()
        }
        .task { run() }
        .sheet(isPresented: $showingReview) { TutorialView { showingReview = false } }
        #else
        Text("Synthetic profile checks require Simulator.")
        #endif
    }

    #if targetEnvironment(simulator)
    @MainActor private func run() {
        guard AppLaunchConfiguration.current.usesNaturalProfileForTesting else { result = "Profile lifecycle failed: synthetic scope required"; return }
        let phase = ProcessInfo.processInfo.environment["UITEST_PROFILE_PHASE"] ?? "verify-metric"
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let unitKeys = ["measurementSystem", "heightUnit", "weightUnit", "distanceUnit"]
        let defaultsWereMissing = unitKeys.allSatisfy { defaults.persistentDomain(forName: domain)?[$0] == nil }
        let metric = phase.contains("metric") || phase.contains("unknown")
        let unknown = phase.contains("unknown")
        let legacy = phase.contains("legacy")
        if phase.hasPrefix("seed-") {
            for key in unitKeys + ["profileMeasurementsNeedUnitReview", "age", "sex", "heightValue", "targetWeight"] { defaults.removeObject(forKey: key) }
            if legacy && !unknown {
                defaults.set(metric ? "metric" : "imperial", forKey: "measurementSystem")
                defaults.set(metric ? "cm" : "in", forKey: "heightUnit")
                defaults.set(metric ? "kg" : "lbs", forKey: "weightUnit")
            }
            let profile = UserProfileStore.Profile(age: 37, sex: "male", heightValue: metric ? 180 : 70, targetWeight: metric ? 80 : 165,
                heightUnit: legacy ? nil : metric ? "cm" : "in", weightUnit: legacy ? nil : metric ? "kg" : "lbs")
            guard UserProfileStore.seedSyntheticProfileForTesting(profile) else { result = "Profile lifecycle failed: synthetic seed write"; return }
        }
        let store = UserProfileStore.shared
        store.reloadSyntheticProfileForTesting()
        guard let raw = UserProfileStore.syntheticProfileForTesting(), store.isAvailable else {
            result = "Profile lifecycle failed: actual synthetic Keychain item unavailable"; return
        }
        let valid: Bool
        if unknown {
            valid = store.needsUnitReview && !store.hasBasicProfile && store.heightValue == 0 && store.targetWeight == 0
                && raw.heightValue == 180 && raw.targetWeight == 80 && raw.heightUnit == nil && raw.weightUnit == nil
                && raw.unitReviewRequired == true
        } else {
            valid = store.hasBasicProfile && !store.needsUnitReview && store.heightValue == (metric ? 180 : 70)
                && store.targetWeight == (metric ? 80 : 165) && raw.heightUnit == (metric ? "cm" : "in") && raw.weightUnit == (metric ? "kg" : "lbs")
                && defaults.string(forKey: "measurementSystem") == (metric ? "metric" : "imperial")
                && defaults.string(forKey: "heightUnit") == (metric ? "cm" : "in") && defaults.string(forKey: "weightUnit") == (metric ? "kg" : "lbs")
        }
        needsReview = store.needsUnitReview
        result = "Profile lifecycle \(valid ? "passed" : "failed"): phase=\(phase);defaultsWereMissing=\(defaultsWereMissing);review=\(store.needsUnitReview);height=\(store.heightValue);target=\(store.targetWeight);heightUnit=\(defaults.string(forKey: "heightUnit") ?? "unset");weightUnit=\(defaults.string(forKey: "weightUnit") ?? "unset");" + store.naturalProfileTestStatus
    }
    #endif
}
#endif
