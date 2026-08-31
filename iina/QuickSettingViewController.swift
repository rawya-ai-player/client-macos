//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let eqUserDefinedProfileMenuItemTag = 0
fileprivate let eqPresetProfileMenuItemTag = 1
fileprivate let eqDeleteMenuItemTag = -1
fileprivate let eqRenameMenuItemTag = -2
fileprivate let eqSaveMenuItemTag = -3
fileprivate let eqCustomMenuItemTag = 1000

/// Formatter for `customSpeedTextField`.
///
/// Configure the number formatter in code instead of the XIB so it is easier to follow.
fileprivate let speedFormatter: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = true
  fmt.maximumSignificantDigits = 25  // just make very big
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 6  // matches mpv behavior
  fmt.usesSignificantDigits = false
  fmt.roundingMode = .halfDown   // matches mpv behavior
  fmt.minimum = NSNumber(floatLiteral: AppData.mpvMinPlaybackSpeed)
  return fmt
}()

class QuickSettingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, SidebarViewController {
  override var nibName: NSNib.Name {
    return NSNib.Name("QuickSettingViewController")
  }

  let sliderSteps = 24.0

  enum TabViewType: Equatable {
    case video
    case audio
    case sub
    case aiSubtitle

    init(buttonTag: Int) {
      self = [.video, .audio, .sub, .aiSubtitle][at: buttonTag] ?? .video
    }

    init?(name: String) {
      switch name {
      case "video":
        self = .video
      case "audio":
        self = .audio
      case "sub":
        self = .sub
      case "aiSubtitle":
        self = .aiSubtitle
      default:
        self = .video
      }
    }

    var buttonTag: Int {
      switch self {
      case .video: return 0
      case .audio: return 1
      case .sub: return 2
      case .aiSubtitle: return 3
      }
    }

    var name: String {
      switch self {
      case .video: return "video"
      case .audio: return "audio"
      case .sub: return "sub"
      case .aiSubtitle: return "aiSubtitle"
      }
    }
  }

  /**
   Similar to the one in `PlaylistViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  weak var player: PlayerCore!

  weak var mainWindow: MainWindowController! {
    didSet {
      self.player = mainWindow.player
    }
  }

  var currentTab: TabViewType = .video

  var observers: [NSObjectProtocol] = []

  // These are top-level objects in the XIB, so the controller must retain them
  // until they are attached to their NSTabViewItems.
  @IBOutlet var videoTabScrollView: NSScrollView!
  @IBOutlet var audioTabScrollView: NSScrollView!
  @IBOutlet var subtitlesTabScrollView: NSScrollView!

  @IBOutlet weak var videoTabBtn: NSButton!
  @IBOutlet weak var audioTabBtn: NSButton!
  @IBOutlet weak var subTabBtn: NSButton!
  @IBOutlet weak var aiSubtitleTabBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!

  private var aiSubtitleTabScrollView: NSScrollView!
  private var aiSubtitleDocumentView: FlippedView!
  private var aiSubtitleContentStack: NSStackView!
  private let aiSubtitleStatusLabel = NSTextField(wrappingLabelWithString: "")
  private let aiSubtitleStatusRow = NSStackView()
  private let aiSubtitleFeatureSwitch = NSSwitch()
  private var aiSubtitleAutoModeButtons: [NSButton] = []
  private let aiSubtitleTargetLanguagePopup = NSPopUpButton()
  private let aiSubtitleSourceLanguageStack = NSStackView()
  private var aiSubtitleSourceLanguageButtons: [NSButton] = []
  private let aiSubtitleMoreLanguagesPopup = NSPopUpButton()
  private var aiSubtitleSelectedSourceLanguageCode: String?
  private var aiSubtitleSelectionMediaURL: URL?
  private let aiSubtitleLivePreviewCheckbox = NSButton()
  private let aiSubtitleGenerateButton = NSButton()
  private let aiSubtitleStopButton = NSButton()
  private let aiSubtitleManageButton = NSButton()
  private let aiSubtitleRevealButton = NSButton()
  private let aiSubtitleUpgradeButton = NSButton()
  private var aiSubtitlePreparedSpeechCodes = Set<String>()
  private var aiSubtitlePreparedTranslationPairs = Set<String>()
  private var aiSubtitleLanguageProbeTask: Task<Void, Never>?
  private var aiSubtitleLanguageProbeGeneration = 0

  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!

  @IBOutlet weak var videoTableView: NSTableView!
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  @IBOutlet weak var secSubTableView: NSTableView!

  @IBOutlet weak var rotateSegment: NSSegmentedControl!

  @IBOutlet weak var aspectSegment: NSSegmentedControl!
  @IBOutlet weak var customAspectTextField: NSTextField!

  @IBOutlet weak var cropSegment: NSSegmentedControl!

  @IBOutlet weak var speedSlider: NSSlider!
  @IBOutlet weak var speedSliderIndicator: NSTextField!
  @IBOutlet weak var speedSliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var speedSliderContainerView: NSView!

  @IBOutlet weak var speedSlider0_25xLabel: NSTextField!
  @IBOutlet weak var speedSlider1xLabel: NSTextField!
  @IBOutlet weak var speedSlider4xLabel: NSTextField!
  @IBOutlet weak var speedSlider16xLabel: NSTextField!
  @IBOutlet var speedSlider1xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider1xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider16xLabelPrevLabelConstraint: NSLayoutConstraint!

  @IBOutlet weak var customSpeedTextField: NSTextField!
  @IBOutlet weak var speedResetBtn: NSButton!
  @IBOutlet weak var switchHorizontalLine: NSBox!
  @IBOutlet weak var switchHorizontalLine2: NSBox!
  @IBOutlet weak var hardwareDecodingSwitch: NSSwitch!
  @IBOutlet weak var deinterlaceSwitch: NSSwitch!
  @IBOutlet weak var hdrSwitch: NSSwitch!
  @IBOutlet weak var hardwareDecodingLabel: NSTextField!
  @IBOutlet weak var deinterlaceLabel: NSTextField!
  @IBOutlet weak var hdrLabel: NSTextField!

  @IBOutlet weak var brightnessSlider: NSSlider!
  @IBOutlet weak var contrastSlider: NSSlider!
  @IBOutlet weak var saturationSlider: NSSlider!
  @IBOutlet weak var gammaSlider: NSSlider!
  @IBOutlet weak var hueSlider: NSSlider!

  @IBOutlet weak var audioDelaySlider: NSSlider!
  @IBOutlet weak var audioDelaySliderIndicator: NSTextField!
  @IBOutlet weak var audioDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customAudioDelayTextField: NSTextField!

  @IBOutlet weak var hideSwitch: NSSwitch!
  @IBOutlet weak var secHideSwitch: NSSwitch!
  @IBOutlet weak var subLoadSegmentedControl: NSSegmentedControl!
  @IBOutlet weak var subDelaySlider: NSSlider!
  @IBOutlet weak var subDelaySliderIndicator: NSTextField!
  @IBOutlet weak var subDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customSubDelayTextField: NSTextField!
  @IBOutlet weak var subSegmentedControl: NSSegmentedControl!

  @IBOutlet weak var eqPopUpButton: NSPopUpButton!
  @IBOutlet weak var audioEqSlider1: NSSlider!
  @IBOutlet weak var audioEqSlider2: NSSlider!
  @IBOutlet weak var audioEqSlider3: NSSlider!
  @IBOutlet weak var audioEqSlider4: NSSlider!
  @IBOutlet weak var audioEqSlider5: NSSlider!
  @IBOutlet weak var audioEqSlider6: NSSlider!
  @IBOutlet weak var audioEqSlider7: NSSlider!
  @IBOutlet weak var audioEqSlider8: NSSlider!
  @IBOutlet weak var audioEqSlider9: NSSlider!
  @IBOutlet weak var audioEqSlider10: NSSlider!

  @IBOutlet weak var subScaleSlider: NSSlider!
  @IBOutlet weak var subScaleResetBtn: NSButton!
  @IBOutlet weak var subPosSlider: NSSlider!

  var subTextColorWell: NSColorWell!
  var subTextBorderColorWell: NSColorWell!
  var subTextBgColorWell: NSColorWell!

  @IBOutlet weak var subTextColorWellContainer: NSView!
  @IBOutlet weak var subTextSizePopUp: NSPopUpButton!
  @IBOutlet weak var subTextBorderColorWellContainer: NSView!
  @IBOutlet weak var subTextBorderWidthPopUp: NSPopUpButton!
  @IBOutlet weak var subTextBgColorWellContainer: NSView!
  @IBOutlet weak var subTextFontBtn: NSButton!

  @IBOutlet weak var subtitleSwitch: NSSwitch!
  @IBOutlet weak var secondarySubtitleSwitch: NSSwitch!
  
  private lazy var audioEQSliders: [NSSlider] = [
    audioEqSlider1, audioEqSlider2, audioEqSlider3, audioEqSlider4, audioEqSlider5,
    audioEqSlider6, audioEqSlider7, audioEqSlider8, audioEqSlider9, audioEqSlider10
  ]

  private lazy var videoEQSliders: [NSSlider] = [
    brightnessSlider, contrastSlider, saturationSlider, gammaSlider, hueSlider
  ]

  private var lastUsedProfileName: String = ""
  private var inputString: String = ""

  var downShift: CGFloat = 0 {
    didSet {
      buttonTopConstraint.constant = downShift
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let tabScrollViews = [videoTabScrollView, audioTabScrollView, subtitlesTabScrollView]
    for (view, item) in zip(tabScrollViews, tabView.tabViewItems) {
      item.view = view
    }
    installAISubtitleTab()

    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
      view.superview?.superview?.layer?.cornerRadius = 4
    }

    // Color Wells
    if #available(macOS 13.0, *) {
      subTextColorWell = NSColorWell(style: .minimal)
      subTextBgColorWell = NSColorWell(style: .minimal)
      subTextBorderColorWell = NSColorWell(style: .minimal)
    } else {
      subTextColorWell = RoundedColorWell()
      subTextBgColorWell = RoundedColorWell()
      subTextBorderColorWell = RoundedColorWell()
    }
    [(subTextColorWellContainer, subTextColorWell),
     (subTextBgColorWellContainer, subTextBgColorWell),
     (subTextBorderColorWellContainer, subTextBorderColorWell)].forEach { (view, well) in
      well.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(well)
      Utility.quickConstraints(["H:|[v]|", "V:|[v]|"], ["v": well])
    }
    
    // Wire color wells to IBAction handlers
    subTextColorWell.target = self
    subTextColorWell.action = #selector(subTextColorAction(_:))

    subTextBgColorWell.target = self
    subTextBgColorWell.action = #selector(subTextBgColorAction(_:))

    subTextBorderColorWell.target = self
    subTextBorderColorWell.action = #selector(subTextBorderColorAction(_:))
    
    
    if #available(macOS 26, *) {
      subtitleSwitch.controlSize = .small
      secondarySubtitleSwitch.controlSize = .small

      speedSlider.neutralValue = 8
      (audioEQSliders + videoEQSliders + [audioDelaySlider, subDelaySlider, subScaleSlider]).forEach {
        $0.neutralValue = 0
      }

      subPosSlider.tintProminence = .none
    }

    // colors
    withAllTableViews { tableView, _ in tableView.backgroundColor = NSColor(named: .sidebarTableBackground)! }

    if pendingSwitchRequest == nil {
      updateTabActiveStatus()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    speedResetBtn.toolTip = NSLocalizedString("quicksetting.reset_speed", comment: "Reset speed to 1x")

    subLoadSegmentedControl.image(forSegment: 1)?.isTemplate = true
    switchHorizontalLine.wantsLayer = true
    switchHorizontalLine.layer?.opacity = 0.5
    switchHorizontalLine2.wantsLayer = true
    switchHorizontalLine2.layer?.opacity = 0.5

    // Localize decimal format of numbers
    speedSlider0_25xLabel.stringValue = "\(0.25.groupedStringUpTo6Decimals)x"
    speedSlider1xLabel.stringValue = "1x"
    speedSlider4xLabel.stringValue = "4x"
    speedSlider16xLabel.stringValue = "16x"

    customSpeedTextField.formatter = speedFormatter

    if let data = UserDefaults.standard.data(forKey: Preference.Key.userEQPresets.rawValue),
       let dict = try? JSONDecoder().decode(Dictionary<String, EQProfile>.self, from: data) {
      userEQs = dict
    }

    eqPopUpButton.menu!.delegate = self
    presetEQs.forEach { preset in
      eqPopUpButton.menu?.addItem(withTitle: preset.name, tag: eqPresetProfileMenuItemTag, obj: preset.localizationKey)
    }
    eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
    lastUsedProfileName = eqPopUpButton.selectedItem!.title

    func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: player, queue: .main, using: block))
    }

    // notifications
    observe(.iinaTracklistChanged) { [unowned self] _ in
      self.withAllTableViews { view, _ in view.reloadData() }
    }
    observe(.iinaVIDChanged) { [unowned self] _ in self.videoTableView.reloadData() }
    observe(.iinaAIDChanged) { [unowned self] _ in self.audioTableView.reloadData() }
    observe(.iinaSIDChanged) { [unowned self] _ in
      self.subTableView.reloadData()
      self.secSubTableView.reloadData()
    }
    observe(.iinaSecondSubVisibilityChanged) { [unowned self] _ in secHideSwitch.state = player.info.isSecondSubVisible ? .on : .off }
    observe(.iinaSubVisibilityChanged) { [unowned self] _ in hideSwitch.state = player.info.isSubVisible ? .on : .off }
    observe(.iinaAISubtitleStateDidChange) { [unowned self] _ in self.updateAISubtitleTab() }
  }

  private func installAISubtitleTab() {
    aiSubtitleTabBtn.title = aiSubtitleLocalized("ai_subtitle.tab", fallback: "AI")
    aiSubtitleTabBtn.tag = TabViewType.aiSubtitle.buttonTag
    if #available(macOS 14.0, *) {
      let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
      aiSubtitleTabBtn.image = NSImage.findSFSymbol(["wand.and.stars"],
                                                   withConfiguration: configuration)
    } else {
      aiSubtitleTabBtn.image = NSImage(named: "tab_sub")
    }
    aiSubtitleTabBtn.imagePosition = .imageLeading
    aiSubtitleTabBtn.imageScaling = .scaleProportionallyDown

    aiSubtitleTabScrollView = NSScrollView()
    aiSubtitleTabScrollView.drawsBackground = false
    aiSubtitleTabScrollView.hasVerticalScroller = true
    aiSubtitleTabScrollView.autohidesScrollers = true
    let documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: 1000))
    documentView.autoresizingMask = [.width]
    aiSubtitleTabScrollView.documentView = documentView
    aiSubtitleDocumentView = documentView

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(stack)
    aiSubtitleContentStack = stack
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: documentView.topAnchor)
    ])
    attachAISubtitleTabScrollView()

    aiSubtitleFeatureSwitch.controlSize = .small
    aiSubtitleFeatureSwitch.target = self
    aiSubtitleFeatureSwitch.action = #selector(aiSubtitleFeatureChanged(_:))
    let featureLabel = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.enable_feature",
      fallback: "Enable AI Subtitles"
    ))
    featureLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    aiSubtitleFeatureSwitch.setAccessibilityLabel(featureLabel.stringValue)
    let featureRow = NSStackView(views: [aiSubtitleFeatureSwitch, featureLabel])
    featureRow.orientation = .horizontal
    featureRow.alignment = .centerY
    featureRow.spacing = 8
    stack.addArrangedSubview(featureRow)

    aiSubtitleStatusLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    aiSubtitleStatusLabel.maximumNumberOfLines = 3
    aiSubtitleStatusLabel.lineBreakMode = .byWordWrapping
    aiSubtitleStatusRow.addArrangedSubview(aiSubtitleStatusLabel)
    aiSubtitleStatusRow.orientation = .horizontal
    aiSubtitleStatusRow.alignment = .firstBaseline
    stack.addArrangedSubview(aiSubtitleStatusRow)
    aiSubtitleStatusRow.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                               constant: -stack.edgeInsets.left - stack.edgeInsets.right).isActive = true

    let separator = NSBox()
    separator.boxType = .separator
    stack.addArrangedSubview(separator)
    separator.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    aiSubtitleTargetLanguagePopup.target = self
    aiSubtitleTargetLanguagePopup.action = #selector(aiSubtitleLanguageChanged(_:))
    aiSubtitleTargetLanguagePopup.controlSize = .small
    aiSubtitleMoreLanguagesPopup.controlSize = .small
    aiSubtitleMoreLanguagesPopup.target = self
    aiSubtitleMoreLanguagesPopup.action = #selector(aiSubtitleMoreLanguageChanged(_:))
    let languageSectionLabel = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.section.languages",
      fallback: "Default Languages"
    ))
    let sourceLanguageLabel = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.default_spoken_language",
      fallback: "Audio language"
    ))
    let targetLanguageLabel = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.default_subtitle_language",
      fallback: "Subtitle language"
    ))
    let autoModeLabel = NSTextField(labelWithString: aiSubtitleLocalized(
      "ai_subtitle.section.automation",
      fallback: "Generation"
    ))
    let sectionTitleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
    languageSectionLabel.font = sectionTitleFont
    autoModeLabel.font = sectionTitleFont
    [sourceLanguageLabel, targetLanguageLabel].forEach {
      $0.textColor = .secondaryLabelColor
      $0.alignment = .right
    }
    let autoModeOptions: [(AISubtitleAutoMode, String, String)] = [
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
    var autoModeOptionViews: [NSView] = []
    aiSubtitleAutoModeButtons = autoModeOptions.map { mode, title, description in
      let button = NSButton(radioButtonWithTitle: title,
                            target: self,
                            action: #selector(aiSubtitleAutoModeChanged(_:)))
      button.tag = mode.rawValue
      button.controlSize = .regular
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
      optionStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 2, right: 0)
      descriptionLabel.leadingAnchor.constraint(equalTo: optionStack.leadingAnchor, constant: 22).isActive = true
      descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: optionStack.trailingAnchor).isActive = true
      autoModeOptionViews.append(optionStack)
      return button
    }
    let autoModeStack = NSStackView(views: autoModeOptionViews)
    autoModeStack.orientation = .vertical
    autoModeStack.alignment = .leading
    autoModeStack.spacing = 8
    autoModeOptionViews.forEach { $0.widthAnchor.constraint(equalTo: autoModeStack.widthAnchor).isActive = true }
    aiSubtitleTargetLanguagePopup.widthAnchor.constraint(equalToConstant: 128).isActive = true
    aiSubtitleMoreLanguagesPopup.widthAnchor.constraint(equalToConstant: 128).isActive = true
    aiSubtitleSourceLanguageStack.orientation = .vertical
    aiSubtitleSourceLanguageStack.alignment = .leading
    aiSubtitleSourceLanguageStack.spacing = 5
    aiSubtitleSourceLanguageStack.detachesHiddenViews = true
    let targetLanguageRow = NSStackView(views: [targetLanguageLabel, aiSubtitleTargetLanguagePopup])
    let sourceLanguageRow = NSStackView(views: [sourceLanguageLabel, aiSubtitleSourceLanguageStack])
    targetLanguageRow.orientation = .horizontal
    targetLanguageRow.alignment = .centerY
    targetLanguageRow.spacing = 12
    sourceLanguageRow.orientation = .horizontal
    sourceLanguageRow.alignment = .top
    sourceLanguageRow.spacing = 12
    let languageRows = NSStackView(views: [targetLanguageRow, sourceLanguageRow])
    languageRows.orientation = .vertical
    languageRows.alignment = .leading
    languageRows.spacing = 10
    languageRows.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
    targetLanguageLabel.widthAnchor.constraint(equalTo: sourceLanguageLabel.widthAnchor).isActive = true
    targetLanguageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 128).isActive = true
    let languageSection = NSStackView(views: [languageSectionLabel, languageRows])
    languageSection.orientation = .vertical
    languageSection.alignment = .leading
    languageSection.spacing = 8
    stack.addArrangedSubview(languageSection)
    languageSection.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    autoModeStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
    let autoModeSection = NSStackView(views: [autoModeLabel, autoModeStack])
    autoModeSection.orientation = .vertical
    autoModeSection.alignment = .leading
    autoModeSection.spacing = 6
    stack.addArrangedSubview(autoModeSection)
    autoModeSection.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true
    autoModeStack.widthAnchor.constraint(equalTo: autoModeSection.widthAnchor, constant: -12).isActive = true
    stack.setCustomSpacing(16, after: languageSection)

    aiSubtitleLivePreviewCheckbox.setButtonType(.switch)
    aiSubtitleLivePreviewCheckbox.title = aiSubtitleLocalized(
      "ai_subtitle.live_preview",
      fallback: "Show subtitles as they are generated"
    )
    aiSubtitleLivePreviewCheckbox.controlSize = .regular
    aiSubtitleLivePreviewCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    aiSubtitleLivePreviewCheckbox.target = self
    aiSubtitleLivePreviewCheckbox.action = #selector(aiSubtitleLivePreviewChanged(_:))
    stack.addArrangedSubview(aiSubtitleLivePreviewCheckbox)

    aiSubtitleGenerateButton.title = aiSubtitleLocalized("ai_subtitle.generate",
                                                         fallback: "Start Generating Subtitles")
    aiSubtitleGenerateButton.target = self
    aiSubtitleGenerateButton.action = #selector(generateAISubtitles(_:))
    aiSubtitleStopButton.title = aiSubtitleLocalized("ai_subtitle.stop_short",
                                                     fallback: "Stop Generating Subtitles")
    aiSubtitleStopButton.target = self
    aiSubtitleStopButton.action = #selector(stopAISubtitles(_:))
    aiSubtitleManageButton.title = NSLocalizedString("preference.title", comment: "Settings") + "…"
    aiSubtitleManageButton.target = self
    aiSubtitleManageButton.action = #selector(manageAISubtitles(_:))
    aiSubtitleRevealButton.title = NSLocalizedString("pl_menu.show_in_finder", comment: "Show in Finder")
    aiSubtitleRevealButton.target = self
    aiSubtitleRevealButton.action = #selector(revealAISubtitleFiles(_:))
    [aiSubtitleGenerateButton, aiSubtitleStopButton, aiSubtitleRevealButton, aiSubtitleManageButton].forEach {
      $0.controlSize = .regular
    }
    let primaryActions = NSStackView(views: [aiSubtitleGenerateButton, aiSubtitleStopButton])
    primaryActions.orientation = .vertical
    primaryActions.spacing = 0
    primaryActions.detachesHiddenViews = true
    stack.addArrangedSubview(primaryActions)
    primaryActions.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true
    aiSubtitleGenerateButton.widthAnchor.constraint(equalTo: primaryActions.widthAnchor).isActive = true
    aiSubtitleStopButton.widthAnchor.constraint(equalTo: primaryActions.widthAnchor).isActive = true

    let secondaryActions = NSStackView(views: [aiSubtitleManageButton, aiSubtitleRevealButton])
    secondaryActions.orientation = .horizontal
    secondaryActions.distribution = .fillEqually
    secondaryActions.spacing = 8
    secondaryActions.detachesHiddenViews = true
    stack.addArrangedSubview(secondaryActions)
    secondaryActions.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    aiSubtitleUpgradeButton.title = aiSubtitleLocalized("ai_subtitle.open_software_update",
                                                        fallback: "Open Software Update")
    aiSubtitleUpgradeButton.target = self
    aiSubtitleUpgradeButton.action = #selector(openAISubtitleSoftwareUpdate(_:))
    aiSubtitleUpgradeButton.controlSize = .regular
    stack.addArrangedSubview(aiSubtitleUpgradeButton)
    aiSubtitleUpgradeButton.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    let disclaimerSeparator = NSBox()
    disclaimerSeparator.boxType = .separator
    stack.addArrangedSubview(disclaimerSeparator)
    disclaimerSeparator.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    let disclaimer = NSTextField(wrappingLabelWithString: aiSubtitleLocalized(
      "ai_subtitle.disclaimer",
      fallback: "AI-generated subtitles may be inaccurate and are for reference only."
    ))
    disclaimer.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    disclaimer.textColor = .secondaryLabelColor
    disclaimer.maximumNumberOfLines = 0
    stack.addArrangedSubview(disclaimer)
    disclaimer.widthAnchor.constraint(equalTo: aiSubtitleStatusRow.widthAnchor).isActive = true

    scheduleAISubtitleContentLayout()
    refreshAISubtitlePreparedLanguages()
    updateAISubtitleTab()
  }

  private func attachAISubtitleTabScrollView() {
    let item = tabView.tabViewItem(at: TabViewType.aiSubtitle.buttonTag)
    item.identifier = TabViewType.aiSubtitle.name
    let containerFrame = item.view?.frame ?? NSRect(x: 0, y: 0, width: 360, height: 480)
    let containerView = NSView(frame: containerFrame)
    containerView.autoresizingMask = [.width, .height]
    aiSubtitleTabScrollView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(aiSubtitleTabScrollView)
    NSLayoutConstraint.activate([
      aiSubtitleTabScrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      aiSubtitleTabScrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      aiSubtitleTabScrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
      aiSubtitleTabScrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
    ])
    item.view = containerView
  }

  private func scheduleAISubtitleContentLayout() {
    DispatchQueue.main.async { [weak self] in
      self?.updateAISubtitleContentLayout()
    }
  }

  private func updateAISubtitleContentLayout() {
    guard let scrollView = aiSubtitleTabScrollView,
          let documentView = aiSubtitleDocumentView,
          let stack = aiSubtitleContentStack else { return }
    let contentSize = scrollView.contentSize
    let width = max(contentSize.width, 1)
    documentView.setFrameSize(NSSize(width: width, height: max(contentSize.height, 1)))
    documentView.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    let height = max(ceil(stack.fittingSize.height), contentSize.height)
    documentView.setFrameSize(NSSize(width: width, height: height))
    documentView.layoutSubtreeIfNeeded()
  }

  private func updateAISubtitleTab() {
    guard isViewLoaded else { return }
    loadAISubtitlePreparedLanguageSnapshot()
    let supported = player.isAISubtitleSystemSupported
    let featureEnabled = AISubtitleFeatureState().isEnabled
    let planReady = AISubtitleInitializationState().isComplete
    let state = player.aiSubtitleState
    let running = ![.idle, .completed, .failed, .canceled, .maintaining].contains(state.phase)
    if aiSubtitleSelectionMediaURL != player.info.currentURL {
      aiSubtitleSelectionMediaURL = player.info.currentURL
      aiSubtitleSelectedSourceLanguageCode = nil
    }
    let historyStore = AISubtitleLanguageHistoryStore()
    let rememberedSourceCode = player.info.currentURL.flatMap {
      historyStore.sourceLanguageCode(for: $0)
    }
    let preferredSourceCode = running
      ? player.aiSubtitleActiveSourceLanguage?.code
      : aiSubtitleSelectedSourceLanguageCode
        ?? rememberedSourceCode
        ?? (AISubtitleAutoMode.current.requiresLanguageConfirmation
          ? historyStore.recentSourceLanguageCodes.first
          : nil)
        ?? UserDefaults.standard.string(forKey: "aiSubtitle.sourceLanguage")
        ?? player.info.currentTrack(.audio)?.lang
    let preferredTargetCode = running
      ? player.aiSubtitleActiveTargetLanguage?.code
      : (aiSubtitleTargetLanguagePopup.selectedItem?.representedObject as? String)
        ?? UserDefaults.standard.string(forKey: "aiSubtitle.targetLanguage")
    refreshAISubtitleLanguageMenus(preferredTargetCode: preferredTargetCode,
                                   preferredSourceCode: preferredSourceCode)
    let sourceCode = aiSubtitleSelectedSourceLanguageCode
    let targetCode = aiSubtitleTargetLanguagePopup.selectedItem?.representedObject as? String
    aiSubtitleFeatureSwitch.state = planReady && featureEnabled ? .on : .off
    aiSubtitleFeatureSwitch.isEnabled = planReady
    let selectedAutoMode = AISubtitleAutoMode.current
    aiSubtitleAutoModeButtons.forEach {
      $0.state = $0.tag == selectedAutoMode.rawValue ? .on : .off
      $0.isEnabled = planReady && featureEnabled
    }
    let hasTargetOptions = aiSubtitleTargetLanguagePopup.itemArray.contains { $0.representedObject is String }
    let hasSourceOptions = !aiSubtitleSourceLanguageButtons.isEmpty
    aiSubtitleTargetLanguagePopup.isEnabled = supported && featureEnabled && !running && hasTargetOptions
    let sourceSelectionEnabled = supported
      && featureEnabled
      && !running
      && targetCode != nil
      && hasSourceOptions
    aiSubtitleSourceLanguageButtons.forEach { $0.isEnabled = sourceSelectionEnabled }
    aiSubtitleMoreLanguagesPopup.isEnabled = sourceSelectionEnabled
    aiSubtitleLivePreviewCheckbox.state = AISubtitleLivePreviewState().isEnabled ? .on : .off
    aiSubtitleLivePreviewCheckbox.isEnabled = supported && featureEnabled
    aiSubtitleGenerateButton.isEnabled = supported
      && featureEnabled
      && !running
      && sourceCode != nil
      && targetCode != nil
      && player.info.currentURL != nil
      && !player.info.audioTracks.isEmpty
    aiSubtitleGenerateButton.title = player.hasExportableAISubtitles
      ? aiSubtitleLocalized("ai_subtitle.regenerate", fallback: "Regenerate Subtitles")
      : aiSubtitleLocalized("ai_subtitle.generate", fallback: "Start Generating Subtitles")
    aiSubtitleGenerateButton.isHidden = running
    aiSubtitleStopButton.isEnabled = running
    aiSubtitleStopButton.isHidden = !running
    aiSubtitleManageButton.isEnabled = true
    aiSubtitleRevealButton.isHidden = player.aiSubtitleSidecarURLs.isEmpty
    aiSubtitleRevealButton.isEnabled = !player.aiSubtitleSidecarURLs.isEmpty
    aiSubtitleUpgradeButton.isHidden = supported

    if supported && (!featureEnabled || targetCode == nil || sourceCode == nil) {
      aiSubtitleStatusLabel.stringValue = ""
    } else if supported && running {
      aiSubtitleStatusLabel.stringValue = ""
    } else if supported && (state.phase == .completed
      || state.message == aiSubtitleLocalized(
        "ai_subtitle.loaded_cached_result",
        fallback: "Loaded the existing AI subtitles."
      )) {
      aiSubtitleStatusLabel.stringValue = ""
    } else if supported {
      aiSubtitleStatusLabel.stringValue = state.error?.message ?? state.message ?? ""
    } else {
      aiSubtitleStatusLabel.stringValue = aiSubtitleLocalized(
        "ai_subtitle.upgrade_message",
        fallback: "AI Subtitles requires macOS 26 or later for Apple on-device speech and translation."
      )
    }
    aiSubtitleStatusRow.isHidden = aiSubtitleStatusLabel.stringValue.isEmpty
    scheduleAISubtitleContentLayout()
  }

  private func configureAISubtitleLanguagePopup(_ popup: NSPopUpButton,
                                                options: [AISubtitleLanguageOption]) {
    for option in options {
      let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
      item.representedObject = option.code
      popup.menu?.addItem(item)
    }
  }

  private func refreshAISubtitlePreparedLanguages() {
    loadAISubtitlePreparedLanguageSnapshot()
    aiSubtitleLanguageProbeTask?.cancel()
    guard aiSubtitlePreparedSpeechCodes.isEmpty else { return }
    aiSubtitleLanguageProbeGeneration += 1
    let generation = aiSubtitleLanguageProbeGeneration
    guard AISubtitleSystemSupport.isSupported, #available(macOS 26.0, *) else { return }

    let sourceCodes = AISubtitleLanguageCatalog.sourceLanguages.compactMap(\.code)
    aiSubtitleLanguageProbeTask = Task { [weak self] in
      var installedCodes = Set<String>()
      await withTaskGroup(of: (String, AISubtitleProviderStatus).self) { group in
        for code in sourceCodes {
          group.addTask {
            let capability = await AppleAISubtitleTranscriber().probe(language: AISubtitleLanguage(code))
            return (code, capability.status)
          }
        }
        for await (code, status) in group where status == .available {
          installedCodes.insert(code)
        }
      }
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, generation == self.aiSubtitleLanguageProbeGeneration else { return }
        self.aiSubtitlePreparedSpeechCodes = installedCodes
        AISubtitlePreparedLanguageStore().save(
          speechLanguageCodes: installedCodes,
          translationPairs: self.aiSubtitlePreparedTranslationPairs
        )
        self.updateAISubtitleTab()
      }
    }
  }

  private func loadAISubtitlePreparedLanguageSnapshot() {
    let store = AISubtitlePreparedLanguageStore()
    aiSubtitlePreparedSpeechCodes = store.speechLanguageCodes
    aiSubtitlePreparedTranslationPairs = store.translationPairs
  }

  private func refreshAISubtitleLanguageMenus(preferredTargetCode: String?,
                                              preferredSourceCode: String?) {
    let sourceCandidates = AISubtitleLanguageCatalog.sourceLanguages.compactMap(\.code)
    let targetCandidates = AISubtitleLanguageCatalog.targetLanguages.compactMap(\.code)
    let preparedTargetCodes = AISubtitlePreparedLanguageStore.preparedTargetCodes(
      sourceCandidates: Set(sourceCandidates),
      targetCandidates: targetCandidates,
      speechLanguageCodes: aiSubtitlePreparedSpeechCodes,
      translationPairs: aiSubtitlePreparedTranslationPairs
    )
    let targetOptions = AISubtitleLanguageCatalog.targetLanguages.filter { option in
      guard let targetCode = option.code else { return false }
      return preparedTargetCodes.contains(targetCode)
    }
    replaceAISubtitleLanguagePopup(aiSubtitleTargetLanguagePopup,
                                   options: targetOptions,
                                   preferredCode: preferredTargetCode)

    guard let targetCode = aiSubtitleTargetLanguagePopup.selectedItem?.representedObject as? String else {
      refreshAISubtitleSourceLanguageChoices(availableCodes: [], preferredCode: nil)
      return
    }
    let preparedSourceCodes = AISubtitlePreparedLanguageStore.preparedSourceCodes(
      for: targetCode,
      sourceCandidates: sourceCandidates,
      speechLanguageCodes: aiSubtitlePreparedSpeechCodes,
      translationPairs: aiSubtitlePreparedTranslationPairs
    )
    refreshAISubtitleSourceLanguageChoices(availableCodes: preparedSourceCodes,
                                           preferredCode: preferredSourceCode)
  }

  private func refreshAISubtitleSourceLanguageChoices(availableCodes: Set<String>,
                                                       preferredCode: String?) {
    let historyStore = AISubtitleLanguageHistoryStore()
    let suggestedCodes = historyStore.suggestedSourceLanguageCodes(
      for: player.info.currentURL,
      availableCodes: availableCodes,
      selectedCode: preferredCode,
      defaultCode: UserDefaults.standard.string(forKey: "aiSubtitle.sourceLanguage")
    )
    let selectedCode = preferredCode.flatMap { availableCodes.contains($0) ? $0 : nil }
      ?? suggestedCodes.first
    aiSubtitleSelectedSourceLanguageCode = selectedCode

    aiSubtitleSourceLanguageStack.arrangedSubviews.forEach {
      aiSubtitleSourceLanguageStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    aiSubtitleSourceLanguageButtons = suggestedCodes.map { code in
      let button = NSButton(
        radioButtonWithTitle: AISubtitleLanguageCatalog.localizedTitle(for: code),
        target: self,
        action: #selector(aiSubtitleSourceLanguageChanged(_:))
      )
      button.identifier = NSUserInterfaceItemIdentifier(code)
      button.state = code == selectedCode ? .on : .off
      button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      if let cell = button.cell as? NSButtonCell {
        cell.lineBreakMode = .byTruncatingTail
      }
      aiSubtitleSourceLanguageStack.addArrangedSubview(button)
      return button
    }

    aiSubtitleMoreLanguagesPopup.removeAllItems()
    let moreItem = NSMenuItem(title: aiSubtitleLocalized(
      "ai_subtitle.more_languages",
      fallback: "More Languages…"
    ), action: nil, keyEquivalent: "")
    aiSubtitleMoreLanguagesPopup.menu?.addItem(moreItem)
    AISubtitleLanguageCatalog.sourceLanguages.forEach { option in
      guard let code = option.code,
            availableCodes.contains(code),
            !suggestedCodes.contains(code) else { return }
      let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
      item.representedObject = code
      aiSubtitleMoreLanguagesPopup.menu?.addItem(item)
    }
    aiSubtitleMoreLanguagesPopup.selectItem(at: 0)
    aiSubtitleMoreLanguagesPopup.isHidden = aiSubtitleMoreLanguagesPopup.numberOfItems <= 1
    if !aiSubtitleMoreLanguagesPopup.isHidden {
      aiSubtitleSourceLanguageStack.addArrangedSubview(aiSubtitleMoreLanguagesPopup)
    }
  }

  private func replaceAISubtitleLanguagePopup(_ popup: NSPopUpButton,
                                              options: [AISubtitleLanguageOption],
                                              preferredCode: String?) {
    popup.removeAllItems()
    let placeholder = AISubtitleLanguageCatalog.sourceLanguages.first { $0.code == nil }
    configureAISubtitleLanguagePopup(popup,
                                     options: Array([placeholder].compactMap { $0 }) + options)
    selectAISubtitleLanguage(preferredCode, in: popup)
  }

  private func isPreparedAISubtitleCombination(source: String, target: String) -> Bool {
    AISubtitlePreparedLanguageStore.isPrepared(
      source: source,
      target: target,
      speechLanguageCodes: aiSubtitlePreparedSpeechCodes,
      translationPairs: aiSubtitlePreparedTranslationPairs
    )
  }

  @objc private func aiSubtitleFeatureChanged(_ sender: NSSwitch) {
    guard AISubtitleInitializationState().isComplete else {
      sender.state = .off
      updateAISubtitleTab()
      return
    }
    let enabled = sender.state == .on
    AISubtitleFeatureState().setEnabled(enabled)
    if !enabled {
      PlayerCore.playerCores.forEach { $0.stopAISubtitles() }
    }
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }
    updateAISubtitleTab()
  }

  @objc private func aiSubtitleAutoModeChanged(_ sender: NSButton) {
    AISubtitleAutoMode.current = AISubtitleAutoMode(rawValue: sender.tag) ?? .whenMissing
    PlayerCore.playerCores.forEach {
      NotificationCenter.default.post(name: .iinaAISubtitleStateDidChange, object: $0)
    }
    updateAISubtitleTab()
  }

  private func selectAISubtitleLanguage(_ code: String?, in popup: NSPopUpButton) {
    guard let code else {
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

  @objc private func aiSubtitleLanguageChanged(_ sender: NSPopUpButton) {
    let key = "aiSubtitle.targetLanguage"
    if let code = sender.selectedItem?.representedObject as? String {
      UserDefaults.standard.set(code, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
    if let targetCode = sender.selectedItem?.representedObject as? String,
       let sourceCode = UserDefaults.standard.string(forKey: "aiSubtitle.sourceLanguage"),
       !isPreparedAISubtitleCombination(source: sourceCode, target: targetCode) {
      UserDefaults.standard.removeObject(forKey: "aiSubtitle.sourceLanguage")
    } else if sender.selectedItem?.representedObject == nil {
      UserDefaults.standard.removeObject(forKey: "aiSubtitle.sourceLanguage")
    }
    aiSubtitleSelectedSourceLanguageCode = nil
    updateAISubtitleTab()
  }

  @objc private func aiSubtitleSourceLanguageChanged(_ sender: NSButton) {
    guard let code = sender.identifier?.rawValue else { return }
    aiSubtitleSelectedSourceLanguageCode = code
    updateAISubtitleTab()
  }

  @objc private func aiSubtitleMoreLanguageChanged(_ sender: NSPopUpButton) {
    guard let code = sender.selectedItem?.representedObject as? String else { return }
    aiSubtitleSelectedSourceLanguageCode = code
    updateAISubtitleTab()
  }

  @objc private func aiSubtitleLivePreviewChanged(_ sender: NSButton) {
    player.setAISubtitleLivePreviewEnabled(sender.state == .on)
  }

  @objc private func generateAISubtitles(_ sender: NSButton) {
    if let sourceCode = aiSubtitleSelectedSourceLanguageCode {
      player.rememberAISubtitleSourceLanguageForCurrentMedia(sourceCode)
    }
    player.generateAISubtitlesUsingSavedPreferences(
      showConfigurationIfNeeded: true,
      forceRegeneration: player.hasExportableAISubtitles
    )
  }

  @objc private func stopAISubtitles(_ sender: NSButton) {
    player.stopAISubtitles()
  }

  @objc private func manageAISubtitles(_ sender: NSButton) {
    player.showAISubtitleSettings(parentWindow: view.window)
  }

  @objc private func revealAISubtitleFiles(_ sender: NSButton) {
    NSWorkspace.shared.activateFileViewerSelecting(player.aiSubtitleSidecarURLs)
  }

  @objc private func openAISubtitleSoftwareUpdate(_ sender: NSButton) {
    player.presentAISubtitleSystemUpgrade(parentWindow: view.window)
  }

  // MARK: - Right to Left Constraints

  /// Prepares the receiver for service after it has been loaded from an Interface Builder archive, or nib file.
  ///
  /// If the user interface layout direction is right to left then certain layout constraints that assume a left to right layout will need to be
  /// replaced. That will be handled by the `viewWillLayout` method. This method will disable these constraints to avoid triggering
  /// constraint errors before the constraints can be replaced.
  override func awakeFromNib() {
    super.awakeFromNib()
    guard speedSlider.userInterfaceLayoutDirection == .rightToLeft else { return }
    NSLayoutConstraint.deactivate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])
  }

  /// Calculate the constraint multiplier for a speed slider label.
  ///
  /// This method calculates the appropriate multiplier to use in a
  /// [centerX](https://developer.apple.com/documentation/uikit/nslayoutconstraint/attribute/centerx)
  /// constraint for a text field that sits under the speed slider and displays the speed associated with a particular tick mark.
  /// - Parameter speed: Playback speed the label indicates.
  /// - Returns: Multiplier to use in the constraint.
  private func calculateSliderLabelMultiplier(speed: Double) -> CGFloat {
    let tickIndex = Int(convertSpeedToSliderValue(speedSlider.closestTickMarkValue(toValue: speed)))
    let tickRect = speedSlider.rectOfTickMark(at: tickIndex)
    let tickCenterX = tickRect.origin.x + tickRect.width / 2
    let containerViewX = speedSlider.frame.origin.x + tickCenterX
    return containerViewX / speedSliderContainerView.frame.width
  }

  /// Called just before the `layout()` method of the view controller's view is called.
  ///
  /// If the user interface layout direction is right to left then this method will replace certain layout constraints with ones that properly
  /// position the reversed views.
  override func viewWillLayout() {
    // When the layout is right to left the first time this method is called the views will not have
    // been reversed. Once the views have been repositioned this method will be called again. Must
    // wait for that to happen before adjusting constraints to avoid triggering constraint errors.
    // Detect this based on the order of the speed slider labels.
    guard speedSliderContainerView.userInterfaceLayoutDirection == .rightToLeft,
          speedSlider16xLabel.frame.origin.x < speedSlider0_25xLabel.frame.origin.x else {
      super.viewWillLayout()
      return
    }

    // Deactivate the layout constraints that will be replaced.
    NSLayoutConstraint.deactivate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])

    // The multiplier in the constraints that position the 1x and 4x labels must be changed to
    // reflect the reversed views.
    speedSlider1xLabelCenterXConstraint = NSLayoutConstraint(
      item: speedSlider1xLabel as Any, attribute: .centerX, relatedBy: .equal, toItem: speedSlider,
      attribute: .right, multiplier: calculateSliderLabelMultiplier(speed: 1), constant: 0)
    speedSlider4xLabelCenterXConstraint = NSLayoutConstraint(
      item: speedSlider4xLabel as Any, attribute: .centerX, relatedBy: .equal, toItem: speedSlider,
      attribute: .right, multiplier: calculateSliderLabelMultiplier(speed: 4), constant: 0)

    // The constraints that impose an order on the labels must be changed to reflect the reversed
    // views.
    speedSlider1xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider1xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider0_25xLabel, attribute: .left, multiplier: 1, constant: 0)
    speedSlider4xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider4xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider1xLabel, attribute: .left, multiplier: 1, constant: 0)
    speedSlider16xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider16xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider4xLabel, attribute: .left, multiplier: 1, constant: 0)

    NSLayoutConstraint.activate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])
    super.viewWillLayout()
  }

  // MARK: - Validate UI

  /** Do synchronization*/
  override func viewDidAppear() {
    // image sub
    super.viewDidAppear()
    updateControlsState()
  }

  deinit {
    aiSubtitleLanguageProbeTask?.cancel()
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }

  private func updateControlsState() {
    updateVideoTabControl()
    updateAudioTabControl()
    updateSubTabControl()
    updateVideoEqState()
    updateAudioEqState()
  }

  /// Return the slider value that represents the given playback speed.
  /// - Parameter speed: Playback speed.
  /// - Returns: Appropriate slider value.
  private func convertSpeedToSliderValue(_ speed: Double) -> Double {
    log(speed / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
  }

  private func updateVideoTabControl() {
    if let index = AppData.aspectsInPanel.firstIndex(of: player.info.unsureAspect) {
      aspectSegment.selectedSegment = index
    } else {
      aspectSegment.selectedSegment = -1
    }
    if let index = AppData.cropsInPanel.firstIndex(of: player.info.unsureCrop) {
      cropSegment.selectedSegment = index
    } else {
      // Select last segment ("Custom...")
      cropSegment.selectedSegment = cropSegment.segmentCount - 1
    }
    rotateSegment.selectSegment(withTag: AppData.rotations.firstIndex(of: player.info.rotation) ?? -1)

    hardwareDecodingSwitch.state = player.info.hwdecEnabled ? .on : .off
    deinterlaceSwitch.state = player.info.deinterlace ? .on : .off
    hdrSwitch.isEnabled = player.info.hdrAvailable
    hdrSwitch.state = (player.info.hdrAvailable && player.info.hdrEnabled) ? .on : .off
    
    // These strings are also contained in the strings file of this view. Remove these lines if the localization of these strings are complete enough.
    hardwareDecodingLabel.stringValue = NSLocalizedString("quicksetting.hwdec", comment: "Hardware Decoding")
    deinterlaceLabel.stringValue = NSLocalizedString("quicksetting.deinterlace", comment: "Deinterlace")
    hdrLabel.stringValue = NSLocalizedString("quicksetting.hdr", comment: "HDR")

    let speed = player.mpv.getDouble(MPVOption.PlaybackControl.speed)
    updateSpeed(to: speed)
  }

  private func updateAudioTabControl() {
    let audioDelay = player.mpv.getDouble(MPVOption.Audio.audioDelay)
    audioDelaySlider.doubleValue = audioDelay
    customAudioDelayTextField.doubleValue = audioDelay
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")
  }

  private func updateSubTabControl() {
    hideSwitch.state = player.info.isSubVisible ? .on : .off
    secHideSwitch.state = player.info.isSecondSubVisible ? .on : .off

    if let currSub = player.info.currentTrack(.sub) {
      // FIXME: CollorWells cannot be disable?
      let enableTextSettings = !(currSub.isAssSub || currSub.isImageSub)
      let textStyleControls: [NSControl?] = [
        subTextColorWell,
        subTextSizePopUp,
        subTextBgColorWell,
        subTextBorderColorWell,
        subTextBorderWidthPopUp,
        subTextFontBtn
      ]
      textStyleControls.compactMap { $0 }.forEach { $0.isEnabled = enableTextSettings }
    }

    let isPrimary = (subSegmentedControl.selectedSegment == 0)
    let delayOption = isPrimary ? MPVOption.Subtitles.subDelay : MPVOption.Subtitles.secondarySubDelay
    let subDelay = player.mpv.getDouble(delayOption)
    subDelaySlider.doubleValue = subDelay
    customSubDelayTextField.doubleValue = subDelay
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")

    let posOption = isPrimary ? MPVOption.Subtitles.subPos : MPVOption.Subtitles.secondarySubPos
    let currSubPos = player.mpv.getInt(posOption)
    subPosSlider.intValue = Int32(currSubPos)

    let currSubScale = player.mpv.getDouble(MPVOption.Subtitles.subScale).clamped(to: 0.1...10)
    let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)
    subScaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)

    if let textSizePopup = subTextSizePopUp,
       let borderWidthPopup = subTextBorderWidthPopUp {
      let fontSize = player.mpv.getInt(MPVOption.Subtitles.subFontSize)
      textSizePopup.selectItem(withTitle: fontSize.description)

      let borderWidth = player.mpv.getDouble(MPVOption.Subtitles.subBorderSize)
      borderWidthPopup.selectItem(at: -1)
      borderWidthPopup.itemArray.forEach { item in
        if borderWidth == Double(item.title) {
          borderWidthPopup.select(item)
        }
      }
    }
  }

  private func updateVideoEqState() {
    brightnessSlider.intValue = Int32(player.info.brightness)
    contrastSlider.intValue = Int32(player.info.contrast)
    saturationSlider.intValue = Int32(player.info.saturation)
    gammaSlider.intValue = Int32(player.info.gamma)
    hueSlider.intValue = Int32(player.info.hue)
  }

  private func updateAudioEqState() {
    if let filter = player.info.audioEqFilter {
      guard let eqString = Regex("\\[(.+?)\\]").captures(in: filter.stringFormat)[at: 1] else { return }
      let filters = eqString.split(separator: ",")
      zip(filters, audioEQSliders).forEach { (filter, slider) in
        if let gain = filter.split(separator: "=").last {
          slider.doubleValue = Double(gain) ?? 0
        } else {
          slider.doubleValue = 0
        }
      }
    } else {
      audioEQSliders.forEach { $0.doubleValue = 0 }
    }
  }

  private func switchToTab(_ tab: TabViewType) {
    guard isViewLoaded else { return }
    currentTab = tab
    tabView.selectTabViewItem(at: tab.buttonTag)
    updateTabActiveStatus()
    reload()
    mainWindow.refreshAISubtitleLanguageConfirmationHUD()
    if tab == .aiSubtitle {
      tabView.layoutSubtreeIfNeeded()
      scheduleAISubtitleContentLayout()
    }
  }

  private func updateTabActiveStatus() {
    let currentTag = currentTab.buttonTag
    [videoTabBtn, audioTabBtn, subTabBtn, aiSubtitleTabBtn].forEach { btn in
      let isActive = currentTag == btn!.tag
      btn!.state = .off
      btn!.contentTintColor = isActive ? .sidebarTabTintActive : .sidebarTabTint
    }
  }

  func reload() {
    guard isViewLoaded else { return }
    switch currentTab {
    case .audio:
      audioTableView.reloadData()
      updateAudioTabControl()
      updateAudioEqState()
    case .video:
      videoTableView.reloadData()
      updateVideoTabControl()
      updateVideoEqState()
    case .sub:
      subTableView.reloadData()
      secSubTableView.reloadData()
      updateSubTabControl()
    case .aiSubtitle:
      updateAISubtitleTab()
    }
  }

  func setHdrAvailability(to available: Bool) {
    player.info.hdrAvailable = available
    if isViewLoaded {
      hdrSwitch.isEnabled = available
      hdrSwitch.state = (available && player.info.hdrEnabled) ? .on : .off
    }
  }

  // MARK: - Switch tab

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabViewType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  // MARK: - NSTableView delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == videoTableView {
      return player.info.videoTracks.count + 1
    } else if tableView == audioTableView {
      return player.info.audioTracks.count + 1
    } else if tableView == subTableView || tableView == secSubTableView {
      return player.info.$subTracks.withLock { $0.count + 1 }
    } else {
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    // get track according to tableview
    // row=0: <None> row=1~: tracks[row-1]
    let track: MPVTrack?
    let activeId: Int
    let columnName = tableColumn?.identifier
    if tableView == videoTableView {
      track = row == 0 ? nil : player.info.videoTracks[at: row-1]
      activeId = player.info.vid!
    } else if tableView == audioTableView {
      track = row == 0 ? nil : player.info.audioTracks[at: row-1]
      activeId = player.info.aid!
    } else if tableView == subTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.sid!
    } else if tableView == secSubTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.secondSid!
    } else {
      return nil
    }
    // return track data
    if columnName == .isChosen {
      let isChosen = track == nil ? (activeId == 0) : (track!.id == activeId)
      return isChosen ? Constants.String.dot : ""
    } else if columnName == .trackName {
      if tableView == subTableView || tableView == secSubTableView {
        return track?.subtitleListInfoString ?? Constants.String.trackNone
      }
      return track?.infoString ?? Constants.String.trackNone
    } else if columnName == .trackId {
      return track?.idString
    }
    return nil
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        // note that track ids start from 1
        let subId = view.selectedRow > 0 ? player.info.trackList(type)[view.selectedRow-1].id : 0
        self.player.setTrack(subId, forType: type)
        view.deselectAll(self)
      }
    }
    // Revalidate layout and controls
    updateControlsState()
  }

  private func withAllTableViews(_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
    block(videoTableView, .video)
  }

  // MARK: - Actions

  // MARK: Tab buttons

  @IBAction func tabBtnAction(_ sender: NSButton) {
    switchToTab(.init(buttonTag: sender.tag))
  }

  @IBAction func aiSubtitleTabBtnAction(_ sender: NSButton) {
    switchToTab(.aiSubtitle)
  }

  // MARK: Video tab

  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    let aspect = AppData.aspectsInPanel[sender.selectedSegment]
    player.setVideoAspect(aspect)
    player.sendOSD(.aspect(aspect))
  }

  @IBAction func cropChangedAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == sender.segmentCount - 1 {
      // User clicked on "Custom...": show custom crop UI
      mainWindow.hideSideBar {
        self.mainWindow.enterInteractiveMode(.crop, selectWholeVideoByDefault: true)
      }
    } else {
      let cropStr = AppData.cropsInPanel[sender.selectedSegment]
      player.setCrop(fromString: cropStr)
      player.sendOSD(.crop(cropStr))
    }
  }

  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = AppData.rotations[sender.selectedSegment]
    player.setVideoRotate(value)
    player.sendOSD(.rotate(value))
  }

  @IBAction func customAspectEditFinishedAction(_ sender: AnyObject?) {
    let value = customAspectTextField.stringValue
    if value != "" {
      aspectSegment.setSelected(false, forSegment: aspectSegment.selectedSegment)
      player.setVideoAspect(value)
      player.sendOSD(.aspect(value))
    }
  }

  @IBAction func hardwareDecodingAction(_ sender: NSSwitch) {
    player.toggleHardwareDecoding(sender.state == .on)
  }
  
  @IBAction func deinterlaceAction(_ sender: NSSwitch) {
    player.toggleDeinterlace(sender.state == .on)
  }
  
  @IBAction func hdrAction(_ sender: NSSwitch) {
    self.player.info.hdrEnabled = sender.state == .on
    self.player.refreshEdrMode()
  }

  private func redraw(indicator: NSTextField, constraint: NSLayoutConstraint, slider: NSSlider, value: String) {
    indicator.stringValue = value
    let offset: CGFloat = 6
    let sliderInnerWidth = slider.frame.width - offset * 2
    constraint.constant = offset + sliderInnerWidth * CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    view.layout()
  }

  @IBAction func resetSpeedAction(_ sender: AnyObject) {
    player.setSpeed(1.0)
  }

  @IBAction func speedChangedAction(_ sender: NSSlider) {
    // Each step is 64^(1/24)
    //   0       1   ..    7      8      9   ..   24
    // 0.250x 0.297x .. 0.841x 1.000x 1.189x .. 16.00x
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    // Attempt to round speed to 2 decimal places. If user is using the slider, any more
    // precision than that is just a distraction
    let newSpeed = (AppData.minSpeed * pow(AppData.maxSpeed / AppData.minSpeed, sliderValue / sliderSteps)).roundedTo2Decimals()
    updateSpeed(to: newSpeed)
  }

  @IBAction func customSpeedEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "1"
    }
    /// Unfortunately, the text field has not applied validation/formatting to the number at this point.
    /// We will do that manually via `constrainSpeed`.
    updateSpeed(to: sender.doubleValue)
    if let window = sender.window {
      window.makeFirstResponder(window.contentView)
    }
  }

  /// Ensure that the given `Double` is a speed which is valid for mpv.
  ///
  /// - This is necessary because libmpv cannot be relied on to report the correct number & will reply
  /// with a property change event which echoes the number which was submitted, even if it is not the
  /// same as the number which mpv is actually using (it will internally round the number to 6 digits
  /// after the decimal but tell us that it used the non-rounded number).
  /// - `NumberFormatter` doesn't provide APIs to validate or correct an `NSNumber`.
  /// But we can get the same effect by converting to a `String` and back again.
  private func constrainSpeed(_ inputSpeed: Double) -> Double {
    let newSpeedString: String = speedFormatter.string(from: inputSpeed as NSNumber) ?? "1"
    return Double(truncating: speedFormatter.number(from: newSpeedString)!)
  }

  private func updateSpeed(to inputSpeed: Double) {
    let newSpeed = constrainSpeed(inputSpeed)
    speedSlider.doubleValue = convertSpeedToSliderValue(newSpeed)
    customSpeedTextField.doubleValue = newSpeed
    speedResetBtn.isHidden = newSpeed == 1.0
    if player.info.playSpeed != newSpeed {
      player.setSpeed(newSpeed)
    }
    /// Use `customSpeedTextField.stringValue` to take advantage of its formatter
    /// (e.g. `16` will be displayed instead of `16.0`)
    redraw(indicator: speedSliderIndicator, constraint: speedSliderConstraint, slider: speedSlider, value: "\(customSpeedTextField.stringValue)x")
  }

  @IBAction func equalizerSliderAction(_ sender: NSSlider) {
    let type: PlayerCore.VideoEqualizerType
    switch sender {
    case brightnessSlider:
      type = .brightness
    case contrastSlider:
      type = .contrast
    case saturationSlider:
      type = .saturation
    case gammaSlider:
      type = .gamma
    case hueSlider:
      type = .hue
    default:
      return
    }
    player.setVideoEqualizer(forOption: type, value: Int(sender.intValue))
  }

  // use tag for buttons
  @IBAction func resetEqualizerBtnAction(_ sender: NSButton) {
    let type: PlayerCore.VideoEqualizerType
    let slider: NSSlider?
    switch sender.tag {
    case 0:
      type = .brightness
      slider = brightnessSlider
    case 1:
      type = .contrast
      slider = contrastSlider
    case 2:
      type = .saturation
      slider = saturationSlider
    case 3:
      type = .gamma
      slider = gammaSlider
    case 4:
      type = .hue
      slider = hueSlider
    default:
      return
    }
    player.setVideoEqualizer(forOption: type, value: 0)
    slider?.intValue = 0
  }

  // MARK: Audio tab

  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(
      title: "Load external audio file",
      chooseDir: false,
      dir: currentDir,
      sheetWindow: player.currentWindow,
      allowedFileTypes: Utility.playableFileExt
    ) { url in
      self.player.loadExternalAudioFile(url)
      self.audioTableView.reloadData()
    }
  }

  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    let sliderValue: Double
    switch eventType {
    case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
      // When dragging slider with the mouse, snap to the nearest 50ms (1/20 sec)
      // Although it is possible to show tick marks at every step of 0.05 in the slider, it is visually unpleasant.
      // So we draw less tick marks, and keep "Only stop on tick marks" disabled, and add our own logic to stop on
      // "virtual tick marks" for these values.
      sliderValue = (sender.doubleValue * 20.0).rounded() / 20.0
      sender.doubleValue = sliderValue
    default:
      sliderValue = sender.doubleValue
    }
    customAudioDelayTextField.doubleValue = sliderValue
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sliderValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setAudioDelay(sliderValue)
      }
    }
  }

  @IBAction func customAudioDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setAudioDelay(value)
    audioDelaySlider.doubleValue = value
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sender.stringValue)s")
  }

  func applyEQ(_ profile: EQProfile) {
    zip(audioEQSliders, profile.gains).forEach { (slider, gain) in
      slider.doubleValue = gain
    }
    player.setAudioEq(fromGains: profile.gains)
  }



  @IBAction func audioEqSliderAction(_ sender: NSSlider) {
    player.setAudioEq(fromGains: audioEQSliders.map { $0.doubleValue })
    eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
  }

  // MARK: Sub tab

  @IBAction func hideSubAction(_ sender: NSSwitch) {
    player.toggleSubVisibility()
  }

  @IBAction func hideSecSubAction(_ sender: NSSwitch) {
    player.toggleSecondSubVisibility()
  }

  @IBAction func loadExternalSubAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      let currentDir = player.info.currentURL?.deletingLastPathComponent()
      // In addition to subtitle files allow the user to choose video files as mpv will look for
      // and load embedded subtitle streams in the video file.
      Utility.quickOpenPanel(title: "Load external subtitle", chooseDir: false, dir: currentDir,
                             sheetWindow: player.currentWindow,
                             allowedFileTypes: Utility.containsSubExt) { url in
        // set a delay
        self.player.loadExternalSubFile(url, delay: true)
        self.subTableView.reloadData()
        self.secSubTableView.reloadData()
      }
    } else if sender.selectedSegment == 1 {
      showSubChooseMenu(forView: sender)
    }
  }

  func showSubChooseMenu(forView view: NSView, showLoadedSubs: Bool = false) {
    let activeSubs = player.info.trackList(.sub) + player.info.trackList(.secondSub)
    let menu = NSMenu()
    menu.autoenablesItems = false
    // loaded subtitles
    if showLoadedSubs {
      if player.info.subTracks.isEmpty {
        menu.addItem(withTitle: NSLocalizedString("subtrack.no_loaded", comment: "No subtitles loaded"), enabled: false)
      } else {
        menu.addItem(withTitle: NSLocalizedString("track.none", comment: "<None>"),
                     action: #selector(self.chosenSubFromMenu(_:)), target: self,
                     stateOn: player.info.sid == 0 ? true : false)

        for sub in player.info.subTracks {
          menu.addItem(withTitle: sub.readableTitle,
                       action: #selector(self.chosenSubFromMenu(_:)),
                       target: self,
                       obj: sub,
                       stateOn: sub.id == player.info.sid ? true : false)
        }
      }
      menu.addItem(NSMenuItem.separator())
    }
    // external subtitles
    let addMenuItem = { (sub: FileInfo) -> Void in
      let isActive = !showLoadedSubs && activeSubs.contains { $0.externalFilename == sub.path }
      menu.addItem(withTitle: "\(sub.filename).\(sub.ext)",
                   action: #selector(self.chosenSubFromMenu(_:)),
                   target: self,
                   obj: sub,
                   stateOn: isActive ? true : false)

    }
    if player.info.currentSubsInfo.isEmpty {
      menu.addItem(withTitle: NSLocalizedString("subtrack.no_external", comment: "No external subtitles found"),
                   enabled: false)
    } else {
      if let videoInfo = player.info.currentVideosInfo.first(where: { $0.url == player.info.currentURL }),
        !videoInfo.relatedSubs.isEmpty {
        videoInfo.relatedSubs.forEach(addMenuItem)
        menu.addItem(NSMenuItem.separator())
      }
      player.info.currentSubsInfo.sorted { (f1, f2) in
        return f1.filename.localizedStandardCompare(f2.filename) == .orderedAscending
      }.forEach(addMenuItem)
    }
    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: view)
  }

  @objc func chosenSubFromMenu(_ sender: NSMenuItem) {
    if let fileInfo = sender.representedObject as? FileInfo {
      player.loadExternalSubFile(fileInfo.url)
    } else if let sub = sender.representedObject as? MPVTrack {
      player.setTrack(sub.id, forType: .sub)
    } else {
      player.setTrack(0, forType: .sub)
    }
  }

  @IBAction func searchOnlineAction(_ sender: AnyObject) {
    mainWindow.menuActionHandler.menuFindOnlineSub(.dummy)
  }

  @IBAction func subSegmentedControlAction(_ sender: NSSegmentedControl) {
    updateSubTabControl()
  }

  @IBAction func subDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    customSubDelayTextField.doubleValue = sliderValue
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setSubDelay(sliderValue, forPrimary: subSegmentedControl.selectedSegment == 0)
      }
    }
  }

  @IBAction func customSubDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setSubDelay(value, forPrimary: subSegmentedControl.selectedSegment == 0)
    subDelaySlider.doubleValue = value
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(sender.stringValue)s")
  }

  @IBAction func subScaleReset(_ sender: AnyObject) {
    player.setSubScale(1)
    subScaleSlider.doubleValue = 0
  }

  @IBAction func subPosSliderAction(_ sender: NSSlider) {
    player.setSubPos(Int(sender.intValue), forPrimary: subSegmentedControl.selectedSegment == 0)
  }

  @IBAction func subScaleSliderAction(_ sender: NSSlider) {
    let value = sender.doubleValue
    let mappedValue: Double, realValue: Double
    // map [-10, -1], [1, 10] to [-9, 9], bounds may change in future
    if value > 0 {
      mappedValue = round((value + 1) * 20) / 20
      realValue = mappedValue
    } else {
      mappedValue = round((value - 1) * 20) / 20
      realValue = 1 / mappedValue
    }
    player.setSubScale(realValue)
  }

  @IBAction func subTextColorAction(_ sender: AnyObject) {
    player.setSubTextColor(subTextColorWell.color.mpvColorString)
  }

  @IBAction func subTextSizeAction(_ sender: AnyObject) {
    if let selectedItem = subTextSizePopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextSize(value)
    }
  }

  @IBAction func subTextBorderColorAction(_ sender: AnyObject) {
    player.setSubTextBorderColor(subTextBorderColorWell.color.mpvColorString)
  }

  @IBAction func subTextBorderWidthAction(_ sender: AnyObject) {
    if let selectedItem = subTextBorderWidthPopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextBorderSize(value)
    }
  }

  @IBAction func subTextBgColorAction(_ sender: AnyObject) {
    player.setSubTextBgColor(subTextBgColorWell.color.mpvColorString)
  }

  @IBAction func subFontAction(_ sender: AnyObject) {
    player.chooseSubFont()
  }

}

extension QuickSettingViewController: NSMenuDelegate {
  private func promptAudioEQProfileName(isNewProfile: Bool) -> String? {
    let key = isNewProfile ? "eq.new_profile" : "eq.rename"
    let nameList = eqPopUpButton.itemArray
      .filter{ $0.tag == eqPresetProfileMenuItemTag || $0.tag == eqUserDefinedProfileMenuItemTag }
      .map{ $0.title }
    let validator: Utility.InputValidator<String> = { input in
      if input.isEmpty {
        return .valueIsEmpty
      }
      if nameList.contains( where: { $0 == input } ) {
        return .valueAlreadyExists
      } else {
        return .ok
      }
    }
    var inputString: String?
    Utility.quickPromptPanel(key, validator: validator, callback: { inputString = $0 })
    return inputString
  }
  
  func findItem(_ name: String, _ tag: Int = eqUserDefinedProfileMenuItemTag) -> NSMenuItem? {
    return eqPopUpButton.itemArray.filter{ $0.tag == tag }.first { $0.title == name }
  }

  @IBAction func eqPopUpButtonAction(_ sender: NSPopUpButton) {
    let tag = sender.selectedTag()
    let name = sender.titleOfSelectedItem
    let representedObject = sender.selectedItem?.representedObject as? String
    switch tag {
    case eqSaveMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: true) {
        let newProfile = EQProfile(fromCurrentSliders: audioEQSliders)
        userEQs[inputString] = newProfile
        menuNeedsUpdate(eqPopUpButton.menu!)
        eqPopUpButton.select(findItem(inputString))
        lastUsedProfileName = inputString
      } else {
        eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
      }
    case eqRenameMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: false) {
        let profile = userEQs.removeValue(forKey: lastUsedProfileName)
        userEQs[inputString] = profile
        menuNeedsUpdate(eqPopUpButton.menu!)
        eqPopUpButton.select(findItem(inputString))
        lastUsedProfileName = inputString
      } else {
        eqPopUpButton.select(findItem(lastUsedProfileName))
      }
    case eqDeleteMenuItemTag:
      userEQs.removeValue(forKey: lastUsedProfileName)
      menuNeedsUpdate(eqPopUpButton.menu!)
      eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
    case eqCustomMenuItemTag:
      lastUsedProfileName = sender.selectedItem!.title
    case eqPresetProfileMenuItemTag:
      guard let preset = presetEQs.first(where: { $0.localizationKey == representedObject }) else { break }
      lastUsedProfileName = preset.name
      applyEQ(preset)
    default: // user defined EQ Profiles
      guard let pair = userEQs.first(where: { $0.0 == name }) else { break }
      lastUsedProfileName = pair.0
      applyEQ(pair.1)
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    let tag = eqPopUpButton.selectedTag()
    let saveItem = menu.item(withTag: eqSaveMenuItemTag)!
    let editingItems = [menu.item(withTag: eqRenameMenuItemTag)!, menu.item(withTag: eqDeleteMenuItemTag)!]

    editingItems.forEach { $0.isEnabled = (tag == eqUserDefinedProfileMenuItemTag) }
    saveItem.isEnabled = (tag == eqCustomMenuItemTag)

    let selectedName = eqPopUpButton.titleOfSelectedItem!
    let selectedTag = eqPopUpButton.selectedTag()
    var items = menu.items
    items.removeAll { $0.tag == eqUserDefinedProfileMenuItemTag }
    if !userEQs.isEmpty {
      items.append(NSMenuItem.separator())
    }
    menu.items = items
    userEQs.forEach { (name, eq) in
      menu.addItem(withTitle: name, tag: eqUserDefinedProfileMenuItemTag)
    }
    eqPopUpButton.select(findItem(selectedName, selectedTag))
    eqPopUpButton.itemArray.forEach { $0.state = .off }
    eqPopUpButton.selectedItem?.state = .on
  }
}

class QuickSettingView: NSView {

  override func mouseDown(with event: NSEvent) {}

}
