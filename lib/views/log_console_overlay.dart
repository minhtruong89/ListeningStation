import 'package:flutter/material.dart';
import '../services/log_service.dart';

class LogConsoleOverlay extends StatefulWidget {
  final Widget child;
  const LogConsoleOverlay({super.key, required this.child});

  @override
  State<LogConsoleOverlay> createState() => _LogConsoleOverlayState();
}

class _LogConsoleOverlayState extends State<LogConsoleOverlay> {
  bool _isVisible = false;
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => ValueListenableBuilder<int>(
              valueListenable: LogService.logUpdateNotifier,
              builder: (context, _, child) {
                return Stack(
                  children: [
                    widget.child,
                    // Floating button to toggle console overlay
                    if (LogService.flagWriteLogDevice)
                      Positioned(
                        top: 10,
                        right: 10,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      child: Opacity(
                        opacity: 0.5,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isVisible = !_isVisible;
                            });
                            if (_isVisible) {
                              _scrollToBottom();
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              Icons.terminal,
                              color: Colors.greenAccent,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The overlay panel
                if (_isVisible)
                  Positioned.fill(
                    child: Material(
                      color: Colors.black.withOpacity(0.9),
                      child: SafeArea(
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.white12)),
                                color: Color(0xFF1E1E1E),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.bug_report, color: Colors.redAccent),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "SYSTEM LOG CONSOLE",
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      // flagWriteLogDevice Switch
                                      Row(
                                        children: [
                                          const Text(
                                            "Ghi log:",
                                            style: TextStyle(fontSize: 12, color: Colors.white70),
                                          ),
                                          Switch(
                                            value: LogService.flagWriteLogDevice,
                                            onChanged: (val) {
                                              setState(() {
                                                LogService.flagWriteLogDevice = val;
                                              });
                                              LogService.logUpdateNotifier.value++;
                                            },
                                            activeColor: Colors.greenAccent,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.arrow_downward, color: Colors.white),
                                        tooltip: "Cuộn xuống cuối",
                                        onPressed: _scrollToBottom,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                                        tooltip: "Xóa log",
                                        onPressed: () {
                                          LogService.clear();
                                          setState(() {});
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        tooltip: "Đóng",
                                        onPressed: () {
                                          setState(() {
                                            _isVisible = false;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Logs list
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable: LogService.logUpdateNotifier,
                                builder: (context, _, child) {
                                  final logs = LogService.logs;
                                  _scrollToBottom();
                                  return ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.all(12),
                                    itemCount: logs.length,
                                    itemBuilder: (context, index) {
                                      final text = logs[index];
                                      Color textColor = Colors.white;
                                      if (text.contains("Error") || text.contains("Exception") || text.contains("fail")) {
                                        textColor = Colors.redAccent;
                                      } else if (text.contains("RULE") || text.contains("[RuleEngine]") || text.contains("[STAFF RULE]")) {
                                        textColor = Colors.yellowAccent;
                                      } else if (text.contains("TTS") || text.contains("LocalSpeechService") || text.contains("speak")) {
                                        textColor = Colors.cyanAccent;
                                      } else if (text.contains("UART") || text.contains("serial") || text.contains("SAY") || text.contains("SIL")) {
                                        textColor = Colors.greenAccent;
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: SelectableText(
                                          text,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: textColor,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
