// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common

@MainActor
protocol TabRestoreLaunchTracking: AnyObject {
    /// Records a restore for `windowUUID`; returns true only for the first call per window in this process.
    func registerRestore(for windowUUID: WindowUUID) -> Bool
}

@MainActor
final class DefaultTabRestoreLaunchTracker: TabRestoreLaunchTracking {
    static let shared = DefaultTabRestoreLaunchTracker()

    private var restoredWindowUUIDs = Set<WindowUUID>()

    func registerRestore(for windowUUID: WindowUUID) -> Bool {
        return restoredWindowUUIDs.insert(windowUUID).inserted
    }
}
