import Foundation
import Combine

/// One control moving right now, for the multi-control readout.
public struct LiveReading: Equatable, Hashable {
    public let control: String
    public let param: String
    public let value: String
}

/// State that changes on every USB packet. Kept out of `StudioEngine` so turning
/// twelve knobs at once redraws only the notch readout, not the Map window.
public final class HUDFeed: ObservableObject {
    public static let shared = HUDFeed()
    @Published public private(set) var mode: ActiveDisplayMode = .idle
    /// The newest mode, which may not be on screen yet.
    public private(set) var latest: ActiveDisplayMode = .idle
    private var flushScheduled = false
    private var lastFlush = Date.distantPast
    private let frameInterval: TimeInterval = 1.0 / 30.0
    private init() {}

    /// Called on the main thread for every change. The screen updates at most 30 times a
    /// second with the newest value, so turning many controls never backs up the UI.
    public func submit(_ next: ActiveDisplayMode) {
        guard next != latest else { return }
        latest = next
        let now = Date()
        // Appearing, disappearing, and mode banners show at once; readout values are paced.
        let immediate: Bool
        switch next {
        case .knob, .ring, .trackball, .multi: immediate = false
        default: immediate = true
        }
        if immediate || now.timeIntervalSince(lastFlush) >= frameInterval {
            flush()
        } else if !flushScheduled {
            flushScheduled = true
            let wait = frameInterval - now.timeIntervalSince(lastFlush)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, wait)) { [weak self] in
                self?.flushScheduled = false
                self?.flush()
            }
        }
    }

    private func flush() {
        lastFlush = Date()
        if mode != latest { mode = latest }
    }
}

/// Raw input for the Learn Key Positions sheet. Only that sheet observes it.
public final class HardwareTelemetry: ObservableObject {
    public static let shared = HardwareTelemetry()
    @Published public var reportId: Int? = nil
    @Published public var slotOrBit: Int? = nil
    @Published public var timestamp: Date = .distantPast
    private init() {}
}

/// Decides which controls are moving *together*. Turning contrast and then shadows is two
/// separate moves, so the readout just switches; turning them at the same time shows both.
struct RecentReadings {
    private struct Entry {
        var reading: LiveReading
        var burstStart: Date
        var last: Date
    }
    private var entries: [String: Entry] = [:]
    /// A pause longer than this starts a new move on that control.
    let burstGap: TimeInterval = 0.35
    /// A control still counts as moving this long after its last tick.
    let window: TimeInterval = 0.45

    mutating func record(_ reading: LiveReading, now: Date = Date()) -> [LiveReading] {
        if var entry = entries[reading.control], now.timeIntervalSince(entry.last) < burstGap {
            entry.reading = reading
            entry.last = now
            entries[reading.control] = entry
        } else {
            entries[reading.control] = Entry(reading: reading, burstStart: now, last: now)
        }
        entries = entries.filter { now.timeIntervalSince($0.value.last) < window }
        guard let current = entries[reading.control] else { return [reading] }
        // Others count only if they kept moving after this control started.
        let together = entries.values.filter { $0.reading.control == reading.control || $0.last > current.burstStart }
        return together.map(\.reading).sorted { Self.order($0.control) < Self.order($1.control) }
    }

    mutating func reset() { entries.removeAll() }

    /// Panel order keeps cells from jumping around while you turn.
    private static func order(_ control: String) -> Int {
        if let i = PanelLayout.knobs.firstIndex(of: control) { return i }
        if let i = PanelLayout.balls.firstIndex(of: control) { return 20 + i * 2 }
        if let i = PanelLayout.rings.firstIndex(of: control) { return 21 + i * 2 }
        return 100
    }
}
