#!/usr/bin/env swift

import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: atomic-replace.swift <new-directory> <destination>")
}

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]

guard source.hasPrefix("/"), destination.hasPrefix("/") else {
    fail("source and destination must be absolute paths")
}
guard source != destination else { fail("source and destination must differ") }

func fileType(at path: String) -> mode_t? {
    var info = stat()
    let result = path.withCString { lstat($0, &info) }
    return result == 0 ? info.st_mode & mode_t(S_IFMT) : nil
}

func rejectUnsafeComponents(in path: String, allowMissingLeaf: Bool) {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.contains("."), !components.contains("..") else {
        fail("path traversal components are not allowed: \(path)")
    }

    var current = ""
    let meaningful = components.filter { !$0.isEmpty }
    for (index, component) in meaningful.enumerated() {
        current += "/\(component)"
        if fileType(at: current) == mode_t(S_IFLNK) {
            fail("symlinked path component is not allowed: \(current)")
        }
        if fileType(at: current) == nil,
           !(allowMissingLeaf && index == meaningful.count - 1) {
            fail("path component does not exist: \(current)")
        }
    }
}

rejectUnsafeComponents(in: source, allowMissingLeaf: false)
rejectUnsafeComponents(in: destination, allowMissingLeaf: true)

guard fileType(at: source) == mode_t(S_IFDIR) else {
    fail("source must be a non-symlink directory: \(source)")
}

let destinationType = fileType(at: destination)
if let destinationType, destinationType != mode_t(S_IFDIR) {
    fail("destination must be a non-symlink directory when it exists: \(destination)")
}

let status: Int32
if destinationType == nil {
    status = source.withCString { sourcePointer in
        destination.withCString { destinationPointer in
            rename(sourcePointer, destinationPointer)
        }
    }
} else {
    status = source.withCString { sourcePointer in
        destination.withCString { destinationPointer in
            renameatx_np(
                AT_FDCWD,
                sourcePointer,
                AT_FDCWD,
                destinationPointer,
                UInt32(RENAME_SWAP)
            )
        }
    }
}

guard status == 0 else {
    let message = String(cString: strerror(errno))
    fail("atomic replacement failed: \(message)")
}

// A successful swap leaves the old destination at `source`. The caller owns
// cleanup so it can validate and remove its private staging directory.
