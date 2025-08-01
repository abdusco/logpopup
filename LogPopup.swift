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
    var scrollView: NSScrollView!
    var cliArgs: CLIArgs!
    // Terminate process when window closes
    func windowWillClose(_ notification: Notification) {
        terminateProcess()
    }
    var window: NSWindow!
    var textView: NSTextView!
    var process: Process!
    var outputPipe: Pipe!
    var errorPipe: Pipe!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up signal handler for Ctrl+C
        setupSignalHandler()
        
        // Create menu
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        let appMenu = NSMenu()
        // Quit menu item (Cmd+Q)
        appMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        appMenu.addItem(withTitle: "Exit", action: #selector(quitApp), keyEquivalent: "w")
        appMenuItem.submenu = appMenu

        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Set window title to command and bring to front
        let args = CommandLine.arguments
        let cliArgs = CLIArgs.parse(from: args)
        self.cliArgs = cliArgs
        window.title = cliArgs.command ?? "logpopup"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.delegate = self
        // Create scrollable text view
        scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)
        // Track user scroll position
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        // Run command
        runCommand()
    }

    func setupSignalHandler() {
        signal(SIGINT) { _ in
            // Get the delegate and terminate the process
            if let delegate = NSApp.delegate as? LogPopupApp {
                delegate.terminateProcess()
            }
        }
    }

    func terminateProcess() {
        if self.process.isRunning {
            self.process.terminate()
            appendOutput("\n[Process terminated by user]\n")
        }
        NSApp.terminate(nil)
    }

    func runCommand() {
        let cliArgs = self.cliArgs!
        guard let command = cliArgs.command else { return }
        process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = [command] + cliArgs.commandArgs
        process.environment = ProcessInfo.processInfo.environment

        outputPipe = Pipe()
        errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.standardInput

        // Tee output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                self?.appendOutput(str)
                FileHandle.standardOutput.write(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                self?.appendOutput(str)
                FileHandle.standardError.write(data)
            }
        }

        do {
            try process.run()
        } catch {
            appendOutput("Failed to run command: \(error)\n")
        }

        // Terminate app immediately if successful, else after 5 seconds (unless keepOnFail)
        process.terminationHandler = { [weak self] proc in
            self?.appendOutput("\n[Process exited with code: \(proc.terminationStatus)]\n")

            if proc.terminationStatus == 0 {
                NSApp.terminate(nil)
            } else if cliArgs.keepOnFail {
                // Do nothing, keep window open
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func appendOutput(_ str: String) {
        DispatchQueue.main.async {
            let font = self.textView.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: str, attributes: attributes)
            self.textView.textStorage?.append(attrStr)
            if self.shouldAutoScroll {
                self.textView.scrollToEndOfDocument(nil)
            }
        }
    }

    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard let scrollView = self.scrollView else { return }
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
        NSApp.terminate(nil)
    }

    @objc func hideApp() {
        window.orderBack(nil)
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
let delegate = LogPopupApp()
delegate.cliArgs = cliArgs
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
