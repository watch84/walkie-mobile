import Foundation

/// Port of the web client's `src/radio/stations.ts`.
struct ChannelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    /// `LIVE_CHANNELS`
    static let live: [ChannelInfo] = [
        ChannelInfo(id: "channel-1", name: "Channel 1"),
        ChannelInfo(id: "channel-2", name: "Channel 2"),
        ChannelInfo(id: "channel-3", name: "Channel 3"),
    ]
    static let defaultChannel = live[0]
}

struct Station: Identifiable, Hashable, Sendable {
    let index: Int
    let frequency: String
    let name: String
    /// nil for locked stations, which never touch the network.
    let channel: ChannelInfo?

    var id: Int { index }
    var isLocked: Bool { channel == nil }
}

enum Stations {
    /// `STATIONS`
    static let all: [Station] = {
        let live = Dictionary(uniqueKeysWithValues: ChannelInfo.live.map { ($0.id, $0) })
        let rows: [(String, String, String?)] = [
            ("88.1", "Morning Static", nil),
            ("89.7", "Night Shift", nil),
            ("91.3", "Field Notes", nil),
            ("92.9", "Channel 1", "channel-1"),
            ("94.5", "Channel 2", "channel-2"),
            ("96.1", "Channel 3", "channel-3"),
            ("97.7", "Lo-Fi Desk", nil),
            ("99.3", "Open Mic", nil),
            ("100.9", "Late Bus", nil),
            ("102.5", "Weather Desk", nil),
            ("104.1", "Quiet Car", nil),
            ("105.7", "Deep Sea", nil),
        ]
        return rows.enumerated().map { index, row in
            Station(index: index, frequency: row.0, name: row.1, channel: row.2.flatMap { live[$0] })
        }
    }()

    /// `DEFAULT_STATION`: the index of Channel 1.
    static let defaultIndex = all.firstIndex { $0.channel?.id == "channel-1" }!

    static func clamp(_ index: Int) -> Int {
        min(max(index, 0), all.count - 1)
    }
}
