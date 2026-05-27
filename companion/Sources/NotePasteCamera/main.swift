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
    showWindow(request: request, status: "Opening iPhone camera options...")
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

  init(request: CaptureRequest?, initialStatus: String) {
    self.request = request
    self.cameraView = ContinuityCameraView(request: request)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
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

    let title = NSTextField(labelWithString: "NotePaste Camera")
    title.font = .systemFont(ofSize: 18, weight: .semibold)

    let body = NSTextField(labelWithString: "Use the system iPhone camera menu. Captured images are sent back to the active Obsidian note.")
    body.lineBreakMode = .byWordWrapping
    body.maximumNumberOfLines = 3
    body.textColor = .secondaryLabelColor

    let button = NSButton(title: "Use iPhone Camera", target: cameraView, action: #selector(ContinuityCameraView.showContinuityCameraMenu))
    button.bezelStyle = .rounded

    statusLabel.stringValue = initialStatus
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.lineBreakMode = .byWordWrapping
    statusLabel.maximumNumberOfLines = 2

    let stack = NSStackView(views: [title, body, button, statusLabel])
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
      stack.bottomAnchor.constraint(lessThanOrEqualTo: cameraView.bottomAnchor, constant: -24),
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
    ])
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
