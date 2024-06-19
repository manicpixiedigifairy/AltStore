//
//  AppMarketplace.swift
//  AltStore
//
//  Created by Riley Testut on 1/26/24.
//  Copyright © 2024 Riley Testut. All rights reserved.
//

import MarketplaceKit
import CoreData

import AltStoreCore

// App == InstalledApp

@available(iOS 17.4, *)
extension AppLibrary
{
    //TODO: Tie to iCloud value
    static let `defaultAccount` = "AltStore"
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    struct InstallTaskContext
    {
        @TaskLocal
        static var bundleIdentifier: String = ""
        
        @TaskLocal
        static var beginInstallationHandler: ((String) -> Void)?
        
        @TaskLocal
        static var operationContext: OperationContext = OperationContext()
        
        @TaskLocal
        static var progress: Progress = Progress.discreteProgress(totalUnitCount: 100)
        
        @TaskLocal
        static var presentingViewController: UIViewController?
    }
    
    struct InstallVerificationTokenRequest: Encodable
    {
        var bundleID: String
        var redownload: Bool
    }

    struct InstallVerificationTokenResponse: Decodable
    {
        var token: String
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    #if STAGING
    static let marketplaceDomain = "https://6xxqrbufz0.execute-api.eu-central-1.amazonaws.com"
    #else
    static let marketplaceDomain = "https://8b7i0f8qea.execute-api.eu-central-1.amazonaws.com"
    #endif
}

@available(iOS 17.4, *)
actor AppMarketplace
{
    static let shared = AppMarketplace()
    
    private var didUpdateInstalledApps = false
    
    private init()
    {
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func update() async
    {
        //FIXME: Uncomment once AppLibrary can reliably tell us whether app is installed or not.
//        if !self.didUpdateInstalledApps
//        {
//            // Wait until the first observed change before we trust the returned value.
//            await withCheckedContinuation { continuation in
//                Task<Void, Never> { @MainActor in
//                    _ = withObservationTracking {
//                        AppLibrary.current.installedApps
//                    } onChange: {
//                        Task {
//                            continuation.resume()
//                        }
//                    }
//                }
//            }
//            
//            self.didUpdateInstalledApps = true
//        }
//        
//        let installedMarketplaceIDs = await Set(AppLibrary.current.installedApps.map(\.id))
//        
//        do
//        {
//            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
//            try await context.performAsync {
//
//                let installedApps = InstalledApp.all(in: context)
//                for installedApp in installedApps where installedApp.bundleIdentifier != StoreApp.altstoreAppID
//                {
//                    // Ignore any installed apps without valid marketplace StoreApp.
//                    guard let storeApp = installedApp.storeApp, let marketplaceID = storeApp.marketplaceID else { continue }
//
//                    // Ignore any apps we are actively installing.
//                    guard !AppManager.shared.isActivelyManagingApp(withBundleID: installedApp.bundleIdentifier) else { continue }
//
//                    if !installedMarketplaceIDs.contains(marketplaceID)
//                    {
//                        // This app is no longer installed, so delete.
//                        context.delete(installedApp)
//                    }
//                }
//
//                try context.save()
//            }
//        }
//        catch
//        {
//            Logger.main.error("Failed to update installed apps. \(error.localizedDescription, privacy: .public)")
//        }
    }
    
    func install(@AsyncManaged _ storeApp: StoreApp, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let progress = InstallTaskContext.progress
        
        let operation = AppManager.AppOperation.install(storeApp)
        AppManager.shared.set(progress, for: operation)
        
        let bundleID = await $storeApp.bundleIdentifier
        
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.$presentingViewController.withValue(presentingViewController) {
                try await InstallTaskContext.$bundleIdentifier.withValue(bundleID) {
                    try await InstallTaskContext.$beginInstallationHandler.withValue(beginInstallationHandler) {
                        do
                        {
                            let installedApp = try await self.install(storeApp, preferredVersion: nil, presentingViewController: presentingViewController, operation: operation)
                            await installedApp.perform {
                                self.finish(operation, result: .success($0), progress: progress)
                            }
                            
                            return installedApp
                        }
                        catch
                        {
                            self.finish(operation, result: .failure(error), progress: progress)
                            
                            throw error
                        }
                    }
                }
            }
        }
        
        return (task, progress)
    }
    
    func update(@AsyncManaged _ installedApp: InstalledApp, to version: AltStoreCore.AppVersion? = nil, presentingViewController: UIViewController?, beginInstallationHandler: ((String) -> Void)?) async -> (Task<AsyncManaged<InstalledApp>, Error>, Progress)
    {
        let (appName, bundleID) = await $installedApp.perform { ($0.name, $0.bundleIdentifier) }
        
        let (storeApp, latestSupportedVersion) = await $installedApp.perform({ ($0.storeApp, $0.storeApp?.latestSupportedVersion) })
        guard let storeApp, let appVersion = version ?? latestSupportedVersion else {
            let task = Task<AsyncManaged<InstalledApp>, Error> { throw OperationError.appNotFound(name: appName) }
            return (task, Progress.discreteProgress(totalUnitCount: 1))
        }
        
        let progress = InstallTaskContext.progress
        
        let operation = AppManager.AppOperation.update(installedApp)
        AppManager.shared.set(progress, for: operation)
        
        let installationHandler = { (bundleID: String) in
            if bundleID == StoreApp.altstoreAppID
            {
                DispatchQueue.main.async {
                    // AltStore will quit before installation finishes,
                    // so assume if we get this far the update will finish successfully.
                    let event = AnalyticsManager.Event.updatedApp(installedApp)
                    AnalyticsManager.shared.trackEvent(event)
                }
            }
            
            beginInstallationHandler?(bundleID)
        }
                
        let task = Task<AsyncManaged<InstalledApp>, Error>(priority: .userInitiated) {
            try await InstallTaskContext.$presentingViewController.withValue(presentingViewController) {
                try await InstallTaskContext.$bundleIdentifier.withValue(bundleID) {
                    try await InstallTaskContext.$beginInstallationHandler.withValue(installationHandler) {
                        do
                        {
                            let installedApp = try await self.install(storeApp, preferredVersion: appVersion, presentingViewController: presentingViewController, operation: operation)
                            await installedApp.perform {
                                self.finish(operation, result: .success($0), progress: progress)
                            }
                            
                            return installedApp
                        }
                        catch
                        {
                            self.finish(operation, result: .failure(error), progress: progress)
                            
                            throw error
                        }
                    }
                }
            }
        }
        
        return (task, progress)
    }
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    func install(@AsyncManaged _ storeApp: StoreApp,
                 preferredVersion: AltStoreCore.AppVersion?,
                 presentingViewController: UIViewController?,
                 operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        // Verify pledge
        try await self.verifyPledge(for: storeApp, presentingViewController: presentingViewController)
        
        // Verify version is supported
        @AsyncManaged
        var appVersion: AltStoreCore.AppVersion
        
        if let preferredVersion
        {
            appVersion = preferredVersion
        }
        else
        {
            guard let latestAppVersion = await $storeApp.latestAvailableVersion else {
                let failureReason = await String(format: NSLocalizedString("The latest version of %@ could not be determined.", comment: ""), $storeApp.name)
                throw OperationError.unknown(failureReason: failureReason) //TODO: Make proper error case
            }
            
            appVersion = latestAppVersion
        }
        
        do
        {
            if let source = await $storeApp.source
            {
                let sourceID = await $storeApp.perform { $0.sourceIdentifier }
                guard sourceID == Source.altStoreIdentifier else {
                    // Only support installing apps from default source initially.
                    throw SourceError.unsupported(source)
                }
            }
            
            // Verify app version is supported
            try await $storeApp.perform { _ in
                try self.verify(appVersion)
            }
        }
        catch let error as VerificationError where error.code == .iOSVersionNotSupported
        {
            guard let presentingViewController, let latestSupportedVersion = await $storeApp.latestSupportedVersion else { throw error }
            
            try await $storeApp.perform { storeApp in
                if let installedApp = storeApp.installedApp
                {
                    guard !installedApp.matches(latestSupportedVersion) else { throw error }
                }
            }
            
            let title = NSLocalizedString("Unsupported iOS Version", comment: "")
            let message = error.localizedDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
            let localizedVersion = await $storeApp.perform { _ in latestSupportedVersion.localizedVersion }
            
            let action = await UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), $storeApp.name, localizedVersion), style: .default)
            try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
            
            appVersion = latestSupportedVersion
        }
        
        // Install app
        let installedApp = try await self._install(appVersion, operation: operation)
        return installedApp
    }
}

// Operations
@available(iOS 17.4, *)
private extension AppMarketplace
{
    func verifyPledge(for storeApp: StoreApp, presentingViewController: UIViewController?) async throws
    {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let verifyPledgeOperation = VerifyAppPledgeOperation(storeApp: storeApp, presentingViewController: presentingViewController)
            verifyPledgeOperation.resultHandler = { result in
                switch result
                {
                case .failure(let error): continuation.resume(throwing: error)
                case .success: continuation.resume()
                }
            }
            
            AppManager.shared.run([verifyPledgeOperation], context: InstallTaskContext.operationContext)
        }
    }
    
    nonisolated func verify(_ appVersion: AltStoreCore.AppVersion) throws
    {
        if let minOSVersion = appVersion.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
        {
            throw VerificationError.iOSVersionNotSupported(app: appVersion, requiredOSVersion: minOSVersion)
        }
        else if let maxOSVersion = appVersion.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
        {
            throw VerificationError.iOSVersionNotSupported(app: appVersion, requiredOSVersion: maxOSVersion)
        }
    }
    
    func _install(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, operation: AppManager.AppOperation) async throws -> AsyncManaged<InstalledApp>
    {
        @AsyncManaged
        var storeApp: StoreApp
        
        guard let _app = await $appVersion.app else {
            let failureReason = NSLocalizedString("The app listing could not be found.", comment: "")
            throw OperationError.unknown(failureReason: failureReason)
        }
        storeApp = _app
        
        guard let marketplaceID = await $storeApp.marketplaceID else {
            throw await OperationError.unknownMarketplaceID(appName: $storeApp.name)
        }
        
        // Can't rely on localApp.isInstalled to be accurate... FB://feedback-placeholder
        // let isInstalled = await localApp.isInstalled
        // let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
        
        let installedApps = await AppLibrary.current.installedApps
        let isInstalled = installedApps.contains(where: { $0.id == marketplaceID })
        
        let bundleID = await $storeApp.bundleIdentifier
        InstallTaskContext.beginInstallationHandler?(bundleID) // TODO: Is this called too early?
        
        guard bundleID != StoreApp.altstoreAppID else {
            // MarketplaceKit doesn't support updating marketplaces themselves (🙄)
            // so we have to ask user to manually update AltStore via Safari.
            // TODO: Figure out how to handle beta AltStore
            
            await MainActor.run {
                let openURL = URL(string: "https://altstore.io/update-pal")!
                UIApplication.shared.open(openURL)
            }
            
            // Cancel installation and let user manually update.
            throw CancellationError()
        }
                
        let installMarketplaceAppViewController = await MainActor.run { [operation] () -> InstallMarketplaceAppViewController? in
            
            var action: AppBannerView.AppAction?
            var isRedownload: Bool = false
            
            switch operation
            {
            case .install(let app):
                guard let storeApp = app.storeApp else { break }
                action = .install(storeApp)
                isRedownload = isInstalled // "redownload" if app is already installed
                
            case .update(let app):
                guard let installedApp = app as? InstalledApp ?? app.storeApp?.installedApp else { break }
                action = .update(installedApp)
                isRedownload = false // Updates are never redownloads
                
            default: break
            }
            
            guard let action else { return nil }
            
            let installMarketplaceAppViewController = InstallMarketplaceAppViewController(action: action, isRedownload: isRedownload)
            return installMarketplaceAppViewController
        }
        
        if let installMarketplaceAppViewController
        {
            guard let presentingViewController = InstallTaskContext.presentingViewController else { throw OperationError.unknown(failureReason: NSLocalizedString("Could not determine presenting context.", comment: "")) }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
                DispatchQueue.main.async {
                    installMarketplaceAppViewController.completionHandler = { result in
                        continuation.resume(with: result)
                    }
                    
                    let navigationController = UINavigationController(rootViewController: installMarketplaceAppViewController)
                    presentingViewController.present(navigationController, animated: true)
                }
            }
        }
        
        var didAddChildProgress = false
        
        while true
        {
            // Wait until app is finished installing...
            
            let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
            
            let (isInstalled, installation, installedMetadata) = await MainActor.run {
                // isInstalled is not reliable, but we use it for logging purposes.
                (localApp.isInstalled, localApp.installation, localApp.installedMetadata)
            }
                        
            Logger.sideload.info("Installing app \(bundleID, privacy: .public)... Installed: \(isInstalled). Metadata: \(String(describing: installedMetadata), privacy: .public). Installation: \(String(describing: installation), privacy: .public)")
                                    
            if let installation
            {
                // App is currently being installed.
                Logger.sideload.info("App \(bundleID, privacy: .public) has valid installation metadata!")
                
                if !didAddChildProgress
                {
                    Logger.sideload.info("Added child progress for app \(bundleID, privacy: .public)")
                    
                    InstallTaskContext.progress.addChild(installation.progress, withPendingUnitCount: InstallTaskContext.progress.totalUnitCount)
                    didAddChildProgress = true
                }
                
                if installation.progress.fractionCompleted != 1.0
                {
                    // Progress has not yet completed, so add it as child and wait for it to complete.
                    
                    Logger.sideload.info("Installation progress is less than 1.0, polling until finished...")
                    
                    var fractionComplete: Double?
                    
                    while true
                    {
                        if installation.progress.isCancelled
                        {
                            // Installation was cancelled, so assume error occured.
                            Logger.sideload.info("Installation cancelled! \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                            throw CancellationError()
                        }
                        
                        if installation.progress.fractionCompleted == 1.0
                        {
                            Logger.sideload.info("Installation finished with progress: \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                            break
                        }
                        
                        if let fractionComplete, installation.progress.fractionCompleted != fractionComplete
                        {
                            // If fractionComplete has changed at least once but the value is negative, consider it complete.
                            if installation.progress.fractionCompleted < 0 || installation.progress.completedUnitCount < 0
                            {
                                Logger.sideload.fault("Installation progress returned invalid value! \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                                break
                            }
                        }
                        
                        fractionComplete = installation.progress.fractionCompleted
                        
                        if installation.progress.fractionCompleted < 0 || installation.progress.completedUnitCount < 0
                        {
                            // One last sanity check: if progress is negative, check if AppLibrary _does_ report correct value.
                            // If it does, we can exit early.
                            
                            let didInstallSuccessfully = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                            if didInstallSuccessfully
                            {
                                break
                            }
                        }
                        
                        Logger.sideload.info("Installation progress: \(installation.progress.fractionCompleted) (\(installation.progress.completedUnitCount) of \(installation.progress.totalUnitCount))")
                        
                        // I hate that this is the best way to _reliably_ know when app finished installing...but it is.
                        try await Task.sleep(for: .seconds(0.5))
                    }
                }
                
                //FIXME: Uncomment this when AppLibrary bugs are fixed.
                // let didInstallSuccessfully = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                // if !didInstallSuccessfully
                // {
                //     // App version does not match the version we attempted to install, so assume error occured.
                //     throw CancellationError()
                // }
                
                // App version matches version we're installing, so break loop.
                Logger.sideload.info("Finished installing marketplace app \(bundleID, privacy: .public)")
                
                break
            }
            else
            {
                Logger.sideload.info("App \(bundleID, privacy: .public) is missing installation metadata, falling back to manual check.")
                
                let isVersionInstalled = try await self.isAppVersionInstalled(appVersion, for: storeApp)
                if !isVersionInstalled
                {
                    // App version is not installed...supposedly.
                    
                    if !isInstalled
                    {
                        // App itself apparently isn't installed, but check if we can open URL as fallback.
                        
                        if let openURL = await $storeApp._installedOpenURL, await UIApplication.shared.canOpenURL(openURL)
                        {
                            Logger.sideload.info("Fallback Open URL check for \(bundleID, privacy: .public) succeeded, assuming installation finished successfully.")
                        }
                        else
                        {
                            try await Task.sleep(for: .milliseconds(50))
                            continue
                        }
                    }
                    else
                    {
                        // App is either not installed, or installed version doesn't match the version we're installing,
                        // Either way, keep polling.
                                            
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                }
                
                if !didAddChildProgress
                {
                    // Make sure we set manually set progress as completed.
                    Logger.sideload.info("Manually updated progress for app \(bundleID, privacy: .public) to \(InstallTaskContext.progress.fractionCompleted) (\(InstallTaskContext.progress.completedUnitCount) of \(InstallTaskContext.progress.totalUnitCount))")
                    InstallTaskContext.progress.completedUnitCount = InstallTaskContext.progress.totalUnitCount
                }
                
                // App is installed, break loop.
                Logger.sideload.info("(Apparently) finished installing marketplace app \(bundleID, privacy: .public) (with manual check)")
                break
            }
        }
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        let installedApp = await backgroundContext.performAsync {
            
            let storeApp = backgroundContext.object(with: storeApp.objectID) as! StoreApp
            let appVersion = backgroundContext.object(with: appVersion.objectID) as! AltStoreCore.AppVersion
            
            /* App */
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(marketplaceApp: storeApp, context: backgroundContext)
            }
            
            installedApp.update(forMarketplaceAppVersion: appVersion)
            
            //TODO: Include app extensions?
            
            return installedApp
        }
        
        return AsyncManaged(wrappedValue: installedApp)
    }
    
    func isAppVersionInstalled(@AsyncManaged _ appVersion: AltStoreCore.AppVersion, @AsyncManaged for storeApp: StoreApp) async throws -> Bool
    {
        guard let marketplaceID = await $storeApp.marketplaceID else {
            throw await OperationError.unknownMarketplaceID(appName: $storeApp.name)
        }
        
        // First, check that the app is installed in the first place.
        let isInstalled = await AppLibrary.current.installedApps.contains(where: { $0.id == marketplaceID })
        guard isInstalled else { return false }
        
        let localApp = await AppLibrary.current.app(forAppleItemID: marketplaceID)
        let bundleID = await $storeApp.bundleIdentifier
        
        if let installedMetadata = await localApp.installedMetadata
        {
            // Verify installed metadata matches expected version.

            let (version, buildVersion, localizedVersion) = await $appVersion.perform { ($0.version, $0.buildVersion, $0.localizedVersion) }
            
            if version == installedMetadata.shortVersion && buildVersion == installedMetadata.version
            {
                // Installed version matches storeApp version.
                return true
            }
            else
            {
                // Installed version does NOT match the version we're installing.
                Logger.sideload.info("App \(bundleID, privacy: .public) is installed, but does not match the version we're expecting. Expected: \(localizedVersion). Actual: \(installedMetadata.shortVersion) (\(installedMetadata.version))")
                return false
            }
        }
        else
        {
            // App is installed, but has no installedMetadata...
            // This is most likely a bug, but we still have to handle it.
            // Assume this only happens during initial install.
            
            Logger.sideload.error("App \(bundleID, privacy: .public) is installed, but installedMetadata is nil. Assuming this is a new installation (or that the update completes successfully).")
            return true
        }
    }
}

@available(iOS 17.4, *)
extension AppMarketplace
{
    func requestInstallToken(bundleID: String, isRedownload: Bool) async throws -> String
    {
        let requestURL = URL(string: "https://8b7i0f8qea.execute-api.eu-central-1.amazonaws.com/install-token")!
        
        let payload = InstallVerificationTokenRequest(bundleID: bundleID, redownload: isRedownload)
        let bodyData = try JSONEncoder().encode(payload)
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse
        {
            guard httpResponse.statusCode == 200 else { throw OperationError.unknown() } //TODO: Proper error
        }
        
        let responseJSON = try Foundation.JSONDecoder().decode(InstallVerificationTokenResponse.self, from: data)
        return responseJSON.token
    }
}

@available(iOS 17.4, *)
private extension AppMarketplace
{
    func finish(_ operation: AppManager.AppOperation, result: Result<InstalledApp, Error>, progress: Progress?)
    {
        // Must remove before saving installedApp.
        if let currentProgress = AppManager.shared.progress(for: operation), currentProgress == progress
        {
            // Only remove progress if it hasn't been replaced by another one.
            AppManager.shared.set(nil, for: operation)
        }
        
        do
        {
            let installedApp = try result.get()
            
            // DON'T schedule expiration warning for Marketplace version.
            // if installedApp.bundleIdentifier == StoreApp.altstoreAppID
            // {
            //     AppManager.shared.scheduleExpirationWarningLocalNotification(for: installedApp)
            // }
            
            let event: AnalyticsManager.Event?
            
            switch operation
            {
            case .install: event = .installedApp(installedApp)
            case .refresh: event = .refreshedApp(installedApp)
            case .update where installedApp.bundleIdentifier == StoreApp.altstoreAppID:
                // AltStore quits before update finishes, so we've preemptively logged this update event.
                // In case AltStore doesn't quit, such as when update has a different bundle identifier,
                // make sure we don't log this update event a second time.
                event = nil
                
            case .update: event = .updatedApp(installedApp)
            case .activate, .deactivate, .backup, .restore: event = nil
            }
            
            if let event = event
            {
                AnalyticsManager.shared.trackEvent(event)
            }
            
            // No widget included in Marketplace version of AltStore.
            // WidgetCenter.shared.reloadAllTimelines()
            
            try installedApp.managedObjectContext?.save()
        }
        catch let nsError as NSError
        {
            var appName: String!
            if let app = operation.app as? (NSManagedObject & AppProtocol)
            {
                if let context = app.managedObjectContext
                {
                    context.performAndWait {
                        appName = app.name
                    }
                }
                else
                {
                    appName = NSLocalizedString("App", comment: "")
                }
            }
            else
            {
                appName = operation.app.name
            }
            
            let localizedTitle: String
            switch operation
            {
            case .install: localizedTitle = String(format: NSLocalizedString("Failed to Install %@", comment: ""), appName)
            case .refresh: localizedTitle = String(format: NSLocalizedString("Failed to Refresh %@", comment: ""), appName)
            case .update: localizedTitle = String(format: NSLocalizedString("Failed to Update %@", comment: ""), appName)
            case .activate: localizedTitle = String(format: NSLocalizedString("Failed to Activate %@", comment: ""), appName)
            case .deactivate: localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@", comment: ""), appName)
            case .backup: localizedTitle = String(format: NSLocalizedString("Failed to Back Up %@", comment: ""), appName)
            case .restore: localizedTitle = String(format: NSLocalizedString("Failed to Restore %@ Backup", comment: ""), appName)
            }
            
            let error = nsError.withLocalizedTitle(localizedTitle)
            AppManager.shared.log(error, operation: operation.loggedErrorOperation, app: operation.app)
        }
    }
}
