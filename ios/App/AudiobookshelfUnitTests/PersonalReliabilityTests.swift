import XCTest
@testable import Audiobookshelf

final class PersonalReliabilityTests: XCTestCase {
    func testAuthenticationErrorIsNeverAcceptedAsAudio() {
        XCTAssertNotNil(DownloadValidation.failure(statusCode: 401, actualSize: 400, expectedSize: 400, isCover: false))
        XCTAssertNotNil(DownloadValidation.failure(statusCode: 403, actualSize: 400, expectedSize: 400, isCover: false))
    }
    func testTruncatedAndEmptyDownloadsAreRejected() {
        XCTAssertNotNil(DownloadValidation.failure(statusCode: 200, actualSize: 900, expectedSize: 1000, isCover: false))
        XCTAssertNotNil(DownloadValidation.failure(statusCode: 200, actualSize: 0, expectedSize: 0, isCover: true))
    }
    func testCompleteRangeDownloadAndConvertedCoverAreAccepted() {
        XCTAssertNil(DownloadValidation.failure(statusCode: 206, actualSize: 1000, expectedSize: 1000, isCover: false))
        XCTAssertNil(DownloadValidation.failure(statusCode: 200, actualSize: 750, expectedSize: 1000, isCover: true))
    }
    func testRetryIsBoundedAndDoesNotLoopAuthenticationFailures() {
        XCTAssertTrue(DownloadValidation.shouldRetry(errorCode: NSURLErrorNetworkConnectionLost, statusCode: nil, attempt: 0))
        XCTAssertFalse(DownloadValidation.shouldRetry(errorCode: nil, statusCode: 403, attempt: 0))
        XCTAssertFalse(DownloadValidation.shouldRetry(errorCode: NSURLErrorTimedOut, statusCode: nil, attempt: 3))
    }
    func testFailedSyncCanRetryBeforeNormalAcknowledgementInterval() {
        XCTAssertTrue(ProgressSyncPolicy.shouldSend(now: 10000, acknowledgedAt: -100000, attemptedAt: 0, interval: 15000, force: false))
        XCTAssertFalse(ProgressSyncPolicy.shouldSend(now: 4000, acknowledgedAt: -100000, attemptedAt: 0, interval: 15000, force: false))
    }
    func testNewListeningWhileSyncRunsIsNotDiscarded() {
        XCTAssertEqual(ProgressSyncPolicy.remainingListening(current: 19, reported: 15), 4)
        XCTAssertEqual(ProgressSyncPolicy.remainingListening(current: 2, reported: 15), 0)
    }
    func testSessionCannotBeDeletedWhileNewProgressIsPending() {
        XCTAssertFalse(ProgressSyncPolicy.canDiscard(isActive: false, updatedAt: 2000, acknowledgedThrough: 1000))
        XCTAssertFalse(ProgressSyncPolicy.canDiscard(isActive: true, updatedAt: 1000, acknowledgedThrough: 1000))
        XCTAssertTrue(ProgressSyncPolicy.canDiscard(isActive: false, updatedAt: 1000, acknowledgedThrough: 1000))
    }
    func testConflictUsesUpdateTimeRatherThanFurthestPosition() {
        XCTAssertTrue(ProgressSyncPolicy.hasNewerRemote(localUpdatedAt: 1000, remoteUpdatedAt: 2000, localPosition: 500, remotePosition: 100))
        XCTAssertFalse(ProgressSyncPolicy.hasNewerRemote(localUpdatedAt: 2000, remoteUpdatedAt: 1000, localPosition: 100, remotePosition: 500))
    }
}
