import UIKit
import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called with `true` only when the user finished an activity, such as
    /// saving to Files or sending with AirDrop. Canceling reports `false`.
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let onComplete {
            controller.completionWithItemsHandler = { _, completed, _, error in
                onComplete(completed && error == nil)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
