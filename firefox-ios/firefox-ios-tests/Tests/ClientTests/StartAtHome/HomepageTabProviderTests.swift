// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Shared
import XCTest

@testable import Client

@MainActor
final class HomepageTabProviderTests: XCTestCase {
    private var mockProfile: MockProfile!
    private var mockTabManager: MockTabManager!
    private let customHomepageURL = URL(string: "https://www.mozilla.org")!
    private let firefoxHomeURL = URL(string: "internal://local/about/home")!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = makeProfile()
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)
        mockTabManager = MockTabManager()
    }

    override func tearDown() async throws {
        mockProfile = nil
        mockTabManager = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Custom homepage URL

    func testHomepageTab_withCustomURL_addsTabWithCustomURL() {
        setHomepage(.homePage, customURL: customHomepageURL)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: false)

        XCTAssertNotNil(tab)
        XCTAssertTrue(mockTabManager.addTabWasCalled)
        XCTAssertEqual(mockTabManager.lastAddTabRequest?.url, customHomepageURL)
        XCTAssertEqual(tab?.isPrivate, false)
    }

    func testHomepageTab_withCustomURL_reusesExistingTab() {
        setHomepage(.homePage, customURL: customHomepageURL)
        let existingTab = Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: existingTab, isPrivate: false)

        XCTAssertIdentical(tab, existingTab)
        XCTAssertFalse(mockTabManager.addTabWasCalled)
    }

    func testHomepageTab_withCustomURL_inPrivateMode_addsPrivateTab() {
        setHomepage(.homePage, customURL: customHomepageURL)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: true)

        XCTAssertEqual(tab?.isPrivate, true)
    }

    // MARK: - Firefox Home

    func testHomepageTab_withFirefoxHome_addsTabShowingFirefoxHome() {
        setHomepage(.topSites)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: false)

        XCTAssertTrue(mockTabManager.addTabWasCalled)
        XCTAssertEqual(tab?.url, firefoxHomeURL)
        XCTAssertEqual(tab?.isPrivate, false)
    }

    func testHomepageTab_withFirefoxHome_reusesExistingTab() {
        setHomepage(.topSites)
        let existingTab = Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: existingTab, isPrivate: false)

        XCTAssertIdentical(tab, existingTab)
        XCTAssertEqual(existingTab.url, firefoxHomeURL)
        XCTAssertFalse(mockTabManager.addTabWasCalled)
    }

    func testHomepageTab_withHomepageCustomButNoURL_fallsBackToFirefoxHome() {
        setHomepage(.homePage)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: false)

        XCTAssertEqual(tab?.url, firefoxHomeURL)
    }

    // MARK: - Blank page

    func testHomepageTab_withBlankPage_returnsSelectedTab() {
        setHomepage(.blankPage)
        let selectedTab = Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID)
        mockTabManager.selectedTab = selectedTab
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: false)

        XCTAssertIdentical(tab, selectedTab)
        XCTAssertFalse(mockTabManager.addTabWasCalled)
    }

    func testHomepageTab_withBlankPage_andNoSelectedTab_addsTab() {
        setHomepage(.blankPage)
        let subject = createSubject()

        let tab = subject.homepageTab(in: mockTabManager, reusing: nil, isPrivate: false)

        XCTAssertNotNil(tab)
        XCTAssertTrue(mockTabManager.addTabWasCalled)
        XCTAssertNil(mockTabManager.lastAddTabRequest)
    }

    // MARK: - Helpers

    private func createSubject() -> DefaultHomepageTabProvider {
        return DefaultHomepageTabProvider(prefs: mockProfile.prefs)
    }

    private func setHomepage(_ page: NewTabPage, customURL: URL? = nil) {
        mockProfile.prefs.setString(page.rawValue, forKey: PrefsKeys.HomePageTab)
        if let customURL {
            mockProfile.prefs.setString(customURL.absoluteString, forKey: PrefsKeys.HomeButtonHomePageURL)
        }
    }
}
