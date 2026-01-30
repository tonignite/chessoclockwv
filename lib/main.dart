import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chess O'Clock",
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AlarmSettingsPage(),
        '/puzzle': (context) => const LichessWebView(),
      },
    );
  }
}

class AlarmSettingsPage extends StatefulWidget {
  const AlarmSettingsPage({super.key});

  @override
  State<AlarmSettingsPage> createState() => _AlarmSettingsPageState();
}

class _AlarmSettingsPageState extends State<AlarmSettingsPage> {
  List<TimeOfDay> _alarms = [];

  @override
  void initState() {
    super.initState();
    _loadAlarms();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    // Listen for alarm ring to show the puzzle if app is open
    Alarm.ringStream.stream.listen((_) {
      Navigator.pushNamed(context, '/puzzle');
    });
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? alarmStrings = prefs.getStringList('alarms');
    if (alarmStrings != null) {
      setState(() {
        _alarms = alarmStrings.map((s) {
          final split = s.split(':');
          return TimeOfDay(hour: int.parse(split[0]), minute: int.parse(split[1]));
        }).toList();
      });
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmStrings = _alarms.map((t) => '${t.hour}:${t.minute}').toList();
    await prefs.setStringList('alarms', alarmStrings);
  }

  Future<void> _scheduleAlarm(TimeOfDay time, int id) async {
    final now = DateTime.now();
    DateTime scheduleTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    
    // If the time is already passed today, schedule for tomorrow
    if (scheduleTime.isBefore(now)) {
      scheduleTime = scheduleTime.add(const Duration(days: 1));
    }

    final alarmSettings = AlarmSettings(
      id: id,
      dateTime: scheduleTime,
      assetAudioPath: 'assets/alarm.mp3', // Note: You need to add this file to assets
      loopAudio: true,
      vibrate: true,
      volumeMax: true,
      fadeDuration: 3.0,
      notificationTitle: 'Chess Puzzle Alarm!',
      notificationBody: 'Solve the puzzle to stop the noise.',
      enableNotificationOnKill: true,
    );

    await Alarm.set(alarmSettings: alarmSettings);
  }

  void _addAlarm() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _alarms.add(picked);
      });
      _saveAlarms();
      _scheduleAlarm(picked, _alarms.length);
    }
  }

  void _deleteAlarm(int index) async {
    await Alarm.stop(index + 1);
    setState(() {
      _alarms.removeAt(index);
    });
    _saveAlarms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Chess O'Clock Alarms")),
      body: _alarms.isEmpty
          ? const Center(child: Text("No alarms set (24h format)"))
          : ListView.builder(
              itemCount: _alarms.length,
              itemBuilder: (context, index) {
                final alarm = _alarms[index];
                return ListTile(
                  title: Text(
                    "${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}",
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteAlarm(index),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAlarm,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pushNamed(context, '/puzzle'),
          child: const Text("TEST PUZZLE LOCK", style: TextStyle(color: Colors.white)),
        ),
      ),
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
  bool _isSolved = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _injectCSS();
            _injectInterceptor();
            _fixViewport();
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

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _fixViewport() {
    _webViewController.runJavaScript("""
      var meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
      document.getElementsByTagName('head')[0].appendChild(meta);
    """);
  }

  void _injectCSS() {
    const String css = """
      html, body, main, #main-wrap, .round, .puzzle__main, .puzzle__board {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        height: 100% !important;
        max-width: none !important;
        overflow: hidden !important;
        position: fixed !important;
        left: 0 !important;
        top: 0 !important;
        background: black !important;
      }

      header, footer, #top, .site-header, .site-footer,
      .puzzle__side, .puzzle__tools, .puzzle__controls, .puzzle__session,
      .analyse-controls, .site-title, .site-buttons,
      .ready-to-play, .copy-it, .round__side, .puzzles-side,
      .round__app__sidebar, .side-menu { 
        display: none !important; 
        visibility: hidden !important;
      }
      
      .puzzle__main { 
        display: flex !important;
        justify-content: center !important;
        align-items: center !important;
        width: 100vw !important; 
        height: 100vw !important;
      }
      
      .main-board, .cg-wrap, cg-board {
        width: 100vw !important;
        height: 100vw !important;
        touch-action: auto !important;
      }
    """;
    _webViewController.runJavaScript("""
      (function() {
        const style = document.createElement('style');
        style.innerHTML = `$css`;
        document.head.appendChild(style);
        
        const observer = new MutationObserver(() => {
          if (!document.head.contains(style)) document.head.appendChild(style);
          document.body.style.padding = '0px';
          document.body.style.margin = '0px';
          const main = document.querySelector('main');
          if (main) {
            main.style.padding = '0px';
            main.style.margin = '0px';
          }
        });
        observer.observe(document.body, { childList: true, subtree: true, attributes: true });

        document.body.addEventListener('touchmove', function(e) {
          if (!e.target.closest('cg-board')) { e.preventDefault(); }
        }, { passive: false });
      })();
    """);
  }

  void _injectInterceptor() {
    _webViewController.runJavaScript("""
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
                const clone = resource.clone();
                bodyText = await clone.text();
              } else if (config.body) {
                if (config.body instanceof URLSearchParams || config.body instanceof FormData) {
                  bodyText = JSON.stringify(Object.fromEntries(config.body.entries()));
                } else { bodyText = config.body; }
              }
              InterceptChannel.postMessage(JSON.stringify({ url: url, body: bodyText }));
            } catch (e) {}
          }
          return originalFetch(...args);
        };
      })();
    """);
  }

  void _handleInterceptedData(String data) {
    try {
      final decoded = jsonDecode(data);
      final rawBody = decoded['body'];
      Map body = (rawBody is String) ? jsonDecode(rawBody) : rawBody;
      if (body.containsKey('win') && (body['win'] == true || body['win'] == 'true')) {
        setState(() => _isSolved = true);
        Alarm.stopAll(); // Silence the alarm when puzzle is solved
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isSolved,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("SOLVE THE PUZZLE TO EXIT")),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                "PUZZLE LOCK ACTIVE",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.width,
                  child: WebViewWidget(controller: _webViewController),
                ),
              ),
              const Spacer(),
              if (_isSolved)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ElevatedButton(
                    onPressed: () {
                      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      SystemNavigator.pop(); // Close the app
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: const Text("STOP ALARM & CLOSE APP", style: TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
