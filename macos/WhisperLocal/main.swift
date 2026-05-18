import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var backend: Process?
    private var pollTimer: Timer?
    private let port = 7860

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        startBackend()
        waitForBackend()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pollTimer?.invalidate()
        stopBackend()
        return .terminateNow
    }

    private func buildWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Whisper Local"
        window.minSize = NSSize(width: 940, height: 680)
        window.center()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        showLoading()
    }

    private func showLoading(_ message: String = "Whisper Local запускается. При первом запуске приложение скачает Python-пакеты и модель Whisper, это может занять несколько минут.") {
        let html = """
        <!doctype html>
        <html lang="ru">
        <head>
          <meta charset="utf-8">
          <style>
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background: #f7f8f5;
              color: #20241f;
              font: 18px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            main {
              width: min(520px, calc(100vw - 48px));
              line-height: 1.45;
            }
            h1 {
              margin: 0 0 10px;
              font-size: 28px;
            }
            p {
              margin: 0;
              color: #667064;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>Whisper Local</h1>
            <p>\(message)</p>
          </main>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func startBackend() {
        let resourcesURL = Bundle.main.resourceURL!
        let appURL = resourcesURL.appendingPathComponent("app", isDirectory: true)
        let launcherURL = appURL.appendingPathComponent("desktop_run.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [launcherURL.path]
        process.currentDirectoryURL = appURL

        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = "\(port)"
        environment["WHISPER_OPEN_BROWSER"] = "0"
        process.environment = environment

        do {
            try process.run()
            backend = process
        } catch {
            showLoading("Не получилось запустить внутренний сервис: \(error.localizedDescription)")
        }
    }

    private func waitForBackend() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] timer in
            guard let self else { return }

            var request = URLRequest(url: self.baseURL.appendingPathComponent("config"))
            request.timeoutInterval = 0.5

            URLSession.shared.dataTask(with: request) { _data, response, _error in
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    return
                }

                DispatchQueue.main.async {
                    timer.invalidate()
                    self.pollTimer = nil
                    self.webView.load(URLRequest(url: self.baseURL))
                }
            }.resume()
        }
    }

    private func stopBackend() {
        guard let shutdownURL = URL(string: "/shutdown", relativeTo: baseURL) else {
            backend?.terminate()
            return
        }

        var request = URLRequest(url: shutdownURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 0.7

        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 1.0)

        if backend?.isRunning == true {
            backend?.terminate()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
