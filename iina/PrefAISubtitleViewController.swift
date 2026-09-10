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
  case notReady(String)
  case notRequired(String)
}

private enum AppleLocalResourceID: Hashable {
  case speech(String)
  case translation(source: String, target: String)

  var sourceCode: String {
    switch self {
    case .speech(let code), .translation(let code, _): return code
    }
  }
}

private enum AppleLocalResourceStatus {
  case available
  case installed
  case downloading(Progress?)
  case failed(String)
}

private struct AppleLocalResourceItem {
  let id: AppleLocalResourceID
  let title: String
  var status: AppleLocalResourceStatus
}

private final class AISubtitlePlanCardView: NSView {
  private var cardIsSelected = false

  func configureAppearance() {
    wantsLayer = true
    layer?.cornerRadius = 6
    updateColors()
  }

  func setSelected(_ selected: Bool) {
    cardIsSelected = selected
    updateColors()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.applyAppearanceFor {
      layer?.borderWidth = cardIsSelected ? 2 : 1
      layer?.borderColor = (cardIsSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
      layer?.backgroundColor = cardIsSelected
        ? NSColor.controlAccentColor.withAlphaComponent(0.035).cgColor
        : NSColor.controlBackgroundColor.cgColor
    }
  }
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
    case .notReady(let detail):
      setIcon(symbol: "circle", fallback: NSImage.statusPartiallyAvailableName, color: .secondaryLabelColor)
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
      preferenceTabTitle: [
        aiSubtitleLocalized("ai_subtitle.enable_feature", fallback: "Enable AI Subtitles"),
        aiSubtitleLocalized("ai_subtitle.provider.apple_option", fallback: "Apple Local AI"),
        aiSubtitleLocalized("ai_subtitle.provider.rawya_remote", fallback: "Rawya Remote AI"),
        aiSubtitleLocalized("ai_subtitle.setup.video_languages", fallback: "Audio languages"),
        aiSubtitleLocalized("ai_subtitle.setup.subtitle_language", fallback: "Subtitle language"),
        aiSubtitleLocalized("ai_subtitle.setup.start", fallback: "Start Download"),
        aiSubtitleLocalized("ai_subtitle.auto_mode", fallback: "Automatic generation"),
        aiSubtitleLocalized("ai_subtitle.default_spoken_language", fallback: "Audio language"),
        aiSubtitleLocalized("ai_subtitle.default_subtitle_language", fallback: "Default subtitle language")
      ]
    ]
  }

  private let defaults = UserDefaults.standard
  private let featureSwitch = NSSwitch()
  private let reminderContainer = NSView()
  private let reminderLabel = NSTextField(wrappingLabelWithString: "")
  private let localPlanSelectionButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
  private let remotePlanSelectionButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
  private var autoModeButtons: [NSButton] = []
  private let sourcePopup = NSPopUpButton()
  private let targetPopup = NSPopUpButton()
  private let preparationTargetPopup = NSPopUpButton()
  private let preparationSourceLanguagesStack = NSStackView()
  private var preparationSourceLanguageButtons: [String: NSButton] = [:]
  private var preparationSourceLanguagesRow: NSView?
  private let preparationSummaryLabel = NSTextField(wrappingLabelWithString: "")
  private let prepareLocalPlanButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.setup.start", fallback: "Start Download"),
    target: nil,
    action: nil
  )
  private let preparationProgressIndicator = NSProgressIndicator()
  private let preparationProgressLabel = NSTextField(labelWithString: "")
  private let preparationProgressRow = NSStackView()
  private let upgradeButton = NSButton(
    title: aiSubtitleLocalized("ai_subtitle.open_software_update", fallback: "Open Software Update"),
    target: nil,
    action: nil
  )
  private let cacheLimitPopup = NSPopUpButton()
  private let cacheUsageLabel = NSTextField(labelWithString: "")
  private var cacheUsageGeneration = 0
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let statusContainer = NSView()

  private let systemResourceRow = AISubtitleResourceRowView(
    title: aiSubtitleLocalized("ai_subtitle.resource.system", fallback: "macOS compatibility")
  )
  private let localPlanStatusIcon = NSImageView()
  private let localPlanStatusLabel = NSTextField(labelWithString: "")
  private let remotePlanStatusIcon = NSImageView()
  private let remotePlanStatusLabel = NSTextField(labelWithString: "")

  private let localSection = AISubtitlePlanCardView()
  private let localContentStack = NSStackView()
  private let remoteSection = AISubtitlePlanCardView()
  private let remoteContentStack = NSStackView()
  private let translationHostContainer = NSStackView()
  private var translationPreparationHost: NSView?
  private var resourceProbeTask: Task<Void, Never>?
  private var resourceProbeGeneration = 0
  private var batchDownloadTask: Task<Void, Never>?
  private var speechResourceItems: [AppleLocalResourceItem] = []
  private var translationResourceItems: [AppleLocalResourceItem] = []
  private var selectedAppleResources = Set<AppleLocalResourceID>()
  private var installedSpeechCodes = Set<String>()
  private var installedTranslationPairs = Set<String>()
  private var pendingTranslationDownloads: [(source: AISubtitleLanguage, target: AISubtitleLanguage)] = []
  private var isPreparingAppleResources = false
  private var isCheckingAppleResources = false
  private var isLocalPlanReady = false
  private var isRemotePlanReady = false
  private var preparationErrorMessage: String?
  private weak var preferenceWindow: NSWindow?
  private var windowWillCloseObserver: NSObjectProtocol?

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 1))
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    windowWillCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.preferenceWindowWillClose(notification)
    }
    isLocalPlanReady = AISubtitleInitializationState().isPrepared(.apple)
    buildUI()
    restoreSelections()
    refreshAll()
  }

  deinit {
    resourceProbeTask?.cancel()
    batchDownloadTask?.cancel()
    if let windowWillCloseObserver {
      NotificationCenter.default.removeObserver(windowWillCloseObserver)
    }
  }

  func preferenceViewDidOpen() {
    preferenceWindow = view.window
    restoreSelections()
    refreshAll()
  }

  private func preferenceWindowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          closingWindow === preferenceWindow else { return }
    clearPendingPreparationSelection()
  }

  private func buildUI() {
    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 14
    root.detachesHiddenViews = true
    root.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      root.topAnchor.constraint(equalTo: view.topAnchor),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    configureReminder()
    root.addArrangedSubview(buildFeatureToggleSection())
    root.addArrangedSubview(NSBox.horizontalLine())

    configureLocalSection()
    root.addArrangedSubview(localSection)
    configureRemoteSection()
    root.addArrangedSubview(remoteSection)
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildAutomationSection())
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildLanguageSection())
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildStorageSection())

    configureStatusContainer()
    root.addArrangedSubview(statusContainer)
    root.addArrangedSubview(NSBox.horizontalLine())
    root.addArrangedSubview(buildDisclaimer())

    root.views.forEach { arrangedView in
      arrangedView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
  }

  private func configureReminder() {
    reminderContainer.wantsLayer = true
    reminderContainer.layer?.cornerRadius = 6
    reminderContainer.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.10).cgColor
    reminderContainer.isHidden = true

    reminderLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    reminderLabel.maximumNumberOfLines = 0
    reminderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let icon = NSImageView()
    if #available(macOS 11.0, *) {
      icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
    } else {
      icon.image = NSImage(named: NSImage.statusPartiallyAvailableName)
    }
    icon.contentTintColor = .systemOrange
    let row = NSStackView(views: [icon, reminderLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    row.translatesAutoresizingMaskIntoConstraints = false
    reminderContainer.addSubview(row)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 16),
      icon.heightAnchor.constraint(equalToConstant: 16),
      row.leadingAnchor.constraint(equalTo: reminderContainer.leadingAnchor, constant: 12),
      row.trailingAnchor.constraint(equalTo: reminderContainer.trailingAnchor, constant: -10),
      row.topAnchor.constraint(equalTo: reminderContainer.topAnchor, constant: 8),
      row.bottomAnchor.constraint(equalTo: reminderContainer.bottomAnchor, constant: -8)
    ])
  }

  private func buildFeatureToggleSection() -> NSView {
    let title = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.enable_feature",
      fallback: "Enable AI Subtitles"
    ))
    title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    featureSwitch.target = self
    featureSwitch.action = #selector(featureEnabledChanged(_:))
    featureSwitch.setAccessibilityLabel(title.stringValue)

    let toggleRow = NSStackView(views: [featureSwitch, title])
    toggleRow.orientation = .horizontal
    toggleRow.alignment = .centerY
    toggleRow.spacing = 12

    let stack = NSStackView(views: [toggleRow, reminderContainer])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.detachesHiddenViews = true
    stack.translatesAutoresizingMaskIntoConstraints = false

    let container = NSView()
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
      toggleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      reminderContainer.widthAnchor.constraint(equalTo: stack.widthAnchor)
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
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      label.topAnchor.constraint(equalTo: container.topAnchor),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    return container
  }

  private func buildAutomationSection() -> NSView {
    let section = sectionStack(title: aiSubtitleLocalized(
      "ai_subtitle.section.automation",
      fallback: "Generation"
    ), identifier: "SectionTitleAISubtitleAutomation")
    let options: [(AISubtitleAutoMode, String, String)] = [
      (.always,
       aiSubtitleLocalized("ai_subtitle.auto.always",
                           fallback: "Generate automatically using default languages"),
       aiSubtitleLocalized("ai_subtitle.auto.always_description",
                           fallback: "Best for videos usually in the same language. Starts when a video opens.")),
      (.whenMissing,
       aiSubtitleLocalized("ai_subtitle.auto.when_missing",
                           fallback: "Use default languages when subtitles are missing"),
       aiSubtitleLocalized("ai_subtitle.auto.when_missing_description",
                           fallback: "Uses existing subtitles first and generates only when none are available.")),
      (.confirmLanguage,
       aiSubtitleLocalized("ai_subtitle.auto.confirm_language",
                           fallback: "Generate after confirming languages"),
       aiSubtitleLocalized("ai_subtitle.auto.confirm_language_description",
                           fallback: "Best when switching between video languages. Confirm the audio language to start.")),
      (.manual,
       aiSubtitleLocalized("ai_subtitle.auto.manual",
                           fallback: "Generate manually only"),
       aiSubtitleLocalized("ai_subtitle.auto.manual_description",
                           fallback: "Best for occasional use. Start AI subtitles only when needed."))
    ]
    var optionViews: [NSView] = []
    autoModeButtons = options.map { mode, title, description in
      let button = NSButton(radioButtonWithTitle: title,
                            target: self,
                            action: #selector(autoModeChanged(_:)))
      button.tag = mode.rawValue
      button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      if let cell = button.cell as? NSButtonCell {
        cell.lineBreakMode = .byWordWrapping
        cell.wraps = true
      }
      let descriptionLabel = NSTextField(wrappingLabelWithString: description)
      descriptionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
      descriptionLabel.textColor = .secondaryLabelColor
      descriptionLabel.maximumNumberOfLines = 0
      descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let optionStack = NSStackView(views: [button, descriptionLabel])
      optionStack.orientation = .vertical
      optionStack.alignment = .leading
      optionStack.spacing = 2
      descriptionLabel.leadingAnchor.constraint(equalTo: optionStack.leadingAnchor, constant: 22).isActive = true
      descriptionLabel.trailingAnchor.constraint(equalTo: optionStack.trailingAnchor).isActive = true
      optionViews.append(optionStack)
      return button
    }
    let controls = NSStackView(views: optionViews)
    controls.orientation = .vertical
    controls.alignment = .leading
    controls.spacing = 10
    optionViews.forEach { $0.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true }
    let row = formRow(label: "", control: controls, alignment: .top)
    section.content.addArrangedSubview(row)
    row.widthAnchor.constraint(equalTo: section.content.widthAnchor).isActive = true
    controls.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
    return section.container
  }

  private func buildLanguageSection() -> NSView {
    let section = sectionStack(title: aiSubtitleLocalized(
      "ai_subtitle.section.languages",
      fallback: "Default Languages"
    ), identifier: "SectionTitleAISubtitleLanguages")
    sourcePopup.target = self
    sourcePopup.action = #selector(languageChanged(_:))
    targetPopup.target = self
    targetPopup.action = #selector(languageChanged(_:))
    sourcePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.default_subtitle_language", fallback: "Subtitle language"),
      control: targetPopup
    ))
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.default_spoken_language", fallback: "Audio language"),
      control: sourcePopup
    ))
    return section.container
  }

  private func configureLocalSection() {
    localPlanSelectionButton.target = self
    localPlanSelectionButton.action = #selector(defaultSchemeChanged(_:))
    localPlanSelectionButton.tag = 0
    configurePlanCard(localSection,
                      content: localContentStack,
                      selectionButton: localPlanSelectionButton,
                      title: aiSubtitleLocalized("ai_subtitle.provider.apple_option", fallback: "Apple Local AI"),
                      description: aiSubtitleLocalized(
                        "ai_subtitle.plan.apple_description",
                        fallback: "Runs on this Mac. Audio is not uploaded."
                      ),
                      identifier: "SectionTitleAISubtitleResources",
                      statusIcon: localPlanStatusIcon,
                      statusLabel: localPlanStatusLabel)
    systemResourceRow.isHidden = true
    localContentStack.addArrangedSubview(systemResourceRow)
    systemResourceRow.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true

    configureLanguagePopup(preparationTargetPopup, options: AISubtitleLanguageCatalog.targetLanguages)
    preparationTargetPopup.target = self
    preparationTargetPopup.action = #selector(preparationTargetChanged(_:))
    let targetLanguageRow = formRow(
      label: aiSubtitleLocalized("ai_subtitle.setup.subtitle_language", fallback: "Subtitle language"),
      control: preparationTargetPopup
    )
    localContentStack.addArrangedSubview(targetLanguageRow)
    targetLanguageRow.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true

    configurePreparationSourceLanguageChoices()
    let sourceLanguagesRow = formRow(
      label: aiSubtitleLocalized("ai_subtitle.setup.video_languages", fallback: "Audio languages"),
      control: preparationSourceLanguagesStack,
      alignment: .top
    )
    preparationSourceLanguagesRow = sourceLanguagesRow
    localContentStack.addArrangedSubview(sourceLanguagesRow)
    sourceLanguagesRow.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true

    upgradeButton.target = self
    upgradeButton.action = #selector(openSoftwareUpdate(_:))
    upgradeButton.isHidden = true
    localContentStack.addArrangedSubview(upgradeButton)

    translationHostContainer.orientation = .vertical
    translationHostContainer.alignment = .leading
    translationHostContainer.isHidden = true
    translationHostContainer.detachesHiddenViews = true
    localContentStack.addArrangedSubview(translationHostContainer)
    translationHostContainer.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true

    preparationProgressIndicator.style = .spinning
    preparationProgressIndicator.controlSize = .small
    preparationProgressIndicator.isDisplayedWhenStopped = false
    preparationProgressLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    preparationProgressLabel.textColor = .secondaryLabelColor
    preparationProgressRow.orientation = .horizontal
    preparationProgressRow.alignment = .centerY
    preparationProgressRow.spacing = 8
    preparationProgressRow.addArrangedSubview(preparationProgressIndicator)
    preparationProgressRow.addArrangedSubview(preparationProgressLabel)
    preparationProgressRow.isHidden = true
    localContentStack.addArrangedSubview(preparationProgressRow)

    preparationSummaryLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    preparationSummaryLabel.textColor = .secondaryLabelColor
    preparationSummaryLabel.maximumNumberOfLines = 0
    preparationSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    prepareLocalPlanButton.target = self
    prepareLocalPlanButton.action = #selector(prepareSelectedLocalPlan(_:))
    let footerSpacer = NSView()
    footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let footer = NSStackView(views: [preparationSummaryLabel, footerSpacer, prepareLocalPlanButton])
    footer.orientation = .horizontal
    footer.alignment = .centerY
    footer.spacing = 10
    localContentStack.addArrangedSubview(footer)
    footer.widthAnchor.constraint(equalTo: localContentStack.widthAnchor).isActive = true
    refreshPreparationState()
  }

  private func configurePreparationSourceLanguageChoices() {
    preparationSourceLanguagesStack.orientation = .vertical
    preparationSourceLanguagesStack.alignment = .leading
    preparationSourceLanguagesStack.spacing = 6
    preparationSourceLanguagesStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
  }

  private func rebuildPreparationSourceLanguageChoices() {
    preparationSourceLanguagesStack.arrangedSubviews.forEach {
      preparationSourceLanguagesStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    preparationSourceLanguageButtons.removeAll()

    guard let targetLanguage = selectedPreparationTargetLanguage else { return }
    let options = AISubtitleLanguageCatalog.sourceLanguages.compactMap { option -> (String, String)? in
      guard let code = option.code,
            speechResourceItems.contains(where: { $0.id == .speech(code) }) else { return nil }
      let sourceLanguage = AISubtitleLanguage(code)
      guard sourceLanguage.isEquivalent(to: targetLanguage)
        || translationResourceItems.contains(where: {
          $0.id == .translation(source: code, target: targetLanguage.code)
        }) else { return nil }
      return (code, option.title)
    }
    let columnCount = 3
    for startIndex in stride(from: 0, to: options.count, by: columnCount) {
      let row = NSStackView()
      row.orientation = .horizontal
      row.alignment = .centerY
      row.distribution = .fillEqually
      row.spacing = 12
      for column in 0..<columnCount {
        let index = startIndex + column
        if index < options.count {
          let (code, title) = options[index]
          if preparationCombinationIsInstalled(sourceCode: code, targetLanguage: targetLanguage) {
            row.addArrangedSubview(supportedPreparationLanguageView(title: title))
          } else {
            let button = NSButton(checkboxWithTitle: title,
                                  target: self,
                                  action: #selector(preparationSourceLanguageChanged(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(code)
            button.setAccessibilityLabel(title)
            preparationSourceLanguageButtons[code] = button
            row.addArrangedSubview(button)
          }
        } else {
          row.addArrangedSubview(NSView())
        }
      }
      preparationSourceLanguagesStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: preparationSourceLanguagesStack.widthAnchor).isActive = true
    }
    let footnote = NSTextField(wrappingLabelWithString: aiSubtitleLocalized(
      "ai_subtitle.setup.supported_languages_only",
      fallback: "Only languages supported by this Mac are shown."
    ))
    footnote.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    footnote.textColor = .secondaryLabelColor
    footnote.maximumNumberOfLines = 0
    preparationSourceLanguagesStack.addArrangedSubview(footnote)
  }

  private func supportedPreparationLanguageView(title: String) -> NSView {
    let icon = NSImageView()
    let supported = aiSubtitleLocalized("ai_subtitle.plan.prepared", fallback: "Supported")
    if #available(macOS 11.0, *) {
      icon.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                           accessibilityDescription: supported)
    } else {
      icon.image = NSImage(named: NSImage.statusAvailableName)
    }
    icon.contentTintColor = .systemGreen
    icon.imageScaling = .scaleProportionallyDown
    icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
    let label = NSTextField(labelWithString: title)
    let row = NSStackView(views: [icon, label])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 5
    row.setAccessibilityElement(true)
    row.setAccessibilityLabel("\(title), \(supported)")
    return row
  }

  private func preparationCombinationIsInstalled(sourceCode: String,
                                                  targetLanguage: AISubtitleLanguage) -> Bool {
    AISubtitlePreparedLanguageStore.isPrepared(
      source: sourceCode,
      target: targetLanguage.code,
      speechLanguageCodes: installedSpeechCodes,
      translationPairs: installedTranslationPairs
    )
  }

  private func configureRemoteSection() {
    remotePlanSelectionButton.target = self
    remotePlanSelectionButton.action = #selector(defaultSchemeChanged(_:))
    remotePlanSelectionButton.tag = 1
    configurePlanCard(remoteSection,
                      content: remoteContentStack,
                      selectionButton: remotePlanSelectionButton,
                      title: aiSubtitleLocalized("ai_subtitle.provider.rawya_remote", fallback: "Rawya Remote AI"),
                      description: aiSubtitleLocalized(
                        "ai_subtitle.plan.remote_description",
                        fallback: "More languages and higher-quality translation."
                      ),
                      identifier: "SectionTitleAISubtitleRemote",
                      statusIcon: remotePlanStatusIcon,
                      statusLabel: remotePlanStatusLabel)
    setPlanHeader(icon: remotePlanStatusIcon,
                  label: remotePlanStatusLabel,
                  prepared: false,
                  text: aiSubtitleLocalized("ai_subtitle.plan.remote_pending", fallback: "Not Available Yet"))
  }

  private func configurePlanCard(_ container: AISubtitlePlanCardView,
                                 content: NSStackView,
                                 selectionButton: NSButton,
                                 title: String,
                                 description: String,
                                 identifier: String,
                                 statusIcon: NSImageView,
                                 statusLabel: NSTextField) {
    container.configureAppearance()

    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 12
    content.detachesHiddenViews = true
    content.translatesAutoresizingMaskIntoConstraints = false

    selectionButton.title = title
    selectionButton.identifier = NSUserInterfaceItemIdentifier(identifier)
    selectionButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let descriptionLabel = NSTextField(wrappingLabelWithString: description)
    descriptionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    descriptionLabel.textColor = .secondaryLabelColor
    descriptionLabel.maximumNumberOfLines = 2
    let titleStack = NSStackView(views: [selectionButton, descriptionLabel])
    titleStack.orientation = .vertical
    titleStack.alignment = .leading
    titleStack.spacing = 3
    selectionButton.setAccessibilityLabel(title)
    selectionButton.setContentHuggingPriority(.required, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    statusIcon.imageScaling = .scaleProportionallyDown
    statusLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    let header = NSStackView(views: [titleStack, spacer, statusIcon, statusLabel])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 10
    header.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(header)
    container.addSubview(content)
    NSLayoutConstraint.activate([
      statusIcon.widthAnchor.constraint(equalToConstant: 16),
      statusIcon.heightAnchor.constraint(equalToConstant: 16),
      titleStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
      header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      header.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
    ])
  }

  private func buildStorageSection() -> NSView {
    let section = sectionStack(title: aiSubtitleLocalized("ai_subtitle.section.storage", fallback: "AI Subtitle Cache"),
                               identifier: "SectionTitleAISubtitleStorage")
    let description = NSTextField(wrappingLabelWithString: aiSubtitleLocalized(
      "ai_subtitle.cache_description",
      fallback: "Clearing the cache does not delete subtitle files saved beside videos."
    ))
    description.textColor = .secondaryLabelColor
    description.maximumNumberOfLines = 0
    section.content.addArrangedSubview(description)
    description.widthAnchor.constraint(equalTo: section.content.widthAnchor).isActive = true

    cacheUsageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                            weight: .regular)
    section.content.addArrangedSubview(formRow(
      label: aiSubtitleLocalized("ai_subtitle.cache_usage", fallback: "Currently used"),
      control: cacheUsageLabel
    ))

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
      statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
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
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.identifier = NSUserInterfaceItemIdentifier(identifier)
    titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(titleLabel)
    container.addSubview(content)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
  }

  private func formRow(label: String,
                       control: NSView,
                       alignment: NSLayoutConstraint.Attribute = .centerY) -> NSView {
    let labelView = NSTextField(labelWithString: label)
    labelView.alignment = .right
    labelView.widthAnchor.constraint(equalToConstant: 160).isActive = true
    let row = NSStackView(views: [labelView, control])
    row.orientation = .horizontal
    row.alignment = alignment
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
    refreshAutoModeSelection()
    selectLanguage(defaults.string(forKey: "aiSubtitle.preparationTargetLanguage")
      ?? defaults.string(forKey: "aiSubtitle.resourceTargetLanguage")
      ?? defaults.string(forKey: "aiSubtitle.targetLanguage")
      ?? Locale.preferredLanguages.first,
                   in: preparationTargetPopup)
    clearPendingPreparationSelection()
    let configuredLimit = AISubtitleCachePolicy().maximumBytes
    let selectedLimit = cacheLimitPopup.itemArray.firstIndex {
      ($0.representedObject as? NSNumber)?.int64Value == configuredLimit
    } ?? 2
    cacheLimitPopup.selectItem(at: selectedLimit)
    refreshCacheUsage()
  }

  private func clearPendingPreparationSelection() {
    defaults.removeObject(forKey: "aiSubtitle.preparationSourceLanguages")
    preparationSourceLanguageButtons.values.forEach { $0.state = .off }
    preparationErrorMessage = nil
    selectedAppleResources = []
    refreshPreparationState()
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

  private func refreshAll() {
    upgradeButton.isHidden = AISubtitleSystemSupport.isSupported
    refreshAppleResourceInventory()
    refreshSchemeAvailability()
  }

  private func refreshSchemeAvailability() {
    let selectedProvider = explicitDefaultProvider
    let localSelected = selectedProvider == .apple && isLocalPlanReady
    let prepared = aiSubtitleLocalized("ai_subtitle.plan.prepared", fallback: "Supported")
    let notPrepared = aiSubtitleLocalized("ai_subtitle.plan.not_prepared", fallback: "Not Downloaded")
    let localStatus: String
    if isLocalPlanReady {
      localStatus = prepared
    } else if isCheckingAppleResources {
      localStatus = aiSubtitleLocalized("ai_subtitle.resource.checking", fallback: "Checking availability…")
    } else if AISubtitleSystemSupport.isSupported {
      localStatus = notPrepared
    } else {
      localStatus = aiSubtitleLocalized("ai_subtitle.plan.unavailable", fallback: "Unavailable")
    }

    localPlanSelectionButton.state = localSelected ? .on : .off
    localPlanSelectionButton.isEnabled = isLocalPlanReady && !isPreparingAppleResources
    remotePlanSelectionButton.state = .off
    remotePlanSelectionButton.isEnabled = false
    setPlanCardSelected(localSection, selected: localSelected)
    setPlanCardSelected(remoteSection, selected: false)
    setPlanHeader(icon: localPlanStatusIcon,
                  label: localPlanStatusLabel,
                  prepared: isLocalPlanReady,
                  text: localStatus,
                  checking: isCheckingAppleResources,
                  unavailable: !AISubtitleSystemSupport.isSupported)
    setPlanHeader(icon: remotePlanStatusIcon,
                  label: remotePlanStatusLabel,
                  prepared: false,
                  text: aiSubtitleLocalized("ai_subtitle.plan.remote_pending", fallback: "Not Available Yet"))

    let hasUsableDefault = localSelected
    featureSwitch.state = hasUsableDefault && AISubtitleFeatureState().isEnabled ? .on : .off
    featureSwitch.isEnabled = hasUsableDefault
    autoModeButtons.forEach { $0.isEnabled = hasUsableDefault && !isPreparingAppleResources }
    let hasSourceOptions = sourcePopup.itemArray.contains { $0.representedObject is String }
    let hasTargetOptions = targetPopup.itemArray.contains { $0.representedObject is String }
    targetPopup.isEnabled = hasUsableDefault && !isPreparingAppleResources && hasTargetOptions
    sourcePopup.isEnabled = hasUsableDefault
      && !isPreparingAppleResources
      && selectedTargetLanguage != nil
      && hasSourceOptions

    reminderLabel.stringValue = aiSubtitleLocalized(
      "ai_subtitle.reminder.prepare_plan",
      fallback: "Prepare Apple Local AI or, when available, Rawya Remote AI before enabling AI subtitles."
    )
    reminderContainer.isHidden = isLocalPlanReady || isRemotePlanReady
  }

  private func setPlanCardSelected(_ card: AISubtitlePlanCardView, selected: Bool) {
    card.setSelected(selected)
  }

  private func refreshAppleResourceInventory() {
    resourceProbeTask?.cancel()
    resourceProbeGeneration += 1
    let generation = resourceProbeGeneration
    isCheckingAppleResources = false

    guard AISubtitleSystemSupport.isSupported else {
      isLocalPlanReady = false
      systemResourceRow.isHidden = false
      systemResourceRow.setState(.unavailable(aiSubtitleLocalized(
        "ai_subtitle.plan.local_system_unavailable",
        fallback: "This Mac cannot prepare Apple Local AI. Rawya Remote AI remains independent."
      )))
      speechResourceItems = []
      translationResourceItems = []
      selectedAppleResources = []
      preparationSourceLanguagesRow?.isHidden = true
      setPlanHeader(icon: localPlanStatusIcon,
                    label: localPlanStatusLabel,
                    prepared: false,
                    text: aiSubtitleLocalized("ai_subtitle.plan.unavailable", fallback: "Unavailable"),
                    unavailable: true)
      refreshPreparationState()
      refreshSchemeAvailability()
      return
    }

    systemResourceRow.isHidden = true
    isCheckingAppleResources = true
    preparationSourceLanguagesRow?.isHidden = true
    refreshPreparationState()
    setPlanHeader(icon: localPlanStatusIcon,
                  label: localPlanStatusLabel,
                  prepared: isLocalPlanReady,
                  text: aiSubtitleLocalized(isLocalPlanReady ? "ai_subtitle.plan.prepared" : "ai_subtitle.resource.checking",
                                            fallback: isLocalPlanReady ? "Supported" : "Checking availability…"),
                  checking: true)
    refreshSchemeAvailability()

    guard #available(macOS 26.0, *), let targetLanguage = selectedPreparationTargetLanguage else { return }
    resourceProbeTask = Task { [weak self] in
      let sourceOptions = AISubtitleLanguageCatalog.sourceLanguages.compactMap { option -> (String, String)? in
        option.code.map { ($0, option.title) }
      }
      var speechStatuses: [String: AISubtitleProviderStatus] = [:]
      await withTaskGroup(of: (String, AISubtitleProviderStatus).self) { group in
        for (code, _) in sourceOptions {
          group.addTask {
            let capability = await AppleAISubtitleTranscriber().probe(
              language: AISubtitleLanguage(code)
            )
            return (code, capability.status)
          }
        }
        for await (code, status) in group {
          speechStatuses[code] = status
        }
      }

      guard !Task.isCancelled else { return }
      var speechItems: [AppleLocalResourceItem] = []
      var installedSpeechCodes = Set<String>()
      for (code, title) in sourceOptions {
        guard let status = speechStatuses[code] else { continue }
        switch status {
        case .available:
          installedSpeechCodes.insert(code)
          speechItems.append(AppleLocalResourceItem(id: .speech(code),
                                                    title: title,
                                                    status: .installed))
        case .needsDownload, .needsAuthorization, .needsConfiguration, .requiresRuntimeProbe:
          speechItems.append(AppleLocalResourceItem(id: .speech(code),
                                                    title: title,
                                                    status: .available))
        case .unavailable:
          break
        }
      }

      var translationItems: [AppleLocalResourceItem] = []
      var installedPairs = AISubtitlePreparedLanguageStore().translationPairs
      let translationInputs = speechItems.compactMap { speechItem -> (String, String)? in
        let sourceCode = speechItem.id.sourceCode
        let sourceLanguage = AISubtitleLanguage(sourceCode)
        guard !sourceLanguage.isEquivalent(to: targetLanguage) else { return nil }
        let title = "\(self?.localizedLanguageName(sourceCode) ?? sourceCode) → \(self?.localizedLanguageName(targetLanguage.code) ?? targetLanguage.code)"
        return (sourceCode, title)
      }
      var translationStatuses: [String: (title: String, installed: Bool, supported: Bool)] = [:]
      await withTaskGroup(of: (String, String, Bool, Bool).self) { group in
        for (sourceCode, title) in translationInputs {
          group.addTask {
            let status = await LanguageAvailability().status(
              from: Locale.Language(identifier: sourceCode),
              to: Locale.Language(identifier: targetLanguage.code)
            )
            return (sourceCode, title, status == .installed, status != .unsupported)
          }
        }
        for await (sourceCode, title, installed, supported) in group {
          translationStatuses[sourceCode] = (title, installed, supported)
        }
      }

      guard !Task.isCancelled else { return }
      for (sourceCode, _) in translationInputs {
        guard let status = translationStatuses[sourceCode] else { continue }
        let pairKey = AISubtitlePreparedLanguageStore.pairKey(source: sourceCode,
                                                              target: targetLanguage.code)
        installedPairs.remove(pairKey)
        if status.installed {
          installedPairs.insert(pairKey)
          translationItems.append(AppleLocalResourceItem(
            id: .translation(source: sourceCode, target: targetLanguage.code),
            title: status.title,
            status: .installed
          ))
        } else if status.supported {
          translationItems.append(AppleLocalResourceItem(
            id: .translation(source: sourceCode, target: targetLanguage.code),
            title: status.title,
            status: .available
          ))
        }
      }

      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, generation == self.resourceProbeGeneration else { return }
        self.applyAppleResourceInventory(speechItems: speechItems,
                                         translationItems: translationItems,
                                         installedSpeechCodes: installedSpeechCodes,
                                         installedPairs: installedPairs)
      }
    }
  }

  private func applyAppleResourceInventory(speechItems: [AppleLocalResourceItem],
                                           translationItems: [AppleLocalResourceItem],
                                           installedSpeechCodes: Set<String>,
                                           installedPairs: Set<String>) {
    isCheckingAppleResources = false
    speechResourceItems = speechItems
    translationResourceItems = translationItems
    self.installedSpeechCodes = installedSpeechCodes
    installedTranslationPairs = installedPairs
    AISubtitlePreparedLanguageStore().save(speechLanguageCodes: installedSpeechCodes,
                                           translationPairs: installedPairs)
    isLocalPlanReady = !installedSpeechCodes.isEmpty
    if isLocalPlanReady {
      AISubtitleInitializationState().markPrepared(provider: .apple)
    }
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }

    rebuildPreparationSourceLanguageChoices()
    preparationSourceLanguagesRow?.isHidden = false

    setPlanHeader(icon: localPlanStatusIcon,
                  label: localPlanStatusLabel,
                  prepared: isLocalPlanReady,
                  text: aiSubtitleLocalized(isLocalPlanReady ? "ai_subtitle.plan.prepared" : "ai_subtitle.plan.not_prepared",
                                            fallback: isLocalPlanReady ? "Supported" : "Not Downloaded"))
    refreshPreparationState()
    refreshDailyLanguageAvailability()
    refreshSchemeAvailability()
  }

  private var selectedPreparationSourceCodes: Set<String> {
    Set(preparationSourceLanguageButtons.compactMap { code, button in
      button.state == .on ? code : nil
    })
  }

  private func requiredResourcesForPreparation() -> Set<AppleLocalResourceID> {
    guard let targetLanguage = selectedPreparationTargetLanguage else { return [] }
    var required = Set<AppleLocalResourceID>()
    for sourceCode in selectedPreparationSourceCodes {
      if let speech = speechResourceItems.first(where: { $0.id == .speech(sourceCode) }),
         !isInstalled(speech.status) {
        required.insert(speech.id)
      }
      let sourceLanguage = AISubtitleLanguage(sourceCode)
      guard !sourceLanguage.isEquivalent(to: targetLanguage) else { continue }
      let translationID = AppleLocalResourceID.translation(source: sourceCode, target: targetLanguage.code)
      if let translation = translationResourceItems.first(where: { $0.id == translationID }),
         !isInstalled(translation.status) {
        required.insert(translation.id)
      }
    }
    return required
  }

  private func isInstalled(_ status: AppleLocalResourceStatus) -> Bool {
    if case .installed = status { return true }
    return false
  }

  private func preparationSelectionIsSupported() -> Bool {
    guard let targetLanguage = selectedPreparationTargetLanguage else { return false }
    return selectedPreparationSourceCodes.allSatisfy { sourceCode in
      guard speechResourceItems.contains(where: { $0.id == .speech(sourceCode) }) else { return false }
      let sourceLanguage = AISubtitleLanguage(sourceCode)
      if sourceLanguage.isEquivalent(to: targetLanguage) { return true }
      let translationID = AppleLocalResourceID.translation(source: sourceCode, target: targetLanguage.code)
      return translationResourceItems.contains(where: { $0.id == translationID })
    }
  }

  private func refreshPreparationState() {
    let canEdit = AISubtitleSystemSupport.isSupported
      && !isCheckingAppleResources
      && !isPreparingAppleResources
    preparationSourceLanguageButtons.values.forEach { $0.isEnabled = canEdit }
    preparationTargetPopup.isEnabled = canEdit
    preparationProgressRow.isHidden = !isPreparingAppleResources
    preparationSummaryLabel.isHidden = false
    prepareLocalPlanButton.isHidden = false

    if isPreparingAppleResources {
      preparationProgressLabel.stringValue = aiSubtitleLocalized(
        "ai_subtitle.setup.preparing",
        fallback: "Downloading Apple Local AI…"
      )
      preparationProgressIndicator.startAnimation(nil)
      preparationSummaryLabel.isHidden = true
      prepareLocalPlanButton.isEnabled = false
      return
    }

    preparationProgressIndicator.stopAnimation(nil)
    if let preparationErrorMessage {
      preparationSummaryLabel.textColor = .systemRed
      preparationSummaryLabel.stringValue = preparationErrorMessage
      selectedAppleResources = requiredResourcesForPreparation()
      prepareLocalPlanButton.title = aiSubtitleLocalized("ai_subtitle.setup.retry", fallback: "Try Again")
      prepareLocalPlanButton.isEnabled = canEdit && !selectedAppleResources.isEmpty
      return
    }

    preparationSummaryLabel.textColor = .secondaryLabelColor
    prepareLocalPlanButton.title = aiSubtitleLocalized("ai_subtitle.setup.start", fallback: "Start Download")
    if !AISubtitleSystemSupport.isSupported {
      preparationSummaryLabel.isHidden = true
      prepareLocalPlanButton.isEnabled = false
    } else if isCheckingAppleResources {
      preparationSummaryLabel.isHidden = true
      prepareLocalPlanButton.isEnabled = false
    } else if selectedPreparationSourceCodes.isEmpty {
      selectedAppleResources = []
      preparationSummaryLabel.isHidden = true
      prepareLocalPlanButton.isEnabled = false
    } else if !preparationSelectionIsSupported() {
      selectedAppleResources = []
      preparationSummaryLabel.stringValue = aiSubtitleLocalized(
        "ai_subtitle.setup.selection_unavailable",
        fallback: "One or more selected language combinations are unavailable on this Mac."
      )
      prepareLocalPlanButton.isEnabled = false
    } else {
      selectedAppleResources = requiredResourcesForPreparation()
      if selectedAppleResources.isEmpty {
        preparationSummaryLabel.isHidden = true
        prepareLocalPlanButton.isEnabled = false
      } else {
        preparationSummaryLabel.isHidden = true
        prepareLocalPlanButton.isEnabled = canEdit
      }
    }
  }

  private func setPlanHeader(icon: NSImageView,
                             label: NSTextField,
                             prepared: Bool,
                             text: String,
                             checking: Bool = false,
                             unavailable: Bool = false) {
    let symbol = prepared ? "checkmark.circle.fill" : (checking ? "clock" : (unavailable ? "xmark.circle.fill" : "circle"))
    if #available(macOS 11.0, *) {
      icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
    } else {
      icon.image = NSImage(named: prepared ? NSImage.statusAvailableName : NSImage.statusPartiallyAvailableName)
    }
    icon.contentTintColor = prepared ? .systemGreen : (unavailable ? .systemOrange : .secondaryLabelColor)
    label.stringValue = text
    label.textColor = prepared ? .labelColor : .secondaryLabelColor
  }

  @objc private func defaultSchemeChanged(_ sender: NSButton) {
    guard sender.tag == 0, isLocalPlanReady else {
      refreshSchemeAvailability()
      return
    }
    selectDefaultProvider(.apple)
  }

  private func selectDefaultProvider(_ provider: AISubtitleProviderID) {
    guard provider == .apple, isLocalPlanReady else { return }
    persistProvider(provider)
    ensureDailyLanguagesMatchPreparedPlan()
    setStatus("")
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }
    refreshSchemeAvailability()
  }

  @objc private func featureEnabledChanged(_ sender: NSSwitch) {
    guard explicitDefaultProvider == .apple, isLocalPlanReady else {
      sender.state = .off
      refreshSchemeAvailability()
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
    refreshSchemeAvailability()
  }

  @objc private func autoModeChanged(_ sender: NSButton) {
    AISubtitleAutoMode.current = AISubtitleAutoMode(rawValue: sender.tag) ?? .whenMissing
    refreshAutoModeSelection()
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }
  }

  private func refreshAutoModeSelection() {
    let selectedMode = AISubtitleAutoMode.current
    for button in autoModeButtons {
      button.state = button.tag == selectedMode.rawValue ? .on : .off
    }
  }

  @objc private func languageChanged(_ sender: NSPopUpButton) {
    if sender === targetPopup {
      defaults.set(selectedTargetLanguage?.code, forKey: "aiSubtitle.targetLanguage")
      refreshDailyLanguageAvailability()
    } else {
      defaults.set(selectedSourceLanguage?.code, forKey: "aiSubtitle.sourceLanguage")
    }
    setStatus("")
    refreshSchemeAvailability()
  }

  @objc private func preparationSourceLanguageChanged(_ sender: NSButton) {
    preparationErrorMessage = nil
    refreshPreparationState()
  }

  @objc private func preparationTargetChanged(_ sender: NSPopUpButton) {
    guard let code = sender.selectedItem?.representedObject as? String else { return }
    clearPendingPreparationSelection()
    defaults.set(code, forKey: "aiSubtitle.preparationTargetLanguage")
    defaults.set(code, forKey: "aiSubtitle.resourceTargetLanguage")
    refreshAppleResourceInventory()
  }

  @objc private func prepareSelectedLocalPlan(_ sender: NSButton) {
    guard AISubtitleSystemSupport.isSupported else {
      presentSystemUpgrade()
      return
    }
    preparationErrorMessage = nil
    selectedAppleResources = requiredResourcesForPreparation()
    guard #available(macOS 26.0, *), !selectedAppleResources.isEmpty else { return }

    let speechCodes = selectedAppleResources.compactMap { resourceID -> String? in
      if case .speech(let code) = resourceID { return code }
      return nil
    }.sorted()
    let translationPairs = selectedAppleResources.compactMap { resourceID -> (AISubtitleLanguage, AISubtitleLanguage)? in
      if case .translation(let source, let target) = resourceID {
        return (AISubtitleLanguage(source), AISubtitleLanguage(target))
      }
      return nil
    }.sorted { lhs, rhs in
      lhs.0.code == rhs.0.code ? lhs.1.code < rhs.1.code : lhs.0.code < rhs.0.code
    }

    isPreparingAppleResources = true
    refreshPreparationState()
    pendingTranslationDownloads = translationPairs

    batchDownloadTask?.cancel()
    batchDownloadTask = Task { [weak self] in
      guard let self else { return }
      do {
        for code in speechCodes {
          guard !Task.isCancelled else { return }
          let resourceID = AppleLocalResourceID.speech(code)
          await MainActor.run { self.updateResourceStatus(resourceID, status: .downloading(nil)) }
          try await self.installSpeechResource(AISubtitleLanguage(code), resourceID: resourceID)
          await MainActor.run {
            self.selectedAppleResources.remove(resourceID)
            self.updateResourceStatus(resourceID, status: .installed)
          }
        }
        await MainActor.run { self.prepareNextTranslationDownload() }
      } catch let error as AISubtitleError {
        await MainActor.run { self.finishAppleResourceBatch(.failure(error)) }
      } catch {
        await MainActor.run {
          self.finishAppleResourceBatch(.failure(AISubtitleError(code: "apple_resource_batch_failed",
                                                                 message: error.localizedDescription)))
        }
      }
    }
  }

  @available(macOS 26.0, *)
  private func installSpeechResource(_ language: AISubtitleLanguage,
                                     resourceID: AppleLocalResourceID) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      AppleAISubtitleTranscriber().installAssets(language: language, progressHandler: { [weak self] progress in
        DispatchQueue.main.async {
          self?.updateResourceStatus(resourceID, status: .downloading(progress))
        }
      }, completion: { result in
        switch result {
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      })
    }
  }

  private func prepareNextTranslationDownload() {
    guard isPreparingAppleResources else { return }
    guard !pendingTranslationDownloads.isEmpty else {
      finishAppleResourceBatch(.success(()))
      return
    }
    guard #available(macOS 26.0, *) else { return }
    let pair = pendingTranslationDownloads.removeFirst()
    let resourceID = AppleLocalResourceID.translation(source: pair.source.code, target: pair.target.code)
    updateResourceStatus(resourceID, status: .downloading(nil))
    showTranslationPreparation(sourceLanguage: pair.source,
                               targetLanguage: pair.target) { [weak self] result in
      guard let self else { return }
      self.clearTranslationPreparation()
      switch result {
      case .success:
        self.selectedAppleResources.remove(resourceID)
        self.updateResourceStatus(resourceID, status: .installed)
        self.prepareNextTranslationDownload()
      case .failure(let error):
        self.updateResourceStatus(resourceID, status: .failed(error.message))
        self.finishAppleResourceBatch(.failure(error))
      }
    }
  }

  @available(macOS 26.0, *)
  private func showTranslationPreparation(sourceLanguage: AISubtitleLanguage,
                                          targetLanguage: AISubtitleLanguage,
                                          completion: @escaping (Result<Void, AISubtitleError>) -> Void) {
    clearTranslationPreparation()
    let preparationView = AppleTranslationPreparationView(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      completion: completion
    )
    let host = NSHostingView(rootView: preparationView)
    host.translatesAutoresizingMaskIntoConstraints = false
    translationPreparationHost = host
    translationHostContainer.addArrangedSubview(host)
    host.widthAnchor.constraint(equalTo: translationHostContainer.widthAnchor).isActive = true
    host.heightAnchor.constraint(equalToConstant: 1).isActive = true
    translationHostContainer.isHidden = false
  }

  private func finishAppleResourceBatch(_ result: Result<Void, AISubtitleError>) {
    isPreparingAppleResources = false
    pendingTranslationDownloads = []
    clearTranslationPreparation()
    switch result {
    case .success:
      preparationErrorMessage = nil
      preparationSourceLanguageButtons.values.forEach { $0.state = .off }
    case .failure(let error):
      preparationErrorMessage = error.message
    }
    refreshAll()
  }

  private func clearTranslationPreparation() {
    translationPreparationHost?.removeFromSuperview()
    translationPreparationHost = nil
    translationHostContainer.isHidden = true
  }

  private func updateResourceStatus(_ resourceID: AppleLocalResourceID,
                                    status: AppleLocalResourceStatus) {
    if let index = speechResourceItems.firstIndex(where: { $0.id == resourceID }) {
      speechResourceItems[index].status = status
    }
    if let index = translationResourceItems.firstIndex(where: { $0.id == resourceID }) {
      translationResourceItems[index].status = status
    }
    refreshPreparationState()
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
      if result.removedEntryCount == 0 {
        setStatus("")
      } else {
        setStatus(String(format: aiSubtitleLocalized("ai_subtitle.cache_removed",
                                                     fallback: "Removed %d cached item(s), freeing %@."),
                         result.removedEntryCount,
                         ByteCountFormatter.string(fromByteCount: result.removedBytes, countStyle: .file)))
      }
      refreshCacheUsage()
    } catch {
      setStatus(error.localizedDescription)
      refreshCacheUsage()
    }
  }

  private func refreshCacheUsage() {
    cacheUsageGeneration += 1
    let generation = cacheUsageGeneration
    cacheUsageLabel.stringValue = "…"
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let totalBytes = try? AISubtitleCacheStore().usage().totalBytes
      DispatchQueue.main.async {
        guard let self, generation == self.cacheUsageGeneration else { return }
        guard let totalBytes else {
          self.cacheUsageLabel.stringValue = aiSubtitleLocalized("ai_subtitle.plan.unavailable",
                                                                 fallback: "Unavailable")
          return
        }
        self.cacheUsageLabel.stringValue = totalBytes == 0
          ? "0 KB"
          : ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
      }
    }
  }

  private func persistProvider(_ provider: AISubtitleProviderID) {
    defaults.set(provider.preferenceIndex, forKey: "aiSubtitle.provider")
  }

  private var explicitDefaultProvider: AISubtitleProviderID? {
    guard defaults.object(forKey: "aiSubtitle.provider") != nil,
          let provider = AISubtitleProviderID(preferenceIndex: defaults.integer(forKey: "aiSubtitle.provider")),
          provider != .whisperCpp else { return nil }
    return provider
  }

  private var selectedSourceLanguage: AISubtitleLanguage? {
    (sourcePopup.selectedItem?.representedObject as? String).map(AISubtitleLanguage.init)
  }

  private var selectedTargetLanguage: AISubtitleLanguage? {
    (targetPopup.selectedItem?.representedObject as? String).map(AISubtitleLanguage.init)
  }

  private var selectedPreparationTargetLanguage: AISubtitleLanguage? {
    (preparationTargetPopup.selectedItem?.representedObject as? String).map(AISubtitleLanguage.init)
  }

  private func localizedLanguageName(_ code: String) -> String {
    AISubtitleLanguageCatalog.localizedTitle(for: code)
  }

  private func refreshDailyLanguageAvailability() {
    let preferredTarget = selectedTargetLanguage?.code
      ?? defaults.string(forKey: "aiSubtitle.targetLanguage")
      ?? selectedPreparationTargetLanguage?.code
    let sourceCandidates = AISubtitleLanguageCatalog.sourceLanguages.compactMap(\.code)
    let targetCandidates = AISubtitleLanguageCatalog.targetLanguages.compactMap(\.code)
    let preparedTargetCodes = AISubtitlePreparedLanguageStore.preparedTargetCodes(
      sourceCandidates: Set(sourceCandidates),
      targetCandidates: targetCandidates,
      speechLanguageCodes: installedSpeechCodes,
      translationPairs: installedTranslationPairs
    )
    let preparedTargetOptions = AISubtitleLanguageCatalog.targetLanguages.filter { option in
      guard let targetCode = option.code else { return false }
      return preparedTargetCodes.contains(targetCode)
    }
    replaceLanguagePopup(targetPopup,
                         options: preparedTargetOptions,
                         preferredCode: preferredTarget,
                         includesPlaceholder: true)

    guard let targetCode = selectedTargetLanguage?.code else {
      replaceLanguagePopup(sourcePopup,
                           options: [],
                           preferredCode: nil,
                           includesPlaceholder: true)
      defaults.removeObject(forKey: "aiSubtitle.sourceLanguage")
      refreshSchemeAvailability()
      return
    }
    defaults.set(targetCode, forKey: "aiSubtitle.targetLanguage")

    let preferredSource = selectedSourceLanguage?.code
      ?? defaults.string(forKey: "aiSubtitle.sourceLanguage")
    let preparedSourceCodes = AISubtitlePreparedLanguageStore.preparedSourceCodes(
      for: targetCode,
      sourceCandidates: sourceCandidates,
      speechLanguageCodes: installedSpeechCodes,
      translationPairs: installedTranslationPairs
    )
    let preparedSourceOptions = AISubtitleLanguageCatalog.sourceLanguages.filter { option in
      guard let sourceCode = option.code else { return false }
      return preparedSourceCodes.contains(sourceCode)
    }
    replaceLanguagePopup(sourcePopup,
                         options: preparedSourceOptions,
                         preferredCode: preferredSource,
                         includesPlaceholder: true)
    defaults.set(selectedSourceLanguage?.code, forKey: "aiSubtitle.sourceLanguage")
    refreshSchemeAvailability()
  }

  private func replaceLanguagePopup(_ popup: NSPopUpButton,
                                    options: [AISubtitleLanguageOption],
                                    preferredCode: String?,
                                    includesPlaceholder: Bool = false) {
    popup.removeAllItems()
    let placeholder = AISubtitleLanguageCatalog.sourceLanguages.first { $0.code == nil }
    configureLanguagePopup(popup,
                           options: includesPlaceholder ? Array([placeholder].compactMap { $0 }) + options : options)
    guard popup.numberOfItems > 0 else { return }
    selectLanguage(preferredCode, in: popup)
  }

  private func ensureDailyLanguagesMatchPreparedPlan() {
    let sourceCandidates = AISubtitleLanguageCatalog.sourceLanguages.compactMap(\.code)
    let preparedTargetCodes = AISubtitlePreparedLanguageStore.preparedTargetCodes(
      sourceCandidates: Set(sourceCandidates),
      targetCandidates: AISubtitleLanguageCatalog.targetLanguages.compactMap(\.code),
      speechLanguageCodes: installedSpeechCodes,
      translationPairs: installedTranslationPairs
    )
    let preparedTargets = AISubtitleLanguageCatalog.targetLanguages.compactMap(\.code).filter {
      preparedTargetCodes.contains($0)
    }
    guard !preparedTargets.isEmpty else { return }

    let currentTarget = selectedTargetLanguage?.code
      ?? defaults.string(forKey: "aiSubtitle.targetLanguage")
    let preparationTarget = selectedPreparationTargetLanguage?.code
    let targetCode = currentTarget.flatMap { preparedTargets.contains($0) ? $0 : nil }
      ?? preparationTarget.flatMap { preparedTargets.contains($0) ? $0 : nil }
      ?? preparedTargets[0]
    defaults.set(targetCode, forKey: "aiSubtitle.targetLanguage")

    let preparedSourceCodes = AISubtitlePreparedLanguageStore.preparedSourceCodes(
      for: targetCode,
      sourceCandidates: sourceCandidates,
      speechLanguageCodes: installedSpeechCodes,
      translationPairs: installedTranslationPairs
    )
    let preparedSources = sourceCandidates.filter { preparedSourceCodes.contains($0) }
    let currentSource = selectedSourceLanguage?.code
      ?? defaults.string(forKey: "aiSubtitle.sourceLanguage")
    if let sourceCode = currentSource.flatMap({ preparedSources.contains($0) ? $0 : nil })
      ?? preparedSources.first {
      defaults.set(sourceCode, forKey: "aiSubtitle.sourceLanguage")
    } else {
      defaults.removeObject(forKey: "aiSubtitle.sourceLanguage")
    }
    refreshDailyLanguageAvailability()
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
    Color.clear
    .frame(height: 1)
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
