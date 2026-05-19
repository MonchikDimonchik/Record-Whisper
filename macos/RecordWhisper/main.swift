import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var backend: Process?
    private var pollTimer: Timer?
    private var pollAttempts = 0
    private let port = 7860
    private let appName = "Record-Whisper"

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
        window.title = appName
        window.minSize = NSSize(width: 940, height: 680)
        window.center()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        showLoading()
    }

    private func showLoading(_ message: String = "Record-Whisper запускается. При первом запуске приложение скачает модель Whisper, это может занять несколько минут.") {
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
            .loader {
              width: 34px;
              height: 34px;
              margin-bottom: 22px;
              border: 4px solid #dfe4dc;
              border-top-color: #0f7c6b;
              border-radius: 50%;
              animation: spin 900ms linear infinite;
            }
            h1 {
              margin: 0 0 10px;
              font-size: 28px;
            }
            p {
              margin: 0;
              color: #667064;
            }
            small {
              display: block;
              margin-top: 14px;
              color: #8a9287;
              font-size: 13px;
            }
            @keyframes spin {
              to { transform: rotate(360deg); }
            }
          </style>
        </head>
        <body>
          <main>
            <div class="loader" aria-hidden="true"></div>
            <h1>Record-Whisper</h1>
            <p>\(message)</p>
            <small>Если окно долго висит здесь, откройте лог в ~/Library/Application Support/Record-Whisper/backend.log.</small>
          </main>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func startBackend() {
        let resourcesURL = Bundle.main.resourceURL!
        let backendURL = resourcesURL
            .appendingPathComponent("backend", isDirectory: true)
            .appendingPathComponent("RecordWhisperBackend", isDirectory: true)
        let executableURL = backendURL.appendingPathComponent("RecordWhisperBackend")

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            showLoading("Внутренний движок приложения не найден. Переустановите Record-Whisper.")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = backendURL

        var environment = ProcessInfo.processInfo.environment
        let appSupportPath = "\(NSHomeDirectory())/Library/Application Support/Record-Whisper"
        environment["PORT"] = "\(port)"
        environment["WHISPER_OPEN_BROWSER"] = "0"
        environment["WHISPER_DATA_DIR"] = appSupportPath
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        try? FileManager.default.createDirectory(
            atPath: appSupportPath,
            withIntermediateDirectories: true
        )
        let logPath = "\(appSupportPath)/backend.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
            backend = process
        } catch {
            showLoading("Не получилось запустить внутренний сервис: \(error.localizedDescription)")
        }
    }

    private func waitForBackend() {
        pollTimer?.invalidate()
        pollAttempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] timer in
            guard let self else { return }

            self.pollAttempts += 1
            if self.pollAttempts == 20 {
                self.showLoading("Внутренний сервис запускается дольше обычного. Проверяю дальше; лог пишется в backend.log.")
            }

            var request = URLRequest(url: self.baseURL.appendingPathComponent("health"))
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
