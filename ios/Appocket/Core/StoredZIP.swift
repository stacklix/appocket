import Foundation

// The publishing tool emits ZIP_STORED archives. No third-party decompressor or zip bombs.
// Reject all other formats, traversal, duplicate entries, symlinks and size mismatches.
enum StoredZIP {
    static func extract(_ data: Data, to directory: URL) throws {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset + length <= bytes.count else { throw ModuleError.invalid("压缩包已截断") }
            return (0..<length).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        var offset = 0, total = 0
        var names = Set<String>()
        while try number(offset, 4) == 0x04034b50 {
            let flags = try number(offset + 6, 2), compression = try number(offset + 8, 2)
            let size = try number(offset + 18, 4), unpacked = try number(offset + 22, 4)
            let nameLength = try number(offset + 26, 2), extraLength = try number(offset + 28, 2)
            let start = offset + 30, body = start + nameLength + extraLength
            guard flags & ~0x0800 == 0, compression == 0, size == unpacked, nameLength > 0,
                  body <= bytes.count, size <= bytes.count - body, total + size <= 50 * 1024 * 1024,
                  names.count < 2000, let name = String(bytes: bytes[start..<(start + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                  name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  names.insert(name).inserted else { throw ModuleError.invalid("不安全或不支持的 ZIP 包") }
            let output = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes[body..<(body + size)]).write(to: output, options: .atomic)
            total += size; offset = body + size
        }
        // Validate central-directory metadata against local entries, reject symlinks.
        var centralNames = Set<String>()
        while try number(offset, 4) == 0x02014b50 {
            let nameLength = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let attrs = try number(offset + 38, 4), end = offset + 46 + nameLength + extra + comment
            guard end <= bytes.count, (attrs >> 16) & 0xf000 != 0xa000,
                  let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8),
                  names.contains(name), centralNames.insert(name).inserted else { throw ModuleError.invalid("ZIP 目录无效") }
            offset = end
        }
        guard try number(offset, 4) == 0x06054b50, try number(offset + 8, 2) == names.count,
              try number(offset + 10, 2) == names.count, names == centralNames, !names.isEmpty,
              offset + 22 + (try number(offset + 20, 2)) == bytes.count else { throw ModuleError.invalid("ZIP 结尾无效") }
    }
}
