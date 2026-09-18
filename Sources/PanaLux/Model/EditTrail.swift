import Foundation

/// One value change, exactly as the plugin reported it. Values are MIDI2LR's normalised 0…1,
/// the same numbers `LightroomBridge` sends and receives.
public struct TrailEvent: Codable, Equatable {
    public var t: TimeInterval
    public var param: String
    public var value: Double

    public init(t: TimeInterval, param: String, value: Double) {
        self.t = t
        self.param = param
        self.value = value
    }
}

/// A landmark on the trail. Structural edits and "I liked it" marks both land here, because
/// both are places worth stopping at — and both are restored exactly, not interpolated.
public struct TrailKeyframe: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case open       // the photo as it was when it came on screen
        case mark       // the user pressed Mark this
        case branch     // a branch started here
        case mask
        case crop
        case preset
        case paste
        case reset
        case action     // anything else discrete enough to be worth a full table
    }

    public var id: String
    public var t: TimeInterval
    public var kind: Kind
    public var label: String
    /// Every value PanaLux knew at capture. Enough to rebuild the sliders on its own.
    public var values: [String: Double]
    /// The opaque `getDevelopSettings()` table from the plugin, base64 of a Lua literal.
    /// PanaLux never parses it; it hands the same string back to restore masks and crop.
    public var blob: String?

    public init(id: String = UUID().uuidString, t: TimeInterval, kind: Kind, label: String,
                values: [String: Double] = [:], blob: String? = nil) {
        self.id = id
        self.t = t
        self.kind = kind
        self.label = label
        self.values = values
        self.blob = blob
    }

    /// Marks and opens are always worth stopping at; the rest are landmarks too, but quieter.
    public var snaps: Bool { kind == .mark || kind == .open || kind == .branch }
}

/// One line of editing. A branch keeps its own events; its parent keeps everything it had.
/// Nothing is ever removed from a parent when a branch starts.
public struct TrailBranch: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var parent: String?
    /// Trail time where this branch leaves its parent. The root starts at 0.
    public var forkTime: TimeInterval
    /// Wall clock at which `forkTime` was "now". Trail time is measured from here.
    public var clockOrigin: Date
    public var events: [TrailEvent]
    public var keyframes: [TrailKeyframe]

    public init(id: String = UUID().uuidString, name: String, parent: String? = nil,
                forkTime: TimeInterval = 0, clockOrigin: Date = Date(),
                events: [TrailEvent] = [], keyframes: [TrailKeyframe] = []) {
        self.id = id
        self.name = name
        self.parent = parent
        self.forkTime = forkTime
        self.clockOrigin = clockOrigin
        self.events = events
        self.keyframes = keyframes
    }

    /// Latest time anything happened on this branch alone.
    public var localTip: TimeInterval {
        var tip = forkTime
        if let last = events.last?.t { tip = max(tip, last) }
        for k in keyframes { tip = max(tip, k.t) }
        return tip
    }
}

/// The whole recording for one photo: a tree of branches over one shared clock.
///
/// Trail time is *editing* time, not wall time. A branch re-bases its clock when it starts and
/// again when a later session picks the photo back up, so the tape stays dense and scrubbable
/// instead of carrying the hours PanaLux spent quit.
public struct EditTrail: Codable, Equatable {
    public static let formatVersion = 1
    /// Samples closer together than this are one continuous move, and are interpolated.
    /// Further apart, the earlier value simply held — so the playhead steps.
    public static let gestureGap: TimeInterval = 0.4
    /// A resumed session starts this far after the tip rather than hours later.
    public static let resumeGap: TimeInterval = 1.0
    /// Above this, the oldest dense runs are thinned. Keyframes are never dropped.
    public static let maxEventsPerBranch = 40_000

    public var version: Int
    public var photoID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var branches: [TrailBranch]
    public var activeBranchID: String

    public init(photoID: String, now: Date = Date()) {
        let root = TrailBranch(name: "Original", parent: nil, forkTime: 0, clockOrigin: now)
        self.version = EditTrail.formatVersion
        self.photoID = photoID
        self.createdAt = now
        self.updatedAt = now
        self.branches = [root]
        self.activeBranchID = root.id
    }

    // MARK: - Branch access

    public func branch(_ id: String) -> TrailBranch? {
        branches.first { $0.id == id }
    }

    public var activeBranch: TrailBranch {
        branch(activeBranchID) ?? branches[0]
    }

    private var activeIndex: Int {
        branches.firstIndex { $0.id == activeBranchID } ?? 0
    }

    /// Root first, active branch last. Each segment owns trail time from its own fork up to
    /// the fork of the child that follows it.
    public func lineage(of branchID: String? = nil) -> [TrailBranch] {
        var chain: [TrailBranch] = []
        var cursor = branch(branchID ?? activeBranchID)
        var guardCount = 0
        while let b = cursor, guardCount < branches.count + 1 {
            chain.append(b)
            guardCount += 1
            cursor = b.parent.flatMap { branch($0) }
        }
        return Array(chain.reversed())
    }

    /// Branches that left the active path, and where they left it.
    public func forks(of branchID: String? = nil) -> [TrailBranch] {
        let path = Set(lineage(of: branchID).map(\.id))
        return branches.filter { b in
            guard let parent = b.parent else { return false }
            return path.contains(parent) && !path.contains(b.id)
        }
    }

    // MARK: - The clock

    /// Trail time for a wall-clock instant, on the active branch.
    public func time(at wall: Date = Date()) -> TimeInterval {
        let b = activeBranch
        return b.forkTime + wall.timeIntervalSince(b.clockOrigin)
    }

    /// Latest point on the active path. Rolling back never moves it.
    public var tipTime: TimeInterval {
        lineage().reduce(0.0) { max($0, $1.localTip) }
    }

    /// Where the recording starts on the active path.
    public var originTime: TimeInterval {
        lineage().first?.forkTime ?? 0
    }

    /// A session that opens this photo again continues just after the tip instead of
    /// leaving a gap as long as PanaLux was quit.
    public mutating func resume(at wall: Date = Date()) {
        let index = activeIndex
        let localTip = max(branches[index].localTip, branches[index].forkTime)
        branches[index].clockOrigin = wall.addingTimeInterval(-(localTip - branches[index].forkTime) - EditTrail.resumeGap)
        updatedAt = wall
    }

    // MARK: - Recording

    /// Append one reported value. Repeats of the same value are dropped: the tape only needs
    /// the places the number actually moved.
    @discardableResult
    public mutating func record(param: String, value: Double, at t: TimeInterval) -> Bool {
        let index = activeIndex
        // A knob that is not moving still reports. Scanning only the tail keeps recording O(1);
        // a repeat of a value always sits within a few events of its twin.
        let events = branches[index].events
        let window = events.index(events.endIndex, offsetBy: -64, limitedBy: events.startIndex) ?? events.startIndex
        // Lightroom resends every value after any action, so most reports say nothing changed.
        // The tape only needs the moments a number actually moved.
        if let last = events[window...].last(where: { $0.param == param }),
           abs(last.value - value) < 0.00001 {
            return false
        }
        let clamped = max(0.0, min(1.0, value))
        branches[index].events.append(TrailEvent(t: max(t, branches[index].forkTime), param: param, value: clamped))
        if branches[index].events.count > EditTrail.maxEventsPerBranch {
            EditTrail.thin(&branches[index].events)
        }
        return true
    }

    @discardableResult
    public mutating func addKeyframe(_ keyframe: TrailKeyframe) -> TrailKeyframe {
        let index = activeIndex
        var k = keyframe
        k.t = max(k.t, branches[index].forkTime)
        branches[index].keyframes.append(k)
        branches[index].keyframes.sort { $0.t < $1.t }
        return k
    }

    /// Attach a settings table to the keyframe the plugin was asked about. The reply comes
    /// back long after the press, so it is matched by id rather than by time.
    @discardableResult
    public mutating func attachBlob(_ blob: String, toKeyframe id: String) -> Bool {
        for bi in branches.indices {
            if let ki = branches[bi].keyframes.firstIndex(where: { $0.id == id }) {
                branches[bi].keyframes[ki].blob = blob
                return true
            }
        }
        return false
    }

    /// Start a new line of editing at `t`, leaving everything before and after it intact.
    /// The parent keeps its whole future; this is the one thing Lightroom's history cannot do.
    @discardableResult
    public mutating func fork(at t: TimeInterval, name: String? = nil, wall: Date = Date()) -> TrailBranch {
        let takeNumber = branches.count + 1
        let branch = TrailBranch(
            name: name ?? "Take \(takeNumber)",
            parent: activeBranchID,
            forkTime: t,
            clockOrigin: wall
        )
        branches.append(branch)
        activeBranchID = branch.id
        updatedAt = wall
        return branch
    }

    /// Thin the oldest half of a long recording, keeping the ends of every gesture so the
    /// shape of the editing survives. Nothing is dropped from the recent past.
    static func thin(_ events: inout [TrailEvent]) {
        let cut = events.count / 2
        var kept: [TrailEvent] = []
        kept.reserveCapacity(events.count)
        for (i, event) in events.enumerated() {
            guard i < cut else {
                kept.append(event)
                continue
            }
            let isEdge = i == 0 || i == cut - 1
                || events[i - 1].param != event.param
                || (i + 1 < events.count && events[i + 1].param != event.param)
                || (i + 1 < events.count && events[i + 1].t - event.t > gestureGap)
            if isEdge || i.isMultiple(of: 2) {
                kept.append(event)
            }
        }
        events = kept
    }

    // MARK: - Playback

    public func playback(on branchID: String? = nil) -> TrailPlayback {
        TrailPlayback(trail: self, branchID: branchID ?? activeBranchID)
    }
}

/// A trail flattened onto one path, ready to be scrubbed. Built once per rewind and reused,
/// so moving the playhead is a binary search rather than a walk of the whole recording.
public struct TrailPlayback: Equatable {
    /// Every event on the path, split per parameter and in time order.
    public let series: [String: [TrailEvent]]
    public let keyframes: [TrailKeyframe]
    public let start: TimeInterval
    public let tip: TimeInterval
    /// Where each branch left this path, for the readout's forks.
    public let forks: [(time: TimeInterval, name: String, id: String)]
    /// Every moment something changed, oldest first, with the start and the tip as the two ends.
    /// One step is one thing you did, so the ring can walk them one at a time and any value you
    /// ever had is somewhere it can stop, whether the session was thirty seconds or two hours.
    public let stepTimes: [TimeInterval]
    /// Samples closer together than this are one step: a trackball's hue and saturation land a
    /// few milliseconds apart and are a single move.
    public static let stepMerge: TimeInterval = 0.03

    public static func == (lhs: TrailPlayback, rhs: TrailPlayback) -> Bool {
        lhs.series == rhs.series && lhs.keyframes == rhs.keyframes
            && lhs.start == rhs.start && lhs.tip == rhs.tip
            && lhs.forks.map(\.id) == rhs.forks.map(\.id)
    }

    public init(trail: EditTrail, branchID: String) {
        let chain = trail.lineage(of: branchID)
        var bounds: [(TrailBranch, TimeInterval)] = []
        for (i, b) in chain.enumerated() {
            let end = i + 1 < chain.count ? chain[i + 1].forkTime : Double.greatestFiniteMagnitude
            bounds.append((b, end))
        }

        var grouped: [String: [TrailEvent]] = [:]
        var marks: [TrailKeyframe] = []
        var latest = chain.first?.forkTime ?? 0
        for (b, end) in bounds {
            for e in b.events where e.t >= b.forkTime && e.t <= end {
                grouped[e.param, default: []].append(e)
            }
            for k in b.keyframes where k.t >= b.forkTime && k.t <= end {
                marks.append(k)
            }
            latest = max(latest, min(b.localTip, end))
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.t < $1.t }
        }
        marks.sort { $0.t < $1.t }

        let startTime = chain.first?.forkTime ?? 0
        self.series = grouped
        self.keyframes = marks
        self.start = startTime
        self.tip = latest

        var moments = marks.map(\.t)
        for events in grouped.values { for e in events { moments.append(e.t) } }
        moments.sort()
        var steps: [TimeInterval] = []
        for t in moments {
            if let last = steps.last, t - last < TrailPlayback.stepMerge { continue }
            steps.append(t)
        }
        // The two ends are always places to stand. A landmark that opened the session a moment
        // after the clock started is the start, not a step of its own.
        if let first = steps.first, first - startTime < TrailPlayback.stepMerge {
            steps[0] = min(first, startTime)
        } else {
            steps.insert(startTime, at: 0)
        }
        if let last = steps.last, latest - last < TrailPlayback.stepMerge {
            steps[steps.count - 1] = max(last, latest)
        } else {
            steps.append(latest)
        }
        self.stepTimes = steps
        self.forks = trail.forks(of: branchID)
            .sorted { $0.forkTime < $1.forkTime }
            .map { (time: $0.forkTime, name: $0.name, id: $0.id) }
    }

    /// Every parameter the recording knows about.
    public var parameters: [String] { Array(series.keys) }

    /// The photo as it stood at `t`. Inside a gesture the value is interpolated, so scrubbing
    /// is continuous; between gestures the earlier value simply held, so the playhead steps.
    public func values(at t: TimeInterval) -> [String: Double] {
        var out = seed(at: t)?.values ?? [:]
        for (param, events) in series {
            guard let value = value(of: param, in: events, at: t) else { continue }
            out[param] = value
        }
        return out
    }

    public func value(of param: String, at t: TimeInterval) -> Double? {
        guard let events = series[param] else { return seed(at: t)?.values[param] }
        return value(of: param, in: events, at: t) ?? seed(at: t)?.values[param]
    }

    /// The table to start from. Before the first landmark there is nothing recorded yet, so the
    /// first landmark — the photo as it arrived — is the honest baseline.
    private func seed(at t: TimeInterval) -> TrailKeyframe? {
        keyframe(at: t) ?? keyframes.first
    }

    private func value(of param: String, in events: [TrailEvent], at t: TimeInterval) -> Double? {
        guard let i = lastIndex(in: events, atOrBefore: t) else { return nil }
        let a = events[i]
        guard i + 1 < events.count else { return a.value }
        let b = events[i + 1]
        let span = b.t - a.t
        guard span > 0, span <= EditTrail.gestureGap else { return a.value }
        let f = min(1.0, max(0.0, (t - a.t) / span))
        return a.value + (b.value - a.value) * f
    }

    private func lastIndex(in events: [TrailEvent], atOrBefore t: TimeInterval) -> Int? {
        guard let first = events.first, first.t <= t else { return nil }
        var low = 0
        var high = events.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if events[mid].t <= t {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// The landmark at or before `t`: what a restore would put back exactly.
    public func keyframe(at t: TimeInterval) -> TrailKeyframe? {
        var best: TrailKeyframe?
        for k in keyframes {
            if k.t <= t + 0.0001 { best = k } else { break }
        }
        return best
    }

    public func previousLandmark(before t: TimeInterval) -> TrailKeyframe? {
        keyframes.last { $0.t < t - 0.05 }
    }

    public func nextLandmark(after t: TimeInterval) -> TrailKeyframe? {
        keyframes.first { $0.t > t + 0.05 }
    }

    /// Distinct moments on the tape: one continuous move counts as one edit, so a slow turn
    /// of the ring walks the editing rather than the samples.
    public var editTimes: [TimeInterval] {
        var times: [TimeInterval] = []
        for events in series.values {
            for e in events { times.append(e.t) }
        }
        times += keyframes.map(\.t)
        times.sort()
        // A run counts as one edit for as long as its samples keep coming; the next edit is
        // wherever the hand stopped for longer than a gesture. Measured sample to sample, so a
        // long slow turn stays one edit rather than splitting every `gestureGap`.
        var merged: [TimeInterval] = []
        var previous: TimeInterval?
        for t in times {
            if let previous, t - previous < EditTrail.gestureGap {
                // still the same move
            } else {
                merged.append(t)
            }
            previous = t
        }
        return merged
    }

    /// Index of the last step at or before `t`; -1 when `t` is before all of them.
    public func stepIndex(atOrBefore t: TimeInterval) -> Int {
        var low = 0
        var high = stepTimes.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if stepTimes[mid] <= t + 1e-9 {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// The step `clicks` away from `t`, parking on the ends rather than wrapping. Forward from
    /// between two steps lands on the next one; back from between two lands on the one behind.
    public func step(from t: TimeInterval, by clicks: Int) -> TimeInterval {
        guard !stepTimes.isEmpty, clicks != 0 else { return t }
        let i = stepIndex(atOrBefore: t)
        let onStep = i >= 0 && abs(stepTimes[i] - t) < 1e-6
        let target = clicks > 0 ? i + clicks : (onStep ? i + clicks : i + clicks + 1)
        return stepTimes[min(stepTimes.count - 1, max(0, target))]
    }

    /// How long the stretch of quiet around `t` is, when `t` sits inside one.
    public func surroundingGap(at t: TimeInterval) -> TimeInterval? {
        let i = stepIndex(atOrBefore: t)
        guard i >= 0, i + 1 < stepTimes.count else { return nil }
        return stepTimes[i + 1] - stepTimes[i]
    }

    /// The nearest edit before or after `from`, for one-edit-at-a-time scrubbing.
    public func stepToEdit(from: TimeInterval, forward: Bool) -> TimeInterval {
        let times = editTimes
        if forward {
            return times.first { $0 > from + 0.01 } ?? tip
        }
        return times.last { $0 < from - 0.01 } ?? start
    }

    /// Marks pull the playhead in when it comes close, so "I liked it" is easy to land on.
    public func snapTarget(near t: TimeInterval, within window: TimeInterval) -> TimeInterval? {
        var best: TrailKeyframe?
        var bestDistance = window
        for k in keyframes where k.snaps {
            let d = abs(k.t - t)
            if d < bestDistance {
                bestDistance = d
                best = k
            }
        }
        return best?.t
    }
}

// MARK: - Persistence

/// Trails live beside the map, one file per photo, and outlive quitting.
public enum TrailStore {
    public static var directory: URL {
        AppPaths.supportDir.appendingPathComponent("Trails", isDirectory: true)
    }

    /// A photo id is a catalog string; make it a filename without losing which photo it is.
    public static func fileName(for photoID: String) -> String {
        let safe = photoID.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return "\(String(String(safe).prefix(48)))-\(fnv1a(photoID)).json"
    }

    /// Stable across launches, unlike `hashValue`.
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Array(text.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    public static func url(for photoID: String, in dir: URL? = nil) -> URL {
        (dir ?? directory).appendingPathComponent(fileName(for: photoID))
    }

    public static func save(_ trail: EditTrail, in dir: URL? = nil) throws {
        var copy = trail
        copy.updatedAt = Date()
        let folder = dir ?? directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(copy).write(to: url(for: trail.photoID, in: folder), options: .atomic)
    }

    public static func load(photoID: String, in dir: URL? = nil) -> EditTrail? {
        guard let data = try? Data(contentsOf: url(for: photoID, in: dir)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var trail = try? decoder.decode(EditTrail.self, from: data) else { return nil }
        // A file written by a newer PanaLux is left alone rather than rewritten badly.
        guard trail.version <= EditTrail.formatVersion else { return nil }
        if trail.branch(trail.activeBranchID) == nil, let first = trail.branches.first {
            trail.activeBranchID = first.id
        }
        return trail.branches.isEmpty ? nil : trail
    }

    public static func delete(photoID: String, in dir: URL? = nil) {
        try? FileManager.default.removeItem(at: url(for: photoID, in: dir))
    }
}
