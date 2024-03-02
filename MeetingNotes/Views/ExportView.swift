import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// A toolbar button to coordinate merging documents.
@available(macOS 14.0, iOS 17.0, *)
struct ExportView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var isExporting: Bool = false
    @State private var importURL: String = ""
    var body: some View {
        Button {
            isExporting = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
        .fileExporter(
            isPresented: $isExporting,
            item: document.doc,
            contentTypes: [UTType.automerge],
            defaultFilename: document.id.description
        ) { result in
            switch result {
            case let .success(fileURLToWrite):
                precondition(fileURLToWrite.isFileURL)
                // gain access to the directory
                if fileURLToWrite.startAccessingSecurityScopedResource() {
                    defer { fileURLToWrite.stopAccessingSecurityScopedResource() }
                    let snapshot = document.doc.save()
                    do {
                        try snapshot.write(to: fileURLToWrite, options: .atomic)
                        Logger.document
                            .info("Wrote automerge doc to file \(fileURLToWrite.absoluteString, privacy: .public)")
                    } catch {
                        Logger.document
                            .error(
                                "Error attempting to merge file: \(error.localizedDescription, privacy: .public)"
                            )
                    }
                }
            case let .failure(failure):
                Logger.document
                    .error("Error exporting file: \(failure, privacy: .public)")
            }
        }
    }
}

/// Preview of the merge toolbar button.
@available(macOS 14.0, iOS 17.0, *)
struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView(document: MeetingNotesDocument.sample())
    }
}

// let nowString = Date().formatted(
//    .iso8601
//        .year()
//        .month()
//        .day()
//        .timeZone(separator: .omitted)
//        .time(includingFractionalSeconds: false)
//        .timeSeparator(.omitted)
// )
//
// do {
//    let codedData = try encoder.encode(collectedMetrics)
//    let fileURL = try FileManager.default
//        .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
//        .appending(path: "capturedmetrics_\(nowString)")
//        .appendingPathExtension("json")
//
//    try codedData.write(to: fileURL)
// } catch {
//    print(error.localizedDescription)
// }
