import Automerge

// upcoming: this file part of the AutomergeUtilities package

public extension Document {
    /// Returns a Boolean value that indicates whether the document is empty.
    func isEmpty() throws -> Bool {
        let x = try self.mapEntries(obj: .ROOT)
        return x.count < 1
    }
}
