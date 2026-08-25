//
//  PrefAISubtitleViewController.swift
//  iina
//
//  Created by Codex on 2026/8/24.
//

import Cocoa
import SwiftUI
import Translation

extension Notification.Name {
  static let iinaAISubtitleStateDidChange = Notification.Name("IINAAISubtitleStateDidChange")
}

private enum AISubtitleResourceViewState {
  case checking(String)
  case ready(String)
  case actionRequired(String)
  case preparing(String, Progress?)
  case unavailable(String)
  case notRequired(String)
}

private final class AISubtitleResourceRowView: NSView {
  private let iconView = NSImageView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(wrappingLabelWithString: "")
  private let progressIndicator = NSProgressIndicator()

  init(title: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    iconView.imageScaling = .scaleProportionallyDown
    iconView.setContentHuggingPriority(.required, for: .horizontal)

    titleLabel.stringValue = title
    titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

    detailLabel.textColor = .secondaryLabelColor
    detailLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    detailLabel.maximumNumberOfLines = 2

    progressIndicator.style = .bar
    progressIndicator.controlSize = .small
    progressIndicator.isDisplayedWhenStopped = false
    progressIndicator.isHidden = true

    let textStack = NSStackView(views: [titleLabel, detailLabel, progressIndicator])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3

    let row = NSStackView(views: [iconView, textStack])
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 10
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 18),
      iconView.heightAnchor.constraint(equalToConstant: 18),
      progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
      row.leadingAnchor.constraint(equalTo: leadingAnchor),
      row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setTitle(_ title: String) {
    titleLabel.stringValue = title
  }

  func setState(_ state: AISubtitleResourceViewState) {
    if #available(macOS 14.0, *) {
      progressIndicator.observedProgress = nil
    }
    progressIndicator.stopAnimation(nil)
    progressIndicator.isHidden = true

    switch state {
    case .checking(let detail):
      setIcon(symbol: "clock", fallback: NSImage.statusPartiallyAvailableName, color: .secondaryLabelColor)
      detailLabel.stringValue = detail
    case .ready(let detail):
      setIcon(symbol: "checkmark.circle.fill", fallback: NSImage.statusAvailableName, color: .systemGreen)
      detailLabel.stringValue = detail
    case .actionRequired(let detail):
      setIcon(symbol: "arrow.down.circle", fallback: NSImage.statusPartiallyAvailableName, color: .controlAccentColor)
      detailLabel.stringValue = detail
    case .preparing(let detail, let progress):
      setIcon(symbol: "arrow.down.circle.fill", fallback: NSImage.statusPartiallyAvailableName, color: .controlAccentColor)
      detailLabel.stringValue = detail
      progressIndicator.isHidden = false
      if #available(macOS 14.0, *) {
        progressIndicator.observedProgress = progress
      } else if let progress {
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = progress.fractionCompleted
      }
      progressIndicator.isIndeterminate = progress == nil
      progressIndicator.startAnimation(nil)
    case .unavailable(let detail):
      setIcon(symbol: "exclamationmark.triangle.fill", fallback: NSImage.statusUnavailableName, color: .systemOrange)
      detailLabel.stringValue = detail
    case .notRequired(let detail):
      setIcon(symbol: "checkmark.circle", fallback: NSImage.statusAvailableName, color: .secondaryLabelColor)
      detailLabel.stringValue = detail
    }
  }

  private func setIcon(symbol: String, fallback: NSImage.Name, color: NSColor) {
    if #available(macOS 11.0, *) {
      iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    } else {
      iconView.image = NSImage(named: fallback)
    }
    iconView.contentTintColor = color
  }
}

final class PrefAISubtitleViewController: PreferenceViewController, PreferenceWindowEmbeddable {
  override var nibName: NSNib.Name {
    return NSNib.Name("PrefAISubtitleViewController")
  }

  var preferenceTabTitle: String {
    return aiSubtitleLocalized("preference.ai_subtitle", fallback: "AI Subtitles")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("wand.and.stars", fallbackImage: "pref_sub")
  }

  var preferenceSearchSections: [String: [String]]? {
    return [
      aiSubtitleLocalized("ai_subtitle.section.defaults", fallback: "Defaults"): [
        aiSubtitleLocalized("ai_subtitle.enable_feature", fallback: "Enable AI Subtitles"),
        aiSubtitleLocalized("ai_subtitle.default_provider", fallback: "Default AI provider"),
        aiSubtitleLocalized("ai_subtitle.provider.apple_option", fallback: "Apple Local AI"),
        "OpenAI",
        aiSubtitleLocalized("ai_subtitle.provider.aliyun_option", fallback: "Aliyun"),
        aiSubtitleLocalized("ai_subtitle.auto_mode", fallback: "Automatic generation"),
        aiSubtitleLocalized("ai_subtitle.default_spoken_language", fallback: "Default audio language"),
        aiSubtitleLocalized("ai_subtitle.default_subtitle_language", fallback: "Default subtitle language")
      ],
      aiSubtitleLocalized("ai_subtitle.section.resources", fallback: "Apple Resources"): [
        aiSubtitleLocalized("ai_subtitle.resource.system", fallback: "macOS compatibility"),
        aiSubtitleLocalized("ai_subtitle.resource.speech", fallback: "Apple speech model"),
        aiSubtitleLocalized("ai_subtitle.resource.translation", fallback: "Apple translation languages")
      ]
    ]
  }

  private let defaults = UserDefaults.standard
  private let featureSwitch = NSSwitch()
  private let defaultProviderPopup = NSPopUpButton()
  private let schemeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
  private let autoModePopup = NSPopUpButton()
  private let sourcePopup = NSPopUpButton()
  private let targetPopup = NSPopUpButton()
  private let openAIKeyField = NSSecureTextField()
  private let aliyunDashScopeField = NSSecureTextField()
  private let aliyunAccessKeyIDField = NSTextField()
  private let aliyunAccessKeySecretField = NSSecureTextField()
  private let consentButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private let removeCredentialsButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.remove_credentials", fallback: "Remove Saved Credentials…"),
    target: nil,
    action: nil
  )
  private let prepareLocalButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.download_required_resources", fallback: "Download Required Resources"),
    target: nil,
    action: nil
  )
  private let saveRemoteButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.initialize_remote", fallback: "Save and Finish"),
    target: nil,
    action: nil
  )
  private let upgradeButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.open_software_update", fallback: "Open Software Update"),
    target: nil,
    action: nil
  )
  private let cacheLimitPopup = NSPopUpButton()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let statusContainer = NSView()

  private let systemResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.system", fallback: "macOS compatibility")
  )
  private let speechResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.speech", fallback: "Apple speech model")
  )
  private let translationResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.translation", fallback: "Apple translation languages")
  )
  private let credentialResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.credentials", fallback: "Service credentials")
  )
  private let translationCredentialResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.translation_credentials", fallback: "Translation credentials")
  )
  private let consentResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.cloud_consent", fallback: "Cloud processing permission")
  )

  private let localSection = NSView()
  private let localContentStack = NSStackView()
  private let remoteSection = NSView()
  private let remoteContentStack = NSStackView()
  private let cloudFieldsStack = NSStackView()
  private let translationHostContainer = NSStackView()
  private var translationPreparationHost: NSView?
  private var speechCapability: AISubtitleProviderCapability?
  private var translationCapability: AISubtitleProviderCapability?
  private var resourceProbeTask: Task<Void, Never>?
  private var resourceProbeGeneration = 0
  private var languageStatusTask: Task<Void, Never>?
  private var languageStatusGeneration = 0
  private var isPreparingAppleResources = false

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 1))
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    buildUI()
    restoreSelections()
    refreshAll(syncCloudConsent: true)
  }

  deinit {
    resourceProbeTask?.cancel()
    languageStatusTask?.cancel()
  }

  func preferenceViewDidOpen() {
    restoreSelections()
    refreshAll(syncCloudConsent: true)
  }

  private func buildUI() {
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 16
    root.detachesHiddenViews = true
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      root.topAnchor.constraint(equalTo: view.topAnchor),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    root.addArrangedSubview(buildFeatureToggleSection())
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildDefaultsSection())
    root.addArrangedSubview(NSBox.horizontalLine())
    configureLocalSection()
    root.addArrangedSubview(localSection)
    configureRemoteSection()
    root.addArrangedSubview(remoteSection)
    configureStatusContainer()
    root.addArrangedSubview(statusContainer)
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildStorageSection())
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildDisclaimer())

    root.views.forEach { arrangedView in
      arrangedView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
  }

  private func buildFeatureToggleSection() -> NSView {
    let title = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.enable_feature",
      fallback: "Enable AI Subtitles"
    ))
    title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    featureSwitch.target = self
    featureSwitch.action = #selector(featureEnabledChanged(_:))

    let row = NSStackView(views: [featureSwitch, title])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      row.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
      row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
      row.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
    ])
    return container
  }

  private func buildDisclaimer() -> NSView {
    let label = NSTextField(wrappingLabelWithString: aiSubtitleLocalized(
      "ai_subtitle.disclaimer",
      fallback: "AI-generated subtitles may be inaccurate and are for reference only."
    ))
    label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 120),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      label.topAnchor.constraint(equalTo: container.topAnchor),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    return container
  }

  private func buildDefaultsSection() -> NSView {
    let section = sectionStack(title: aiSubtitleLocalized("ai_subtitle.section.defaults", fallback: "Defaults"),
                               identifier: "SectionTitleAISubtitleDefaults")
    for provider in [AISubtitleProviderID.apple, .openAI, .aliyun] {
      let title = providerOptionTitle(provider)
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.representedObject = provider.rawValue
      defaultProviderPopup.menu?.addItem(item)
    }
    defaultProviderPopup.target = self
    defaultProviderPopup.action = #selector(defaultProviderChanged(_:))
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.default_provider", fallback: "AI provider"),
      control: defaultProviderPopup
    ))

    schemeDescriptionLabel.textColor = .secondaryLabelColor
    schemeDescriptionLabel.maximumNumberOfLines = 2
    section.content.addArrangedSubview(schemeDescriptionLabel)
    schemeDescriptionLabel.widthAnchor.constraint(equalTo: section.content.widthAnchor).isActive = true

    upgradeButton.target = self
    upgradeButton.action = #selector(openSoftwareUpdate(_:))
    upgradeButton.isHidden = true
    section.content.addArrangedSubview(upgradeButton)

    autoModePopup.addItems(withTitles: [
      aiSubtitleLocalized("ai_subtitle.auto.always", fallback: "Always generate automatically"),
      aiSubtitleLocalized("ai_subtitle.auto.when_missing", fallback: "Generate when subtitles are missing"),
      aiSubtitleLocalized("ai_subtitle.auto.manual", fallback: "Manual only")
    ])
    autoModePopup.target = self
    autoModePopup.action = #selector(autoModeChanged(_:))
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.auto_mode", fallback: "Automatic generation"),
      control: autoModePopup
    ))

    configureLanguagePopup(sourcePopup, options: AISubtitleLanguageCatalog.sourceLanguages)
    configureLanguagePopup(targetPopup, options: AISubtitleLanguageCatalog.targetLanguages)
    sourcePopup.target = self
    sourcePopup.action = #selector(languageChanged(_:))
    targetPopup.target = self
    targetPopup.action = #selector(languageChanged(_:))
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.default_spoken_language", fallback: "Audio language"),
      control: sourcePopup
    ))
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.default_subtitle_language", fallback: "Subtitle language"),
      control: targetPopup
    ))
    return section.container
  }

  private func configureLocalSection() {
    configureSection(localSection,
                     content: localContentStack,
                     title: aiSubtitleLocalized("ai_subtitle.section.resources", fallback: "Apple Resources"),
                     identifier: "SectionTitleAISubtitleResources")
    [systemResourceRow, speechResourceRow, translationResourceRow].forEach {
      localContentStack.addArrangedSubview($0)
      $0.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true
    }

    translationHostContainer.orientation = .vertical
    translationHostContainer.alignment = .leading
    translationHostContainer.isHidden = true
    translationHostContainer.detachesHiddenViews = true
    localContentStack.addArrangedSubview(translationHostContainer)
    translationHostContainer.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true

    prepareLocalButton.target = self
    prepareLocalButton.action = #selector(prepareLocalAI(_:))
    prepareLocalButton.isHidden = true
    localContentStack.addArrangedSubview(prepareLocalButton)
  }

  private func configureRemoteSection() {
    configureSection(remoteSection,
                     content: remoteContentStack,
                     title: aiSubtitleLocalized("ai_subtitle.section.remote", fallback: "Remote Service"),
                     identifier: "SectionTitleAISubtitleRemote")

    cloudFieldsStack.orientation = .vertical
    cloudFieldsStack.alignment = .leading
    cloudFieldsStack.spacing = 8
    openAIKeyField.placeholderString = aiSubtitleLocalized(
      "ai_subtitle.openai_key_placeholder",
      fallback: "OpenAI API key (leave blank to keep the saved key)"
    )
    aliyunDashScopeField.placeholderString = aiSubtitleLocalized(
      "ai_subtitle.aliyun_model_key_placeholder",
      fallback: "Model Studio API key"
    )
    aliyunAccessKeyIDField.placeholderString = aiSubtitleLocalized(
      "ai_subtitle.aliyun_access_key_id_placeholder",
      fallback: "Machine Translation AccessKey ID"
    )
    aliyunAccessKeySecretField.placeholderString = aiSubtitleLocalized(
      "ai_subtitle.aliyun_access_key_secret_placeholder",
      fallback: "Machine Translation AccessKey Secret"
    )
    [openAIKeyField, aliyunDashScopeField, aliyunAccessKeyIDField, aliyunAccessKeySecretField].forEach {
      cloudFieldsStack.addArrangedSubview($0)
      $0.widthAnchor.constraint(equalToConstant: 430).isActive = true
    }
    consentButton.target = self
    consentButton.action = #selector(consentChanged(_:))
    cloudFieldsStack.addArrangedSubview(consentButton)
    removeCredentialsButton.target = self
    removeCredentialsButton.action = #selector(removeCloudCredentials(_:))
    cloudFieldsStack.addArrangedSubview(removeCredentialsButton)
    remoteContentStack.addArrangedSubview(cloudFieldsStack)

    [credentialResourceRow, translationCredentialResourceRow, consentResourceRow].forEach {
      remoteContentStack.addArrangedSubview($0)
      $0.widthAnchor.constraint(equalTo: remoteContentStack.widthAnchor).isActive = true
    }

    saveRemoteButton.target = self
    saveRemoteButton.action = #selector(saveRemoteAI(_:))
    remoteContentStack.addArrangedSubview(saveRemoteButton)
  }

  private func buildStorageSection() -> NSView {
    let section = sectionStack(title: aiSubtitleLocalized("ai_subtitle.section.storage", fallback: "AI Subtitle Cache"),
                               identifier: "SectionTitleAISubtitleStorage")
    let description = NSTextField(wrappingLabelWithString: aiSubtitleLocalized(
      "ai_subtitle.cache_description",
      fallback: "Stores generation progress and results so work can resume without starting over. Clearing the cache does not delete subtitle files saved beside videos."
    ))
    description.textColor = .secondaryLabelColor
    description.maximumNumberOfLines = 2
    section.content.addArrangedSubview(description)
    description.widthAnchor.constraint(equalTo: section.content.widthAnchor).isActive = true

    let cacheLimits: [(String, Int64)] = [
      ("512 MB", 512 * 1024 * 1024),
      ("1 GB", 1024 * 1024 * 1024),
      ("2 GB", 2 * 1024 * 1024 * 1024),
      ("5 GB", 5 * 1024 * 1024 * 1024),
      ("10 GB", 10 * 1024 * 1024 * 1024)
    ]
    for (title, bytes) in cacheLimits {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.representedObject = NSNumber(value: bytes)
      cacheLimitPopup.menu?.addItem(item)
    }
    cacheLimitPopup.target = self
    cacheLimitPopup.action = #selector(cacheLimitChanged(_:))
    let clearButton = NSButton(
      title: aiSubtitleLocalized("ai_subtitle.clear_inactive_cache", fallback: "Clear Other Video Caches"),
      target: self,
      action: #selector(clearCache(_:))
    )
    let controls = NSStackView(views: [cacheLimitPopup, clearButton])
    controls.orientation = .horizontal
    controls.spacing = 8
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.cache_limit", fallback: "Maximum storage"),
      control: controls
    ))

    return section.container
  }

  private func configureStatusContainer() {
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.maximumNumberOfLines = 2
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusContainer.addSubview(statusLabel)
    statusContainer.isHidden = true
    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 120),
      statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor),
      statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor),
      statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor)
    ])
  }

  private func setStatus(_ text: String) {
    statusLabel.stringValue = text
    statusContainer.isHidden = text.isEmpty
  }

  private struct PreferenceSection {
    let container: NSView
    let content: NSStackView
  }

  private func sectionStack(title: String, identifier: String) -> PreferenceSection {
    let container = NSView()
    let content = NSStackView()
    configureSection(container, content: content, title: title, identifier: identifier)
    let section = PreferenceSection(container: container, content: content)
    return section
  }

  private func configureSection(_ container: NSView,
                                content: NSStackView,
                                title: String,
                                identifier: String) {
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 10
    content.detachesHiddenViews = true
    content.translatesAutoresizingMaskIntoConstraints = false
    let titleLabel = NSTextField(labelWithString: "\(title):")
    titleLabel.identifier = NSUserInterfaceItemIdentifier(identifier)
    titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(titleLabel)
    container.addSubview(content)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.leadingAnchor, constant: -12),
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 120),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
  }

  private func formRow(label: String, control: NSView) -> NSView {
    let labelView = NSTextField(labelWithString: label)
    labelView.alignment = .right
    labelView.widthAnchor.constraint(equalToConstant: 120).isActive = true
    let row = NSStackView(views: [labelView, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 14
    return row
  }

  private func configureLanguagePopup(_ popup: NSPopUpButton, options: [AISubtitleLanguageOption]) {
    for option in options {
      let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
      item.representedObject = option.code
      popup.menu?.addItem(item)
    }
  }

  private func restoreSelections() {
    autoModePopup.selectItem(at: AISubtitleAutoMode.current.rawValue)
    let provider = configuredProvider
    if let providerIndex = defaultProviderPopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == provider.rawValue
    }) {
      defaultProviderPopup.selectItem(at: providerIndex)
    }
    selectLanguage(defaults.string(forKey: "aiSubtitle.sourceLanguage"), in: sourcePopup)
    selectLanguage(defaults.string(forKey: "aiSubtitle.targetLanguage")
      ?? Locale.preferredLanguages.first,
                   in: targetPopup)
    let configuredLimit = AISubtitleCachePolicy().maximumBytes
    let selectedLimit = cacheLimitPopup.itemArray.firstIndex {
      ($0.representedObject as? NSNumber)?.int64Value == configuredLimit
    } ?? 2
    cacheLimitPopup.selectItem(at: selectedLimit)
  }

  private func selectLanguage(_ code: String?, in popup: NSPopUpButton) {
    guard let code = code else {
      popup.selectItem(at: 0)
      return
    }
    let normalized = code.replacingOccurrences(of: "_", with: "-").lowercased()
    let exact = popup.itemArray.firstIndex {
      ($0.representedObject as? String)?.lowercased() == normalized
    }
    let primary = popup.itemArray.firstIndex {
      guard let itemCode = $0.representedObject as? String else { return false }
      return itemCode.lowercased().split(separator: "-").first == normalized.split(separator: "-").first
    }
    popup.selectItem(at: exact ?? primary ?? 0)
  }

  private func refreshAll(syncCloudConsent: Bool = false) {
    let supported = AISubtitleSystemSupport.isSupported
    let featureEnabled = AISubtitleFeatureState().isEnabled
    let provider = configuredProvider
    let remote = provider.isCloudProvider
    if let providerIndex = defaultProviderPopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == provider.rawValue
    }) {
      defaultProviderPopup.selectItem(at: providerIndex)
    }
    localSection.isHidden = remote
    remoteSection.isHidden = !remote
    upgradeButton.isHidden = supported
    featureSwitch.state = featureEnabled ? .on : .off
    featureSwitch.isEnabled = supported

    schemeDescriptionLabel.stringValue = remote
      ? String(format: aiSubtitleLocalized("ai_subtitle.setup_remote_provider_description",
                                           fallback: "Audio and subtitle text are sent to %@ for processing."),
               providerServiceName(provider))
      : aiSubtitleLocalized("ai_subtitle.setup_local_description",
                            fallback: "Runs on this Mac with Apple speech and translation. Video audio is not uploaded.")

    let configurationEnabled = supported && featureEnabled
    [defaultProviderPopup, autoModePopup, sourcePopup, targetPopup,
     openAIKeyField, aliyunDashScopeField, aliyunAccessKeyIDField,
     aliyunAccessKeySecretField, consentButton, saveRemoteButton].forEach { $0.isEnabled = configurationEnabled }

    refreshLanguageDownloadIndicators(provider: provider)

    if remote {
      refreshRemoteControls(syncCloudConsent: syncCloudConsent)
    } else {
      refreshAppleResourceStatus()
    }
  }

  private func refreshRemoteControls(syncCloudConsent: Bool) {
    let provider = selectedRemoteProvider
    openAIKeyField.isHidden = provider != .openAI
    aliyunDashScopeField.isHidden = provider != .aliyun
    aliyunAccessKeyIDField.isHidden = provider != .aliyun
    aliyunAccessKeySecretField.isHidden = provider != .aliyun
    removeCredentialsButton.isHidden = !AISubtitleKeychainCredentialChecker().hasCredential(for: provider)
    if syncCloudConsent {
      consentButton.state = UserDefaultsAISubtitleCloudConsentStore().hasConsent(for: provider) ? .on : .off
    }
    consentButton.title = provider == .aliyun
      ? aiSubtitleLocalized("ai_subtitle.aliyun_upload_consent",
                            fallback: "Upload audio (kept up to 48h) and subtitle text to Aliyun")
      : aiSubtitleLocalized("ai_subtitle.openai_upload_consent",
                            fallback: "Allow uploading audio and subtitle text to OpenAI")

    let hasCredential = AISubtitleKeychainCredentialChecker().hasCredential(for: provider)
    credentialResourceRow.setState(hasCredential
      ? .ready(String(format: aiSubtitleLocalized("ai_subtitle.resource.saved_in_keychain", fallback: "%@ credentials are saved in Keychain"), providerServiceName(provider)))
      : .actionRequired(String(format: aiSubtitleLocalized("ai_subtitle.resource.credentials_required", fallback: "Enter and save %@ credentials"), providerServiceName(provider))))

    if provider == .openAI {
      translationCredentialResourceRow.setState(.notRequired(
        aiSubtitleLocalized("ai_subtitle.resource.openai_translation_credential_shared",
                            fallback: "Uses the same OpenAI API key as transcription")
      ))
    } else if translationRequired {
      let aliyun = AISubtitleAliyunKeychainCredentialProvider().credentials()
      let hasTranslationCredentials = !(aliyun.machineTranslationAccessKeyID?.isEmpty ?? true)
        && !(aliyun.machineTranslationAccessKeySecret?.isEmpty ?? true)
      translationCredentialResourceRow.setState(hasTranslationCredentials
        ? .ready(aiSubtitleLocalized("ai_subtitle.resource.translation_credentials_ready", fallback: "Machine Translation credentials are saved"))
        : .actionRequired(aiSubtitleLocalized("ai_subtitle.resource.translation_credentials_required", fallback: "Machine Translation AccessKey ID and Secret are required")))
    } else {
      translationCredentialResourceRow.setState(.notRequired(
        aiSubtitleLocalized("ai_subtitle.resource.not_required", fallback: "Not required for the current language selection")
      ))
    }

    let hasConsent = UserDefaultsAISubtitleCloudConsentStore().hasConsent(for: provider)
    consentResourceRow.setState(hasConsent
      ? .ready(aiSubtitleLocalized("ai_subtitle.resource.cloud_consent_ready", fallback: "Cloud processing is allowed"))
      : .actionRequired(aiSubtitleLocalized("ai_subtitle.resource.cloud_consent_required", fallback: "Review and allow cloud processing")))
    saveRemoteButton.title = AISubtitleInitializationState().isComplete
      ? aiSubtitleLocalized("ai_subtitle.save_remote_settings", fallback: "Save Settings")
      : aiSubtitleLocalized("ai_subtitle.initialize_remote", fallback: "Save and Enable")
  }

  private func refreshAppleResourceStatus() {
    resourceProbeTask?.cancel()
    resourceProbeGeneration += 1
    let generation = resourceProbeGeneration
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let systemDescription = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

    guard AISubtitleSystemSupport.isSupported else {
      systemResourceRow.setState(.unavailable(String(
        format: aiSubtitleLocalized("ai_subtitle.resource.system_unsupported", fallback: "%@ · macOS 26 or later is required"),
        systemDescription
      )))
      speechResourceRow.setState(.unavailable(aiSubtitleLocalized("ai_subtitle.resource.blocked_by_system", fallback: "Unavailable until macOS is upgraded")))
      translationResourceRow.setState(.unavailable(aiSubtitleLocalized("ai_subtitle.resource.blocked_by_system", fallback: "Unavailable until macOS is upgraded")))
      prepareLocalButton.isHidden = true
      return
    }

    systemResourceRow.setState(.ready(String(
      format: aiSubtitleLocalized("ai_subtitle.resource.system_supported", fallback: "%@ · supported"),
      systemDescription
    )))
    guard let sourceLanguage = selectedSourceLanguage else {
      speechCapability = nil
      translationCapability = nil
      speechResourceRow.setState(.actionRequired(aiSubtitleLocalized("ai_subtitle.resource.choose_audio_language", fallback: "Choose a default audio language")))
      translationResourceRow.setState(.actionRequired(aiSubtitleLocalized("ai_subtitle.resource.choose_audio_language_first", fallback: "Choose the audio language before checking translation resources")))
      prepareLocalButton.isHidden = true
      return
    }

    let targetLanguage = selectedTargetLanguage
    let checking = aiSubtitleLocalized("ai_subtitle.resource.checking", fallback: "Checking availability…")
    speechResourceRow.setState(.checking(checking))
    translationResourceRow.setState(.checking(checking))
    prepareLocalButton.isHidden = true

    if #available(macOS 26.0, *) {
      resourceProbeTask = Task { [weak self] in
        async let speechProbe = AppleAISubtitleTranscriber().probe(language: sourceLanguage)
        async let translationProbe = AppleAISubtitleTranslator().probe(sourceLanguage: sourceLanguage,
                                                                        targetLanguage: targetLanguage)
        let capabilities = await (speechProbe, translationProbe)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self = self, generation == self.resourceProbeGeneration else { return }
          self.speechCapability = capabilities.0
          self.translationCapability = capabilities.1
          self.applyAppleCapabilities(sourceLanguage: sourceLanguage,
                                      targetLanguage: targetLanguage)
        }
      }
    }
  }

  private func applyAppleCapabilities(sourceLanguage: AISubtitleLanguage,
                                      targetLanguage: AISubtitleLanguage) {
    let sourceName = localizedLanguageName(sourceLanguage.code)
    let targetName = localizedLanguageName(targetLanguage.code)
    if let speechCapability {
      speechResourceRow.setState(resourceState(for: speechCapability,
                                               readyDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.speech_ready", fallback: "%@ · downloaded"), sourceName),
                                               downloadDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.speech_download", fallback: "%@ · download required"), sourceName),
                                               unavailableDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.speech_unavailable", fallback: "%@ · unavailable on this Mac"), sourceName)))
    }
    if sourceLanguage.isEquivalent(to: targetLanguage) {
      translationResourceRow.setState(.notRequired(String(
        format: aiSubtitleLocalized("ai_subtitle.resource.translation_not_required", fallback: "%@ · source and target languages are the same"),
        targetName
      )))
    } else if let translationCapability {
      let pair = "\(sourceName) → \(targetName)"
      translationResourceRow.setState(resourceState(for: translationCapability,
                                                    readyDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.translation_ready", fallback: "%@ · downloaded"), pair),
                                                    downloadDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.translation_download", fallback: "%@ · download required"), pair),
                                                    unavailableDetail: String(format: aiSubtitleLocalized("ai_subtitle.resource.translation_unavailable", fallback: "%@ · unsupported language pair"), pair)))
    }

    let resourcesReady = speechCapability?.status == .available
      && (sourceLanguage.isEquivalent(to: targetLanguage) || translationCapability?.status == .available)
    let resourcesNeedDownload = speechCapability?.status == .needsDownload
      || (!sourceLanguage.isEquivalent(to: targetLanguage) && translationCapability?.status == .needsDownload)
    if resourcesReady {
      prepareLocalButton.title = aiSubtitleLocalized("ai_subtitle.enable_local", fallback: "Enable Apple Local AI")
      prepareLocalButton.isHidden = AISubtitleInitializationState().isComplete
    } else if resourcesNeedDownload {
      prepareLocalButton.title = aiSubtitleLocalized("ai_subtitle.download_required_resources", fallback: "Download Required Resources")
      prepareLocalButton.isHidden = false
    } else {
      prepareLocalButton.isHidden = true
    }
    prepareLocalButton.isEnabled = AISubtitleFeatureState().isEnabled && !isPreparingAppleResources
  }

  private func resourceState(for capability: AISubtitleProviderCapability,
                             readyDetail: String,
                             downloadDetail: String,
                             unavailableDetail: String) -> AISubtitleResourceViewState {
    switch capability.status {
    case .available:
      return .ready(readyDetail)
    case .needsDownload:
      return .actionRequired(downloadDetail)
    case .unavailable:
      return .unavailable(unavailableDetail)
    case .needsAuthorization, .needsConfiguration, .requiresRuntimeProbe:
      return .actionRequired(capability.reason ?? downloadDetail)
    }
  }

  @objc private func defaultProviderChanged(_ sender: NSPopUpButton) {
    guard let rawValue = sender.selectedItem?.representedObject as? String,
          let provider = AISubtitleProviderID(rawValue: rawValue),
          provider != .whisperCpp else { return }
    persistProvider(provider)
    setStatus("")
    refreshAll(syncCloudConsent: true)
  }

  @objc private func featureEnabledChanged(_ sender: NSSwitch) {
    guard AISubtitleSystemSupport.isSupported else {
      sender.state = .off
      presentSystemUpgrade()
      return
    }
    let enabled = sender.state == .on
    AISubtitleFeatureState().setEnabled(enabled)
    if !enabled {
      PlayerCore.playerCores.forEach { $0.stopAISubtitles() }
      setStatus("")
    }
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }
    refreshAll(syncCloudConsent: true)
  }

  @objc private func autoModeChanged(_ sender: NSPopUpButton) {
    AISubtitleAutoMode.current = AISubtitleAutoMode(rawValue: sender.indexOfSelectedItem) ?? .whenMissing
  }

  @objc private func languageChanged(_ sender: NSPopUpButton) {
    defaults.set(selectedSourceLanguage?.code, forKey: "aiSubtitle.sourceLanguage")
    defaults.set(selectedTargetLanguage.code, forKey: "aiSubtitle.targetLanguage")
    setStatus("")
    refreshAll()
  }

  @objc private func consentChanged(_ sender: NSButton) {
    UserDefaultsAISubtitleCloudConsentStore().setConsent(sender.state == .on, for: selectedRemoteProvider)
    refreshRemoteControls(syncCloudConsent: false)
  }

  @objc private func prepareLocalAI(_ sender: NSButton) {
    guard AISubtitleSystemSupport.isSupported else {
      presentSystemUpgrade()
      return
    }
    guard #available(macOS 26.0, *), let sourceLanguage = selectedSourceLanguage else {
      setStatus(aiSubtitleLocalized("ai_subtitle.source_required",
                                    fallback: "Choose the video's spoken language before generating AI subtitles."))
      return
    }
    persistProvider(.apple)
    defaults.set(sourceLanguage.code, forKey: "aiSubtitle.sourceLanguage")
    defaults.set(selectedTargetLanguage.code, forKey: "aiSubtitle.targetLanguage")
    isPreparingAppleResources = true
    setPreparationControlsEnabled(false)
    setStatus(aiSubtitleLocalized("ai_subtitle.resource.checking", fallback: "Checking availability…"))

    let targetLanguage = selectedTargetLanguage
    Task { [weak self] in
      async let speechProbe = AppleAISubtitleTranscriber().probe(language: sourceLanguage)
      async let translationProbe = AppleAISubtitleTranslator().probe(sourceLanguage: sourceLanguage,
                                                                      targetLanguage: targetLanguage)
      let capabilities = await (speechProbe, translationProbe)
      await MainActor.run {
        guard let self = self else { return }
        self.speechCapability = capabilities.0
        self.translationCapability = capabilities.1
        self.continueApplePreparation(sourceLanguage: sourceLanguage,
                                      targetLanguage: targetLanguage)
      }
    }
  }

  @available(macOS 26.0, *)
  private func continueApplePreparation(sourceLanguage: AISubtitleLanguage,
                                        targetLanguage: AISubtitleLanguage) {
    guard let speechCapability else {
      finishApplePreparation(.failure(AISubtitleError(code: "apple_speech_probe_failed",
                                                       message: aiSubtitleLocalized("ai_subtitle.resource.probe_failed", fallback: "Could not check Apple speech resources."))))
      return
    }
    switch speechCapability.status {
    case .available:
      prepareAppleTranslationIfNeeded(sourceLanguage: sourceLanguage,
                                      targetLanguage: targetLanguage)
    case .needsDownload:
      speechResourceRow.setState(.preparing(
        aiSubtitleLocalized("ai_subtitle.downloading_speech", fallback: "Downloading Apple speech resources…"),
        nil
      ))
      AppleAISubtitleTranscriber().installAssets(language: sourceLanguage,
                                                 progressHandler: { [weak self] progress in
        DispatchQueue.main.async {
          self?.speechResourceRow.setState(.preparing(
            aiSubtitleLocalized("ai_subtitle.downloading_speech", fallback: "Downloading Apple speech resources…"),
            progress
          ))
        }
      }, completion: { [weak self] result in
        DispatchQueue.main.async {
          guard let self = self else { return }
          switch result {
          case .success:
            self.prepareAppleTranslationIfNeeded(sourceLanguage: sourceLanguage,
                                                  targetLanguage: targetLanguage)
          case .failure(let error):
            self.finishApplePreparation(.failure(error))
          }
        }
      })
    case .unavailable, .needsAuthorization, .needsConfiguration, .requiresRuntimeProbe:
      finishApplePreparation(.failure(AISubtitleError(
        code: "apple_speech_unavailable",
        message: speechCapability.reason ?? aiSubtitleLocalized("ai_subtitle.resource.speech_unavailable_generic", fallback: "The selected Apple speech model is unavailable.")
      )))
    }
  }

  @available(macOS 26.0, *)
  private func prepareAppleTranslationIfNeeded(sourceLanguage: AISubtitleLanguage,
                                               targetLanguage: AISubtitleLanguage) {
    if sourceLanguage.isEquivalent(to: targetLanguage) {
      finishApplePreparation(.success(()))
      return
    }
    guard let translationCapability else {
      finishApplePreparation(.failure(AISubtitleError(code: "apple_translation_probe_failed",
                                                       message: aiSubtitleLocalized("ai_subtitle.resource.translation_probe_failed", fallback: "Could not check Apple translation resources."))))
      return
    }
    switch translationCapability.status {
    case .available:
      finishApplePreparation(.success(()))
    case .needsDownload:
      translationResourceRow.setState(.preparing(
        aiSubtitleLocalized("ai_subtitle.preparing_translation", fallback: "Preparing on-device translation resources…"),
        nil
      ))
      showTranslationPreparation(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    case .unavailable, .needsAuthorization, .needsConfiguration, .requiresRuntimeProbe:
      finishApplePreparation(.failure(AISubtitleError(
        code: "apple_translation_unavailable",
        message: translationCapability.reason ?? aiSubtitleLocalized("ai_subtitle.resource.translation_unavailable_generic", fallback: "The selected Apple translation languages are unavailable.")
      )))
    }
  }

  @available(macOS 26.0, *)
  private func showTranslationPreparation(sourceLanguage: AISubtitleLanguage,
                                          targetLanguage: AISubtitleLanguage) {
    clearTranslationPreparation()
    let preparationView = AppleTranslationPreparationView(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage
    ) { [weak self] result in
      self?.clearTranslationPreparation()
      self?.finishApplePreparation(result)
    }
    let host = NSHostingView(rootView: preparationView)
    host.translatesAutoresizingMaskIntoConstraints = false
    translationPreparationHost = host
    translationHostContainer.addArrangedSubview(host)
    host.widthAnchor.constraint(equalTo: translationHostContainer.widthAnchor).isActive = true
    host.heightAnchor.constraint(equalToConstant: 58).isActive = true
    translationHostContainer.isHidden = false
  }

  private func finishApplePreparation(_ result: Result<Void, AISubtitleError>) {
    isPreparingAppleResources = false
    setPreparationControlsEnabled(true)
    switch result {
    case .success:
      AISubtitleInitializationState().markComplete(provider: .apple)
      setStatus(aiSubtitleLocalized("ai_subtitle.local_ready", fallback: "Apple Local AI is ready."))
    case .failure(let error):
      setStatus(error.message)
    }
    refreshAll()
  }

  private func clearTranslationPreparation() {
    translationPreparationHost?.removeFromSuperview()
    translationPreparationHost = nil
    translationHostContainer.isHidden = true
  }

  private func setPreparationControlsEnabled(_ enabled: Bool) {
    let configurationEnabled = enabled && AISubtitleFeatureState().isEnabled
    defaultProviderPopup.isEnabled = configurationEnabled
    sourcePopup.isEnabled = configurationEnabled
    targetPopup.isEnabled = configurationEnabled
    prepareLocalButton.isEnabled = configurationEnabled
  }

  @objc private func saveRemoteAI(_ sender: NSButton) {
    let provider = selectedRemoteProvider
    persistProvider(provider)
    do {
      let credentialStore = AISubtitleCloudCredentialStore()
      if provider == .openAI, !openAIKeyField.stringValue.isEmpty {
        try credentialStore.saveOpenAIAPIKey(openAIKeyField.stringValue)
        openAIKeyField.stringValue = ""
      }
      if provider == .aliyun {
        if !aliyunDashScopeField.stringValue.isEmpty {
          try credentialStore.saveAliyunDashScopeAPIKey(aliyunDashScopeField.stringValue)
          aliyunDashScopeField.stringValue = ""
        }
        if !aliyunAccessKeyIDField.stringValue.isEmpty || !aliyunAccessKeySecretField.stringValue.isEmpty {
          guard !aliyunAccessKeyIDField.stringValue.isEmpty,
                !aliyunAccessKeySecretField.stringValue.isEmpty else {
            throw AISubtitleError(code: "aliyun_credentials_incomplete",
                                  message: aiSubtitleLocalized("ai_subtitle.aliyun_credentials_incomplete",
                                                               fallback: "Enter both Machine Translation AccessKey fields."))
          }
          try credentialStore.saveAliyunMachineTranslation(accessKeyID: aliyunAccessKeyIDField.stringValue,
                                                            accessKeySecret: aliyunAccessKeySecretField.stringValue)
          aliyunAccessKeyIDField.stringValue = ""
          aliyunAccessKeySecretField.stringValue = ""
        }
      }
      UserDefaultsAISubtitleCloudConsentStore().setConsent(consentButton.state == .on, for: provider)
      guard AISubtitleKeychainCredentialChecker().hasCredential(for: provider) else {
        throw AISubtitleError(code: "cloud_credentials_required",
                              message: aiSubtitleLocalized("ai_subtitle.cloud_credentials_required",
                                                           fallback: "Enter and save the selected remote service credentials."))
      }
      guard consentButton.state == .on else {
        throw AISubtitleError(code: "cloud_consent_required",
                              message: aiSubtitleLocalized("ai_subtitle.cloud_consent_required",
                                                           fallback: "Allow cloud processing before finishing remote AI setup."))
      }
      if provider == .aliyun && translationRequired {
        let aliyun = AISubtitleAliyunKeychainCredentialProvider().credentials()
        guard !(aliyun.machineTranslationAccessKeyID?.isEmpty ?? true),
              !(aliyun.machineTranslationAccessKeySecret?.isEmpty ?? true) else {
          throw AISubtitleError(code: "aliyun_translation_credentials_required",
                                message: aiSubtitleLocalized("ai_subtitle.aliyun_translation_credentials_required",
                                                             fallback: "Enter the Aliyun Machine Translation AccessKey ID and secret."))
        }
      }
      AISubtitleInitializationState().markComplete(provider: provider)
      setStatus(aiSubtitleLocalized("ai_subtitle.remote_ready", fallback: "Remote AI is ready."))
      refreshAll(syncCloudConsent: true)
    } catch {
      setStatus((error as? AISubtitleError)?.message ?? error.localizedDescription)
      refreshRemoteControls(syncCloudConsent: false)
    }
  }

  @objc private func removeCloudCredentials(_ sender: NSButton) {
    let provider = selectedRemoteProvider
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = aiSubtitleLocalized("ai_subtitle.remove_credentials_title",
                                            fallback: "Remove Saved Cloud Credentials?")
    alert.informativeText = String(format: aiSubtitleLocalized("ai_subtitle.remove_credentials_message",
                                                               fallback: "Remove the saved credentials for %@ from Keychain?"),
                                   providerServiceName(provider))
    alert.addButton(withTitle: aiSubtitleLocalized("ai_subtitle.remove", fallback: "Remove"))
    alert.addButton(withTitle: aiSubtitleLocalized("ai_subtitle.cancel", fallback: "Cancel"))
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn, let self = self else { return }
      do {
        try AISubtitleCloudCredentialStore().removeCredentials(for: provider)
        UserDefaultsAISubtitleCloudConsentStore().setConsent(false, for: provider)
        AISubtitleInitializationState().reset(provider: provider)
        self.setStatus(String(
          format: aiSubtitleLocalized("ai_subtitle.credentials_removed",
                                      fallback: "Removed saved %@ credentials."),
          self.providerServiceName(provider)
        ))
        self.refreshAll(syncCloudConsent: true)
      } catch {
        self.setStatus(error.localizedDescription)
      }
    }
  }

  @objc private func cacheLimitChanged(_ sender: NSPopUpButton) {
    let maximumBytes = (sender.selectedItem?.representedObject as? NSNumber)?.int64Value
      ?? AISubtitleCachePolicy.defaultMaximumBytes
    defaults.set(maximumBytes, forKey: AISubtitleCachePolicy.maximumBytesDefaultsKey)
    pruneCache(maximumBytes: maximumBytes)
  }

  @objc private func clearCache(_ sender: NSButton) {
    pruneCache(maximumBytes: 0)
  }

  private func pruneCache(maximumBytes: Int64) {
    do {
      let result = try PlayerCore.active.pruneAISubtitleCache(maximumBytes: maximumBytes)
      setStatus(result.removedEntryCount == 0
        ? aiSubtitleLocalized("ai_subtitle.cache_nothing_removed",
                              fallback: "No other video cache needed removal.")
        : String(format: aiSubtitleLocalized("ai_subtitle.cache_removed",
                                             fallback: "Removed %d cached item(s), freeing %@."),
                 result.removedEntryCount,
                 ByteCountFormatter.string(fromByteCount: result.removedBytes, countStyle: .file)))
    } catch {
      setStatus(error.localizedDescription)
    }
  }

  private func persistProvider(_ provider: AISubtitleProviderID) {
    defaults.set(preferenceIndex(for: provider), forKey: "aiSubtitle.provider")
  }

  private func preferenceIndex(for provider: AISubtitleProviderID) -> Int {
    switch provider {
    case .apple, .whisperCpp: return 0
    case .openAI: return 1
    case .aliyun: return 2
    }
  }

  private var configuredProvider: AISubtitleProviderID {
    guard defaults.object(forKey: "aiSubtitle.provider") != nil else { return .apple }
    let provider = AISubtitleProviderID(preferenceIndex: defaults.integer(forKey: "aiSubtitle.provider")) ?? .apple
    return provider == .whisperCpp ? .apple : provider
  }

  private var selectedRemoteProvider: AISubtitleProviderID {
    return configuredProvider.isCloudProvider ? configuredProvider : .openAI
  }

  private var selectedSourceLanguage: AISubtitleLanguage? {
    (sourcePopup.selectedItem?.representedObject as? String).map(AISubtitleLanguage.init)
  }

  private var selectedTargetLanguage: AISubtitleLanguage {
    AISubtitleLanguage((targetPopup.selectedItem?.representedObject as? String) ?? "en")
  }

  private var translationRequired: Bool {
    selectedSourceLanguage.map { !$0.isEquivalent(to: selectedTargetLanguage) } ?? true
  }

  private func providerOptionTitle(_ provider: AISubtitleProviderID) -> String {
    provider == .apple
      ? aiSubtitleLocalized("ai_subtitle.provider.apple_option", fallback: "Apple Local AI")
      : providerServiceName(provider)
  }

  private func providerServiceName(_ provider: AISubtitleProviderID) -> String {
    provider == .aliyun
      ? aiSubtitleLocalized("ai_subtitle.provider.aliyun_option", fallback: "Aliyun")
      : provider.displayName
  }

  private func localizedLanguageName(_ code: String) -> String {
    let interfaceLanguage = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
    return Locale(identifier: interfaceLanguage).localizedString(forIdentifier: code) ?? code
  }

  private func refreshLanguageDownloadIndicators(provider: AISubtitleProviderID) {
    languageStatusTask?.cancel()
    languageStatusGeneration += 1
    let generation = languageStatusGeneration
    updateLanguagePopupTitles(sourcePopup,
                              options: AISubtitleLanguageCatalog.sourceLanguages,
                              downloadedCodes: [])
    updateLanguagePopupTitles(targetPopup,
                              options: AISubtitleLanguageCatalog.targetLanguages,
                              downloadedCodes: [])

    guard provider == .apple, AISubtitleSystemSupport.isSupported else { return }
    guard #available(macOS 26.0, *) else { return }
    let sourceLanguage = selectedSourceLanguage
    languageStatusTask = Task { [weak self] in
      let transcriber = AppleAISubtitleTranscriber()
      var downloadedSourceCodes = Set<String>()
      for option in AISubtitleLanguageCatalog.sourceLanguages {
        guard !Task.isCancelled, let code = option.code else { continue }
        let capability = await transcriber.probe(language: AISubtitleLanguage(code))
        if capability.status == .available {
          downloadedSourceCodes.insert(code)
        }
      }

      var downloadedTargetCodes = Set<String>()
      if let sourceLanguage {
        let availability = LanguageAvailability()
        for option in AISubtitleLanguageCatalog.targetLanguages {
          guard !Task.isCancelled, let code = option.code else { continue }
          let targetLanguage = AISubtitleLanguage(code)
          guard !sourceLanguage.isEquivalent(to: targetLanguage) else { continue }
          let status = await availability.status(
            from: Locale.Language(identifier: sourceLanguage.code),
            to: Locale.Language(identifier: code)
          )
          if status == .installed {
            downloadedTargetCodes.insert(code)
          }
        }
      }
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, generation == self.languageStatusGeneration else { return }
        self.updateLanguagePopupTitles(self.sourcePopup,
                                       options: AISubtitleLanguageCatalog.sourceLanguages,
                                       downloadedCodes: downloadedSourceCodes)
        self.updateLanguagePopupTitles(self.targetPopup,
                                       options: AISubtitleLanguageCatalog.targetLanguages,
                                       downloadedCodes: downloadedTargetCodes)
      }
    }
  }

  private func updateLanguagePopupTitles(_ popup: NSPopUpButton,
                                         options: [AISubtitleLanguageOption],
                                         downloadedCodes: Set<String>) {
    for (index, option) in options.enumerated() where index < popup.numberOfItems {
      let title: String
      if let code = option.code, downloadedCodes.contains(code) {
        title = String(format: aiSubtitleLocalized("ai_subtitle.language_downloaded",
                                                   fallback: "%@ · Downloaded"),
                       option.title)
      } else {
        title = option.title
      }
      popup.item(at: index)?.title = title
    }
  }

  private func presentSystemUpgrade() {
    PlayerCore.active.presentAISubtitleSystemUpgrade(parentWindow: view.window)
  }

  @objc private func openSoftwareUpdate(_ sender: NSButton) {
    presentSystemUpgrade()
  }
}

@available(macOS 26.0, *)
private struct AppleTranslationPreparationView: View {
  let sourceLanguage: AISubtitleLanguage
  let targetLanguage: AISubtitleLanguage
  let completion: (Result<Void, AISubtitleError>) -> Void

  var body: some View {
    HStack(spacing: 10) {
      ProgressView()
      Text(aiSubtitleLocalized("ai_subtitle.preparing_translation",
                               fallback: "Preparing on-device translation resources…"))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .translationTask(source: Locale.Language(identifier: sourceLanguage.code),
                     target: Locale.Language(identifier: targetLanguage.code)) { session in
      do {
        try await session.prepareTranslation()
        await MainActor.run { completion(.success(())) }
      } catch {
        await MainActor.run {
          completion(.failure(AISubtitleError(code: "apple_translation_asset_installation_failed",
                                              message: error.localizedDescription)))
        }
      }
    }
  }
}
