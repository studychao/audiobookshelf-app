import Foundation

enum ProgressSyncPolicy {
    static func shouldSend(now: Double, acknowledgedAt: Double, attemptedAt: Double, interval: Double, force: Bool) -> Bool {
        if force { return true }
        return now - acknowledgedAt >= interval && now - attemptedAt >= 5000
    }

    static func canDiscard(isActive: Bool, updatedAt: Double, acknowledgedThrough: Double) -> Bool {
        !isActive && updatedAt <= acknowledgedThrough
    }

    static func remainingListening(current: Double, reported: Double) -> Double {
        max(0, current - reported)
    }

    static func hasNewerRemote(localUpdatedAt: Double, remoteUpdatedAt: Double, localPosition: Double, remotePosition: Double) -> Bool {
        remoteUpdatedAt > localUpdatedAt && abs(localPosition - remotePosition) > 2
    }
}
