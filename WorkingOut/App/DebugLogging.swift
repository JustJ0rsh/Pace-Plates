import Foundation

/// Module-level shadow of `Swift.print` for the app target.
///
/// The codebase uses `print(...)` as ad-hoc diagnostic logging in ~90 places,
/// including import flows that echo workout titles, exercise names, template
/// identifiers, and route point counts. Because unqualified `print` resolves to
/// this module-scoped overload before `Swift.print`, every existing call site
/// becomes a no-op in Release builds without touching each file, so none of
/// that data reaches the unified system log on customer devices.
///
/// Debug builds keep the original behavior. Use `Swift.print(...)` explicitly
/// if output is ever required in a Release build, or prefer `os.Logger` with
/// `privacy: .private` for anything that must be logged in production.
@inline(__always)
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
    #endif
}
