// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Shared

@MainActor
final class StartAtHomeMiddleware {
    private let windowManager: WindowManager
    private let logger: Logger
    private let prefs: Prefs
    private let dateProvider: DateProvider
    private let homepageTabProvider: HomepageTabProviding

    init(profile: Profile = AppContainer.shared.resolve(),
         windowManager: WindowManager = AppContainer.shared.resolve(),
         logger: Logger = DefaultLogger.shared,
         dateProvider: DateProvider = SystemDateProvider(),
         homepageTabProvider: HomepageTabProviding? = nil) {
        self.windowManager = windowManager
        self.logger = logger
        self.prefs = profile.prefs
        self.dateProvider = dateProvider
        self.homepageTabProvider = homepageTabProvider ?? DefaultHomepageTabProvider(prefs: profile.prefs)
    }

    lazy var startAtHomeProvider: Middleware<AppState> = (legacyProvider, modernProvider)

    lazy var modernProvider: MiddlewareClosure<AppState> = { [self] state, action, windowUUID in
        // Does not test any modern actions
    }

    lazy var legacyProvider: LegacyMiddlewareClosure<AppState> = { [self] state, action in
        switch action.actionType {
        case StartAtHomeActionType.didBrowserBecomeActive:
            let shouldStartAtHome = self.startAtHomeCheck(windowUUID: action.windowUUID)
            store.dispatch(
                StartAtHomeAction(
                    shouldStartAtHome: shouldStartAtHome,
                    windowUUID: action.windowUUID,
                    actionType: StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted
                )
            )
        default: break
        }
    }

    /// Checks whether the app should start at the homepage and initiates the process if applicable.
    /// This method uses `StartAtHomeHelper` to determine if the app should launch with a homepage tab,
    /// based on user preferences and session state.
    ///
    /// - Returns: `true` if a homepage tab was selected and displayed, `false` otherwise.
    @MainActor
    private func startAtHomeCheck(windowUUID: WindowUUID) -> Bool {
        guard let tabManager = windowManager.tabManager(for: windowUUID) else { return false }
        let startAtHomeManager = StartAtHomeHelper(
            prefs: prefs,
            isRestoringTabs: !tabManager.tabRestoreHasFinished
        )

        guard !startAtHomeManager.shouldSkipStartHome else {
            logger.log("Skipping start at home", level: .debug, category: .tabs)
            return false
        }

        if startAtHomeManager.shouldStartAtHome(with: dateProvider.now()) {
            let wasLastSessionPrivate = tabManager.selectedTab?.isPrivate ?? false
            let scannableTabs = wasLastSessionPrivate ? tabManager.privateTabs : tabManager.normalTabs
            let existingHomeTab = startAtHomeManager.scanForExistingHomeTab(in: scannableTabs,
                                                                            with: prefs)
            let tabToSelect = homepageTabProvider.homepageTab(in: tabManager,
                                                              reusing: existingHomeTab,
                                                              isPrivate: wasLastSessionPrivate)

            logger.log("Start at home triggered with last session private \(wasLastSessionPrivate)",
                       level: .debug,
                       category: .tabs)
            tabManager.selectTab(tabToSelect)
            return true
        }
        return false
    }
}
