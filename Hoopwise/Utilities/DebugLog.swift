import Foundation

/// Debug-only logging utility. All output is stripped from Release builds.
/// Usage: `debugLog("message")` instead of `print("message")`
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print(output, terminator: terminator)
    #endif
}
