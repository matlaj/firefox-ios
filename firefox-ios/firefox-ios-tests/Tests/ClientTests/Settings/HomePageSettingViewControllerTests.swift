// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Shared

@testable import Client

@MainActor
final class HomePageSettingViewControllerTests: XCTestCase, FeatureFlagTestUtility {
    internal var mockProfile: MockProfile!
    internal var mockNimbusLayer: MockNimbusFeatureFlagLayer!
    private var delegate: MockSettingsDelegate!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = makeProfile()
        mockNimbusLayer = MockNimbusFeatureFlagLayer()

        DependencyHelperMock().bootstrapDependencies(
            injectedProfile: mockProfile,
            injectedFeatureFlagProvider: featureFlagsProviderFactory(),
            injectedUserFeaturePreferences: userFeaturePreferenceManagerFactory()
        )

        delegate = MockSettingsDelegate()
    }

    override func tearDown() async throws {
        DependencyHelperMock().reset()
        mockProfile = nil
        delegate = nil
        mockNimbusLayer = nil

        try await super.tearDown()
    }

    func testHomePageSettingsLeaks_InitCall() throws {
        let subject = createSubject()
        subject.profile = mockProfile
        // Mirrors viewWillAppear(_:), which retains the generated settings on the controller.
        subject.settings = subject.generateSettings()
    }

    func testHomepageSettings_generateSettings_jumpBackInSectionDefaultValue_isFalse() throws {
        let subject = createSubject()
        subject.profile = mockProfile

        let settingsList = subject.generateSettings()

        let customizeFirefoxHomeSettingsList = settingsList.first(
            where: {
                $0.title?.string == .Settings.Homepage.CustomizeFirefoxHome.Title
            })

        let jumpBackInSectionSetting = customizeFirefoxHomeSettingsList?.children.first(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.JumpBackInSection
            }) as? BoolSetting

        let jumpBackInSectionSettingValue = try XCTUnwrap(jumpBackInSectionSetting?.getDefaultValue())

        XCTAssertFalse(jumpBackInSectionSettingValue)
    }

    func testHomepageSettings_generateSettings_bookmarksSectionDefaultValue_isFalse() throws {
        let subject = createSubject()
        subject.profile = mockProfile

        let settingsList = subject.generateSettings()

        let customizeFirefoxHomeSettingsList = settingsList.first(
            where: {
                $0.title?.string == .Settings.Homepage.CustomizeFirefoxHome.Title
            })

        let bookmarksSectionSetting = customizeFirefoxHomeSettingsList?.children.first(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.BookmarksSection
            }) as? BoolSetting

        let bookmarksSectionSettingValue = try XCTUnwrap(bookmarksSectionSetting?.getDefaultValue())

        XCTAssertFalse(bookmarksSectionSettingValue)
    }

    func testHomepageSettings_generateSettings_trackerBlockerModule_whenFeatureDisabled_isHidden() throws {
        let subject = createSubject()
        subject.profile = mockProfile

        let settingsList = subject.generateSettings()

        let customizeFirefoxHomeSettingsList = settingsList.first(
            where: {
                $0.title?.string == .Settings.Homepage.CustomizeFirefoxHome.Title
            })

        let trackerBlockerModuleSetting = customizeFirefoxHomeSettingsList?.children.first(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.TrackerBlockerSection
            }) as? BoolSetting

        XCTAssertNil(trackerBlockerModuleSetting)
    }

    func testHomepageSettings_generateSettings_trackerBlockerModule_whenFeatureEnabledDefaultValue_isTrue() throws {
        setFeatureFlag(.homepageTrackerBlockerModule, isEnabled: true)
        let subject = createSubject()
        subject.profile = mockProfile

        let settingsList = subject.generateSettings()

        let customizeFirefoxHomeSettingsList = settingsList.first(
            where: {
                $0.title?.string == .Settings.Homepage.CustomizeFirefoxHome.Title
            })

        let trackerBlockerModuleSetting = customizeFirefoxHomeSettingsList?.children.first(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.TrackerBlockerSection
            }) as? BoolSetting

        let trackerBlockerModuleSettingValue = try XCTUnwrap(trackerBlockerModuleSetting?.getDefaultValue())

        XCTAssertTrue(trackerBlockerModuleSettingValue)
    }

    func testHomepageSettings_generateSettings_trackerBlockerModule_isOrderedBetweenShortcutsAndJumpBackIn() throws {
        setFeatureFlag(.homepageTrackerBlockerModule, isEnabled: true)
        let subject = createSubject()
        subject.profile = mockProfile

        let settingsList = subject.generateSettings()

        let customizeFirefoxHomeSettingsList = try XCTUnwrap(settingsList.first(
            where: {
                $0.title?.string == .Settings.Homepage.CustomizeFirefoxHome.Title
            }))

        let children = customizeFirefoxHomeSettingsList.children
        let shortcutsIndex = try XCTUnwrap(children.firstIndex(
            where: {
                $0 is HomePageSettingViewController.TopSitesSettings
            }))
        let trackerBlockerModuleIndex = try XCTUnwrap(children.firstIndex(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.TrackerBlockerSection
            }))
        let jumpBackInIndex = try XCTUnwrap(children.firstIndex(
            where: {
                ($0 as? BoolSetting)?.prefKey == PrefsKeys.HomepageSettings.JumpBackInSection
            }))

        XCTAssertLessThan(shortcutsIndex, trackerBlockerModuleIndex)
        XCTAssertLessThan(trackerBlockerModuleIndex, jumpBackInIndex)
    }

    func testHomepageSettings_generateSettings_openingScreenOptions_areOrderedWithClosingTabsBelowHomepage() throws {
        let subject = createSubject()
        subject.profile = mockProfile

        let titles = try openingScreenOptions(in: subject).map { $0.title?.string }

        XCTAssertEqual(titles, [
            .Settings.Homepage.StartAtHome.Always,
            .Settings.Homepage.StartAtHome.AlwaysClosingTabs,
            .Settings.Homepage.StartAtHome.Never,
            .Settings.Homepage.StartAtHome.AfterFourHours
        ])
    }

    func testHomepageSettings_selectingAlwaysClosingTabs_setsAlwaysAndCloseTabsOnLaunch() throws {
        let subject = createSubject()
        subject.profile = mockProfile
        let options = try openingScreenOptions(in: subject)

        options[1].onChecked()

        XCTAssertEqual(mockProfile.prefs.stringForKey(PrefsKeys.FeatureFlags.StartAtHome),
                       StartAtHomeSetting.always.rawValue)
        XCTAssertEqual(mockProfile.prefs.boolForKey(PrefsKeys.Settings.closeTabsOnLaunch), true)
        XCTAssertFalse(options[0].isChecked())
        XCTAssertTrue(options[1].isChecked())
    }

    func testHomepageSettings_selectingHomepage_afterAlwaysClosingTabs_turnsOffCloseTabsOnLaunch() throws {
        let subject = createSubject()
        subject.profile = mockProfile
        let options = try openingScreenOptions(in: subject)

        options[1].onChecked()
        options[0].onChecked()

        XCTAssertEqual(mockProfile.prefs.stringForKey(PrefsKeys.FeatureFlags.StartAtHome),
                       StartAtHomeSetting.always.rawValue)
        XCTAssertEqual(mockProfile.prefs.boolForKey(PrefsKeys.Settings.closeTabsOnLaunch), false)
        XCTAssertTrue(options[0].isChecked())
        XCTAssertFalse(options[1].isChecked())
    }

    func testHomepageSettings_selectingLastTab_afterAlwaysClosingTabs_turnsOffCloseTabsOnLaunch() throws {
        let subject = createSubject()
        subject.profile = mockProfile
        let options = try openingScreenOptions(in: subject)

        options[1].onChecked()
        options[2].onChecked()

        XCTAssertEqual(mockProfile.prefs.stringForKey(PrefsKeys.FeatureFlags.StartAtHome),
                       StartAtHomeSetting.disabled.rawValue)
        XCTAssertEqual(mockProfile.prefs.boolForKey(PrefsKeys.Settings.closeTabsOnLaunch), false)
        XCTAssertFalse(options[1].isChecked())
    }

    func testHomepageSettings_generateSettings_withCloseTabsOnLaunchPref_checksAlwaysClosingTabs() throws {
        mockProfile.prefs.setString(StartAtHomeSetting.always.rawValue, forKey: PrefsKeys.FeatureFlags.StartAtHome)
        mockProfile.prefs.setBool(true, forKey: PrefsKeys.Settings.closeTabsOnLaunch)
        let subject = createSubject()
        subject.profile = mockProfile

        let options = try openingScreenOptions(in: subject)

        XCTAssertEqual(options.map { $0.isChecked() }, [false, true, false, false])
    }

    // MARK: - Helpers

    private func openingScreenOptions(in subject: HomePageSettingViewController) throws -> [CheckmarkSetting] {
        let openingScreenSettingsList = try XCTUnwrap(subject.generateSettings().first(
            where: {
                $0.title?.string == .Settings.Homepage.StartAtHome.SectionTitle
            }))
        return openingScreenSettingsList.children.compactMap { $0 as? CheckmarkSetting }
    }

    private func createSubject() -> HomePageSettingViewController {
        let subject = HomePageSettingViewController(prefs: mockProfile.prefs,
                                                    settingsDelegate: delegate,
                                                    tabManager: MockTabManager())
        trackForMemoryLeaks(subject)
        return subject
    }
}
