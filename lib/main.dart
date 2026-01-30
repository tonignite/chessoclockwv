import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Note: If you want to strictly ignore SSL errors, you'd need the webview_flutter_android package
// but let's first fix the Interceptor and CSS which are the primary issues.

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chess O'Clock",
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const LichessWebView(),
    );
  }
}

class LichessWebView extends StatefulWidget {
  const LichessWebView({super.key});

  @override
  State<LichessWebView> createState() => _LichessWebViewState();
}

class _LichessWebViewState extends State<LichessWebView> {
  late final WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent("Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36")
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              _injectCSS();
              _injectInterceptor();
            },
          ),
        )
        ..addJavaScriptChannel(
          'InterceptChannel',
          onMessageReceived: (JavaScriptMessage message) {
            _handleInterceptedData(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://lichess.org/training/daily'));
    }
  }

  void _injectCSS() {
    const String css = """
      /* Hide all UI elements except the board */
      header, footer, #top, .site-header, .site-footer, 
      .puzzle__side, .puzzle__tools, .puzzle__controls, 
      .analyse-controls, .site-title, .site-buttons, 
      .ready-to-play, .copy-it { 
        display: none !important; 
      }
      /* Center and expand the board */
      .puzzle__main { 
        margin: 0 !important; 
        padding: 0 !important;
        width: 100vw !important; 
        max-width: 100vw !important; 
      }
      .main-board { 
        max-height: 80vh !important; 
      }
    """;

    const String js = """
      (function() {
        const style = document.createElement('style');
        style.innerHTML = `$css`;
        document.head.appendChild(style);

        // MutationObserver to ensure elements STAY hidden if Lichess re-renders
        const observer = new MutationObserver(() => {
          if (!document.head.contains(style)) document.head.appendChild(style);
        });
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    """;
    _webViewController.runJavaScript(js);
  }

  void _injectInterceptor() {
    const String jsInterceptor = """
      (function() {
        const { fetch: originalFetch } = window;
        window.fetch = async (...args) => {
          const resource = args[0];
          const config = args[1] || {};
          const url = (typeof resource === 'string') ? resource : resource.url;
          
          if (url.includes('/training/complete/')) {
            let bodyText = "";
            
            try {
              if (resource instanceof Request) {
                // Clone the request to read the body without consuming the original
                const clone = resource.clone();
                bodyText = await clone.text();
              } else if (config.body) {
                if (config.body instanceof URLSearchParams || config.body instanceof FormData) {
                  bodyText = JSON.stringify(Object.fromEntries(config.body.entries()));
                } else {
                  bodyText = config.body;
                }
              }

              InterceptChannel.postMessage(JSON.stringify({
                url: url,
                body: bodyText
              }));
            } catch (e) {
              console.error("Intercept Error:", e);
            }
          }
          return originalFetch(...args);
        };
      })();
    """;
    _webViewController.runJavaScript(jsInterceptor);
  }

  void _handleInterceptedData(String data) {
    try {
      final decoded = jsonDecode(data);
      final rawBody = decoded['body'];

      // Lichess sends JSON strings in the body
      Map<String, dynamic> body = {};
      if (rawBody is String) {
        try { body = jsonDecode(rawBody); } catch(_) {}
      } else if (rawBody is Map) {
        body = Map<String, dynamic>.from(rawBody);
      }

      debugPrint('INTERCEPTED PAYLOAD: $body');

      if (body.containsKey('win')) {
        bool win = body['win'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(win ? 'SOLVED ✅' : 'FAILED ❌'),
            backgroundColor: win ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Parsing Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chess O'Clock"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _webViewController.reload())
        ],
      ),
      body: kIsWeb
          ? const Center(child: Text('Run on Android'))
          : WebViewWidget(controller: _webViewController),
    );
  }
}