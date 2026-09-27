import Foundation

public struct CarrierLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String { slot + ":" + mcc + mnc }
    public let slot: String
    public let mcc: String
    public let mnc: String
    public let bundleID: String
    public let bundleVersion: String
    public init(slot: String, mcc: String, mnc: String, bundleID: String, bundleVersion: String) {
        self.slot = slot; self.mcc = mcc; self.mnc = mnc; self.bundleID = bundleID; self.bundleVersion = bundleVersion
    }
    public var operatorName: String {
        switch mcc + mnc { case "25702": return "МТС Беларусь"; case "25701": return "A1 Беларусь"; case "25704": return "life Беларусь"; default: return mcc + "-" + mnc }
    }
    public var isBelarus: Bool { ["25701", "25702", "25704"].contains(mcc + mnc) }
}

public struct Phone: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let productType: String
    public let productVersion: String
    public let buildVersion: String
    public let hardwareModel: String
    public let carriers: [CarrierLine]
    public init(id: String, name: String, productType: String, productVersion: String, buildVersion: String, hardwareModel: String, carriers: [CarrierLine]) {
        self.id = id; self.name = name; self.productType = productType; self.productVersion = productVersion; self.buildVersion = buildVersion; self.hardwareModel = hardwareModel; self.carriers = carriers
    }
    public var displayModel: String { productType == "iPhone15,4" ? "iPhone 15" : productType }
}

public enum Support: Equatable, Sendable { case eligible, diagnosisOnly(String) }
public enum Compatibility {
    public static let overlayDirectory = "/var/mobile/Library/CountryBundles/Overlay"
    public static let leaf = "device+carrier+com.apple.Belarus+D37+72.0.plist"
    public static func check(_ phone: Phone, line: CarrierLine) -> Support {
        guard line.isBelarus else { return .diagnosisOnly("Этот профиль предназначен для операторов Беларуси.") }
        guard (try? candidateLeaf(phone, line: line)) != nil else { return .diagnosisOnly("Не удалось определить профиль Беларуси. Переподключите iPhone.") }
        return deviceCheck(phone)
    }
    public static func deviceCheck(_ phone: Phone) -> Support {
        guard phone.productType.range(of: #"^iPhone[0-9]+,[0-9]+$"#, options: .regularExpression) != nil,
              board(phone) != nil, !phone.productVersion.isEmpty, !phone.buildVersion.isEmpty else {
            return .diagnosisOnly("Не удалось прочитать модель iPhone. Разблокируйте телефон и переподключите его.")
        }
        return .eligible
    }
    public static func board(_ phone: Phone) -> String? {
        let value = phone.hardwareModel.uppercased()
        guard value.range(of: #"^[A-Z][A-Z0-9]{1,12}AP$"#, options: .regularExpression) != nil else { return nil }
        return String(value.dropLast(2))
    }
    /// Expected path, inferred from reported board and carrier version; existence is not assumed.
    public static func candidateLeaf(_ phone: Phone, line: CarrierLine) throws -> String {
        guard line.isBelarus, let board = board(phone),
              line.bundleVersion.range(of: #"^[0-9]{1,3}(\.[0-9]{1,3}){1,3}$"#, options: .regularExpression) != nil else {
            throw BridgeError.message("Не удалось определить имя профиля Беларуси по данным iPhone.")
        }
        return "device+carrier+com.apple.Belarus+\(board)+\(line.bundleVersion).plist"
    }
    public static func validLeaf(_ leaf: String, phone: Phone) -> Bool {
        guard let board = board(phone) else { return false }
        let prefix = "device+carrier+com.apple.Belarus+\(board)+"
        guard leaf.hasPrefix(prefix), leaf.hasSuffix(".plist") else { return false }
        let version = String(leaf.dropFirst(prefix.count).dropLast(6))
        return version.range(of: #"^[0-9]{1,3}(\.[0-9]{1,3}){1,3}$"#, options: .regularExpression) != nil
    }

}

public enum BridgeError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum Phase: String, Codable, Sendable {
    case prepared, booksSaved, exportStarted, originalSaved, installStarted, settingsWritten, restartNeeded, nrConfirmed, restoring, restored, recoveryRequired
    public var isUnfinished: Bool { ![.restartNeeded, .nrConfirmed, .restored].contains(self) }
}
public struct SessionRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var created: Date
    public var phone: Phone
    public var line: CarrierLine
    public var phase: Phase
    public var originalSHA256: String?
    public var patchedSHA256: String?
    public var message: String?
    public var previousSessionID: UUID?
    public var interruptedPhase: Phase?
    public var overlayLeaf: String?
    public init(phone: Phone, line: CarrierLine) { id = UUID(); created = Date(); self.phone = phone; self.line = line; phase = .prepared; overlayLeaf = try? Compatibility.candidateLeaf(phone, line: line) }
}

public struct RadioEvidence: Codable, Equatable, Sendable {
    public var plmn: Bool = false
    public var modemNR: Bool = false
    public var activeNR: Bool = false
    public var endcInterface: Bool = false
    public var supported: Bool = false
    public var ambiguousLines: Bool = false
    public var confirmed: Bool { plmn && modemNR && activeNR && endcInterface && !ambiguousLines }
    public init() {}
    public static func parse(_ text: String, plmn: String, unambiguousDataLine: Bool) -> RadioEvidence {
        var e = RadioEvidence(); e.ambiguousLines = !unambiguousDataLine
        for line in text.split(separator: "\n") {
            if line.contains("Set PLMN to \(plmn)") || line.contains("PLMN: \(plmn)") { e.plmn = true }
            if line.contains("Data System status:"), line.contains("kEX_3GPP_5G"), line.contains("data bearer info: kNRNSA") { e.modemNR = true }
            if line.contains("pdp=0, state=kActive"), line.contains("dataMode = kNRNSA") { e.activeNR = true }
            if line.contains("Set radio type to: endc_sub6"), line.contains("pdp_ip0") { e.endcInterface = true }
            if line.contains("5G(kSupported)"), line.contains("result: k5G") { e.supported = true }
        }
        return e
    }
}
