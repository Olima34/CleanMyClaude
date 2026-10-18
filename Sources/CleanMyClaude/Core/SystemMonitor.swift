import Foundation
import Darwin
import IOKit
import IOKit.ps
import Observation

/// Battery details from IOKit (nil on desktop Macs).
struct BatteryInfo: Equatable {
    var level: Double            // 0…1
    var isCharging: Bool
    var onAC: Bool
    var minutesLeft: Int?        // to empty, or to full when charging
    var cycleCount: Int?
    var health: Double?          // max capacity / design capacity
    var temperature: Double?     // °C
}

enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: return "Normale"
        case .warning: return "Élevée"
        case .critical: return "Critique"
        }
    }
}

/// Live system metrics, sampled every couple of seconds. Cheap syscalls only.
@Observable
@MainActor
final class SystemMonitor {
    static let historyLength = 60

    // CPU
    var cpu: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuHistory: [Double] = []
    var coreCount = ProcessInfo.processInfo.activeProcessorCount
    var loadAverage: Double = 0

    // Memory
    var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var memApp: UInt64 = 0
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memCached: UInt64 = 0
    var memFree: UInt64 = 0
    var memUsed: UInt64 { memApp + memWired + memCompressed }
    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    var memHistory: [Double] = []
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal

    // Disk (data volume)
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0          // including purgeable space
    var diskFreeStrict: Int64 = 0    // really empty space
    var diskUsedFraction: Double { diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0 }

    // Network
    var netIn: Double = 0            // bytes per second
    var netOut: Double = 0
    var netInHistory: [Double] = []
    var netOutHistory: [Double] = []
    var netTotalIn: UInt64 = 0
    var netTotalOut: UInt64 = 0

    // Misc
    var battery: BatteryInfo?
    var thermal: ProcessInfo.ThermalState = .nominal
    var bootDate: Date?
    var uptime: TimeInterval { bootDate.map { Date().timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime }
    var lastSample = Date()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var prevTicks: [UInt32]?
    @ObservationIgnored private var prevNet: (bytesIn: UInt64, bytesOut: UInt64, at: Date)?
    @ObservationIgnored private var tick = 0
    private let host = mach_host_self()
    @ObservationIgnored private var pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    var interval: TimeInterval = 2

    init(start: Bool = true) {
        bootDate = Self.readBootDate()
        sample()
        if start { self.start() }
    }

    func start() {
        timer?.invalidate()
        let saved = UserDefaults.standard.double(forKey: Preferences.refreshKey)
        interval = saved > 0 ? saved : 2
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func sample() {
        tick += 1
        if DemoData.isEnabled {
            DemoData.sample(self, tick: tick)
            return
        }
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        if tick % 5 == 1 { sampleDisk() }
        if tick % 15 == 1 { battery = Self.readBattery() }
        thermal = ProcessInfo.processInfo.thermalState
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { loadAverage = loads[0] }
        lastSample = Date()
    }

    private func push(_ v: Double, to array: inout [Double]) {
        array.append(v)
        if array.count > Self.historyLength { array.removeFirst(array.count - Self.historyLength) }
    }

    // MARK: CPU

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let t = info.cpu_ticks
        let ticks = [t.0, t.1, t.2, t.3] // user, system, idle, nice
        defer { prevTicks = ticks }
        guard let prev = prevTicks else { return }
        let d = zip(ticks, prev).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return }
        cpuUser = (d[0] + d[3]) / total
        cpuSystem = d[1] / total
        cpu = min(1, cpuUser + cpuSystem)
        push(cpu, to: &cpuHistory)
    }

    // MARK: Memory

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let p = pageSize
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            memApp = (internalPages > purgeable ? internalPages - purgeable : 0) * p
            memWired = UInt64(stats.wire_count) * p
            memCompressed = UInt64(stats.compressor_page_count) * p
            memCached = (UInt64(stats.external_page_count) + purgeable) * p
            memFree = UInt64(stats.free_count) * p
            push(memFraction, to: &memHistory)
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }

        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0) == 0 {
            pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
    }

    // MARK: Disk

    func sampleDisk() {
        if DemoData.isEnabled { return DemoData.sampleDisk(self) }
        let url = URL(fileURLWithPath: FS.home)
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                                     .volumeAvailableCapacityKey]) {
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            diskFreeStrict = Int64(v.volumeAvailableCapacity ?? 0)
        }
    }

    // MARK: Network

    private func sampleNetwork() {
        guard let (bytesIn, bytesOut) = Self.readInterfaceBytes() else { return }
        let now = Date()
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0, bytesIn >= prev.bytesIn, bytesOut >= prev.bytesOut {
                netIn = Double(bytesIn - prev.bytesIn) / dt
                netOut = Double(bytesOut - prev.bytesOut) / dt
                push(netIn, to: &netInHistory)
                push(netOut, to: &netOutHistory)
            }
        }
        netTotalIn = bytesIn
        netTotalOut = bytesOut
        prevNet = (bytesIn, bytesOut, now)
    }

    /// Sums the 64-bit byte counters of the physical interfaces (en*).
    nonisolated static func readInterfaceBytes() -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var offset = 0
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        buf.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                if Int32(hdr.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let m = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if if_indextoname(UInt32(m.ifm_index), &name) != nil {
                        let n = String(cString: name)
                        if n.hasPrefix("en") {
                            totalIn += m.ifm_data.ifi_ibytes
                            totalOut += m.ifm_data.ifi_obytes
                        }
                    }
                }
                let step = Int(hdr.ifm_msglen)
                if step <= 0 { break }
                offset += step
            }
        }
        return (totalIn, totalOut)
    }

    // MARK: Battery

    nonisolated static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc["Type"] as? String) == "InternalBattery" else { continue }
            let current = desc["Current Capacity"] as? Int ?? 0
            let maxCap = max(1, desc["Max Capacity"] as? Int ?? 100)
            let charging = desc["Is Charging"] as? Bool ?? false
            let onAC = (desc["Power Source State"] as? String) == "AC Power"
            let minutes = charging ? desc["Time to Full Charge"] as? Int : desc["Time to Empty"] as? Int
            var info = BatteryInfo(level: Double(current) / Double(maxCap), isCharging: charging, onAC: onAC,
                                   minutesLeft: (minutes ?? -1) > 0 ? minutes : nil)
            // Health and cycles from the battery controller.
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let d = props?.takeRetainedValue() as? [String: Any] {
                    let nested = d["BatteryData"] as? [String: Any] ?? [:]
                    func int(_ k: String) -> Int? { d[k] as? Int ?? nested[k] as? Int }
                    info.cycleCount = int("CycleCount")
                    let design = int("DesignCapacity") ?? 0
                    // System Settings shows the nominal capacity against the design capacity.
                    let rawMax = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") ?? 0
                    if design > 0 && rawMax > 0 { info.health = min(1, Double(rawMax) / Double(design)) }
                    if let t = d["Temperature"] as? Int { info.temperature = Double(t) / 100 }
                }
            }
            return info
        }
        return nil
    }

    nonisolated static func readBootDate() -> Date? {
        if DemoData.isEnabled { return DemoData.bootDate }
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }

    var thermalLabel: String {
        switch thermal {
        case .nominal: return "Normale"
        case .fair: return "Tiède"
        case .serious: return "Chaude"
        case .critical: return "Critique"
        @unknown default: return "—"
        }
    }

    static var modelName: String {
        if DemoData.isEnabled { return DemoData.modelName }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static var chipName: String {
        if DemoData.isEnabled { return DemoData.chipName }
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// "27.1"
    static var osVersion: String {
        if DemoData.isEnabled { return DemoData.osVersion }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
}
