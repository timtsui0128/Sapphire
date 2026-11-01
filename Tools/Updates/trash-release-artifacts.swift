// Filesystem-only cleanup. Does not control Finder or empty the user's Trash.
import Foundation

for path in CommandLine.arguments.dropFirst() {
    do {
        var destination: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &destination)
        let record = ["source": path, "trash": destination?.path ?? ""]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } catch {
        FileHandle.standardError.write(Data("Could not trash \(path): \(error)\n".utf8))
        exit(1)
    }
}
