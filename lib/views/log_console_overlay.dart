import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  late final FocusNode _switchFocusNode;
  late final FocusNode _scrollUpFocusNode;
  late final FocusNode _scrollDownFocusNode;
  late final FocusNode _clearFocusNode;
  late final FocusNode _closeFocusNode;

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

  void _scrollUp() {
    if (_scrollController.hasClients) {
      final double target = (_scrollController.offset - 150).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    }
  }

  void _scrollDown() {
    if (_scrollController.hasClients) {
      final double target = (_scrollController.offset + 150).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    }
  }



  @override
  void initState() {
    super.initState();
    LogService.consoleVisibilityNotifier.addListener(_onVisibilityChanged);
    LogService.logButtonFocusNode.addListener(_onFocusChanged);
    
    _switchFocusNode = FocusNode();
    _scrollUpFocusNode = FocusNode();
    _scrollDownFocusNode = FocusNode();
    _clearFocusNode = FocusNode();
    _closeFocusNode = FocusNode();

    _switchFocusNode.addListener(_onFocusChanged);
    _scrollUpFocusNode.addListener(_onFocusChanged);
    _scrollDownFocusNode.addListener(_onFocusChanged);
    _clearFocusNode.addListener(_onFocusChanged);
    _closeFocusNode.addListener(_onFocusChanged);

    KeyEventResult handleOverlayFocusTrap(FocusNode node, KeyEvent event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled; // Trap vertical navigation
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft && node == _switchFocusNode) {
          _closeFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight && node == _closeFocusNode) {
          _switchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    _switchFocusNode.onKeyEvent = handleOverlayFocusTrap;
    _scrollUpFocusNode.onKeyEvent = handleOverlayFocusTrap;
    _scrollDownFocusNode.onKeyEvent = handleOverlayFocusTrap;
    _clearFocusNode.onKeyEvent = handleOverlayFocusTrap;
    _closeFocusNode.onKeyEvent = handleOverlayFocusTrap;

    // Remote control D-pad navigation logic for the main trigger button
    LogService.logButtonFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        // ← goes to prevFocusNode (e.g. Send in conversation_view) or retryButton
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final prev = LogService.prevFocusNode;
          if (prev != null && prev.canRequestFocus) {
            prev.requestFocus();
            return KeyEventResult.handled;
          }
          if (LogService.retryButtonFocusNode != null && LogService.retryButtonFocusNode!.canRequestFocus) {
            LogService.retryButtonFocusNode!.requestFocus();
            return KeyEventResult.handled;
          }
        }
        // → goes to nextFocusNode (e.g. Mute in conversation_view) or retryButton
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final next = LogService.nextFocusNode;
          if (next != null && next.canRequestFocus) {
            next.requestFocus();
            return KeyEventResult.handled;
          }
          if (LogService.retryButtonFocusNode != null && LogService.retryButtonFocusNode!.canRequestFocus) {
            LogService.retryButtonFocusNode!.requestFocus();
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    LogService.consoleVisibilityNotifier.removeListener(_onVisibilityChanged);
    LogService.logButtonFocusNode.removeListener(_onFocusChanged);
    
    _switchFocusNode.removeListener(_onFocusChanged);
    _scrollUpFocusNode.removeListener(_onFocusChanged);
    _scrollDownFocusNode.removeListener(_onFocusChanged);
    _clearFocusNode.removeListener(_onFocusChanged);
    _closeFocusNode.removeListener(_onFocusChanged);

    _switchFocusNode.dispose();
    _scrollUpFocusNode.dispose();
    _scrollDownFocusNode.dispose();
    _clearFocusNode.dispose();
    _closeFocusNode.dispose();

    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onVisibilityChanged() {
    if (mounted) {
      setState(() {
        _isVisible = LogService.consoleVisibilityNotifier.value;
      });
      if (_isVisible) {
        _scrollToBottom();
        // Shift focus to Close button when console is opened
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _closeFocusNode.requestFocus();
          }
        });
      } else {
        // Restore focus to logButtonFocusNode when console is closed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            LogService.logButtonFocusNode.requestFocus();
          }
        });
      }
    }
  }

  Widget _buildFocusableAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required FocusNode focusNode,
    Color? iconColor,
  }) {
    final hasFocus = focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        focusNode: focusNode,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: hasFocus ? Colors.green : const Color(0xFF2E2E2E),
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: hasFocus ? Colors.white : Colors.white24,
              width: hasFocus ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: hasFocus ? Colors.white : (iconColor ?? Colors.greenAccent),
                size: 16,
              ),
              const SizedBox(width: 6.0),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: hasFocus ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusableSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required FocusNode focusNode,
  }) {
    final hasFocus = focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: InkWell(
        focusNode: focusNode,
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: hasFocus ? Colors.green : const Color(0xFF2E2E2E),
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: hasFocus ? Colors.white : Colors.white24,
              width: hasFocus ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                color: hasFocus ? Colors.white : Colors.greenAccent,
                size: 16,
              ),
              const SizedBox(width: 6.0),
              Text(
                "$label: ${value ? "BẬT" : "TẮT"}",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: hasFocus ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                        opacity: LogService.logButtonFocusNode.hasFocus ? 1.0 : 0.5,
                        child: InkWell(
                          focusNode: LogService.logButtonFocusNode,
                          onTap: () {
                            LogService.consoleVisibilityNotifier.value = !_isVisible;
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: LogService.logButtonFocusNode.hasFocus ? Colors.green : Colors.black87,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: LogService.logButtonFocusNode.hasFocus ? Colors.white : Colors.white24,
                                width: LogService.logButtonFocusNode.hasFocus ? 2.5 : 1.0,
                              ),
                            ),
                            child: Icon(
                              Icons.terminal,
                              color: LogService.logButtonFocusNode.hasFocus ? Colors.white : Colors.greenAccent,
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
                      color: Colors.black.withValues(alpha: 0.9),
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
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      // Focusable configuration and action buttons
                                      _buildFocusableSwitch(
                                        label: "Ghi log",
                                        value: LogService.flagWriteLogDevice,
                                        onChanged: (val) {
                                          setState(() {
                                            LogService.flagWriteLogDevice = val;
                                          });
                                          LogService.logUpdateNotifier.value++;
                                        },
                                        focusNode: _switchFocusNode,
                                      ),
                                      _buildFocusableAction(
                                        icon: Icons.arrow_upward,
                                        label: "Lên",
                                        onPressed: _scrollUp,
                                        focusNode: _scrollUpFocusNode,
                                      ),
                                      _buildFocusableAction(
                                        icon: Icons.arrow_downward,
                                        label: "Xuống",
                                        onPressed: _scrollDown,
                                        focusNode: _scrollDownFocusNode,
                                      ),
                                      _buildFocusableAction(
                                        icon: Icons.delete_sweep,
                                        label: "Xóa",
                                        onPressed: () {
                                          LogService.clear();
                                          setState(() {});
                                        },
                                        focusNode: _clearFocusNode,
                                        iconColor: Colors.redAccent,
                                      ),
                                      _buildFocusableAction(
                                        icon: Icons.close,
                                        label: "Đóng",
                                        onPressed: () {
                                          LogService.consoleVisibilityNotifier.value = false;
                                        },
                                        focusNode: _closeFocusNode,
                                        iconColor: Colors.white,
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
