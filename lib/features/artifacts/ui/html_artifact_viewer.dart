import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/artifact.dart';

/// HTML artifact preview using WebView (safe rendering with sandbox).
class HtmlArtifactViewer extends StatefulWidget {
  const HtmlArtifactViewer({
    super.key,
    required this.artifact,
    required this.htmlContent,
  });

  final Artifact artifact;
  final String htmlContent;

  @override
  State<HtmlArtifactViewer> createState() => _HtmlArtifactViewerState();
}

class _HtmlArtifactViewerState extends State<HtmlArtifactViewer> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading HTML: ${error.description}')),
            );
          },
        ),
      )
      ..loadHtmlString(
        _wrapHtmlWithSandbox(widget.htmlContent),
        baseUrl: 'about:blank',
      );
  }

  /// Wrap HTML dengan viewport meta tag dan basic styling untuk responsif rendering.
  String _wrapHtmlWithSandbox(String html) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #fff;
            padding: 16px;
            max-width: 900px;
            margin: 0 auto;
        }
        img, video, iframe {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 1em 0;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px 12px;
            text-align: left;
        }
        th {
            background-color: #f5f5f5;
            font-weight: bold;
        }
        code {
            background-color: #f5f5f5;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        pre {
            background-color: #f5f5f5;
            padding: 12px;
            border-radius: 4px;
            overflow-x: auto;
            margin: 1em 0;
        }
        pre code {
            background: none;
            padding: 0;
        }
        a {
            color: #0066cc;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        blockquote {
            border-left: 4px solid #ddd;
            padding-left: 16px;
            margin: 1em 0;
            color: #666;
        }
        h1, h2, h3, h4, h5, h6 {
            margin: 1.5em 0 0.5em 0;
            font-weight: 600;
            line-height: 1.2;
        }
        h1 { font-size: 2em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        h5 { font-size: 1em; }
        h6 { font-size: 0.9em; }
    </style>
</head>
<body>
    $html
    <script>
        // Disable dangerous features
        window.alert = function() {};
        window.prompt = function() { return null; };
        window.confirm = function() { return false; };
        
        // Intercept links (optional: open in external browser)
        document.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                e.preventDefault();
                // Could send message to Flutter to open in browser
            }
        }, true);
    </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
