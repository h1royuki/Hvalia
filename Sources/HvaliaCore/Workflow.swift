import Foundation

public enum ConnectionState: String, Codable, Sendable { case ready, needsTrust, locked, unavailable }
public struct DeviceConnection: Codable, Sendable { public let id: String; public let state: ConnectionState }
public struct ConnectionSnapshot: Codable, Sendable { public let devices: [Phone]; public let connections: [DeviceConnection] }
public enum FlowMode: String, Codable { case activate, restore, recover }
public enum FlowStep: String, Codable { case home, connect, trust, review, backups, prepare, working, restart, settings, network, result, recovery, about }
public struct WizardState: Codable {
    public var mode: FlowMode = .activate
    public var step: FlowStep = .home
    public var phoneID = ""
    public var lineID = ""
    public var backupID: UUID?
    public var operationStartedAt: Date?
    public var operationID: UUID?
    public var sawDisconnect = false
    public var restartConfirmed = false
    public var checkedNetwork = false
    public var confirmedNR = false
    public init() {}
    public mutating func observeConnection(readyIDs: [String], attachedIDs: [String]) {
        if step == .connect || step == .trust {
            if !phoneID.isEmpty && readyIDs.contains(phoneID) { step = mode == .activate ? .review : (mode == .restore ? .backups : .recovery) }
            else if !phoneID.isEmpty && attachedIDs.contains(phoneID) { step = .trust }
        }
        if step == .restart {
            if !attachedIDs.contains(phoneID) { sawDisconnect = true }
            if readyIDs.contains(phoneID) && restartConfirmed { step = mode == .activate ? .settings : .result }
        }
    }
}

public enum BackupEligibility {
    public static func matches(_ session: SessionRecord, phone: Phone) -> Bool {
        session.originalSHA256 != nil && !session.phase.isUnfinished && session.phone.id == phone.id &&
        session.phone.productType == phone.productType && session.phone.hardwareModel == phone.hardwareModel &&
        session.phone.productVersion == phone.productVersion && session.phone.buildVersion == phone.buildVersion &&
        Compatibility.validLeaf(session.overlayLeaf ?? Compatibility.leaf, phone: phone) && Compatibility.deviceCheck(phone) == .eligible
    }
    public static func firstOriginal(_ sessions: [SessionRecord], phone: Phone) -> UUID? {
        sessions.filter { matches($0, phone: phone) && $0.previousSessionID == nil }.min(by: { $0.created < $1.created })?.id
    }
}
