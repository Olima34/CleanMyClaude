import Foundation
import CoreAudio
import CoreMediaIO
import SystemConfiguration
import AppKit

/// What real-time protection watches. Everything is off until the user turns it on (notifications are asked then).
struct ProtectionRealtimeSettings: Codable, Equatable {
    /// A new launch agent or daemon (BlockBlock-style): signature and behaviour checked at once.
    var persistence = false
    /// Every program, script or installer landing in Téléchargements, scanned with Apple's signatures.
    var downloads = false
    /// The camera or the microphone turning on (OverSight-style).
    var devices = false
    /// DNS servers or a proxy changing behind the user's back.
    var network = false

    var anyOn: Bool { persistence || downloads || devices || network }
    static let allOn = ProtectionRealtimeSettings(persistence: true, downloads: true, devices: true, network: true)
}

/// One line of the real-time journal.
struct ProtectionEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case persistence, download, camera, microphone, network

        var symbol: String {
            switch self {
            case .persistence: return "arrow.clockwise.circle"
            case .download: return "arrow.down.circle"
            case .camera: return "camera"
            case .microphone: return "mic"
            case .network: return "network"
            }
        }
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    var detail: String
    /// `Status` raw value.
    var severity: Int
    var path: String?

    var status: Status { Status(rawValue: severity) ?? .info }
}

/// The watchers. Each one reacts to events from macOS (folder changes, device state, network configuration):
/// no timer, nothing runs while nothing happens.
@MainActor
final class ProtectionMonitor {
    /// Called on the main thread for every event worth a line in the journal.
    var onEvent: (ProtectionEvent, _ threat: ProtectionThreat?) -> Void = { _, _ in }

    private var folderSources: [String: DispatchSourceFileSystemObject] = [:]
    private var known: [String: Set<String>] = [:]
    private var pendingFolders: Set<String> = []
    private var downloadsWork: DispatchWorkItem?
    private var persistenceWork: DispatchWorkItem?
    private var deviceListeners: [() -> Void] = []
    private var cameraOn = false
    private var micOn = false
    private var networkStore: SCDynamicStore?
    private var lastNetwork: (dns: Status, proxy: Status)?
    private let queue = DispatchQueue(label: "cleanmyclaude.protection.monitor", qos: .utility)

    static var persistenceFolders: [String] { LaunchDomain.allCases.map(\.folder) }
    static var downloadsFolder: String { FS.home + "/Downloads" }

    func apply(_ s: ProtectionRealtimeSettings) {
        guard !DemoData.isEnabled, !Snapshot.isActive else { return }
        for folder in Self.persistenceFolders {
            if s.persistence { watch(folder) } else { unwatch(folder) }
        }
        if s.downloads { watch(Self.downloadsFolder) } else { unwatch(Self.downloadsFolder) }
        if s.devices { startDevices() } else { stopDevices() }
        if s.network { startNetwork() } else { stopNetwork() }
    }

    func stopAll() {
        apply(ProtectionRealtimeSettings())
    }

    // MARK: Folders

    /// Folders that do not exist yet, waited for in their parent (a fresh account has no ~/Library/LaunchAgents:
    /// the first agent to come creates it).
    private var waiting: [String: DispatchSourceFileSystemObject] = [:]

    private func watch(_ folder: String) {
        guard folderSources[folder] == nil else { return }
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else {
            waitFor(folder)
            return
        }
        waiting.removeValue(forKey: folder)?.cancel()
        known[folder] = Set(FS.children(folder, hidden: true))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The folder itself was removed or replaced: watched again where it is now (or waited for).
                if let events = source?.data, events.contains(.delete) || events.contains(.rename) {
                    self.folderSources.removeValue(forKey: folder)?.cancel()
                    self.watch(folder)
                    return
                }
                self.changed(folder)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderSources[folder] = source
    }

    private func waitFor(_ folder: String) {
        guard waiting[folder] == nil else { return }
        let parent = (folder as NSString).deletingLastPathComponent
        let fd = open(parent, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, FS.isDirectory(folder) else { return }
                self.waiting.removeValue(forKey: folder)?.cancel()
                // Everything already in it is new.
                self.watch(folder)
                self.known[folder] = []
                self.changed(folder)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        waiting[folder] = source
    }

    private func unwatch(_ folder: String) {
        folderSources.removeValue(forKey: folder)?.cancel()
        waiting.removeValue(forKey: folder)?.cancel()
        known[folder] = nil
    }

    /// A folder changed: what appeared is looked at once its writing settled (a download grows for a while).
    private func changed(_ folder: String) {
        pendingFolders.insert(folder)
        let isDownloads = folder == Self.downloadsFolder
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settle(downloads: isDownloads) }
        }
        if isDownloads {
            downloadsWork?.cancel()
            downloadsWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        } else {
            persistenceWork?.cancel()
            persistenceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func settle(downloads: Bool) {
        let folders = pendingFolders.filter { ($0 == Self.downloadsFolder) == downloads }
        pendingFolders.subtract(folders)
        for folder in folders {
            let now = Set(FS.children(folder, hidden: true))
            let added = now.subtracting(known[folder] ?? [])
            known[folder] = now
            // Partial downloads finish under another name: only finished files count.
            let fresh = added.filter { !$0.hasSuffix(".download") && !$0.hasSuffix(".crdownload") && !$0.hasSuffix(".part") && !$0.hasPrefix(".") }
            guard !fresh.isEmpty else { continue }
            let paths = fresh.sorted().map { folder + "/" + $0 }
            if downloads { inspectDownloads(paths) } else { inspectLaunchItems(paths) }
        }
    }

    private func inspectLaunchItems(_ paths: [String]) {
        queue.async {
            let uid = getuid()
            let gui = LaunchItemScanner.parseDisabled(Shell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]).out)
            let sys = LaunchItemScanner.parseDisabled(Shell.run("/bin/launchctl", ["print-disabled", "system"]).out)
            let sig = ProtectionSignatures.load()
            for path in paths where path.hasSuffix(".plist") {
                let domain = LaunchDomain.allCases.first { path.hasPrefix($0.folder + "/") } ?? .userAgent
                guard let item = LaunchItemScanner.parse(path, domain: domain, guiDisabled: gui, sysDisabled: sys, loaded: [:]) else { continue }
                let hits = item.program.flatMap { p in sig.map { ProtectionSignatureScanner.scan(p, with: $0) } } ?? []
                var threat = ProtectionThreatScanner.persistenceThreats([item]).first
                if let hit = hits.first, let program = item.program {
                    threat = ProtectionThreatScanner.link([ProtectionThreat(kind: .signature, severity: Status.bad.rawValue, name: hit.detection,
                                                                            detail: "Les signatures d'Apple reconnaissent le programme lancé par cet élément.",
                                                                            path: program, removable: [ProtectionThreatScanner.container(of: program)])],
                                                          launchItems: [item]).first
                }
                let bad = threat?.status == .bad
                let event = ProtectionEvent(kind: .persistence,
                                            title: bad ? "Élément de démarrage suspect : \(item.label)" : "Nouvel élément de démarrage : \(item.label)",
                                            detail: bad ? (threat?.detail ?? "") : ((item.vendor == item.signature.label ? [item.vendor] : [item.vendor, item.signature.label]).joined(separator: " · ") + " · se lancera à chaque démarrage."),
                                            severity: (bad ? Status.bad : (item.isFlagged ? Status.warn : Status.info)).rawValue, path: path)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.onEvent(event, threat)
                        Notifier.post(id: "protection.persistence." + item.label,
                                      title: bad ? "Clean My Claude a repéré un élément suspect" : "Un programme s'est ajouté au démarrage",
                                      body: "\(item.label) (\(item.signature.label)). " + (bad ? "Ouvre Protection › Menaces pour l'arrêter." : "Il se lancera à chaque démarrage du Mac."),
                                      throttle: 60)
                    }
                }
            }
        }
    }

    private func inspectDownloads(_ paths: [String]) {
        queue.async {
            guard let sig = ProtectionSignatures.load() else { return }
            for path in paths {
                var files: [String] = []
                if path.hasSuffix(".app") {
                    files = ProtectionThreatScanner.bundleExecutables(path)
                } else if !FS.isDirectory(path) {
                    files = [path]
                } else {
                    var found = Set<String>()
                    ProtectionThreatScanner.walk(path, depth: 3, isCancelled: { false }, into: &found)
                    files = found.sorted()
                }
                for file in files {
                    guard let hit = ProtectionSignatureScanner.scan(file, with: sig).first else { continue }
                    let threat = ProtectionThreat(kind: .signature, severity: Status.bad.rawValue, name: hit.detection,
                                                  detail: "Arrivé dans Téléchargements, reconnu par les signatures antimalware d'Apple (XProtect \(sig.version)). Ne l'ouvre pas.",
                                                  path: file, removable: [ProtectionThreatScanner.container(of: path.hasSuffix(".app") ? path : file)])
                    let name = (path as NSString).lastPathComponent
                    let event = ProtectionEvent(kind: .download, title: "Menace dans Téléchargements : \(name)",
                                                detail: "\(hit.detection) : ne l'ouvre pas, mets-le à la Corbeille depuis Protection › Menaces.",
                                                severity: Status.bad.rawValue, path: file)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.onEvent(event, threat)
                            Notifier.post(id: "protection.download." + file, title: "Menace détectée dans Téléchargements",
                                          body: "« \(name) » est reconnu comme \(hit.detection). Ne l'ouvre pas.", throttle: 10)
                        }
                    }
                    break
                }
            }
        }
    }

    // MARK: Camera and microphone

    private var processListeners: [() -> Void] = []

    private func startDevices() {
        guard deviceListeners.isEmpty else { return }
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.checkMicrophone() } }
        }
        let rearm: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.rearmDevices() } }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        // A microphone or camera plugged in later is watched too.
        var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, .main, rearm)
        deviceListeners.append { AudioObjectRemovePropertyListenerBlock(system, &devicesAddress, .main, rearm) }
        if #available(macOS 14.2, *) {
            // Which process records, not whether a device runs: a headset playing music is no microphone in use.
            var list = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            let processes: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.armProcesses()
                        self?.checkMicrophone()
                    }
                }
            }
            AudioObjectAddPropertyListenerBlock(system, &list, .main, processes)
            deviceListeners.append { AudioObjectRemovePropertyListenerBlock(system, &list, .main, processes) }
            armProcesses()
        } else {
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var inputs: [AudioObjectID] = []
            for d in audioInputDevices() ?? [] where AudioObjectAddPropertyListenerBlock(d, &running, .main, changed) == noErr { inputs.append(d) }
            deviceListeners.append { for i in inputs { AudioObjectRemovePropertyListenerBlock(i, &running, .main, changed) } }
        }
        // Cameras, and the list of cameras.
        var camRunning = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                   mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                   mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        let camBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.checkCamera() } }
        }
        var watched: [CMIOObjectID] = []
        for c in cameraDevices() where CMIOObjectAddPropertyListenerBlock(c, &camRunning, .main, camBlock) == noErr { watched.append(c) }
        var camList = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let camRearm: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.rearmDevices() } }
        }
        let cmioSystem = CMIOObjectID(kCMIOObjectSystemObject)
        CMIOObjectAddPropertyListenerBlock(cmioSystem, &camList, .main, camRearm)
        deviceListeners.append {
            for c in watched { CMIOObjectRemovePropertyListenerBlock(c, &camRunning, .main, camBlock) }
            CMIOObjectRemovePropertyListenerBlock(cmioSystem, &camList, .main, camRearm)
        }
        micOn = microphoneInUse()
        cameraOn = cameraInUse()
    }

    private func stopDevices() {
        deviceListeners.forEach { $0() }
        deviceListeners = []
        processListeners.forEach { $0() }
        processListeners = []
    }

    /// The devices changed (one plugged or unplugged): listeners again on the new list, state kept.
    private func rearmDevices() {
        guard !deviceListeners.isEmpty else { return }
        let mic = micOn, cam = cameraOn
        stopDevices()
        startDevices()
        micOn = mic
        cameraOn = cam
        checkMicrophone()
        checkCamera()
    }

    /// A listener on each audio client's "recording" state (macOS 14.2 and later).
    private func armProcesses() {
        guard #available(macOS 14.2, *) else { return }
        processListeners.forEach { $0() }
        processListeners = []
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.checkMicrophone() } }
        }
        var input = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        var armed: [AudioObjectID] = []
        for p in audioProcesses() where AudioObjectAddPropertyListenerBlock(p, &input, .main, block) == noErr { armed.append(p) }
        processListeners.append { for p in armed { AudioObjectRemovePropertyListenerBlock(p, &input, .main, block) } }
    }

    private func checkMicrophone() {
        let users = microphoneUsers()
        let on = users.map { !$0.isEmpty } ?? microphoneInUse()
        guard on != micOn else { return }
        micOn = on
        let who = users.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }
        onEvent(ProtectionEvent(kind: .microphone, title: on ? (who.map { "Le micro s'est allumé : \($0)" } ?? "Le micro s'est allumé") : "Le micro s'est éteint",
                                detail: on ? (who.map { "\($0) enregistre ce que tu dis." } ?? "Une app écoute. Le point orange de la barre des menus, dans le Centre de contrôle, dit laquelle.")
                                           : "Plus aucune app n'écoute.",
                                severity: (on ? Status.warn : Status.info).rawValue), nil)
        if on {
            Notifier.post(id: "protection.mic", title: "Le micro est allumé",
                          body: who.map { "\($0) écoute ce que tu dis." } ?? "Une app écoute ce que tu dis. Le Centre de contrôle indique laquelle.", throttle: 30)
        }
    }

    private func checkCamera() {
        let on = cameraInUse()
        guard on != cameraOn else { return }
        cameraOn = on
        onEvent(ProtectionEvent(kind: .camera, title: on ? "La caméra s'est allumée" : "La caméra s'est éteinte",
                                detail: on ? "Une app filme. Le Centre de contrôle indique laquelle." : "Plus aucune app ne filme.",
                                severity: (on ? Status.warn : Status.info).rawValue), nil)
        if on { Notifier.post(id: "protection.camera", title: "La caméra est allumée", body: "Une app te filme. Le Centre de contrôle indique laquelle.", throttle: 30) }
    }

    /// The audio clients macOS knows (macOS 14.2 and later).
    private func audioProcesses() -> [AudioObjectID] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// The apps recording from a microphone right now, or nil before macOS 14.2 (no way to tell then).
    private func microphoneUsers() -> [String]? {
        guard #available(macOS 14.2, *) else { return nil }
        var names: [String] = []
        for p in audioProcesses() {
            var input = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(p, &input, 0, nil, &size, &running) == noErr, running != 0 else { continue }
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            size = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(p, &pidAddress, 0, nil, &size, &pid)
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? NetworkPorts.executablePath(pid).map { ($0 as NSString).lastPathComponent } ?? "Une app"
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// For `--dump`: whether a camera or a microphone is in use right now, and by whom when macOS says it.
    static func devicesInUse() -> (camera: Bool, microphone: Bool, users: [String]) {
        let m = ProtectionMonitor()
        let users = m.microphoneUsers()
        return (m.cameraInUse(), users.map { !$0.isEmpty } ?? m.microphoneInUse(), users ?? [])
    }

    private func audioInputDevices() -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.filter { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var s: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &s) == noErr && s > 0
        }
    }

    private func microphoneInUse() -> Bool {
        (audioInputDevices() ?? []).contains { id in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
        }
    }

    private func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private func cameraInUse() -> Bool {
        cameraDevices().contains { id in
            var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr && value != 0
        }
    }

    // MARK: Network

    private func startNetwork() {
        guard networkStore == nil else { return }
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<ProtectionMonitor>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { monitor.networkChanged() } }
        }
        guard let store = SCDynamicStoreCreate(nil, "CleanMyClaude.protection" as CFString, callback, &context) else { return }
        SCDynamicStoreSetNotificationKeys(store, ["State:/Network/Global/DNS", "State:/Network/Global/Proxies"] as CFArray, nil)
        SCDynamicStoreSetDispatchQueue(store, queue)
        networkStore = store
        let dns = SecurityAudit.dns().status, proxy = SecurityAudit.proxy().status
        lastNetwork = (dns, proxy)
    }

    private func stopNetwork() {
        if let store = networkStore { SCDynamicStoreSetDispatchQueue(store, nil) }
        networkStore = nil
        lastNetwork = nil
    }

    private func networkChanged() {
        queue.async {
            let dns = SecurityAudit.dns(), proxy = SecurityAudit.proxy()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let before = self.lastNetwork
                    self.lastNetwork = (dns.status, proxy.status)
                    // Only what newly deserves a look: a VPN connecting does not, a DNS changer does.
                    for (check, was) in [(dns, before?.dns), (proxy, before?.proxy)] where check.status == .warn && was != .warn {
                        self.onEvent(ProtectionEvent(kind: .network, title: "\(check.title) : changement à vérifier",
                                                     detail: check.detail + " " + (check.advice ?? ""), severity: Status.warn.rawValue), nil)
                        Notifier.post(id: "protection.network." + check.id, title: "Tes réglages réseau viennent de changer",
                                      body: check.detail, throttle: 600)
                    }
                }
            }
        }
    }
}
