// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import XCTest
import TabDataStore
import Common
import Shared
@testable import Client

final class TabManagerRestoreTabsTests: TabManagerTestsBase {
    override func setUp() async throws {
        // A run killed before its teardown block leaks this key and would skip restore for every test here.
        UserDefaults.standard.removeObject(forKey: Self.skipSessionRestoreDefaultsKey)
        try await super.setUp()
    }

    @MainActor
    func testRestoreTabs() {
        // Needed to ensure AppEventQueue is not fired from a previous test case with the same WindowUUID
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: UUID(),
                                                     tabData: getMockTabData(count: 4))

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) { [mockTabStore] in
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 4)
                XCTAssertEqual(mockTabStore?.fetchWindowDataCalledCount, 1)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    // MARK: - Deeplink-optimization refactor path (snapshot-and-merge)

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_restoresPersistedTabs() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: UUID(),
                                                     tabData: getMockTabData(count: 3))

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) { [mockTabStore] in
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 3)
                XCTAssertEqual(mockTabStore?.fetchWindowDataCalledCount, 1)
                XCTAssertTrue(subject.tabRestoreHasFinished)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_mergesPreRestoreTabsAtEndOfArray() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        // Simulate a deeplink tab added before restore ran.
        let deeplinkTabs = generateTabs(ofType: .normal, count: 1)
        let subject = createSubject(tabs: deeplinkTabs, windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: UUID(),
                                                     tabData: getMockTabData(count: 2))

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 3, "2 restored + 1 pre-restore deeplink tab")
                XCTAssertIdentical(subject.tabs.last, deeplinkTabs.first, "Deeplink tab should land at the end")
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_isOneShotPerSession() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: UUID(),
                                                     tabData: getMockTabData(count: 2))

        subject.restoreTabs()
        // Second call must be a no-op even though tabs are no longer empty post-restore.
        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) { [mockTabStore] in
            ensureMainThread {
                XCTAssertEqual(mockTabStore?.fetchWindowDataCalledCount,
                               1,
                               "Data store should be fetched at most once per session")
                XCTAssertEqual(subject.tabs.count, 2)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_selectsActiveTabFromRestorationResult() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")

        let activeId = UUID()
        var tabData = getMockTabData(count: 3)
        tabData[1] = TabData(id: activeId,
                             title: tabData[1].title,
                             siteUrl: tabData[1].siteUrl,
                             faviconURL: tabData[1].faviconURL,
                             isPrivate: false,
                             lastUsedTime: tabData[1].lastUsedTime,
                             createdAtTime: tabData[1].createdAtTime,
                             temporaryDocumentSession: [:])
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: activeId,
                                                     tabData: tabData)

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.selectedTab?.tabUUID, activeId.uuidString)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_createsNewTabWhenNothingToRestore() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        // No persisted window data — restoration result will be empty.
        mockTabStore.fetchTabWindowData = nil

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 1, "Should fall back to creating a fresh tab")
                XCTAssertNotNil(subject.selectedTab)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_preservesDeeplinkWhenRestorationResultIsEmpty() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let deeplinkTabs = generateTabs(ofType: .normal, count: 1)
        let subject = createSubject(tabs: deeplinkTabs, windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        // No persisted window data — restoration result will be empty, but deeplink must survive.
        mockTabStore.fetchTabWindowData = nil

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 1, "Deeplink should be preserved; no extra empty tab created")
                XCTAssertIdentical(subject.tabs.first, deeplinkTabs.first)
                XCTAssertIdentical(subject.selectedTab, deeplinkTabs.first, "Deeplink should be selected")
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_selectsActiveRestoredTabOverDeeplink() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let deeplinkTabs = generateTabs(ofType: .normal, count: 1)
        let subject = createSubject(tabs: deeplinkTabs, windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")

        let activeId = UUID()
        var tabData = getMockTabData(count: 3)
        tabData[1] = TabData(id: activeId,
                             title: tabData[1].title,
                             siteUrl: tabData[1].siteUrl,
                             faviconURL: tabData[1].faviconURL,
                             isPrivate: false,
                             lastUsedTime: tabData[1].lastUsedTime,
                             createdAtTime: tabData[1].createdAtTime,
                             temporaryDocumentSession: [:])
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: activeId,
                                                     tabData: tabData)

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 4, "3 restored + 1 pre-restore deeplink tab")
                XCTAssertEqual(subject.selectedTab?.tabUUID,
                               activeId.uuidString,
                               "Active restored tab should win over deeplink")
                XCTAssertIdentical(subject.tabs.last, deeplinkTabs.first, "Deeplink should still land at the end")
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    // MARK: - pendingDeeplinkTab Activity

    @MainActor
    func testRestoreTabs_withPendingDeeplinkTabActivity_skipsPostRestoreTabSelection() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        let testUUID = UUID()
        let initialTab = generateTabs(ofType: .normal, count: 1).first!
        let subject = createSubject(tabs: [initialTab], windowUUID: testUUID)
        subject.selectTab(initialTab)

        AppEventQueue.started(.pendingDeeplinkTab(testUUID))
        defer { AppEventQueue.completed(.pendingDeeplinkTab(testUUID)) }

        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        let activeId = UUID()
        var tabData = getMockTabData(count: 3)
        tabData[1] = TabData(id: activeId,
                             title: tabData[1].title,
                             siteUrl: tabData[1].siteUrl,
                             faviconURL: tabData[1].faviconURL,
                             isPrivate: false,
                             lastUsedTime: tabData[1].lastUsedTime,
                             createdAtTime: tabData[1].createdAtTime,
                             temporaryDocumentSession: [:])
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: activeId,
                                                     tabData: tabData)

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertNotEqual(subject.selectedTab?.tabUUID,
                                  activeId.uuidString,
                                  "Restored active tab should not be selected while deeplink is pending")
                XCTAssertEqual(subject.tabs.last?.tabUUID, initialTab.tabUUID)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    @MainActor
    func testRestoreTabs_legacyPath_withPendingDeeplinkTabActivity_skipsPostRestoreTabSelection() {
        setIsDeeplinkOptimizationRefactorEnabled(false)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)

        AppEventQueue.started(.pendingDeeplinkTab(testUUID))
        defer { AppEventQueue.completed(.pendingDeeplinkTab(testUUID)) }

        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")
        let activeId = UUID()
        var tabData = getMockTabData(count: 3)
        tabData[1] = TabData(id: activeId,
                             title: tabData[1].title,
                             siteUrl: tabData[1].siteUrl,
                             faviconURL: tabData[1].faviconURL,
                             isPrivate: false,
                             lastUsedTime: tabData[1].lastUsedTime,
                             createdAtTime: tabData[1].createdAtTime,
                             temporaryDocumentSession: [:])
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: activeId,
                                                     tabData: tabData)

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) {
            ensureMainThread {
                XCTAssertEqual(subject.tabs.count, 3)
                XCTAssertNotEqual(subject.selectedTab?.tabUUID,
                                  activeId.uuidString,
                                  "Restored active tab should not be selected while deeplink is pending")
                XCTAssertNil(subject.selectedTab)
                expectation.fulfill()
            }
        }
        wait(for: [expectation])
    }

    // MARK: - Close tabs on launch

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_opensSingleFreshTab() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true)
        let subject = createSubject(windowUUID: UUID(), launchTracker: MockTabRestoreLaunchTracker())

        try await restoreSavedTabs(in: subject, waitForForcedSave: true)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 0)
        XCTAssertEqual(subject.tabs.count, 1)
        XCTAssertIdentical(subject.selectedTab, subject.tabs.first)
        XCTAssertTrue(subject.tabRestoreHasFinished)
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_restoresTabsWhenNotFirstRestore() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true)
        let subject = createSubject(windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(isFirstRestore: false))

        try await restoreSavedTabs(in: subject)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 1)
        XCTAssertEqual(subject.tabs.count, 3)
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunchOff_restoresTabsAndRegistersRestore() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(false)
        let launchTracker = MockTabRestoreLaunchTracker()
        let subject = createSubject(windowUUID: UUID(), launchTracker: launchTracker)

        try await restoreSavedTabs(in: subject)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 1)
        XCTAssertEqual(subject.tabs.count, 3)
        XCTAssertEqual(launchTracker.registeredWindowUUIDs, [subject.windowUUID])
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_restoresTabsWhenOpeningScreenNotHomepage() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true, startAtHome: .disabled)
        let subject = createSubject(windowUUID: UUID(), launchTracker: MockTabRestoreLaunchTracker())

        try await restoreSavedTabs(in: subject)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 1)
        XCTAssertEqual(subject.tabs.count, 3)
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_keepsDeeplinkTab() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true)
        let deeplinkTabs = generateTabs(ofType: .normal, count: 1)
        let homepageTabProvider = MockHomepageTabProvider()
        let subject = createSubject(tabs: deeplinkTabs,
                                    windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(),
                                    homepageTabProvider: homepageTabProvider)

        try await restoreSavedTabs(in: subject, waitForForcedSave: true)

        XCTAssertEqual(subject.tabs.count, 1)
        XCTAssertIdentical(subject.tabs.first, deeplinkTabs.first)
        XCTAssertIdentical(subject.selectedTab, deeplinkTabs.first)
        XCTAssertEqual(homepageTabProvider.homepageTabCalledCount, 0)
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_opensHomepageTab() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true)
        let homepageTabProvider = MockHomepageTabProvider()
        let subject = createSubject(windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(),
                                    homepageTabProvider: homepageTabProvider)

        try await restoreSavedTabs(in: subject, waitForForcedSave: true)

        XCTAssertEqual(homepageTabProvider.homepageTabCalledCount, 1)
        XCTAssertEqual(homepageTabProvider.lastIsPrivate, false)
        XCTAssertNil(homepageTabProvider.lastExistingTab)
        XCTAssertIdentical(subject.selectedTab, homepageTabProvider.returnedTab)
        XCTAssertEqual(subject.tabs.count, 1)
    }

    @MainActor
    func testRestoreTabs_withDeeplinkFlagEnabled_closeTabsOnLaunch_overwritesSavedTabs() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setCloseTabsOnLaunch(true)
        let subject = createSubject(windowUUID: UUID(), launchTracker: MockTabRestoreLaunchTracker())

        try await restoreSavedTabs(in: subject, waitForForcedSave: true)

        XCTAssertEqual(subject.tabs.count, 1)
        XCTAssertEqual(mockTabStore.saveWindowData?.tabData.count, 1)
        XCTAssertEqual(mockTabStore.saveWindowDataForcedValue, true)
    }

    @MainActor
    func testRestoreTabs_legacyPath_closeTabsOnLaunch_opensSingleFreshTab() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(false)
        setCloseTabsOnLaunch(true)
        let homepageTabProvider = MockHomepageTabProvider()
        let subject = createSubject(windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(),
                                    homepageTabProvider: homepageTabProvider)

        try await restoreSavedTabs(in: subject, waitForForcedSave: true)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 0)
        XCTAssertEqual(subject.tabs.count, 1)
        XCTAssertEqual(homepageTabProvider.homepageTabCalledCount, 1)
        XCTAssertEqual(homepageTabProvider.lastIsPrivate, false)
        XCTAssertIdentical(subject.selectedTab, homepageTabProvider.returnedTab)
    }

    @MainActor
    func testRestoreTabs_legacyPath_closeTabsOnLaunch_withPendingDeeplink_skipsHomepageTab() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(false)
        setCloseTabsOnLaunch(true)
        let homepageTabProvider = MockHomepageTabProvider()
        let subject = createSubject(windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(),
                                    homepageTabProvider: homepageTabProvider)
        AppEventQueue.started(.pendingDeeplinkTab(subject.windowUUID))
        defer { AppEventQueue.completed(.pendingDeeplinkTab(subject.windowUUID)) }

        try await restoreSavedTabs(in: subject)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 0)
        XCTAssertEqual(homepageTabProvider.homepageTabCalledCount, 0)
        XCTAssertTrue(subject.tabs.isEmpty)
        XCTAssertNil(subject.selectedTab)
    }

    @MainActor
    func testRestoreTabs_legacyPath_closeTabsOnLaunch_restoresTabsWhenNotFirstRestore() async throws {
        setIsDeeplinkOptimizationRefactorEnabled(false)
        setCloseTabsOnLaunch(true)
        let subject = createSubject(windowUUID: UUID(),
                                    launchTracker: MockTabRestoreLaunchTracker(isFirstRestore: false))

        try await restoreSavedTabs(in: subject)

        XCTAssertEqual(mockTabStore.fetchWindowDataCalledCount, 1)
        XCTAssertEqual(subject.tabs.count, 3)
    }

    // MARK: - Skipped session restore

    /// FXIOS-16244. The explicit timeout makes a regression fail rather than hang the suite.
    @MainActor
    func testRestoreTabs_whenSessionRestoreIsSkipped_stillCompletesTabRestorationEvent() {
        setSkipSessionRestore(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) { [mockTabStore] in
            ensureMainThread {
                XCTAssertEqual(mockTabStore?.fetchWindowDataCalledCount, 0, "Restore should have been skipped")
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: skippedRestoreTimeout)
    }

    @MainActor
    func testRestoreTabs_whenSessionRestoreIsSkippedWithDeeplinkFlagEnabled_stillCompletesTabRestorationEvent() {
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setSkipSessionRestore(true)
        let testUUID = UUID()
        let subject = createSubject(windowUUID: testUUID)
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(testUUID)) { [mockTabStore] in
            ensureMainThread {
                XCTAssertEqual(mockTabStore?.fetchWindowDataCalledCount, 0, "Restore should have been skipped")
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: skippedRestoreTimeout)
    }

    // MARK: - Helpers

    private static let skipSessionRestoreDefaultsKey = "SettingsBundleSkipSessionRestore"

    private let skippedRestoreTimeout: TimeInterval = 5

    /// Restores three saved tabs into `subject` and waits for its `.tabRestoration` event.
    /// - Parameter waitForForcedSave: Also waits out the forced save of a cleared window, which
    ///   retains the subject until it finishes.
    @MainActor
    private func restoreSavedTabs(in subject: TabManagerImplementation,
                                  waitForForcedSave: Bool = false) async throws {
        mockTabStore.fetchTabWindowData = WindowData(id: UUID(),
                                                     activeTabId: UUID(),
                                                     tabData: getMockTabData(count: 3))
        let expectation = XCTestExpectation(description: "Tab restoration event should have been called")

        subject.restoreTabs()

        AppEventQueue.wait(for: .tabRestoration(subject.windowUUID)) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation])
        if waitForForcedSave {
            try await Task.sleep(nanoseconds: sleepTime)
        }
    }

    /// Mirrors how the Homepage settings store "Homepage, closing all previous tabs".
    private func setCloseTabsOnLaunch(_ enabled: Bool, startAtHome: StartAtHomeSetting = .always) {
        mockProfile.prefs.setBool(enabled, forKey: PrefsKeys.Settings.closeTabsOnLaunch)
        mockProfile.prefs.setString(startAtHome.rawValue, forKey: PrefsKeys.FeatureFlags.StartAtHome)
    }

    private func setSkipSessionRestore(_ skip: Bool) {
        UserDefaults.standard.set(skip, forKey: Self.skipSessionRestoreDefaultsKey)
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: Self.skipSessionRestoreDefaultsKey)
        }
    }
}
