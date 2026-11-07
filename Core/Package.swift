import Foundation

// Read package parts in memory; never extract untrusted archive paths.
final class Package {
    private let parts: [String: Data]
    private static let byteLimit = 256 * 1024 * 1024
    private static let entryLimit = 4096

    init(url: URL) throws {
        guard let reader = archive_read_new() else { throw ModelError.invalid }
        defer { archive_read_free(reader) }
        archive_read_support_format_zip(reader)
        archive_read_support_filter_all(reader)
        guard archive_read_open_filename(reader, url.path, 65536) == ARCHIVE_OK else {
            throw ModelError.invalid
        }
        var result: [String: Data] = [:]
        var entry: OpaquePointer?
        var total = 0
        var count = 0
        var status = archive_read_next_header(reader, &entry)
        while status == ARCHIVE_OK {
            count += 1
            guard count <= Self.entryLimit, let current = entry,
                  let name = archive_entry_pathname(current) else { throw ModelError.limit }
            let path = String(cString: name)
            guard path.hasSuffix(".model") || path == "_rels/.rels" ||
                    path == Plates.settingsPath || path == Plates.layoutPath else {
                archive_read_data_skip(reader)
                status = archive_read_next_header(reader, &entry)
                continue
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let size = archive_read_data(reader, &buffer, buffer.count)
                guard size >= 0 else { throw ModelError.invalid }
                if size == 0 { break }
                total += size
                guard total <= Self.byteLimit else { throw ModelError.limit }
                data.append(contentsOf: buffer.prefix(size))
            }
            guard result[path] == nil else { throw ModelError.invalid }
            result[path] = data
            status = archive_read_next_header(reader, &entry)
        }
        guard status == ARCHIVE_EOF else { throw ModelError.invalid }
        parts = result
    }

    func data(_ path: String) throws -> Data {
        guard let data = parts[path] else { throw ModelError.missing(path) }
        return data
    }

    func root() throws -> String {
        let parser = Relations()
        try parser.read(data("_rels/.rels"))
        guard let target = parser.target else { throw ModelError.invalid }
        return try resolve(target, from: "")
    }

    func resolve(_ path: String, from parent: String) throws -> String {
        let decoded = path.removingPercentEncoding ?? path
        guard !decoded.contains(":"), !decoded.contains("\\") else { throw ModelError.invalid }
        let base = decoded.hasPrefix("/") ? "" : (parent as NSString).deletingLastPathComponent
        let resolved = (("/" + base + "/" + decoded) as NSString).standardizingPath
        return String(resolved.drop(while: { $0 == "/" }))
    }
}

private final class Relations: NSObject, XMLParserDelegate {
    private(set) var target: String?
    func read(_ data: Data) throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw ModelError.invalid }
    }
    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "Relationship", attributes["Type"]?.hasSuffix("/3dmodel") == true,
           attributes["TargetMode"] != "External" { target = attributes["Target"] }
    }
}

enum ModelError: LocalizedError {
    case invalid, limit, missing(String)
    var errorDescription: String? {
        switch self {
        case .invalid: return "The 3MF model is invalid or unsupported."
        case .limit: return "This model exceeds the preview size limit."
        case .missing(let path): return "Missing model part: \(path)"
        }
    }
}
