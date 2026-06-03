import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/conversation_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({super.key});

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final FocusNode _inputFocusNode;
  late final FocusNode _muteButtonFocusNode;
  late final FocusNode _demoButtonFocusNode;
  late final FocusNode _finalizeButtonFocusNode;

  // New Voice & Send button FocusNodes
  late final FocusNode _voiceButtonFocusNode;
  late final FocusNode _sendButtonFocusNode;

  // Focus nodes for popup buttons
  late final FocusNode _closeSummaryButtonFocusNode;
  late final FocusNode _cancelFinalizeButtonFocusNode;
  late final FocusNode _confirmFinalizeButtonFocusNode;
  late final FocusNode _goToResultButtonFocusNode;

  bool _isMuteFocused = false;
  bool _isDemoFocused = false;
  bool _isFinalizeFocused = false;
  bool _isInputFocused = false;
  bool _isVoiceFocused = false;
  bool _isSendFocused = false;

  // Focus states for popup buttons
  bool _isCloseSummaryFocused = false;
  bool _isCancelFinalizeFocused = false;
  bool _isConfirmFinalizeFocused = false;
  bool _isGoToResultFocused = false;

  // Track previous visibility states to detect changes
  bool _prevIsSummaryVisible = false;
  bool _prevIsFinalizeVisible = false;
  bool _prevIsFinalizeConfirmed = false;

  // Optimize scrolling triggers on weak Android Box hardware
  int _lastMessageCount = 0;

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _muteButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _voiceButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleVoiceKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _demoButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _inputFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _sendButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSendKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _finalizeButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _voiceButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleMuteKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _voiceButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _demoButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleDemoKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _voiceButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _muteButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _finalizeButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleFinalizeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _voiceButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _demoButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCancelFinalizeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _confirmFinalizeButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleConfirmFinalizeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _cancelFinalizeButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode(onKeyEvent: _handleInputKeyEvent);
    _muteButtonFocusNode = FocusNode(onKeyEvent: _handleMuteKeyEvent);
    _demoButtonFocusNode = FocusNode(onKeyEvent: _handleDemoKeyEvent);
    _finalizeButtonFocusNode = FocusNode(onKeyEvent: _handleFinalizeKeyEvent);
    _voiceButtonFocusNode = FocusNode(onKeyEvent: _handleVoiceKeyEvent);
    _sendButtonFocusNode = FocusNode(onKeyEvent: _handleSendKeyEvent);

    _closeSummaryButtonFocusNode = FocusNode();
    _cancelFinalizeButtonFocusNode = FocusNode(onKeyEvent: _handleCancelFinalizeKeyEvent);
    _confirmFinalizeButtonFocusNode = FocusNode(onKeyEvent: _handleConfirmFinalizeKeyEvent);
    _goToResultButtonFocusNode = FocusNode();

    _inputFocusNode.addListener(() {
      if (mounted) setState(() => _isInputFocused = _inputFocusNode.hasFocus);
    });
    _muteButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isMuteFocused = _muteButtonFocusNode.hasFocus);
    });
    _demoButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isDemoFocused = _demoButtonFocusNode.hasFocus);
    });
    _finalizeButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isFinalizeFocused = _finalizeButtonFocusNode.hasFocus);
    });
    _voiceButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isVoiceFocused = _voiceButtonFocusNode.hasFocus);
    });
    _sendButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isSendFocused = _sendButtonFocusNode.hasFocus);
    });

    _closeSummaryButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isCloseSummaryFocused = _closeSummaryButtonFocusNode.hasFocus);
    });
    _cancelFinalizeButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isCancelFinalizeFocused = _cancelFinalizeButtonFocusNode.hasFocus);
    });
    _confirmFinalizeButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isConfirmFinalizeFocused = _confirmFinalizeButtonFocusNode.hasFocus);
    });
    _goToResultButtonFocusNode.addListener(() {
      if (mounted) setState(() => _isGoToResultFocused = _goToResultButtonFocusNode.hasFocus);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _muteButtonFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _chatInputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _muteButtonFocusNode.dispose();
    _demoButtonFocusNode.dispose();
    _finalizeButtonFocusNode.dispose();
    _voiceButtonFocusNode.dispose();
    _sendButtonFocusNode.dispose();
    _closeSummaryButtonFocusNode.dispose();
    _cancelFinalizeButtonFocusNode.dispose();
    _confirmFinalizeButtonFocusNode.dispose();
    _goToResultButtonFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppStyles.backgroundStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: const BorderSide(color: AppStyles.glassCardBorder),
        ),
        title: const Text(
          "XÁC NHẬN THOÁT",
          style: TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Bạn có chắc chắn muốn thoát ứng dụng?",
          style: TextStyle(color: AppStyles.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("HỦY", style: TextStyle(color: AppStyles.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              SystemNavigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("THOÁT"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConversationViewModel>();
    final mainVm = context.read<MainViewModel>();

    final Size screenSize = MediaQuery.of(context).size;
    double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);
    scale = 1.5; // 1.5 - 1.2

    // Manage focus transitions based on popup visibility changes
    if (vm.isSummaryVisible && !_prevIsSummaryVisible) {
      _prevIsSummaryVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closeSummaryButtonFocusNode.requestFocus();
      });
    } else if (!vm.isSummaryVisible && _prevIsSummaryVisible) {
      _prevIsSummaryVisible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _muteButtonFocusNode.requestFocus();
      });
    }

    if (vm.isFinalizeVisible && !_prevIsFinalizeVisible) {
      _prevIsFinalizeVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _confirmFinalizeButtonFocusNode.requestFocus();
      });
    } else if (!vm.isFinalizeVisible && _prevIsFinalizeVisible) {
      _prevIsFinalizeVisible = false;
      _prevIsFinalizeConfirmed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _muteButtonFocusNode.requestFocus();
      });
    }

    if (vm.isFinalizeConfirmed && !_prevIsFinalizeConfirmed) {
      _prevIsFinalizeConfirmed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _goToResultButtonFocusNode.requestFocus();
      });
    }

    // Auto-scroll only when new messages are added to prevent loop-scrolling and stutter on TV Boxes
    if (vm.messages.length > _lastMessageCount) {
      _lastMessageCount = vm.messages.length;
      _scrollToBottom();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (vm.isSummaryVisible) {
          vm.closeSummary();
          return;
        }
        if (vm.isFinalizeVisible) {
          vm.cancelFinalize();
          return;
        }
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Landscape split Row
              Padding(
                padding: EdgeInsets.all(24.0 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TOP CONTROL BAR: Horizontal row of controls
                    Row(
                      children: [
                        // Current system state indicator
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.0 * scale, vertical: 10.0 * scale),
                          decoration: AppStyles.glassDecoration(radius: 8.0 * scale),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10.0 * scale,
                                height: 10.0 * scale,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: vm.isProcessing ? AppStyles.warningColor : AppStyles.successColor,
                                ),
                              ),
                              SizedBox(width: 8.0 * scale),
                              Text(
                                vm.isProcessing ? "Đang xử lý phản hồi..." : "Trợ lý hoạt động",
                                style: TextStyle(
                                  color: vm.isProcessing ? AppStyles.warningColor : AppStyles.successColor,
                                  fontSize: 13.0 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.0 * scale),
  
                        // Mute Speech button
                        ElevatedButton.icon(
                          focusNode: _muteButtonFocusNode,
                          onPressed: () => vm.toggleMute(),
                          icon: Icon(vm.isMuted ? Icons.volume_off : Icons.volume_up, size: 18.0 * scale),
                          label: Text(
                            vm.isMuted ? "BẬT ÂM" : "TẮT ÂM",
                            style: TextStyle(fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: vm.isMuted 
                                ? AppStyles.warningColor 
                                : (_isMuteFocused ? AppStyles.primaryAccent : AppStyles.primaryAccent.withValues(alpha: 0.7)),
                            foregroundColor: AppStyles.backgroundEnd,
                            padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 14.0 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                            side: _isMuteFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                            elevation: _isMuteFocused ? 12.0 : 0.0,
                          ),
                        ),
                        SizedBox(width: 12.0 * scale),
  
                        // Run Demo script button
                        ElevatedButton.icon(
                          focusNode: _demoButtonFocusNode,
                          onPressed: () => vm.runDemoModeAsync(),
                          icon: Icon(Icons.slideshow, size: 18.0 * scale),
                          label: Text(
                            "CHẠY KỊCH BẢN DEMO",
                            style: TextStyle(fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isDemoFocused ? AppStyles.primaryAccent : AppStyles.glassCardBg,
                            foregroundColor: _isDemoFocused ? AppStyles.backgroundEnd : AppStyles.textPrimary,
                            surfaceTintColor: Colors.transparent,
                            side: BorderSide(
                              color: _isDemoFocused ? Colors.white : AppStyles.glassCardBorder,
                              width: _isDemoFocused ? 3.0 * scale : 1.0,
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 14.0 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                            elevation: _isDemoFocused ? 12.0 : 0.0,
                          ),
                        ),
                        
                        const Spacer(),
  
                        // Stop / Finalize Button
                        ElevatedButton.icon(
                          focusNode: _finalizeButtonFocusNode,
                          onPressed: () => vm.showFinalizeAsync(),
                          icon: Icon(Icons.check_circle_outline, size: 18.0 * scale),
                          label: Text(
                            "KẾT THÚC HỘI THOẠI & PHÊ DUYỆT",
                            style: TextStyle(fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isFinalizeFocused ? AppStyles.errorColor : AppStyles.errorColor.withValues(alpha: 0.7),
                            foregroundColor: AppStyles.textPrimary,
                            padding: EdgeInsets.symmetric(horizontal: 20.0 * scale, vertical: 14.0 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                            side: _isFinalizeFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                            elevation: _isFinalizeFocused ? 12.0 : 0.0,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.0 * scale),

                    // FULL WIDTH: Chat dialogue bubble history stream
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.all(16.0 * scale),
                        decoration: AppStyles.glassDecoration(radius: 16.0 * scale),
                        child: Column(
                          children: [
                            Text(
                              "HỘI THOẠI TRỰC TIẾP",
                              style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                            ),
                            SizedBox(height: 12.0 * scale),
                            
                            // Scrollable list of chat bubbles
                            Expanded(
                              child: vm.messages.isEmpty
                                  ? Center(
                                      child: Text(
                                        "Bắt đầu nói chuyện...",
                                        style: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      itemCount: vm.messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = vm.messages[index];
                                        final isPatient = msg.sender == "Người cần giúp đỡ" || msg.sender == "Patient";
                                        final isSystem = msg.sender == "System";
  
                                        if (isSystem) {
                                          return Center(
                                            child: Container(
                                              margin: EdgeInsets.symmetric(vertical: 8.0 * scale),
                                              padding: EdgeInsets.symmetric(horizontal: 12.0 * scale, vertical: 4.0 * scale),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(12.0 * scale),
                                              ),
                                              child: Text(
                                                msg.content,
                                                style: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                              ),
                                            ),
                                          );
                                        }
  
                                        return Align(
                                          alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Container(
                                            margin: EdgeInsets.symmetric(vertical: 6.0 * scale),
                                            padding: EdgeInsets.all(14.0 * scale),
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.55,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isPatient
                                                  ? AppStyles.secondaryAccent.withValues(alpha: 0.35)
                                                  : AppStyles.glassCardBorder.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(16.0 * scale),
                                                topRight: Radius.circular(16.0 * scale),
                                                bottomLeft: isPatient ? Radius.circular(16.0 * scale) : Radius.zero,
                                                bottomRight: isPatient ? Radius.zero : Radius.circular(16.0 * scale),
                                              ),
                                              border: Border.all(
                                                color: isPatient
                                                    ? AppStyles.secondaryAccent.withValues(alpha: 0.5)
                                                    : AppStyles.glassCardBorder,
                                                width: 1.0 * scale,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  msg.sender,
                                                  style: AppStyles.caption.copyWith(
                                                    color: isPatient ? AppStyles.secondaryAccent : AppStyles.primaryAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12.0 * scale,
                                                  ),
                                                ),
                                                SizedBox(height: 6.0 * scale),
                                                Text(
                                                  msg.content,
                                                  style: AppStyles.bodyLarge.copyWith(
                                                    fontWeight: FontWeight.normal,
                                                    fontSize: 16.0 * scale,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            SizedBox(height: 12.0 * scale),
  
                            // User text manual override input row
                            Row(
                              children: [
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    decoration: AppStyles.glassDecoration(
                                      radius: 12.0 * scale,
                                      borderColor: _isInputFocused ? Colors.white : AppStyles.glassCardBorder,
                                    ).copyWith(
                                      boxShadow: _isInputFocused ? [
                                        BoxShadow(
                                          color: AppStyles.primaryAccent.withValues(alpha: 0.4),
                                          blurRadius: 8.0 * scale,
                                          spreadRadius: 2.0 * scale,
                                        )
                                      ] : null,
                                    ),
                                    padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                                    child: TextField(
                                      focusNode: _inputFocusNode,
                                      controller: _chatInputController,
                                      style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                                      decoration: InputDecoration(
                                        hintText: "Nhập phản hồi của bệnh nhân...",
                                        hintStyle: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          vm.userInput = val;
                                          vm.sendMessageAsync();
                                          _chatInputController.clear();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12.0 * scale),
                                SizedBox(
                                  height: 50.0 * scale,
                                  child: ElevatedButton(
                                    focusNode: _voiceButtonFocusNode,
                                    onPressed: () async {
                                      final text = await vm.startVoiceInputAsync();
                                      if (text != null && text.trim().isNotEmpty) {
                                        _chatInputController.text = text;
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isVoiceFocused ? AppStyles.secondaryAccent : AppStyles.glassCardBg,
                                      foregroundColor: _isVoiceFocused ? AppStyles.backgroundEnd : AppStyles.textPrimary,
                                      surfaceTintColor: Colors.transparent,
                                      side: BorderSide(
                                        color: _isVoiceFocused ? Colors.white : AppStyles.glassCardBorder,
                                        width: _isVoiceFocused ? 3.0 * scale : 1.0,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0 * scale)),
                                      elevation: _isVoiceFocused ? 12.0 : 0.0,
                                    ),
                                    child: Icon(Icons.mic, size: 18.0 * scale),
                                  ),
                                ),
                                SizedBox(width: 12.0 * scale),
                                SizedBox(
                                  height: 50.0 * scale,
                                  child: ElevatedButton(
                                    focusNode: _sendButtonFocusNode,
                                    onPressed: () {
                                      final val = _chatInputController.text;
                                      if (val.trim().isNotEmpty) {
                                        vm.userInput = val;
                                        vm.sendMessageAsync();
                                        _chatInputController.clear();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isSendFocused ? AppStyles.primaryAccent : AppStyles.primaryAccent.withValues(alpha: 0.7),
                                      foregroundColor: AppStyles.backgroundEnd,
                                      side: _isSendFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0 * scale)),
                                      elevation: _isSendFocused ? 12.0 : 0.0,
                                    ),
                                    child: Icon(Icons.send, size: 18.0 * scale),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
 
              // OVERLAY DIALOG: Summary details popup
              if (vm.isSummaryVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 600.0 * scale,
                      height: 450.0 * scale,
                      padding: EdgeInsets.all(28.0 * scale),
                      decoration: AppStyles.glassDecoration(
                        borderColor: AppStyles.primaryAccent,
                        radius: 16.0 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.assignment, color: AppStyles.primaryAccent, size: 28.0 * scale),
                                  SizedBox(width: 12.0 * scale),
                                  Text(
                                    "TÓM TẮT THÔNG TIN HỘI THOẠI",
                                    style: AppStyles.titleLarge.copyWith(fontSize: 24.0 * scale),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => vm.closeSummary(),
                                icon: Icon(Icons.close, color: AppStyles.textSecondary, size: 24.0 * scale),
                              )
                            ],
                          ),
                          SizedBox(height: 16.0 * scale),
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.all(16.0 * scale),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8.0 * scale),
                                border: Border.all(color: AppStyles.glassCardBorder),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  vm.summaryResult,
                                  style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale, height: 1.5),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 20.0 * scale),
                          SizedBox(
                            height: 45.0 * scale,
                            child: ElevatedButton(
                              focusNode: _closeSummaryButtonFocusNode,
                              onPressed: () => vm.closeSummary(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isCloseSummaryFocused ? AppStyles.primaryAccent : AppStyles.primaryAccent.withValues(alpha: 0.7),
                                foregroundColor: AppStyles.backgroundEnd,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                                side: _isCloseSummaryFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                                elevation: _isCloseSummaryFocused ? 12.0 : 0.0,
                              ),
                              child: Text(
                                "ĐÓNG TÓM TẮT",
                                style: TextStyle(fontSize: 14.0 * scale, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
 
              // OVERLAY DIALOG: Finalize verification popup
              if (vm.isFinalizeVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 600.0 * scale,
                      height: 450.0 * scale,
                      padding: EdgeInsets.all(28.0 * scale),
                      decoration: AppStyles.glassDecoration(
                        borderColor: vm.isFinalizeConfirmed ? AppStyles.successColor : AppStyles.errorColor,
                        radius: 16.0 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    vm.isFinalizeConfirmed ? Icons.task_alt : Icons.analytics_outlined,
                                    color: vm.isFinalizeConfirmed ? AppStyles.successColor : AppStyles.errorColor,
                                    size: 28.0 * scale,
                                  ),
                                  SizedBox(width: 12.0 * scale),
                                  Text(
                                    "TÓM TẮT HỘI THOẠI",
                                    style: AppStyles.titleLarge.copyWith(fontSize: 24.0 * scale),
                                  ),
                                ],
                              ),
                              if (!vm.isFinalizeConfirmed)
                                IconButton(
                                  onPressed: () => vm.cancelFinalize(),
                                  icon: Icon(Icons.close, color: AppStyles.textSecondary, size: 24.0 * scale),
                                )
                            ],
                          ),
                          SizedBox(height: 16.0 * scale),
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.all(16.0 * scale),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8.0 * scale),
                                border: Border.all(color: AppStyles.glassCardBorder),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  vm.finalizeResult,
                                  style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale, height: 1.5),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 24.0 * scale),
 
                          if (!vm.isFinalizeConfirmed) ...[
                            // Cancel or Confirm
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50.0 * scale,
                                    child: OutlinedButton(
                                      focusNode: _cancelFinalizeButtonFocusNode,
                                      onPressed: () => vm.cancelFinalize(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppStyles.textPrimary,
                                        side: BorderSide(
                                          color: _isCancelFinalizeFocused ? Colors.white : AppStyles.glassCardBorder,
                                          width: _isCancelFinalizeFocused ? 3.0 * scale : 1.0,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                                        backgroundColor: _isCancelFinalizeFocused ? AppStyles.glassCardBorder : Colors.transparent,
                                      ),
                                      child: Text(
                                        "HỦY - TIẾP TỤC NÓI CHUYỆN",
                                        style: TextStyle(fontSize: 14.0 * scale, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 16.0 * scale),
                                Expanded(
                                  child: SizedBox(
                                    height: 50.0 * scale,
                                    child: ElevatedButton(
                                      focusNode: _confirmFinalizeButtonFocusNode,
                                      onPressed: () => vm.confirmFinalize(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isConfirmFinalizeFocused ? AppStyles.successColor : AppStyles.successColor.withValues(alpha: 0.7),
                                        foregroundColor: AppStyles.backgroundEnd,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                                        side: _isConfirmFinalizeFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                                        elevation: _isConfirmFinalizeFocused ? 12.0 : 0.0,
                                      ),
                                      child: Text(
                                        "XÁC NHẬN KẾT THÚC",
                                        style: TextStyle(fontSize: 14.0 * scale, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            // Go to result screen
                            SizedBox(
                              height: 50.0 * scale,
                              child: ElevatedButton(
                                focusNode: _goToResultButtonFocusNode,
                                onPressed: () {
                                  vm.navigateToResult(() {
                                    mainVm.navigateTo(AppStage.result);
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isGoToResultFocused ? AppStyles.primaryAccent : AppStyles.primaryAccent.withValues(alpha: 0.7),
                                  foregroundColor: AppStyles.backgroundEnd,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                                  side: _isGoToResultFocused ? BorderSide(color: Colors.white, width: 3.0 * scale) : null,
                                  elevation: _isGoToResultFocused ? 12.0 : 0.0,
                                ),
                                child: Text(
                                  "ĐI ĐẾN TRANG KẾT QUẢ",
                                  style: AppStyles.bodyLarge.copyWith(
                                    fontSize: 16.0 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
              // OVERLAY DIALOG: Voice Input Dialog
              if (vm.isVoiceInputActive)
                VoiceInputDialog(
                  status: vm.voiceInputStatus,
                  isRecording: vm.isVoiceRecording,
                  isTranscribing: vm.isVoiceTranscribing,
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class VoiceInputDialog extends StatefulWidget {
  final String status;
  final bool isRecording;
  final bool isTranscribing;

  const VoiceInputDialog({
    super.key,
    required this.status,
    required this.isRecording,
    required this.isTranscribing,
  });

  @override
  State<VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<VoiceInputDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VoiceInputDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);

    return Container(
      color: Colors.black.withValues(alpha: 0.4), // Less dim background
      child: Align(
        alignment: const Alignment(0, -0.5), // Shifted upwards
        child: Container(
          width: 320.0 * scale,
          height: 200.0 * scale,
          padding: EdgeInsets.all(16.0 * scale),
          decoration: AppStyles.glassDecoration(
            radius: 16.0 * scale,
            borderColor: AppStyles.primaryAccent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 75.0 * scale,
                    height: 75.0 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppStyles.primaryAccent.withValues(
                        alpha: widget.isRecording ? (0.4 / _pulseAnimation.value) : 0.2,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 55.0 * scale * (widget.isRecording ? (_pulseAnimation.value * 0.8) : 1.0),
                        height: 55.0 * scale * (widget.isRecording ? (_pulseAnimation.value * 0.8) : 1.0),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppStyles.primaryAccent,
                        ),
                        child: Icon(
                          widget.isTranscribing ? Icons.sync : Icons.mic,
                          color: AppStyles.backgroundEnd,
                          size: 26.0 * scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 16.0 * scale),
              Text(
                widget.status,
                style: AppStyles.titleLarge.copyWith(
                  color: AppStyles.textPrimary,
                  fontSize: 15.0 * scale,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.isRecording) ...[
                SizedBox(height: 8.0 * scale),
                Text(
                  "Hãy nói gì đó...",
                  style: AppStyles.caption.copyWith(
                    color: AppStyles.textSecondary,
                    fontSize: 12.0 * scale,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
