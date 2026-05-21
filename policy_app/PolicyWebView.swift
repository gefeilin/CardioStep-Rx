//
//  PolicyWebView.swift
//  policy_app
//
//  Created by Gefei Lin on 5/21/26.
//

import SwiftUI
import WebKit

#if os(macOS)
struct PolicyWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct PolicyWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

private func makeWebView() -> WKWebView {
    let webView = WKWebView(frame: .zero)

    if let url = policyHTMLURL() {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
        webView.loadHTMLString(missingPolicyHTMLMessage, baseURL: nil)
    }

    return webView
}

private func policyHTMLURL() -> URL? {
    if let bundledURL = Bundle.main.url(forResource: "policy_app", withExtension: "html") {
        return bundledURL
    }

    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("policy_app.html")

    if FileManager.default.fileExists(atPath: sourceURL.path) {
        return sourceURL
    }

    return nil
}

private let missingPolicyHTMLMessage = """
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #17212b;
      background: #f6f7f9;
    }
    main {
      width: min(560px, calc(100vw - 40px));
      padding: 24px;
      border: 1px solid #d8dee8;
      border-radius: 8px;
      background: #fff;
    }
    h1 { margin: 0 0 8px; font-size: 22px; }
    p { margin: 0; color: #667085; line-height: 1.45; }
  </style>
</head>
<body>
  <main>
    <h1>Policy page not found</h1>
    <p>Could not load policy_app.html from the app bundle or the local source folder.</p>
  </main>
</body>
</html>
"""
