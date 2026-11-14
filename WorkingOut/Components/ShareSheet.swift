import UIKit
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called with `true` only when the user finished an activity that keeps
    /// or sends the file, such as saving to Files or AirDrop. Canceling, and
    /// activities that keep no copy of the file (Copy, Print, Assign to
    /// Contact, Reading List), report `false`.
    var onComplete: ((Bool) -> Void)? = nil

    static let activitiesThatKeepNoFile: Set<UIActivity.ActivityType> = [
        .copyToPasteboard, .print, .assignToContact, .addToReadingList,
    ]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let onComplete {
            controller.completionWithItemsHandler = { activity, completed, _, error in
                let keptFile = activity.map { !Self.activitiesThatKeepNoFile.contains($0) } ?? false
                onComplete(completed && error == nil && keptFile)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
