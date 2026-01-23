import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Only import webview on non-web platforms
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lichess Daily Puzzle',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LichessWebView(),
    );
  }
}

class LichessWebView extends StatefulWidget {
  const LichessWebView({Key? key}) : super(key: key);

  @override
  State<LichessWebView> createState() => _LichessWebViewState();
}

class _LichessWebViewState extends State<LichessWebView> {
  late WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse('https://lichess.org/training/daily'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lichess Daily Puzzle'),
      ),
      body: kIsWeb
          ? const Center(
              child: Text('Please install Visual Studio C++ tools and run on Windows desktop'),
            )
          : WebViewWidget(controller: _webViewController),
    );
  }
}
