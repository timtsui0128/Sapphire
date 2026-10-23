//
//  PublicQuarantineAttribute.swift
//  Sapphire
//
//  Preserve download quarantine when public builds extract an archive.
//

#if !SAPPHIRE_FULL_BUILD
import Darwin
import Foundation
import OSLog

enum QuarantineAttribute {
    private static let attributeName = "com.apple.quarantine"
    private static let logger = Logger(subsystem: "com.cshariq.sapphire", category: "ArchiveQuarantine")

    /// Existing quarantine is retained verbatim; absent source quarantine never removes it.
    static func copy(from sources: [URL], to destination: URL, recursively: Bool) {
        guard destination.isFileURL, let value = sources.lazy.compactMap(readQuarantine).first else { return }
        let descriptor = open(destination.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            logger.error("Could not open extracted item to preserve quarantine (errno \(errno)).")
            return
        }
        defer { close(descriptor) }
        apply(value, to: descriptor, recursively: recursively)
    }

    private static func readQuarantine(_ source: URL) -> Data? {
        guard source.isFileURL else { return nil }
        let length = getxattr(source.path, attributeName, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let count = data.withUnsafeMutableBytes {
            getxattr(source.path, attributeName, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        guard count == length else { return nil }
        return data
    }

    private static func apply(_ value: Data, to descriptor: Int32, recursively: Bool) {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { return }
        let kind = attributes.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else { return }

        let result = value.withUnsafeBytes {
            fsetxattr(descriptor, attributeName, $0.baseAddress, value.count, 0, XATTR_CREATE)
        }
        if result != 0 && errno != EEXIST {
            logger.error("Could not preserve quarantine on an extracted item (errno \(errno)).")
        }
        guard recursively, kind == S_IFDIR else { return }

        // Anchor traversal to the opened directory. A renamed/replaced path cannot redirect
        // descendant writes, and O_NOFOLLOW refuses symlinks even if one appears during a race.
        let scanDescriptor = dup(descriptor)
        guard scanDescriptor >= 0 else { return }
        guard let directory = fdopendir(scanDescriptor) else {
            close(scanDescriptor)
            return
        }
        defer { closedir(directory) }
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            var childAttributes = stat()
            guard fstatat(descriptor, name, &childAttributes, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let childKind = childAttributes.st_mode & S_IFMT
            guard childKind == S_IFREG || childKind == S_IFDIR else { continue }
            let child = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard child >= 0 else {
                logger.error("Could not open an extracted child to preserve quarantine (errno \(errno)).")
                continue
            }
            apply(value, to: child, recursively: true)
            close(child)
        }
    }
}
#endif
