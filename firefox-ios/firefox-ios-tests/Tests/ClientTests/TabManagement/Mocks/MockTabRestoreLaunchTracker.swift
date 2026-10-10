// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
@testable import Client

@MainActor
final class MockTabRestoreLaunchTracker: TabRestoreLaunchTracking {
    var isFirstRestore: Bool
    var registeredWindowUUIDs: [WindowUUID] = []

    init(isFirstRestore: Bool = true) {
        self.isFirstRestore = isFirstRestore
    }

    func registerRestore(for windowUUID: WindowUUID) -> Bool {
        registeredWindowUUIDs.append(windowUUID)
        return isFirstRestore
    }
}
