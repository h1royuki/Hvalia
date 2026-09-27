import Foundation
import CoreFoundation
import CryptoKit

public enum OverlayPatch {
    public static let keys = ["Show5GSwitch", "Enable5GAutoByDefault", "Enable5GByDefault"]
    public static func apply(_ data: Data) throws -> Data {
        guard data.count <= 1_048_576,
              var dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let countries = dictionary["SupportedCountryIds"] as? [String], countries.contains("257"), countries.contains("com.apple.Belarus"),
              let iso = dictionary["ISOAlpha2CountryCode"] as? [String], iso == ["by"] else {
            throw BridgeError.message("Оригинал не соответствует проверенному профилю Беларуси. Изменение остановлено.")
        }
        for key in keys {
            guard let value = dictionary[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
                throw BridgeError.message("Неожиданный тип настройки \(key). Оригинал сохранён.")
            }
            dictionary[key] = true
        }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    }
    public static func isEnabled(_ data: Data) -> Bool {
        guard let dictionary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return false }
        return keys.allSatisfy { (dictionary[$0] as? Bool) == true }
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public enum PrivateStorage {
    public static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    public static func write(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pending")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw BridgeError.message("Не удалось создать резервный файл.") }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
            if rename(temp.path, url.path) != 0 { throw BridgeError.message("Не удалось сохранить резервный файл: \(errno).") }
            let descriptor = open(url.deletingLastPathComponent().path, O_RDONLY)
            if descriptor >= 0 { _ = fsync(descriptor); close(descriptor) }
        } catch { try? FileManager.default.removeItem(at: temp); throw error }
    }
}
