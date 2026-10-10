// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
@testable import Client

@MainActor
final class TabRestoreLaunchTrackerTests: XCTestCase {
    func testRegisterRestore_returnsTrue_forFirstRestoreOfWindow() {
        let subject = createSubject()

        XCTAssertTrue(subject.registerRestore(for: UUID()))
    }

    func testRegisterRestore_returnsFalse_forSecondRestoreOfSameWindow() {
        let subject = createSubject()
        let windowUUID = UUID()

        _ = subject.registerRestore(for: windowUUID)

        XCTAssertFalse(subject.registerRestore(for: windowUUID))
    }

    func testRegisterRestore_tracksWindowsIndependently() {
        let subject = createSubject()
        let firstWindowUUID = UUID()
        let secondWindowUUID = UUID()

        XCTAssertTrue(subject.registerRestore(for: firstWindowUUID))
        XCTAssertTrue(subject.registerRestore(for: secondWindowUUID))
        XCTAssertFalse(subject.registerRestore(for: firstWindowUUID))
        XCTAssertFalse(subject.registerRestore(for: secondWindowUUID))
    }

    // MARK: - Helpers

    private func createSubject(file: StaticString = #filePath,
                               line: UInt = #line) -> DefaultTabRestoreLaunchTracker {
        let subject = DefaultTabRestoreLaunchTracker()
        trackForMemoryLeaks(subject, file: file, line: line)
        return subject
    }
}
