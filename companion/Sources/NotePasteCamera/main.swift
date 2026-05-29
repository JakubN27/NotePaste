import AppKit
import Carbon
import Foundation

@main
struct NotePasteCameraMain {
  @MainActor private static var delegate: AppDelegate?

  @MainActor
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    Self.delegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}

struct CaptureRequest {
  let callbackURL: URL
  let sessionID: String
  let uploadToken: String

  init?(url: URL) {
    guard url.scheme == "notepaste-camera" else {
      return nil
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard
      let callback = items.first(where: { $0.name == "callback" })?.value,
      let callbackURL = URL(string: callback),
      let sessionID = items.first(where: { $0.name == "session" })?.value,
      let uploadToken = items.first(where: { $0.name == "token" })?.value
    else {
      return nil
    }
    self.callbackURL = callbackURL
    self.sessionID = sessionID
    self.uploadToken = uploadToken
  }
}

struct CapturePayload {
  let data: Data
  let contentType: String
}

struct ObsidianVault {
  let id: String
  let name: String
  let url: URL
  let isOpen: Bool

  var displayName: String {
    isOpen ? "\(name) (open)" : name
  }
}

enum PluginInstallError: LocalizedError {
  case missingObsidianConfig
  case missingPluginResources
  case notVault(URL)
  case invalidCommunityPlugins(URL)

  var errorDescription: String? {
    switch self {
    case .missingObsidianConfig:
      return "Could not find Obsidian's vault registry."
    case .missingPluginResources:
      return "This app is missing its bundled NotePaste plugin files."
    case .notVault(let url):
      return "\(url.path) does not look like an Obsidian vault."
    case .invalidCommunityPlugins(let url):
      return "Could not read \(url.path) as an Obsidian community plugin list."
    }
  }
}

final class PluginInstaller {
  private let fileManager = FileManager.default
  private let pluginID = "notepaste"
  private let bundledFiles = ["manifest.json", "main.js", "styles.css", "versions.json"]

  func discoverVaults() throws -> [ObsidianVault] {
    let configURL = try obsidianConfigURL()
    let data = try Data(contentsOf: configURL)
    guard
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let vaults = root["vaults"] as? [String: Any]
    else {
      throw PluginInstallError.missingObsidianConfig
    }

    return vaults.compactMap { id, value in
      guard
        let vault = value as? [String: Any],
        let path = vault["path"] as? String
      else {
        return nil
      }

      let url = URL(fileURLWithPath: path)
      return ObsidianVault(
        id: id,
        name: url.lastPathComponent,
        url: url,
        isOpen: (vault["open"] as? Bool) ?? false
      )
    }
    .sorted { lhs, rhs in
      if lhs.isOpen != rhs.isOpen {
        return lhs.isOpen && !rhs.isOpen
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  func install(into vault: ObsidianVault) throws {
    let obsidianDirectory = vault.url.appendingPathComponent(".obsidian", isDirectory: true)
    guard fileManager.fileExists(atPath: obsidianDirectory.path) else {
      throw PluginInstallError.notVault(vault.url)
    }

    let resources = try pluginResourcesURL()
    let targetDirectory = obsidianDirectory
      .appendingPathComponent("plugins", isDirectory: true)
      .appendingPathComponent(pluginID, isDirectory: true)

    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    for fileName in bundledFiles {
      let source = resources.appendingPathComponent(fileName, isDirectory: false)
      let destination = targetDirectory.appendingPathComponent(fileName, isDirectory: false)
      guard fileManager.fileExists(atPath: source.path) else {
        throw PluginInstallError.missingPluginResources
      }
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.copyItem(at: source, to: destination)
    }

    try enableCommunityPlugin(in: obsidianDirectory)
  }

  private func obsidianConfigURL() throws -> URL {
    guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw PluginInstallError.missingObsidianConfig
    }
    return appSupport
      .appendingPathComponent("obsidian", isDirectory: true)
      .appendingPathComponent("obsidian.json", isDirectory: false)
  }

  private func pluginResourcesURL() throws -> URL {
    guard let resources = Bundle.main.resourceURL?.appendingPathComponent("plugin", isDirectory: true),
          fileManager.fileExists(atPath: resources.path)
    else {
      throw PluginInstallError.missingPluginResources
    }
    return resources
  }

  private func enableCommunityPlugin(in obsidianDirectory: URL) throws {
    let pluginsURL = obsidianDirectory.appendingPathComponent("community-plugins.json", isDirectory: false)
    var plugins: [String] = []

    if fileManager.fileExists(atPath: pluginsURL.path) {
      let data = try Data(contentsOf: pluginsURL)
      guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String] else {
        throw PluginInstallError.invalidCommunityPlugins(pluginsURL)
      }
      plugins = parsed
    }

    if !plugins.contains(pluginID) {
      plugins.append(pluginID)
    }

    let data = try JSONSerialization.data(withJSONObject: plugins, options: [.prettyPrinted])
    try data.appendingNewline().write(to: pluginsURL, options: .atomic)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: CameraWindowController?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    showIdleWindow()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showIdleWindow()
    return true
  }

  @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    guard
      let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: urlString),
      let request = CaptureRequest(url: url)
    else {
      showIdleWindow(status: "Could not read the NotePaste capture request.")
      return
    }
    startCapture(request)
  }

  private func showIdleWindow(status: String = "Start a capture from Obsidian with /notepaste.") {
    showWindow(request: nil, status: status)
  }

  private func startCapture(_ request: CaptureRequest) {
    showWindow(request: request, status: "Opening the iPhone photo capture menu...")
    windowController?.presentContinuityCameraMenuSoon()
  }

  private func showWindow(request: CaptureRequest?, status: String) {
    windowController = CameraWindowController(request: request, initialStatus: status)
    windowController?.showWindow(nil)
    forceActivate()
  }

  private func forceActivate() {
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)

    if let window = windowController?.window {
      window.deminiaturize(nil)
      window.centerOnVisibleScreen()
      window.orderFrontRegardless()
      window.makeKeyAndOrderFront(nil)
    }

    let script = """
    tell application "System Events"
      set visible of process "NotePaste Camera" to true
      set frontmost of process "NotePaste Camera" to true
    end tell
    """
    NSAppleScript(source: script)?.executeAndReturnError(nil)
  }
}

final class CameraWindowController: NSWindowController {
  private let cameraView: ContinuityCameraView
  private let statusLabel = NSTextField(labelWithString: "")
  private let request: CaptureRequest?
  private let pluginInstaller = PluginInstaller()
  private var vaults: [ObsidianVault] = []
  private let vaultPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let installButton = NSButton(title: "Install / Update Plugin", target: nil, action: nil)
  private let primaryButton = NSButton(title: "", target: nil, action: nil)

  init(request: CaptureRequest?, initialStatus: String) {
    self.request = request
    self.cameraView = ContinuityCameraView(request: request)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: request == nil ? 330 : 270),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "NotePaste Camera"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.level = .floating
    window.center()

    super.init(window: window)

    cameraView.statusHandler = { [weak self] status in
      self?.statusLabel.stringValue = status
    }
    cameraView.completionHandler = { [weak self] in
      self?.window?.close()
    }

    cameraView.wantsLayer = true
    cameraView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let eyebrow = NSTextField(labelWithString: request == nil ? "Vault setup" : "Capture ready")
    eyebrow.font = .systemFont(ofSize: 11, weight: .bold)
    eyebrow.textColor = .controlAccentColor
    eyebrow.stringValue = eyebrow.stringValue.uppercased()

    let title = NSTextField(labelWithString: request == nil ? "Install NotePaste" : "Take a photo on iPhone")
    title.font = .systemFont(ofSize: 24, weight: .bold)

    let bodyText = request == nil
      ? "Install the Obsidian plugin into a vault, then use /notepaste from Obsidian. This app also handles iPhone camera capture."
      : "The system iPhone camera menu opens automatically. Captured images are sent back to the active Obsidian note and this window closes."
    let body = NSTextField(labelWithString: bodyText)
    body.lineBreakMode = .byWordWrapping
    body.maximumNumberOfLines = 3
    body.textColor = .secondaryLabelColor

    statusLabel.stringValue = initialStatus
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byWordWrapping
    statusLabel.maximumNumberOfLines = 2

    let controls = request == nil ? installerControls() : cameraControls()
    let stack = NSStackView(views: [eyebrow, title, body, controls, statusLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false

    cameraView.translatesAutoresizingMaskIntoConstraints = false
    cameraView.addSubview(stack)
    window.contentView = cameraView
    window.initialFirstResponder = cameraView

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: cameraView.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: cameraView.bottomAnchor, constant: -24)
    ])

    if request == nil {
      reloadVaultList()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    window?.deminiaturize(sender)
    window?.centerOnVisibleScreen()
    window?.orderFrontRegardless()
    window?.makeKeyAndOrderFront(sender)
    window?.makeFirstResponder(cameraView)
  }

  func presentContinuityCameraMenuSoon() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      self?.cameraView.showContinuityCameraMenu()
    }
  }

  private func cameraControls() -> NSView {
    primaryButton.title = "Take Photo on iPhone"
    primaryButton.target = cameraView
    primaryButton.action = #selector(ContinuityCameraView.showContinuityCameraMenu)
    primaryButton.bezelStyle = .rounded
    primaryButton.controlSize = .large
    primaryButton.keyEquivalent = "\r"
    primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

    let caption = NSTextField(labelWithString: "If macOS shows a device list, choose Take Photo. Apple does not expose a public API to bypass that system confirmation.")
    caption.textColor = .tertiaryLabelColor
    caption.font = .systemFont(ofSize: 12)
    caption.lineBreakMode = .byWordWrapping
    caption.maximumNumberOfLines = 2

    let stack = NSStackView(views: [primaryButton, caption])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    return stack
  }

  private func installerControls() -> NSView {
    vaultPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

    installButton.target = self
    installButton.action = #selector(installSelectedVault)
    installButton.bezelStyle = .rounded
    installButton.controlSize = .large

    let refreshButton = NSButton(title: "Refresh Vaults", target: self, action: #selector(refreshVaultList))
    refreshButton.bezelStyle = .rounded

    let buttonRow = NSStackView(views: [installButton, refreshButton])
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 10

    let stack = NSStackView(views: [vaultPopup, buttonRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    return stack
  }

  @objc private func refreshVaultList() {
    reloadVaultList()
  }

  @objc private func installSelectedVault() {
    let index = vaultPopup.indexOfSelectedItem
    guard vaults.indices.contains(index) else {
      statusLabel.stringValue = "Choose an Obsidian vault first."
      return
    }

    let vault = vaults[index]
    do {
      try pluginInstaller.install(into: vault)
      statusLabel.stringValue = "Installed NotePaste into \(vault.name). Reload Obsidian if it was already open."
    } catch {
      statusLabel.stringValue = "Install failed: \(error.localizedDescription)"
    }
  }

  private func reloadVaultList() {
    do {
      vaults = try pluginInstaller.discoverVaults()
      vaultPopup.removeAllItems()
      vaultPopup.addItems(withTitles: vaults.map { "\($0.displayName) - \($0.url.path)" })
      installButton.isEnabled = !vaults.isEmpty
      statusLabel.stringValue = vaults.isEmpty
        ? "No Obsidian vaults were found."
        : "Choose a vault to install or update the bundled plugin."
    } catch {
      vaults = []
      vaultPopup.removeAllItems()
      installButton.isEnabled = false
      statusLabel.stringValue = "Could not discover vaults: \(error.localizedDescription)"
    }
  }
}

extension NSWindow {
  func centerOnVisibleScreen() {
    guard let screen = screen ?? NSScreen.main else {
      center()
      return
    }
    let visibleFrame = screen.visibleFrame
    let frame = frame
    let origin = NSPoint(
      x: visibleFrame.midX - frame.width / 2,
      y: visibleFrame.midY - frame.height / 2
    )
    setFrameOrigin(origin)
  }
}

final class ContinuityCameraView: NSView {
  var statusHandler: ((String) -> Void)?
  var completionHandler: (() -> Void)?

  private let request: CaptureRequest?
  private var hasHandledCapture = false

  init(request: CaptureRequest?) {
    self.request = request
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func validRequestor(
    forSendType sendType: NSPasteboard.PasteboardType?,
    returnType: NSPasteboard.PasteboardType?
  ) -> Any? {
    if sendType == nil, let returnType, Self.accepts(returnType) {
      return self
    }
    return super.validRequestor(forSendType: sendType, returnType: returnType)
  }

  @objc(readSelectionFromPasteboard:)
  func readSelectionFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
    statusHandler?("Reading photo from Continuity Camera...")
    return handlePasteboard(pasteboard)
  }

  private func handlePasteboard(_ pasteboard: NSPasteboard) -> Bool {
    if hasHandledCapture {
      return true
    }
    guard let request else {
      statusHandler?("No active NotePaste request. Start from Obsidian first.")
      return false
    }
    guard let payload = CapturePayload.from(pasteboard: pasteboard) else {
      statusHandler?("Continuity Camera returned an unsupported image format: \(CapturePayload.describe(pasteboard: pasteboard))")
      return false
    }
    hasHandledCapture = true
    statusHandler?("Sending image to Obsidian...")
    post(payload: payload, request: request)
    return true
  }

  @objc func showContinuityCameraMenu() {
    guard let window else {
      return
    }
    window.makeFirstResponder(self)

    let menuLocation = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
    guard let event = NSEvent.mouseEvent(
      with: .rightMouseDown,
      location: menuLocation,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1.0
    ) else {
      statusHandler?("Could not open the Continuity Camera menu.")
      return
    }

    statusHandler?("Choose your iPhone from the system menu.")
    hasHandledCapture = false
    let menu = NSMenu(title: "Continuity Camera")
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  private func post(payload: CapturePayload, request: CaptureRequest) {
    var urlRequest = URLRequest(url: request.callbackURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(request.sessionID, forHTTPHeaderField: "X-NotePaste-Session")
    urlRequest.setValue(request.uploadToken, forHTTPHeaderField: "X-NotePaste-Token")

    URLSession.shared.uploadTask(with: urlRequest, from: payload.data) { [weak self] _, response, error in
      DispatchQueue.main.async {
        if let error {
          self?.statusHandler?("Could not send image: \(error.localizedDescription)")
          return
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(statusCode) {
          self?.statusHandler?("Image sent to Obsidian.")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self?.completionHandler?()
          }
        } else {
          self?.statusHandler?("Obsidian rejected the image with HTTP \(statusCode).")
        }
      }
    }.resume()
  }

  private static let acceptedReturnTypes: Set<String> = [
    "public.image",
    NSPasteboard.PasteboardType.tiff.rawValue,
    NSPasteboard.PasteboardType.png.rawValue,
    NSPasteboard.PasteboardType.pdf.rawValue,
    NSPasteboard.PasteboardType.fileURL.rawValue,
    "public.jpeg",
    "public.heic",
    "public.heif"
  ]

  private static func accepts(_ returnType: NSPasteboard.PasteboardType) -> Bool {
    let rawValue = returnType.rawValue
    return acceptedReturnTypes.contains(rawValue) || rawValue.hasPrefix("public.image")
  }
}

extension CapturePayload {
  static func from(pasteboard: NSPasteboard) -> CapturePayload? {
    if let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL])?.first as URL?,
       let data = try? Data(contentsOf: fileURL) {
      return CapturePayload(data: data, contentType: contentType(forPathExtension: fileURL.pathExtension))
    }

    if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic")) {
      return CapturePayload(data: data, contentType: "image/heic")
    }

    if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.heif")) {
      return CapturePayload(data: data, contentType: "image/heif")
    }

    if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
      return CapturePayload(data: data, contentType: "image/jpeg")
    }

    if let data = pasteboard.data(forType: .png) {
      return CapturePayload(data: data, contentType: "image/png")
    }

    if let data = pasteboard.data(forType: .pdf) {
      return CapturePayload(data: data, contentType: "application/pdf")
    }

    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData),
       let jpegData = image.jpegData(compression: 0.9) {
      return CapturePayload(data: jpegData, contentType: "image/jpeg")
    }

    return nil
  }

  static func describe(pasteboard: NSPasteboard) -> String {
    let typeNames = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "no pasteboard types"
    return typeNames.isEmpty ? "empty pasteboard" : typeNames
  }

  private static func contentType(forPathExtension pathExtension: String) -> String {
    switch pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "heic":
      return "image/heic"
    case "heif":
      return "image/heif"
    case "webp":
      return "image/webp"
    case "pdf":
      return "application/pdf"
    default:
      return "application/octet-stream"
    }
  }
}

extension NSImage {
  func jpegData(compression: CGFloat) -> Data? {
    guard
      let tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffRepresentation)
    else {
      return nil
    }
    return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
  }
}

extension Data {
  func appendingNewline() -> Data {
    var copy = self
    copy.append(0x0A)
    return copy
  }
}
