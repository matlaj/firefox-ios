// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

@MainActor
protocol HomepageTabProviding {
    /// Returns a tab showing the user's Homepage setting, reusing `existingTab` when provided.
    /// Falls back to the selected tab (or a new tab) when the Homepage setting is a blank page.
    func homepageTab(in tabManager: TabManager, reusing existingTab: Tab?, isPrivate: Bool) -> Tab?
}

@MainActor
struct DefaultHomepageTabProvider: HomepageTabProviding {
    private let prefs: Prefs

    init(prefs: Prefs) {
        self.prefs = prefs
    }

    func homepageTab(in tabManager: TabManager, reusing existingTab: Tab?, isPrivate: Bool) -> Tab? {
        let newTabPage = NewTabAccessors.getHomePage(prefs)
        let customHomepageUrl = HomeButtonHomePageAccessors.getHomePage(prefs)
        let homeUrl = URL(string: "internal://local/about/home")

        if newTabPage == .homePage, let customHomepageUrl {
            return existingTab ?? tabManager.addTab(URLRequest(url: customHomepageUrl), isPrivate: isPrivate)
        } else if newTabPage == .topSites, let homeUrl {
            let home = existingTab ?? tabManager.addTab(isPrivate: isPrivate)
            home.loadRequest(PrivilegedRequest(url: homeUrl) as URLRequest)
            home.url = homeUrl
            return home
        }

        return tabManager.selectedTab ?? tabManager.addTab()
    }
}
