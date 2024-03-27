import struct Foundation.TimeInterval

extension TimeInterval {
    /// Returns a time interval from the number of milliseconds you provide.
    /// - Parameter value: The number of milliseconds.
    static func milliseconds(_ value: Int) -> Self {
        0.001 * Double(value)
    }
}
