//
//  AppBannerView.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import MarketplaceKit

import AltStoreCore
import Roxas

import Nuke

extension AppBannerView
{
    static let standardHeight = 88.0
    
    enum Style
    {
        case app
        case source
    }
    
    enum AppAction: Equatable
    {
        case install(StoreApp)
        case open(AppProtocol)
        case update(InstalledApp)
        case custom(String)
        
        static func ==(lhs: AppAction, rhs: AppAction) -> Bool
        {
            return switch (lhs, rhs)
            {
            case (.install(let appA), .install(let appB)): appA.bundleIdentifier == appB.bundleIdentifier //TODO: Use marketplaceID as well
            case (.open(let appA), .open(let appB)): appA.bundleIdentifier == appB.bundleIdentifier
            case (.update(let appA), .update(let appB)): appA.bundleIdentifier == appB.bundleIdentifier
            case (.custom(let titleA), .custom(let titleB)): titleA == titleB
            case (.install, _), (.open, _), (.update, _), (.custom, _): false
            }
        }
    }
}

class AppBannerView: RSTNibView
{
    override var accessibilityLabel: String? {
        get { return self.accessibilityView?.accessibilityLabel }
        set { self.accessibilityView?.accessibilityLabel = newValue }
    }
    
    override open var accessibilityAttributedLabel: NSAttributedString? {
        get { return self.accessibilityView?.accessibilityAttributedLabel }
        set { self.accessibilityView?.accessibilityAttributedLabel = newValue }
    }
    
    override var accessibilityValue: String? {
        get { return self.accessibilityView?.accessibilityValue }
        set { self.accessibilityView?.accessibilityValue = newValue }
    }
    
    override open var accessibilityAttributedValue: NSAttributedString? {
        get { return self.accessibilityView?.accessibilityAttributedValue }
        set { self.accessibilityView?.accessibilityAttributedValue = newValue }
    }
    
    override open var accessibilityTraits: UIAccessibilityTraits {
        get { return self.accessibilityView?.accessibilityTraits ?? [] }
        set { self.accessibilityView?.accessibilityTraits = newValue }
    }
    
    var style: Style = .app
    
    private var originalTintColor: UIColor?
    private var previousAppAction: AppAction?
    
    @available(iOS 17.4, *)
    private var actionButton: ActionButton? {
        get { _actionButton as? ActionButton }
        set { _actionButton = newValue }
    }
    private var _actionButton: UIControl?
    
    private var actionButtonContainerView: UIView!
    
    var actionButtonCallback: ((AsyncManaged<StoreApp>, AsyncManaged<AltStoreCore.AppVersion>) -> Void)?
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: AppIconImageView!
    @IBOutlet var button: PillButton!
    @IBOutlet var buttonLabel: UILabel!
    @IBOutlet var betaBadgeView: UIView!
    @IBOutlet var sourceIconImageView: AppIconImageView!
    
    @IBOutlet var backgroundEffectView: UIVisualEffectView!
    
    @IBOutlet private var vibrancyView: UIVisualEffectView!
    @IBOutlet private var stackView: UIStackView!
    @IBOutlet private var accessibilityView: UIView!
    
    @IBOutlet private var iconImageViewHeightConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.accessibilityView.accessibilityTraits.formUnion(.button)
        
        self.isAccessibilityElement = false
        self.accessibilityElements = [self.accessibilityView, self.button].compactMap { $0 }
        
        self.betaBadgeView.isHidden = true
        
        self.sourceIconImageView.style = .circular
        self.sourceIconImageView.isHidden = true
        
        self.layoutMargins = self.stackView.layoutMargins
        self.insetsLayoutMarginsFromSafeArea = false
        
        self.stackView.isLayoutMarginsRelativeArrangement = true
        self.stackView.preservesSuperviewLayoutMargins = true
        
        self.actionButtonContainerView = UIView()
        self.actionButtonContainerView.translatesAutoresizingMaskIntoConstraints = false
        self.actionButtonContainerView.backgroundColor = .blue
        self.addSubview(self.actionButtonContainerView)
        
        NSLayoutConstraint.activate([
            self.actionButtonContainerView.leadingAnchor.constraint(equalTo: self.button.leadingAnchor),
            self.actionButtonContainerView.trailingAnchor.constraint(equalTo: self.button.trailingAnchor),
            self.actionButtonContainerView.topAnchor.constraint(equalTo: self.button.topAnchor),
            self.actionButtonContainerView.bottomAnchor.constraint(equalTo: self.button.bottomAnchor),
        ])
    }
    
    override func tintColorDidChange()
    {
        super.tintColorDidChange()
        
        if self.tintAdjustmentMode != .dimmed
        {
            self.originalTintColor = self.tintColor
        }
        
        self.update()
    }
    
    override func layoutSubviews() 
    {
        super.layoutSubviews()
        
//        self.actionButton?.size = self.actionButtonContainerView.bounds.size
//        self.actionButton?.center = CGPoint(x: self.actionButtonContainerView.bounds.midX, y: self.actionButtonContainerView.bounds.midY)
    }
}

extension AppBannerView
{
    func configure(for app: AppProtocol, action: AppAction? = nil, showSourceIcon: Bool = true)
    {
        struct AppValues
        {
            var name: String
            var developerName: String? = nil
            var isBeta: Bool = false
            
            init(app: AppProtocol)
            {
                self.name = app.name
                
                guard let storeApp = (app as? StoreApp) ?? (app as? InstalledApp)?.storeApp else { return }
                self.developerName = storeApp.developerName
                
                if storeApp.isBeta
                {
                    self.name = String(format: NSLocalizedString("%@ beta", comment: ""), app.name)
                    self.isBeta = true
                }
            }
        }
        
        self.style = .app

        let values = AppValues(app: app)
        self.titleLabel.text = app.name // Don't use values.name since that already includes "beta".
        self.betaBadgeView.isHidden = !values.isBeta

        if let developerName = values.developerName
        {
            self.subtitleLabel.text = developerName
            self.accessibilityLabel = String(format: NSLocalizedString("%@ by %@", comment: ""), values.name, developerName)
        }
        else
        {
            self.subtitleLabel.text = NSLocalizedString("Sideloaded", comment: "")
            self.accessibilityLabel = values.name
        }
        
        if let storeApp = app.storeApp, storeApp.isPledgeRequired
        {
            // Always show button label for Patreon apps.
            self.buttonLabel.isHidden = false
            
            if storeApp.isPledged
            {
                self.buttonLabel.text = NSLocalizedString("Pledged", comment: "")
            }
            else if storeApp.installedApp != nil
            {
                self.buttonLabel.text = NSLocalizedString("Pledge Expired", comment: "")
            }
            else
            {
                self.buttonLabel.text = NSLocalizedString("Join Patreon", comment: "")
            }
        }
        else
        {
            self.buttonLabel.isHidden = true
        }
        
        if let source = app.storeApp?.source, showSourceIcon
        {
            self.sourceIconImageView.isHidden = false
            self.sourceIconImageView.backgroundColor = source.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
            
            if let iconURL = source.effectiveIconURL
            {
                if let image = ImageCache.shared[iconURL]
                {
                    self.sourceIconImageView.backgroundColor = .white
                    self.sourceIconImageView.image = image.image
                }
                else
                {
                    self.sourceIconImageView.image = nil
                    
                    Nuke.loadImage(with: iconURL, into: self.sourceIconImageView) { result in
                        switch result
                        {
                        case .failure(let error): Logger.main.error("Failed to fetch source icon from \(iconURL, privacy: .public). \(error.localizedDescription, privacy: .public)")
                        case .success: self.sourceIconImageView.backgroundColor = .white // In case icon has transparent background.
                        }
                    }
                }
            }
        }
        else
        {
            self.sourceIconImageView.isHidden = true
        }
        
        let buttonAction: AppAction
        
        if let action
        {
            buttonAction = action
        }
        else if let storeApp = app.storeApp
        {
            if let installedApp = storeApp.installedApp
            {
                // App is installed
                
                if installedApp.isUpdateAvailable
                {
                    buttonAction = .update(installedApp)
                }
                else
                {
                    buttonAction = .open(installedApp)
                }
            }
            else
            {
                // App is not installed
                buttonAction = .install(storeApp)
            }
        }
        else
        {
            // App is not from a source, fall back to .open
            buttonAction = .open(app)
        }
        
        UIView.performWithoutAnimation {
            switch buttonAction
            {
            case .open:
                let buttonTitle = NSLocalizedString("Open", comment: "")
                self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                self.button.accessibilityLabel = String(format: NSLocalizedString("Open %@", comment: ""), values.name)
                self.button.accessibilityValue = buttonTitle
                
                self.button.countdownDate = nil
                
            case .update:
                let buttonTitle = NSLocalizedString("Update", comment: "")
                self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                self.button.accessibilityLabel = String(format: NSLocalizedString("Update %@", comment: ""), values.name)
                self.button.accessibilityValue = buttonTitle
                
                self.button.countdownDate = nil
                
            case .custom(let buttonTitle):
                self.button.setTitle(buttonTitle, for: .normal)
                self.button.accessibilityLabel = buttonTitle
                self.button.accessibilityValue = buttonTitle
                
                self.button.countdownDate = nil
                
            case .install:
                if let storeApp = app.storeApp, storeApp.isPledgeRequired
                {
                    // Pledge required
                    
                    if storeApp.isPledged
                    {
                        let buttonTitle = NSLocalizedString("Install", comment: "")
                        self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                        self.button.accessibilityLabel = String(format: NSLocalizedString("Install %@", comment: ""), app.name)
                        self.button.accessibilityValue = buttonTitle
                    }
                    else if let amount = storeApp.pledgeAmount, let currencyCode = storeApp.pledgeCurrency, !storeApp.prefersCustomPledge, #available(iOS 15, *)
                    {
                        let price = amount.formatted(.currency(code: currencyCode).presentation(.narrow).precision(.fractionLength(0...2)))
                        
                        let buttonTitle = String(format: NSLocalizedString("%@/mo", comment: ""), price)
                        self.button.setTitle(buttonTitle, for: .normal)
                        self.button.accessibilityLabel = String(format: NSLocalizedString("Pledge %@ a month", comment: ""), price)
                        self.button.accessibilityValue = String(format: NSLocalizedString("%@ a month", comment: ""), price)
                    }
                    else
                    {
                        let buttonTitle = NSLocalizedString("Pledge", comment: "")
                        self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                        self.button.accessibilityLabel = buttonTitle
                        self.button.accessibilityValue = buttonTitle
                    }
                }
                else
                {
                    // Free app
                    
                    let buttonTitle = NSLocalizedString("Free", comment: "")
                    self.button.setTitle(buttonTitle.uppercased(), for: .normal)
                    self.button.accessibilityLabel = String(format: NSLocalizedString("Download %@", comment: ""), app.name)
                    self.button.accessibilityValue = buttonTitle
                }
                
                if let versionDate = app.storeApp?.latestSupportedVersion?.date, versionDate > Date()
                {
                    self.button.countdownDate = versionDate
                }
                else
                {
                    self.button.countdownDate = nil
                }
            }
            
            #if MARKETPLACE
            
            if buttonAction != self.previousAppAction, #available(iOS 17.4, *)
            {
                // Add ActionButton as subview so we can trigger Martketplace APIs.
                
                let uuid = UUID()
                
//                if let actionButton
//                {
//                    actionButton.removeFromSuperview()
//                    self.actionButton = nil
//                    
//                    Logger.main.info("Removing ActionButton: \(uuid, privacy: .public)")
//                }
                
                var action: ActionButton.Action?
                
                switch buttonAction
                {
                case .open(let app):
                    guard let storeApp = app.storeApp, let marketplaceID = storeApp.marketplaceID else { break } //TOOD: Should InstalledApp have it's own reference to marketplaceID?
                    action = .launch(marketplaceID)
                    
                case .install(let storeApp):
                    //TODO: How do we handle fallback of downloading older iOS version if we have to pick the not-latest version? Does provided URL not matter?
                    // JK, it'll only ever fall back to latestSupportedVersion, so just supply that
                    guard let marketplaceID = storeApp.marketplaceID, let downloadURL = storeApp.latestSupportedVersion?.downloadURL else { break }
                                    
                    //TODO: Do accounts matter?
                    let config = InstallConfiguration(install: .init(account: "AltStore", appleItemID: marketplaceID, alternativeDistributionPackage: downloadURL, isUpdate: false),
                                                      confirmInstall: {
                        
                        do
                        {
                            let (installToken, appVersion) = try await AppMarketplace.shared.prepareInstall(for: storeApp, presentingViewController: nil)
                            
                            Task {
                                await self.actionButtonCallback?(AsyncManaged(wrappedValue: storeApp), appVersion)
                            }
                                                    
                            return .confirmed(installVerificationToken: installToken, authenticationContext: nil)
                        }
                        catch
                        {
                            return .cancel
                        }
                    })
                    
                    action = .install(config)
                    
                case .update(let installedApp):
                    guard let storeApp = installedApp.storeApp, let marketplaceID = storeApp.marketplaceID, let downloadURL = storeApp.latestSupportedVersion?.downloadURL else { break }
                    
                    let config = InstallConfiguration(install: .init(account: "AltStore", appleItemID: marketplaceID, alternativeDistributionPackage: downloadURL, isUpdate: true),
                                                      confirmInstall: {
                        do
                        {
                            let (installToken, appVersion) = try await AppMarketplace.shared.prepareInstall(for: storeApp, presentingViewController: nil)
                            
                            Task {
                                await self.actionButtonCallback?(AsyncManaged(wrappedValue: storeApp), appVersion)
                            }
                                                    
                            return .confirmed(installVerificationToken: installToken, authenticationContext: nil)
                        }
                        catch
                        {
                            return .cancel
                        }
                    })
                    action = .install(config)
                    
                case .custom: action = .launch(0) //TOD: Put in AltStore app ID
                }
                
                if let action, _actionButton == nil
                {
                    let actionButton = ActionButton(action: action)
                    actionButton.backgroundColor = .red
                    actionButton.label = "Hi"
                    actionButton.size = self.actionButtonContainerView.bounds.size
                    actionButton.center = CGPoint(x: self.actionButtonContainerView.bounds.midX, y: self.actionButtonContainerView.bounds.midY)
//                    actionButton.center = self.button.center
//                    actionButton.cornerRadius = self.button.layer.cornerRadius
                    
                    // Uncomment these lines ton add it back
                    _actionButton = actionButton
                    self.actionButtonContainerView.addSubview(actionButton)
                    
//                    self.actionButtonContainerView.setNeedsLayout()
                    
                    Logger.main.info("Adding ActionButton: \(uuid, privacy: .public)")
                }
            }
            
            #endif
            
            // Ensure PillButton is correct size before assigning progress.
            self.layoutIfNeeded()
        }
        
        if let progress = AppManager.shared.installationProgress(for: app), progress.fractionCompleted < 1.0
        {
            self.button.progress = progress
        }
        else
        {
            self.button.progress = nil
        }
    }
    
    func configure(for source: Source)
    {
        self.style = .source
        
        let subtitle: String
        if let text = source.subtitle
        {
            subtitle = text
        }
        else if let scheme = source.sourceURL.scheme
        {
            subtitle = source.sourceURL.absoluteString.replacingOccurrences(of: scheme + "://", with: "")
        }
        else
        {
            subtitle = source.sourceURL.absoluteString
        }
        
        self.titleLabel.text = source.name
        self.subtitleLabel.text = subtitle
        
        let tintColor = source.effectiveTintColor ?? .altPrimary
        self.tintColor = tintColor
        
        let accessibilityLabel = source.name + "\n" + subtitle
        self.accessibilityLabel = accessibilityLabel
    }
}

private extension AppBannerView
{
    func update()
    {
        self.clipsToBounds = true
        self.layer.cornerRadius = 22
        
        let tintColor = self.originalTintColor ?? self.tintColor
        self.subtitleLabel.textColor = tintColor
        
        switch self.style
        {
        case .app:
            self.directionalLayoutMargins.trailing = self.stackView.directionalLayoutMargins.trailing
            
            self.iconImageViewHeightConstraint.constant = 60
            self.iconImageView.style = .icon
            
            self.titleLabel.textColor = .label
            
            self.button.style = .pill
            
            self.backgroundEffectView.contentView.backgroundColor = UIColor(resource: .blurTint)
            self.backgroundEffectView.backgroundColor = tintColor
            
        case .source:
            self.directionalLayoutMargins.trailing = 20
            
            self.iconImageViewHeightConstraint.constant = 44
            self.iconImageView.style = .circular
            
            self.titleLabel.textColor = .white
            
            self.button.style = .custom
            
            self.backgroundEffectView.contentView.backgroundColor = tintColor?.adjustedForDisplay
            self.backgroundEffectView.backgroundColor = nil
            
            if let tintColor, tintColor.isTooBright
            {
                let textVibrancyEffect = UIVibrancyEffect(blurEffect: .init(style: .systemChromeMaterialLight), style: .fill)
                self.vibrancyView.effect = textVibrancyEffect
            }
            else
            {
                // Thinner == more dull
                let textVibrancyEffect = UIVibrancyEffect(blurEffect: .init(style: .systemThinMaterialDark), style: .secondaryLabel)
                self.vibrancyView.effect = textVibrancyEffect
            }
        }
    }
    
    @available(iOS 17.4, *)
    @objc func performMarketplaceAction(_ sender: ActionButton)
    {
        //self.button.sendActions(for: .primaryActionTriggered)
    }
}
