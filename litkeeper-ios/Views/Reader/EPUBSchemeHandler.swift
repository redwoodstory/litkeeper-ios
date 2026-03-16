import WebKit

/// Handles `epub-local://<filenameBase>` requests from the foliate-js reader.
/// Maps the filenameBase to the local .epub file and streams it back.
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let requestURL = urlSchemeTask.request.url!
        // filenameBase is the host component of epub-local://<filenameBase>
        let filenameBase = requestURL.host ?? ""
        let localURL = DownloadManager.shared.localEPUBURL(filenameBase: filenameBase)

        guard !filenameBase.isEmpty,
              FileManager.default.fileExists(atPath: localURL.path),
              let data = try? Data(contentsOf: localURL) else {
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }

        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/epub+zip",
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*"
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
