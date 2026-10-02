import Darwin
import Foundation
import Network
import SafariServices

private enum SharedSettings {
    static let appGroupIdentifier = "group.com.Hitoshi.LiveMbpsBar"
    static let colorKey = "bar-color-hex"
    static let maximumMbpsKey = "bar-maximum-mbps"
    static let showSpeedKey = "show-speed"

    static let defaultColorHex = "58DE2F"
    static let defaultMaximumMbps = 20.0
    static let defaultShowSpeed = true
}

private let minimumNativeIntervalSeconds = 0.08
private let maximumContinuousSampleGapSeconds = 1.0

private struct PreviousCounter {
    let bytesIn: UInt32
}

private struct RawCounter {
    let name: String
    let bytesIn: UInt32
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let sampleLock = NSLock()
    private static let processIdentifier = UUID().uuidString
    private static var previousCounters: [String: PreviousCounter] = [:]
    private static var previousInterfaceNames = Set<String>()
    private static var lastCounterReadAt: TimeInterval?
    private static var lastPayload: [String: Any]?
    private static var sampleIdentifier: UInt64 = 0
    private static var continuityRecoveryActive = false
    private static let pathStatusLock = NSLock()
    private static var currentPathStatus: NWPath.Status?
    private static let pathMonitorQueue = DispatchQueue(
        label: "com.Hitoshi.LiveMbpsBar.path-monitor",
        qos: .utility
    )
    private static let pathMonitor = NWPathMonitor()
    private static let startPathMonitor: Void = {
        pathMonitor.pathUpdateHandler = { path in
            pathStatusLock.lock()
            currentPathStatus = path.status
            pathStatusLock.unlock()
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }()

    func beginRequest(with context: NSExtensionContext) {
        _ = Self.startPathMonitor

        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        guard message?["command"] as? String == "sample" else {
            complete(context, payload: ["state": "ignored"])
            return
        }

        Self.sampleLock.lock()
        let payload = sample()
        Self.sampleLock.unlock()
        complete(context, payload: payload)
    }

    private func sample() -> [String: Any] {
        let now = ProcessInfo.processInfo.systemUptime
        let settings = configuredSettings()

        if let previousRead = Self.lastCounterReadAt,
           now - previousRead < minimumNativeIntervalSeconds,
           var cached = Self.lastPayload {
            cached.merge(settings) { _, newValue in newValue }
            return cached
        }

        let result = readPhysicalCounters()
        guard let allPhysicalCounters = result.counters else {
            var payload: [String: Any] = [
                "state": "error",
                "error": result.error ?? "Unable to read network counters"
            ]
            payload.merge(settings) { _, newValue in newValue }
            return payload
        }

        let counters = pathIsKnownUnavailable() ? [] : allPhysicalCounters
        let currentNames = Set(counters.map(\.name))
        let interval = Self.lastCounterReadAt.map { now - $0 }
        Self.lastCounterReadAt = now
        Self.sampleIdentifier &+= 1

        if counters.isEmpty {
            Self.previousCounters = [:]
            Self.previousInterfaceNames = []
            Self.continuityRecoveryActive = false
            return finish(
                payload: statusPayload(state: "disconnected", now: now),
                settings: settings
            )
        }

        let currentBaselines = Dictionary(uniqueKeysWithValues: counters.map {
            ($0.name, PreviousCounter(bytesIn: $0.bytesIn))
        })

        guard let interval, interval > 0, !Self.previousCounters.isEmpty else {
            Self.previousCounters = currentBaselines
            Self.previousInterfaceNames = currentNames
            Self.continuityRecoveryActive = true
            return finish(
                payload: statusPayload(state: "baseline", now: now),
                settings: settings
            )
        }

        let interfaceSetChanged = currentNames != Self.previousInterfaceNames
        let intervalExceededContinuityLimit = interval > maximumContinuousSampleGapSeconds
        if (interfaceSetChanged || intervalExceededContinuityLimit),
           !Self.continuityRecoveryActive {
            Self.previousCounters = currentBaselines
            Self.previousInterfaceNames = currentNames
            Self.continuityRecoveryActive = true
            return finish(
                payload: statusPayload(state: "baseline", now: now),
                settings: settings
            )
        }

        var deltaBytesIn: UInt64 = 0
        var comparableInterfaceCount = 0
        for counter in counters {
            guard let previous = Self.previousCounters[counter.name] else { continue }
            comparableInterfaceCount += 1

            guard counter.bytesIn >= previous.bytesIn else {
                Self.previousCounters = currentBaselines
                Self.previousInterfaceNames = currentNames
                Self.continuityRecoveryActive = true
                return finish(
                    payload: statusPayload(state: "counterReset", now: now),
                    settings: settings
                )
            }

            deltaBytesIn += UInt64(counter.bytesIn - previous.bytesIn)
        }

        guard comparableInterfaceCount > 0 else {
            Self.previousCounters = currentBaselines
            Self.previousInterfaceNames = currentNames
            Self.continuityRecoveryActive = true
            return finish(
                payload: statusPayload(state: "baseline", now: now),
                settings: settings
            )
        }

        Self.previousCounters = currentBaselines
        Self.previousInterfaceNames = currentNames
        Self.continuityRecoveryActive = interfaceSetChanged || intervalExceededContinuityLimit

        var payload = statusPayload(state: "live", now: now)
        payload["mbpsIn"] = Double(deltaBytesIn) * 8 / interval / 1_000_000
        payload["intervalMilliseconds"] = interval * 1_000
        payload["deltaBytesIn"] = deltaBytesIn
        payload["interfaces"] = currentNames.sorted()
        return finish(payload: payload, settings: settings)
    }

    private func statusPayload(state: String, now: TimeInterval) -> [String: Any] {
        [
            "state": state,
            "processId": Self.processIdentifier,
            "sampleId": Self.sampleIdentifier,
            "sampleUptimeMilliseconds": now * 1_000
        ]
    }

    private func finish(payload: [String: Any], settings: [String: Any]) -> [String: Any] {
        var completed = payload
        completed.merge(settings) { _, newValue in newValue }
        Self.lastPayload = completed
        return completed
    }

    private func configuredSettings() -> [String: Any] {
        let defaults = UserDefaults(suiteName: SharedSettings.appGroupIdentifier)

        let colorCandidate = defaults?.string(forKey: SharedSettings.colorKey)?.uppercased() ?? ""
        let validColor = colorCandidate.range(
            of: "^[0-9A-F]{6}$",
            options: .regularExpression
        ) != nil
        let colorHex = validColor ? colorCandidate : SharedSettings.defaultColorHex

        let storedMaximum = defaults?.object(forKey: SharedSettings.maximumMbpsKey) as? NSNumber
        let maximumCandidate = storedMaximum?.doubleValue ?? SharedSettings.defaultMaximumMbps
        let maximumMbps = maximumCandidate.isFinite && (0.1 ... 1_000).contains(maximumCandidate)
            ? maximumCandidate
            : SharedSettings.defaultMaximumMbps

        let showSpeed: Bool
        if defaults?.object(forKey: SharedSettings.showSpeedKey) == nil {
            showSpeed = SharedSettings.defaultShowSpeed
        } else {
            showSpeed = defaults?.bool(forKey: SharedSettings.showSpeedKey) ?? SharedSettings.defaultShowSpeed
        }

        return [
            "colorHex": colorHex,
            "maximumMbps": maximumMbps,
            "showSpeed": showSpeed
        ]
    }

    private func pathIsKnownUnavailable() -> Bool {
        Self.pathStatusLock.lock()
        let status = Self.currentPathStatus
        Self.pathStatusLock.unlock()

        guard let status else { return false }
        return status != .satisfied
    }

    private func readPhysicalCounters() -> (counters: [RawCounter]?, error: String?) {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        let result = getifaddrs(&addressList)
        guard result == 0, let firstAddress = addressList else {
            return (nil, "getifaddrs failed: \(errno)")
        }
        defer { freeifaddrs(addressList) }

        var counters: [RawCounter] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let address = cursor {
            cursor = address.pointee.ifa_next
            guard
                let namePointer = address.pointee.ifa_name,
                let socketAddress = address.pointee.ifa_addr,
                socketAddress.pointee.sa_family == UInt8(AF_LINK),
                let dataPointer = address.pointee.ifa_data
            else { continue }

            let name = String(cString: namePointer)
            guard name == "en0" || name.hasPrefix("pdp_ip") else { continue }

            let flags = UInt32(address.pointee.ifa_flags)
            let isUp = (flags & UInt32(IFF_UP)) != 0
            guard isUp else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            counters.append(RawCounter(name: name, bytesIn: data.ifi_ibytes))
        }

        return (counters, nil)
    }

    private func complete(_ context: NSExtensionContext, payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
