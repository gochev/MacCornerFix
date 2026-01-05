import Cocoa
import ApplicationServices
import ScreenCaptureKit

class MacCornerFixApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var cornerWindows: [CornerWindow] = []
    var updateTimer: Timer?
    var lastFocusedWindow: AXUIElement?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: "MacCornerFix")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About MacCornerFix", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        
        // Check for accessibility permissions
        if !checkAccessibilityPermissions() {
            showAccessibilityAlert()
        }
        
        // Start monitoring
        startMonitoring()
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MacCornerFix"
        alert.informativeText = "Fixes the inconsistent corner radius on macOS fullscreen windows.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MacCornerFix needs accessibility permissions to detect fullscreen windows.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    func startMonitoring() {
        // Monitor active window changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Start periodic check
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkAndUpdateCorners()
        }
        
        // Initial check
        checkAndUpdateCorners()
    }
    
    @objc func activeAppChanged() {
        checkAndUpdateCorners()
    }
    
    func checkAndUpdateCorners() {
        guard checkAccessibilityPermissions() else {
            print("⚠️ No accessibility permissions")
            return
        }
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            hideCornerWindows()
            return
        }
        
        print("📱 Active app: \(frontApp.localizedName ?? "Unknown")")
        
        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Get focused window
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let window = focusedWindow else {
            print("❌ No focused window")
            hideCornerWindows()
            return
        }
        
        let windowElement = window as! AXUIElement
        
        // Check if window is maximized (NOT native fullscreen)
        if isWindowFullscreen(windowElement) {
            print("✅ Showing corner windows")
            let isSafari = frontApp.localizedName == "Safari"
            showCornerWindows(for: windowElement, isSafari: isSafari)
        } else {
            hideCornerWindows()
        }
    }
    
    func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        // Check if window size matches screen size (maximized or fullscreen)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return false
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        // Get screen frame
        guard let screen = NSScreen.main else { return false }
        let visibleFrame = screen.visibleFrame
        
        // Check if window is maximized (covers most of visible screen)
        let widthRatio = size.width / visibleFrame.width
        let heightRatio = size.height / visibleFrame.height
        
        // Consider it "maximized" if it takes up at least 85% of the visible screen
        let isMaximized = widthRatio >= 0.85 && heightRatio >= 0.85
        
        return isMaximized
    }
    
    func showCornerWindows(for window: AXUIElement, isSafari: Bool) {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            print("❌ Failed to get window position/size")
            return
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        print("🪟 Window frame: (\(Int(position.x)), \(Int(position.y))) \(Int(size.width))x\(Int(size.height))")
        
        let cornerSize: CGFloat = isSafari ? 30 : 26
        
        // Create or update corner windows
        if cornerWindows.isEmpty {
            print("🔨 Creating corner windows")
            for corner in Corner.allCases {
                let cornerWindow = CornerWindow(corner: corner, size: cornerSize)
                cornerWindows.append(cornerWindow)
            }
        } else {
            // Recreate windows if size changed
            let currentSize = cornerWindows.first?.cornerSize ?? 0
            if currentSize != cornerSize {
                print("🔄 Recreating corner windows with new size: \(cornerSize)")
                hideCornerWindows()
                cornerWindows.removeAll()
                for corner in Corner.allCases {
                    let cornerWindow = CornerWindow(corner: corner, size: cornerSize)
                    cornerWindows.append(cornerWindow)
                }
            }
        }
        
        // Update positions
        for cornerWindow in cornerWindows {
            cornerWindow.updatePosition(windowFrame: CGRect(origin: position, size: size))
        }
        
        print("✨ Corner windows updated (size: \(cornerSize))")
    }
    
    func hideCornerWindows() {
        for window in cornerWindows {
            window.hide()
        }
    }
}

enum Corner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

class CornerWindow: NSWindow {
    let corner: Corner
    let cornerSize: CGFloat
    var cornerViewController: CornerViewController?
    
    init(corner: Corner, size: CGFloat) {
        self.corner = corner
        self.cornerSize = size
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .statusBar + 1 // Stay on top
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        let viewController = CornerViewController(corner: corner, size: size)
        self.cornerViewController = viewController
        self.contentView = viewController.view
    }
    
    func updatePosition(windowFrame: CGRect) {
        let x: CGFloat
        let y: CGFloat
        
        switch corner {
        case .topLeft:
            x = windowFrame.minX
            y = windowFrame.maxY - cornerSize
        case .topRight:
            x = windowFrame.maxX - cornerSize
            y = windowFrame.maxY - cornerSize
        case .bottomLeft:
            x = windowFrame.minX
            y = windowFrame.minY
        case .bottomRight:
            x = windowFrame.maxX - cornerSize
            y = windowFrame.minY
        }
        
        self.setFrame(NSRect(x: x, y: y, width: cornerSize, height: cornerSize), display: true)
        self.orderFrontRegardless()
        
        // Update the view to sample colors
        cornerViewController?.updateColors(windowFrame: windowFrame)
    }
    
    func hide() {
        self.orderOut(nil)
    }
}

class CornerViewController: NSViewController {
    let corner: Corner
    let cornerSize: CGFloat
    var cornerView: CornerView!
    
    init(corner: Corner, size: CGFloat) {
        self.corner = corner
        self.cornerSize = size
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        cornerView = CornerView(corner: corner, size: cornerSize)
        self.view = cornerView
    }
    
    func updateColors(windowFrame: CGRect) {
        cornerView.updateColors(windowFrame: windowFrame)
    }
}

class CornerView: NSView {
    let corner: Corner
    let cornerSize: CGFloat
    let sampledColor: NSColor = .black  // Always use black
    
    init(corner: Corner, size: CGFloat) {
        self.corner = corner
        self.cornerSize = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateColors(windowFrame: CGRect) {
        // Always use black - no need to sample
        self.needsDisplay = true
    }
    
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Fill with black
        context.setFillColor(sampledColor.cgColor)
        
        // We want to FILL the rounded area to make it square
        // Draw a shape that fills the gap between the rounded corner and a square corner
        // This is the area OUTSIDE the rounded curve but INSIDE the square
        let path = CGMutablePath()
        let size = cornerSize
        let radius = size // The rounded corner radius we're filling
        
        switch corner {
        case .topLeft:
            // Fill the gap in top-left corner
            // Start from the corner point and create a shape that fills the rounded gap
            path.move(to: CGPoint(x: 0, y: size))           // corner point (top-left)
            path.addLine(to: CGPoint(x: radius, y: size))   // along top edge
            path.addQuadCurve(
                to: CGPoint(x: 0, y: size - radius),        // along left edge
                control: CGPoint(x: 0, y: size)             // control point at corner
            )
            path.closeSubpath()
            
        case .topRight:
            // Fill the gap in top-right corner
            path.move(to: CGPoint(x: size, y: size))        // corner point (top-right)
            path.addLine(to: CGPoint(x: size, y: size - radius)) // along right edge
            path.addQuadCurve(
                to: CGPoint(x: size - radius, y: size),     // along top edge
                control: CGPoint(x: size, y: size)          // control point at corner
            )
            path.closeSubpath()
            
        case .bottomLeft:
            // Fill the gap in bottom-left corner
            path.move(to: CGPoint(x: 0, y: 0))              // corner point (bottom-left)
            path.addLine(to: CGPoint(x: 0, y: radius))      // along left edge
            path.addQuadCurve(
                to: CGPoint(x: radius, y: 0),               // along bottom edge
                control: CGPoint(x: 0, y: 0)                // control point at corner
            )
            path.closeSubpath()
            
        case .bottomRight:
            // Fill the gap in bottom-right corner
            path.move(to: CGPoint(x: size, y: 0))           // corner point (bottom-right)
            path.addLine(to: CGPoint(x: size - radius, y: 0)) // along bottom edge
            path.addQuadCurve(
                to: CGPoint(x: size, y: radius),            // along right edge
                control: CGPoint(x: size, y: 0)             // control point at corner
            )
            path.closeSubpath()
        }
        
        context.addPath(path)
        context.fillPath()
    }
}

// Application entry point
let app = NSApplication.shared
let delegate = MacCornerFixApp()
app.delegate = delegate
app.run()
