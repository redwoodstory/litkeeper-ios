import WebKit

/// Handles two URL patterns:
///   epub-local://app/<path>            → serves static bundle resources (epub-reader.html, foliate-js/*)
///   epub-local://epub/<storyID>/<base> → serves the .epub file, local first, then remote fallback
///
/// IMPORTANT: WKURLSchemeHandler.start() is called on the main thread.
/// Synchronously reading a large epub on the main thread deadlocks WKWebView
/// (it needs the main thread to deliver the response while we're blocking it).
/// epub file reads are dispatched to a background queue; the task completion
/// is then dispatched back to main. Static resource reads are small and sync is fine.
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {

    private let serverBase: URL?
    private let token: String?

    // Tracks tasks that were cancelled before our async read finished.
    // Accessed only on the main thread (stop() is always called on main,
    // and we dispatch completions back to main), so no lock needed.
    private var stoppedTasks = Set<ObjectIdentifier>()

    init(serverBase: URL? = nil, token: String? = nil) {
        self.serverBase = serverBase
        self.token = token
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let requestURL = urlSchemeTask.request.url!
        switch requestURL.host ?? "" {
        case "app":
            serveAppResource(urlSchemeTask: urlSchemeTask, requestURL: requestURL)
        case "epub":
            serveEPUBAsync(urlSchemeTask: urlSchemeTask, requestURL: requestURL)
        default:
            finish(urlSchemeTask, statusCode: 404)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Static bundle resources

    private func serveAppResource(urlSchemeTask: WKURLSchemeTask, requestURL: URL) {
        let relativePath = String(requestURL.path.drop(while: { $0 == "/" }))
        guard !relativePath.isEmpty, let resourceURL = Bundle.main.resourceURL else {
            finish(urlSchemeTask, statusCode: 404)
            return
        }

        let fileURL = resourceURL.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: fileURL) else {
            finish(urlSchemeTask, statusCode: 404)
            return
        }

        respond(urlSchemeTask, requestURL: requestURL, data: data,
                contentType: mimeType(for: fileURL.pathExtension))
    }

    // MARK: - EPUB files (async to avoid main-thread deadlock)

    private func serveEPUBAsync(urlSchemeTask: WKURLSchemeTask, requestURL: URL) {
        // URL path is "<storyID>/<filenameBase>"
        let path = String(requestURL.path.drop(while: { $0 == "/" }))
        guard !path.isEmpty else {
            finish(urlSchemeTask, statusCode: 404)
            return
        }

        let parts = path.split(separator: "/", maxSplits: 1)
        let storyID: Int? = parts.count == 2 ? Int(parts[0]) : nil
        let filenameBase: String = parts.count == 2 ? String(parts[1]) : path

        let localURL = DownloadManager.shared.localEPUBURL(filenameBase: filenameBase)
        let taskID = ObjectIdentifier(urlSchemeTask)
        let serverBase = self.serverBase
        let token = self.token

        DispatchQueue.global(qos: .userInitiated).async {
            // Try local file first
            if FileManager.default.fileExists(atPath: localURL.path),
               let data = try? Data(contentsOf: localURL) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.stoppedTasks.remove(taskID) == nil else { return }
                    self.respond(urlSchemeTask, requestURL: requestURL, data: data,
                                 contentType: "application/epub+zip")
                }
                return
            }

            // Remote fallback
            guard let serverBase, let storyID, let token else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.stoppedTasks.remove(taskID) == nil else { return }
                    self.finish(urlSchemeTask, statusCode: 404)
                }
                return
            }

            var request = URLRequest(url: serverBase.appendingPathComponent("epub/file/\(storyID)"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 60

            URLSession.shared.dataTask(with: request) { data, response, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.stoppedTasks.remove(taskID) == nil else { return }
                    guard let data,
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        self.finish(urlSchemeTask, statusCode: 502)
                        return
                    }
                    self.respond(urlSchemeTask, requestURL: requestURL, data: data,
                                 contentType: "application/epub+zip")
                }
            }.resume()
        }
    }

    // MARK: - Helpers

    private func respond(_ urlSchemeTask: WKURLSchemeTask, requestURL: URL,
                         data: Data, contentType: String) {
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": contentType,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*"
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func finish(_ urlSchemeTask: WKURLSchemeTask, statusCode: Int) {
        let response = HTTPURLResponse(
            url: urlSchemeTask.request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didFinish()
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html":         return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript"
        case "css":          return "text/css"
        case "json":         return "application/json"
        case "wasm":         return "application/wasm"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "svg":          return "image/svg+xml"
        default:             return "application/octet-stream"
        }
    }
}
