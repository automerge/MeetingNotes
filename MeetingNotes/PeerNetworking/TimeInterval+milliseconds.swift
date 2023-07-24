import Foundation

extension TimeInterval {
    /// Returns a time interval from the number of milliseconds you provide.
    /// - Parameter value: The number of milliseconds.
    static func milliseconds(_ value: Int) -> Self {
        return 0.001 * Double(value)
    }
}
