import Foundation
import AppKit

var version = "dev" // to be replaced in CI

struct CLIArgs {
    var keepOnFail: Bool
    var showHelp: Bool
    var showVersion: Bool
    var command: String?
    var commandArgs: [String]

    static let usageText = """
logpopup executes a command and shows its output in a popup window.
It combines stdout and stderr and tees the output to both the popup and the terminal.

Usage: logpopup [--keep-on-fail] [--help] [--version] <command> [args...]

Options:
  --keep-on-fail   Keep window open if command fails
  --help           Show this help message and exit
  --version        Show version and exit
"""

    static func parse(from args: [String]) -> CLIArgs {
        var keepOnFail = false
        var showHelp = false
        var showVersion = false
        var command: String? = nil
        var commandArgs: [String] = []
        var i = 1
        while i < args.count {
            let arg = args[i]
            if arg == "--keep-on-fail" {
                keepOnFail = true
                i += 1
            } else if arg == "--help" {
                showHelp = true
                i += 1
            } else if arg == "--version" {
                showVersion = true
                i += 1
            } else if arg.hasPrefix("--") {
                // Unknown flag, skip
                i += 1
            } else {
                command = arg
                commandArgs = Array(args.dropFirst(i + 1))
                break
            }
        }
        return CLIArgs(
            keepOnFail: keepOnFail,
            showHelp: showHelp,
            showVersion: showVersion,
            command: command,
            commandArgs: commandArgs
        )
    }
}

class LogPopupApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var shouldAutoScroll = true
    var scrollView: NSScrollView?
    let cliArgs: CLIArgs
    private var signalSource: DispatchSourceSignal?
    var window: NSWindow?
    var textView: NSTextView?
    var process: Process?
    var outputPipe: Pipe?
    var errorPipe: Pipe?
    
    init(cliArgs: CLIArgs) {
        self.cliArgs = cliArgs
        super.init()
    }
    
    deinit {
        cleanup()
    }
    
    func windowWillClose(_ notification: Notification) {
        terminateProcess()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSignalHandler()
        setupMenu()
        setupWindow()
        setupTextView()
        runCommand()
    }
    
    private func setupMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        appMenu.addItem(withTitle: "Exit", action: #selector(quitApp), keyEquivalent: "w")
        appMenuItem.submenu = appMenu
    }
    
    private func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.title = cliArgs.command ?? "logpopup"
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.delegate = self
    }
    
    private func setupTextView() {
        guard let window = window, let contentView = window.contentView else { return }
        
        scrollView = NSScrollView(frame: contentView.bounds)
        scrollView?.hasVerticalScroller = true
        scrollView?.hasHorizontalScroller = false
        scrollView?.autoresizingMask = [.width, .height]
        
        textView = NSTextView(frame: scrollView?.contentView.bounds ?? .zero)
        textView?.isEditable = false
        textView?.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView?.autoresizingMask = [.width, .height]
        
        scrollView?.documentView = textView
        contentView.addSubview(scrollView!)
        
        // Track user scroll position
        scrollView?.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView?.contentView
        )
    }

    func setupSignalHandler() {
        signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource?.setEventHandler { [weak self] in
            self?.terminateProcess()
        }
        signalSource?.resume()
        
        // Ignore SIGINT for the process (let DispatchSource handle it)
        signal(SIGINT, SIG_IGN)
    }
    
    private func cleanup() {
        NotificationCenter.default.removeObserver(self)
        
        signalSource?.cancel()
        signalSource = nil
        
        cleanupProcess()
    }
    
    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        if let process = process, process.isRunning {
            process.terminate()
        }
        
        outputPipe = nil
        errorPipe = nil
        process = nil
    }

    func terminateProcess() {
        if let process = process, process.isRunning {
            process.terminate()
            appendOutput("\n[Process terminated by user]\n")
        }
        cleanup()
        NSApp.terminate(nil)
    }

    func runCommand() {
        guard let command = cliArgs.command else { 
            appendOutput("Error: No command specified\n")
            return 
        }
        
        process = Process()
        
        process?.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process?.arguments = [command] + cliArgs.commandArgs
        process?.environment = ProcessInfo.processInfo.environment

        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        process?.standardInput = FileHandle.standardInput

        // Tee output with better error handling
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                self?.appendOutput(str)
                do {
                    try FileHandle.standardOutput.write(contentsOf: data)
                } catch {
                    // Handle write error silently to avoid crashes
                }
            }
        }
        
        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                self?.appendOutput(str)
                do {
                    try FileHandle.standardError.write(contentsOf: data)
                } catch {
                    // Handle write error silently to avoid crashes
                }
            }
        }

        do {
            try process?.run()
        } catch {
            appendOutput("Failed to run command: \(error)\n")
            return
        }

        // Terminate app immediately if successful, else after 5 seconds (unless keepOnFail)
        process?.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.appendOutput("\n[Process exited with code: \(proc.terminationStatus)]\n")

                if proc.terminationStatus == 0 {
                    NSApp.terminate(nil)
                } else if self?.cliArgs.keepOnFail == true {
                    // Do nothing, keep window open
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    func appendOutput(_ str: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let textView = self.textView else { return }
            
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: str, attributes: attributes)
            textView.textStorage?.append(attrStr)
            
            if self.shouldAutoScroll {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = scrollView else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentRect = scrollView.documentView?.bounds ?? .zero
        // If at the bottom, enable auto-scroll
        if abs(visibleRect.maxY - documentRect.maxY) < 2.0 {
            shouldAutoScroll = true
        } else {
            shouldAutoScroll = false
        }
    }

    @objc func quitApp() {
        cleanup()
        NSApp.terminate(nil)
    }

    @objc func hideApp() {
        window?.orderBack(nil)
    }
}

let cliArgs = CLIArgs.parse(from: CommandLine.arguments)
if cliArgs.showHelp {
    print(CLIArgs.usageText)
    exit(0)
}
if cliArgs.showVersion {
    print("logpopup version: " + version)
    exit(0)
}

let app = NSApplication.shared
let delegate = LogPopupApp(cliArgs: cliArgs)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
