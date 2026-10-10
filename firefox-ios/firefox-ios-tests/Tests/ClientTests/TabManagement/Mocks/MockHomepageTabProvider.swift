// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
@testable import Client

@MainActor
final class MockHomepageTabProvider: HomepageTabProviding {
    var homepageTabCalledCount = 0
    var lastIsPrivate: Bool?
    var lastExistingTab: Tab?
    var returnedTab: Tab?

    func homepageTab(in tabManager: TabManager, reusing existingTab: Tab?, isPrivate: Bool) -> Tab? {
        homepageTabCalledCount += 1
        lastIsPrivate = isPrivate
        lastExistingTab = existingTab
        let tab = tabManager.addTab(nil, afterTab: nil, zombie: false, isPrivate: isPrivate)
        returnedTab = tab
        return tab
    }
}
