import Foundation
import HvaliaCore

func fixture(enabled: Bool = false) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: ["SupportedCountryIds": ["257", "com.apple.Belarus"], "ISOAlpha2CountryCode": ["by"], "CountryName": "Belarus", "Show5GSwitch": enabled, "Enable5GAutoByDefault": enabled, "Enable5GByDefault": enabled, "SupportsNRNSAInboundRoaming": false, "ShowHighDataModeSwitch": false, "EmergencyCalling": ["EmergencyNumbers": [["Number": "112", "PreferredEmergencyNumber": true]]]], format: .binary, options: 0)
}
let line = CarrierLine(slot: "kOne", mcc: "257", mnc: "02", bundleID: "com.apple.MTS_by", bundleVersion: "72.0")
let phone = Phone(id: "SYNTHETIC-TEST-DEVICE", name: "Test", productType: "iPhone15,4", productVersion: "27.0", buildVersion: "24A437", hardwareModel: "D37AP", carriers: [line])

final class CoreTests {
    func testPatchOnlyThreeKeys() throws {
        let original = try fixture(), result = try OverlayPatch.apply(original)
        var a = try XCTUnwrap(PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any])
        let b = try XCTUnwrap(PropertyListSerialization.propertyList(from: result, format: nil) as? [String: Any])
        for key in OverlayPatch.keys { a[key] = true }
        XCTAssertEqual(a as NSDictionary, b as NSDictionary)
        XCTAssertTrue(OverlayPatch.isEnabled(result))
    }
    func testRejectsIntegerAndForeignCountry() throws {
        var d = try XCTUnwrap(PropertyListSerialization.propertyList(from: fixture(), format: nil) as? [String: Any])
        d["Show5GSwitch"] = 1
        XCTAssertThrowsError(try OverlayPatch.apply(PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)))
        d["Show5GSwitch"] = false; d["ISOAlpha2CountryCode"] = ["ru"]
        XCTAssertThrowsError(try OverlayPatch.apply(PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)))
    }
    func testCompatibilityFailsClosed() {
        XCTAssertEqual(Compatibility.check(phone, line: line), .eligible)
        for mnc in ["01", "04"] { XCTAssertEqual(Compatibility.check(phone, line: CarrierLine(slot: "kOne", mcc: "257", mnc: mnc, bundleID: line.bundleID, bundleVersion: "72.0")), .eligible) }
        XCTAssertNotEqual(Compatibility.check(phone, line: CarrierLine(slot: "kTwo", mcc: "250", mnc: "01", bundleID: "com.apple.MTS_ru", bundleVersion: "72.0")), .eligible)
        let changed = Phone(id: phone.id, name: "Test", productType: phone.productType, productVersion: "27.0", buildVersion: "DIFFERENT", hardwareModel: phone.hardwareModel, carriers: [line])
        XCTAssertEqual(Compatibility.check(changed, line: line), .eligible)
    }
    func testDynamicProfilesAndPathValidation() throws {
        let carrier = CarrierLine(slot: "kTwo", mcc: "257", mnc: "02", bundleID: "com.apple.MTS_by", bundleVersion: "70.0")
        let device = Phone(id: phone.id, name: "Test", productType: phone.productType, productVersion: "26.6.2", buildVersion: "23G90", hardwareModel: "D37AP", carriers: [carrier])
        XCTAssertEqual(Compatibility.check(device, line: carrier), .eligible)
        let leaf = try Compatibility.candidateLeaf(device, line: carrier)
        XCTAssertEqual(leaf, "device+carrier+com.apple.Belarus+D37+70.0.plist")
        XCTAssertTrue(Compatibility.validLeaf(leaf, phone: device))
        XCTAssertFalse(Compatibility.validLeaf("../" + leaf, phone: device))
        XCTAssertFalse(Compatibility.validLeaf(leaf.replacingOccurrences(of: "D37", with: "D74"), phone: device))
        let invalid = CarrierLine(slot: "kTwo", mcc: "257", mnc: "02", bundleID: "synthetic", bundleVersion: "70.0/../../bad")
        XCTAssertThrowsError(try Compatibility.candidateLeaf(device, line: invalid))
        XCTAssertTrue(TransferPlan(export: true, leaf: leaf).ids.last!.hasSuffix(leaf))
        XCTAssertTrue(TransferPlan(export: false, leaf: leaf).destinations.last!.hasSuffix(leaf))
    }
    func testWizardTransitionsAndPersistence() throws {
        var wizard = WizardState(); wizard.step = .connect; wizard.phoneID = phone.id
        wizard.observeConnection(readyIDs: [], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .trust)
        wizard.observeConnection(readyIDs: [phone.id], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .review)
        wizard.mode = .restore; wizard.step = .connect
        wizard.observeConnection(readyIDs: [phone.id], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .backups)
        wizard.step = .restart
        wizard.observeConnection(readyIDs: [], attachedIDs: []); XCTAssertTrue(wizard.sawDisconnect)
        wizard.observeConnection(readyIDs: [phone.id], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .restart)
        wizard.restartConfirmed = true
        let saved = try JSONEncoder().encode(wizard)
        wizard = try JSONDecoder().decode(WizardState.self, from: saved)
        wizard.observeConnection(readyIDs: [phone.id], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .result)
        wizard.mode = .activate; wizard.step = .restart
        wizard.observeConnection(readyIDs: ["OTHER"], attachedIDs: ["OTHER"]); XCTAssertEqual(wizard.step, .restart)
        wizard.observeConnection(readyIDs: [phone.id], attachedIDs: [phone.id]); XCTAssertEqual(wizard.step, .settings)
        let connection = try JSONDecoder().decode(ConnectionSnapshot.self, from: Data("{\"devices\":[],\"connections\":[{\"id\":\"test\",\"state\":\"locked\"}]}".utf8))
        XCTAssertEqual(connection.connections.first?.state, .locked)
    }
    func testLegacyBackupsAndEligibility() throws {
        var session = SessionRecord(phone: phone, line: line); session.phase = .restartNeeded; session.originalSHA256 = "synthetic"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "overlayLeaf")
        let old = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(BackupEligibility.matches(old, phone: phone))
        XCTAssertEqual(BackupEligibility.firstOriginal([old], phone: phone), old.id)
        session.overlayLeaf = "unknown.plist"; XCTAssertFalse(BackupEligibility.matches(session, phone: phone))
        session.overlayLeaf = Compatibility.leaf; session.phase = .recoveryRequired
        XCTAssertFalse(BackupEligibility.matches(session, phone: phone))
    }
    func testOnlyActualRadioEvidenceConfirms() {
        let log = "Set PLMN to 257-02\nData System status: kEX_3GPP_5G data bearer info: kNRNSA\npdp=0, state=kActive dataMode = kNRNSA\nSet radio type to: endc_sub6 on pdp_ip0"
        XCTAssertTrue(RadioEvidence.parse(log, plmn: "257-02", unambiguousDataLine: true).confirmed)
        XCTAssertFalse(RadioEvidence.parse(log, plmn: "257-02", unambiguousDataLine: false).confirmed)
        XCTAssertFalse(RadioEvidence.parse(log, plmn: "250-01", unambiguousDataLine: true).confirmed)
        XCTAssertFalse(RadioEvidence.parse("5G(kSupported) result: k5G NRARFCN 12345 5G On", plmn: "257-02", unambiguousDataLine: true).confirmed)
    }
    func testJSONUsesLastResultAndZIPRoundTrip() throws {
        let parsed = try JSONOutput.parse(Data("framework chatter\n{\"ok\":false}\n{\"ok\":true}\n".utf8))
        XCTAssertEqual(parsed["ok"] as? Bool, true)
        XCTAssertEqual(StreamingArchive.crc32(Data("123456789".utf8)), 0xcbf43926)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try PrivateStorage.directory(temp); defer { try? FileManager.default.removeItem(at: temp) }
        let archive = temp.appendingPathComponent("payload.zip")
        try StreamingArchive.make(payload: Data("synthetic".utf8)).write(to: archive)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-t", archive.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); XCTAssertEqual(p.terminationStatus, 0)
        let plan = TransferPlan(export: false)
        XCTAssertFalse(plan.moveConfirmed(in: "fileCompleteMessages: 2"))
        XCTAssertFalse(plan.moveConfirmed(in: "Airlock moved /wrong/payload to <private>"))
        XCTAssertTrue(plan.moveConfirmed(in: "Airlock moved /var/mobile/Media/Airlock/Book/../../\(plan.source)/payload to <private>"))
    }
    func testOriginalIntegrityAndCorruptJournal() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = try SessionStore(root: temp); var session = SessionRecord(phone: phone, line: line)
        let bytes = try fixture(); try store.save(session); try store.saveOriginal(bytes, session: &session)
        XCTAssertEqual(try store.original(session), bytes)
        try Data("changed".utf8).write(to: store.directory(session.id).appendingPathComponent("original-second-copy.plist"))
        XCTAssertThrowsError(try store.original(session))
        try Data("broken".utf8).write(to: store.directory(session.id).appendingPathComponent("session.json"))
        XCTAssertThrowsError(try store.all())
    }
}

final class FakeLog: EventLog {
    let backend: FakeBackend
    init(_ backend: FakeBackend) { self.backend = backend }
    func read() throws -> String { "Airlock moved /var/mobile/Media/Airlock/Book/\(backend.ids.last ?? "") to <private>" }
    func stop() {}
}
final class FakeBackend: BridgeBackend {
    var calls: [String] = []
    var ids: [String] = []
    var syncs = 0
    var fail = ""
    var bytes = try! fixture()
    var beforeSync: ((Int) throws -> Void)?
    var connected = phone
    func devices() throws -> [Phone] { [connected] }
    func device(_ command: String, _ phone: Phone, _ args: [String]) throws -> [String: Any] {
        calls.append(command)
        if fail == command || fail == "install-stage" && command == "stage" && syncs == 1 { return ["ok": false, "afcError": 10] }
        if command == "read-owned" { try bytes.write(to: URL(fileURLWithPath: args[1])) }
        return ["ok": true]
    }
    func sync(_ phone: Phone, ids: [String], destinations: [String]) throws {
        try beforeSync?(syncs + 1); self.ids = ids; syncs += 1
        if fail == "sync" { throw BridgeError.message("simulated interruption") }
    }
    func capture(_ phone: Phone, file: URL) throws -> EventLog { FakeLog(self) }
}
final class TransactionTests {
    func withStore(_ body: (SessionStore) throws -> Void) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try body(SessionStore(root: temp))
    }
    func testOriginalDurableBeforeSecondSyncAndSuccessfulRollback() throws {
        try withStore { store in
            let fake = FakeBackend()
            fake.beforeSync = { count in if count == 2 { let saved = try XCTUnwrap(store.all().first); XCTAssertEqual(try store.original(saved), fake.bytes) } }
            let result = try Transaction(store: store, backend: fake).apply(phone: phone, line: line)
            XCTAssertEqual(result.phase, .restartNeeded); XCTAssertEqual(fake.syncs, 2)
            XCTAssertEqual(fake.calls.filter { $0 == "full-restore" }.count, 2)
            let original = fake.bytes; fake.beforeSync = nil; fake.bytes = try fixture(enabled: true)
            let rollback = try Transaction(store: store, backend: fake).apply(phone: phone, line: line, restoring: result)
            XCTAssertEqual(rollback.phase, .restored)
            XCTAssertEqual(try Data(contentsOf: store.directory(rollback.id).appendingPathComponent("replacement.plist")), original)
        }
    }
    func testFailureStopsAndBlocksAnotherMutation() throws {
        for failure in ["snapshot-books", "full-snapshot", "full-verify", "stage", "sync", "read-owned", "full-restore", "cleanup-owned", "install-stage", "payload-absent"] {
            try withStore { store in
                let fake = FakeBackend(); fake.fail = failure
                XCTAssertThrowsError(try Transaction(store: store, backend: fake).apply(phone: phone, line: line), failure)
                XCTAssertEqual(try store.all().first?.phase, .recoveryRequired, failure)
                let before = fake.calls.count
                XCTAssertThrowsError(try Transaction(store: store, backend: fake).apply(phone: phone, line: line))
                XCTAssertEqual(fake.calls.count, before)
                if failure == "read-owned" || failure == "full-restore" || failure == "cleanup-owned" { XCTAssertEqual(fake.syncs, 1) }
            }
        }
    }
    func testInvalidOverlayIsReturnedUnchanged() throws {
        try withStore { store in
            let fake = FakeBackend(); fake.bytes = Data("unrecognized original".utf8)
            let result = try Transaction(store: store, backend: fake).apply(phone: phone, line: line)
            XCTAssertEqual(result.phase, .restored)
            XCTAssertNotNil(result.message)
            XCTAssertEqual(try Data(contentsOf: store.directory(result.id).appendingPathComponent("replacement.plist")), fake.bytes)
        }
    }
    func testRecoveryBeforeInstallAndRefusalAfterInstall() throws {
        try withStore { store in
            let fake = FakeBackend(); fake.fail = "cleanup-owned"
            XCTAssertThrowsError(try Transaction(store: store, backend: fake).apply(phone: phone, line: line))
            let failed = try XCTUnwrap(store.all().first)
            fake.fail = ""
            let recovered = try Transaction(store: store, backend: fake).recover(failed)
            XCTAssertEqual(recovered.phase, .restored)
            XCTAssertEqual(fake.syncs, 2)
        }
        try withStore { store in
            let fake = FakeBackend(); fake.fail = "payload-absent"
            XCTAssertThrowsError(try Transaction(store: store, backend: fake).apply(phone: phone, line: line))
            let failed = try XCTUnwrap(store.all().first), before = fake.syncs
            fake.fail = ""
            XCTAssertThrowsError(try Transaction(store: store, backend: fake).recover(failed))
            XCTAssertEqual(fake.syncs, before)
        }
    }
    func testAllCarriersAndSIMIndependentRestore() throws {
        for mnc in ["01", "02", "04"] {
            try withStore { store in
                let carrier = CarrierLine(slot: "kOne", mcc: "257", mnc: mnc, bundleID: "synthetic.operator", bundleVersion: "99.0")
                let target = Phone(id: phone.id, name: phone.name, productType: phone.productType, productVersion: phone.productVersion, buildVersion: phone.buildVersion, hardwareModel: phone.hardwareModel, carriers: [carrier])
                let fake = FakeBackend(); fake.connected = target
                let result = try Transaction(store: store, backend: fake).apply(phone: target, line: carrier)
                XCTAssertEqual(result.phase, .restartNeeded)
                fake.connected = Phone(id: phone.id, name: phone.name, productType: phone.productType, productVersion: phone.productVersion, buildVersion: phone.buildVersion, hardwareModel: phone.hardwareModel, carriers: [])
                XCTAssertTrue(BackupEligibility.matches(result, phone: fake.connected))
                let restored = try Transaction(store: store, backend: fake).apply(phone: fake.connected, line: carrier, restoring: result)
                XCTAssertEqual(restored.phase, .restored)
            }
        }
    }
    func testDynamicProfileTransactionAndRestore() throws {
        try withStore { store in
            let carrier = CarrierLine(slot: "kTwo", mcc: "257", mnc: "02", bundleID: "com.apple.MTS_by", bundleVersion: "70.0")
            let device = Phone(id: phone.id, name: "Test", productType: phone.productType, productVersion: "26.6.2", buildVersion: "23G90", hardwareModel: "D37AP", carriers: [carrier])
            let fake = FakeBackend(); fake.connected = device
            var exports = [String]()
            fake.beforeSync = { number in
                if number % 2 == 0 { XCTAssertTrue(fake.ids.last!.hasSuffix("D37+70.0.plist")); exports.append(fake.ids.last!) }
            }
            let result = try Transaction(store: store, backend: fake).apply(phone: device, line: carrier)
            XCTAssertEqual(result.overlayLeaf, try Compatibility.candidateLeaf(device, line: carrier))
            XCTAssertEqual(try store.load(result.id).overlayLeaf, result.overlayLeaf)
            let restored = try Transaction(store: store, backend: fake).apply(phone: device, line: carrier, restoring: result)
            XCTAssertEqual(restored.overlayLeaf, result.overlayLeaf)
            XCTAssertEqual(exports.count, 2)
        }
    }
    func testConcurrentMutationLock() throws {
        try withStore { store in let lock = try OperationLock(root: store.root); XCTAssertThrowsError(try OperationLock(root: store.root)); withExtendedLifetime(lock) {} }
    }
}

private var failures = 0
private struct CheckFailure: Error {}
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) { if a != b { failures += 1; print("FAIL \(file):\(line) \(message)") } }
private func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(a != b, file: file, line: line) }
private func XCTAssertTrue(_ a: Bool, file: StaticString = #file, line: UInt = #line) { XCTAssertEqual(a, true, file: file, line: line) }
private func XCTAssertFalse(_ a: Bool, file: StaticString = #file, line: UInt = #line) { XCTAssertEqual(a, false, file: file, line: line) }
private func XCTAssertNotNil<T>(_ a: T?, file: StaticString = #file, line: UInt = #line) { XCTAssertTrue(a != nil, file: file, line: line) }
private func XCTUnwrap<T>(_ a: T?) throws -> T { guard let a else { throw CheckFailure() }; return a }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) { do { _ = try expression(); failures += 1; print("FAIL expected error \(file):\(line) \(message)") } catch {} }
@main struct Checks {
    static func main() throws {
        let core = CoreTests(), transaction = TransactionTests()
        try core.testPatchOnlyThreeKeys()
        try core.testRejectsIntegerAndForeignCountry()
        core.testCompatibilityFailsClosed()
        try core.testDynamicProfilesAndPathValidation()
        try core.testWizardTransitionsAndPersistence()
        try core.testLegacyBackupsAndEligibility()
        core.testOnlyActualRadioEvidenceConfirms()
        try core.testJSONUsesLastResultAndZIPRoundTrip()
        try core.testOriginalIntegrityAndCorruptJournal()
        try transaction.testOriginalDurableBeforeSecondSyncAndSuccessfulRollback()
        try transaction.testFailureStopsAndBlocksAnotherMutation()
        try transaction.testInvalidOverlayIsReturnedUnchanged()
        try transaction.testRecoveryBeforeInstallAndRefusalAfterInstall()
        try transaction.testAllCarriersAndSIMIndependentRestore()
        try transaction.testDynamicProfileTransactionAndRestore()
        try transaction.testConcurrentMutationLock()
        print("16 checks, including 10 injected failure paths; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
