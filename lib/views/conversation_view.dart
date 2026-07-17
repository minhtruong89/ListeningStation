import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../utils/styles.dart';

import '../viewmodels/conversation_viewmodel.dart';

import '../viewmodels/main_viewmodel.dart';

import '../services/log_service.dart';



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



  // Focus nodes for voice popup

  late final FocusNode _voiceConfirmFocusNode;
  late final FocusNode _voiceRetryFocusNode;
  late final FocusNode _voiceCancelFocusNode;
  late final FocusNode _voiceFinalizeFocusNode;
  bool _isVoiceConfirmFocused = false;
  bool _isVoiceRetryFocused = false;
  bool _isVoiceCancelFocused = false;
  bool _isVoiceFinalizeFocused = false;



  // Track previous visibility states to detect changes

  bool _prevIsSummaryVisible = false;

  bool _prevIsFinalizeVisible = false;

  bool _prevIsFinalizeConfirmed = false;

  bool _prevIsVoiceActive = false;

  bool _prevHasVoiceResult = false;

  bool _prevHasVoiceError = false;



  // Optimize scrolling triggers on weak Android Box hardware

  int _lastMessageCount = 0;



  bool _isDashboardVisible = false;

  Timer? _dashboardTimer;



  void _showDashboardAndResetTimer() {
    if (!mounted) return;
    
    // Do not show dashboard or steal focus if a popup is active
    final vm = context.read<ConversationViewModel>();
    if (vm.isVoiceInputActive || vm.isSummaryVisible || vm.isFinalizeVisible) {
      return;
    }

    if (!_isDashboardVisible) {

      setState(() {

        _isDashboardVisible = true;

      });

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted && _isDashboardVisible) {

          _muteButtonFocusNode.requestFocus();

        }

      });

    }

    _dashboardTimer?.cancel();

    _dashboardTimer = Timer(const Duration(seconds: 10), () {

      if (mounted) {

        setState(() {

          _isDashboardVisible = false;

        });

      }

    });

  }



  // ── Bottom bar D-pad (closed horizontal loop) ────────────────────────

  // Order: [Mute] ↔ [Demo] ↔ [Finalize] ↔ [Voice] ↔ [Send/Input] ↔ [Log]*

  // * [Log] only included when LogService.flagWriteLogDevice == true

  KeyEventResult _handleMuteKeyEvent(FocusNode node, KeyEvent event) {

    if (event is KeyDownEvent) {

      _showDashboardAndResetTimer();

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {

        _voiceButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {

        // wrap-around: Log → Send → ... → Mute

        if (LogService.flagWriteLogDevice && LogService.logButtonFocusNode.canRequestFocus) {

          LogService.logButtonFocusNode.requestFocus();

        } else {

          _sendButtonFocusNode.requestFocus();

        }

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

      _showDashboardAndResetTimer();

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

      _showDashboardAndResetTimer();

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {

        _voiceButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {

        _demoButtonFocusNode.requestFocus();

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

      _showDashboardAndResetTimer();

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {

        _finalizeButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {

        _finalizeButtonFocusNode.requestFocus();

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

      _showDashboardAndResetTimer();

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {

        _finalizeButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {

        _voiceButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {

        // wrap-around: Send → Log (if enabled) → Mute

        if (LogService.flagWriteLogDevice && LogService.logButtonFocusNode.canRequestFocus) {

          LogService.logButtonFocusNode.requestFocus();

        } else {

          _muteButtonFocusNode.requestFocus();

        }

        return KeyEventResult.handled;

      }

      // Select/Enter on Send button: submit the current text

      if (event.logicalKey == LogicalKeyboardKey.enter ||

          event.logicalKey == LogicalKeyboardKey.select ||

          event.logicalKey == LogicalKeyboardKey.numpadEnter ||

          event.logicalKey == LogicalKeyboardKey.accept ||

          event.logicalKey == LogicalKeyboardKey.space) {

        final vm = context.read<ConversationViewModel>();

        final val = _chatInputController.text;

        if (val.trim().isNotEmpty) {

          vm.userInput = val;

          vm.sendMessageAsync();

          _chatInputController.clear();

        }

        return KeyEventResult.handled;

      }

    }

    return KeyEventResult.ignored;

  }



  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {

    if (event is KeyDownEvent) {

      _showDashboardAndResetTimer();

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {

        _muteButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {

        _voiceButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {

        _muteButtonFocusNode.requestFocus();

        return KeyEventResult.handled;

      }

      // Select/Enter: submit text

      if (event.logicalKey == LogicalKeyboardKey.enter ||

          event.logicalKey == LogicalKeyboardKey.select ||

          event.logicalKey == LogicalKeyboardKey.numpadEnter ||

          event.logicalKey == LogicalKeyboardKey.accept) {

        final vm = context.read<ConversationViewModel>();

        final val = _chatInputController.text;

        if (val.trim().isNotEmpty) {

          vm.userInput = val;

          vm.sendMessageAsync();

          _chatInputController.clear();

        }

        return KeyEventResult.handled;

      }

    }

    return KeyEventResult.ignored;

  }



  // ── Voice popup D-pad ────────────────────────────────────────────────

  // In normal result state (3 buttons): [Retry] ↔ [Confirm] ↔ [Cancel]

  // In error state (2 buttons): [Retry] ↔ [Cancel]

  KeyEventResult _handleVoiceConfirmKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final vm = context.read<ConversationViewModel>();
      if (vm.hasVoiceError) {
        _voiceRetryFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _voiceRetryFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _voiceCancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleVoiceRetryKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final vm = context.read<ConversationViewModel>();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _voiceFinalizeFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (vm.hasVoiceError) {
          _voiceCancelFocusNode.requestFocus();
        } else {
          _voiceConfirmFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleVoiceCancelKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final vm = context.read<ConversationViewModel>();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (vm.hasVoiceError) {
          _voiceRetryFocusNode.requestFocus();
        } else if (vm.hasVoiceResult) {
          _voiceConfirmFocusNode.requestFocus();
        } else {
          _voiceFinalizeFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _voiceFinalizeFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleVoiceFinalizeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final vm = context.read<ConversationViewModel>();
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _voiceCancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (vm.hasVoiceError || vm.hasVoiceResult) {
          _voiceRetryFocusNode.requestFocus();
        } else {
          _voiceCancelFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }



  // ── Finalize popup ──────────────────────────────────────────────────

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



    _voiceConfirmFocusNode = FocusNode(onKeyEvent: _handleVoiceConfirmKeyEvent);
    _voiceRetryFocusNode = FocusNode(onKeyEvent: _handleVoiceRetryKeyEvent);
    _voiceCancelFocusNode = FocusNode(onKeyEvent: _handleVoiceCancelKeyEvent);
    _voiceFinalizeFocusNode = FocusNode(onKeyEvent: _handleVoiceFinalizeKeyEvent);



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



    _voiceConfirmFocusNode.addListener(() {
      if (mounted) setState(() => _isVoiceConfirmFocused = _voiceConfirmFocusNode.hasFocus);
    });
    _voiceRetryFocusNode.addListener(() {
      if (mounted) setState(() => _isVoiceRetryFocused = _voiceRetryFocusNode.hasFocus);
    });
    _voiceCancelFocusNode.addListener(() {
      if (mounted) setState(() => _isVoiceCancelFocused = _voiceCancelFocusNode.hasFocus);
    });
    _voiceFinalizeFocusNode.addListener(() {
      if (mounted) setState(() => _isVoiceFinalizeFocused = _voiceFinalizeFocusNode.hasFocus);
    });







    // Register this view's adjacent nodes so Log button can navigate back into the bar

    // Loop: ... [Send/Input] → [Log] → [Mute] ...

    LogService.prevFocusNode = _sendButtonFocusNode;

    LogService.nextFocusNode = _muteButtonFocusNode;

  }



  @override

  void dispose() {

    // Unregister Log navigation refs so they don't dangle after this view is gone

    if (LogService.prevFocusNode == _sendButtonFocusNode) LogService.prevFocusNode = null;

    if (LogService.nextFocusNode == _muteButtonFocusNode) LogService.nextFocusNode = null;



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

    _voiceConfirmFocusNode.dispose();
    _voiceRetryFocusNode.dispose();
    _voiceCancelFocusNode.dispose();
    _voiceFinalizeFocusNode.dispose();

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

    scale = 1.2; // 1.5 - 1.2



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



    if (vm.isVoiceInputActive && !_prevIsVoiceActive) {

      _prevIsVoiceActive = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted) {

          if (vm.hasVoiceError) {

            _voiceRetryFocusNode.requestFocus();

          } else if (vm.hasVoiceResult) {

            _voiceConfirmFocusNode.requestFocus();

          } else {

            // If active but no result/error yet (i.e. recording), default to cancel/retry to be safe

            _voiceCancelFocusNode.requestFocus();

          }

        }

      });

    } else if (!vm.isVoiceInputActive && _prevIsVoiceActive) {

      _prevIsVoiceActive = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted) _sendButtonFocusNode.requestFocus(); // return focus to Send/Input button

      });

    }



    // Dynamic focus redirection when error or result appears asynchronously

    if (vm.isVoiceInputActive) {

      final bool hasResultWithText = vm.hasVoiceResult && vm.voiceTranscribedText.isNotEmpty;

      final bool hasUnclearResult = vm.hasVoiceResult && vm.voiceTranscribedText.isEmpty;

      final bool currentHasResult = vm.hasVoiceResult;

      final bool currentHasError = vm.hasVoiceError || hasUnclearResult;



      // 1. Detect transitioning to ERROR state

      if (currentHasError && !_prevHasVoiceError) {

        _prevHasVoiceError = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {

          Future.delayed(const Duration(milliseconds: 50), () {

            if (mounted && vm.isVoiceInputActive) _voiceRetryFocusNode.requestFocus();

          });

        });

      }

      // 2. Detect transitioning to SUCCESS state

      else if (hasResultWithText && !_prevHasVoiceResult) {

        _prevHasVoiceResult = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {

          Future.delayed(const Duration(milliseconds: 50), () {

            if (mounted && vm.isVoiceInputActive) _voiceConfirmFocusNode.requestFocus();

          });

        });

      }



      // Reset edge triggers when state goes back to active recording/transcribing

      if (!currentHasResult && !currentHasError) {

        _prevHasVoiceResult = false;

        _prevHasVoiceError = false;

      }

    } else {

      // Reset if popup is closed

      _prevHasVoiceResult = false;

      _prevHasVoiceError = false;

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

        body: Focus(

          autofocus: true,

          onKeyEvent: (node, event) {

            if (event is KeyDownEvent) {

              _showDashboardAndResetTimer();

            }

            return KeyEventResult.ignored;

          },

          child: Container(

            decoration: const BoxDecoration(

              gradient: AppStyles.backgroundGradient,

            ),

            child: SafeArea(

              child: Stack(

                children: [

                  // 1. Base full screen chat dialogue history

                  Padding(

                    padding: EdgeInsets.all(24.0 * scale),

                    child: Container(

                      padding: EdgeInsets.all(16.0 * scale),

                      decoration: AppStyles.glassDecoration(radius: 16.0 * scale),

                      child: Column(

                        children: [

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

                        ],

                      ),

                    ),

                  ),



                  // 2. Dashboard overlay controls

                  IgnorePointer(

                    ignoring: !_isDashboardVisible,

                    child: AnimatedOpacity(

                      opacity: _isDashboardVisible ? 1.0 : 0.0,

                      duration: const Duration(milliseconds: 300),

                      child: Focus(

                        descendantsAreFocusable: !vm.isSummaryVisible && !vm.isFinalizeVisible && !vm.isVoiceInputActive && _isDashboardVisible,

                        child: Padding(

                          padding: EdgeInsets.all(24.0 * scale),

                          child: Column(

                            crossAxisAlignment: CrossAxisAlignment.stretch,

                            children: [

                              // TOP CONTROL BAR: Horizontal row of controls

                                                  // TOP CONTROL BAR: Horizontal row of controls

                    Row(

                      children: [

                        // When using Local TTS (Google TTS / RHVoice): show voice combobox
                        if (vm.showLocalVoiceOptions) ...[
                          // Dropdown/Combobox of Available Vietnamese Voices

                        Container(

                          padding: EdgeInsets.symmetric(horizontal: 14.0 * scale, vertical: 2.0 * scale),

                          decoration: AppStyles.glassDecoration(radius: 8.0 * scale),

                          child: DropdownButtonHideUnderline(

                            child: DropdownButton<String>(

                              value: vm.selectedVoice.isNotEmpty && vm.availableVoices.contains(vm.selectedVoice)

                                  ? vm.selectedVoice

                                  : (vm.availableVoices.isNotEmpty ? vm.availableVoices.first : null),

                              hint: Text(

                                "Chọn giọng đọc",

                                style: TextStyle(color: AppStyles.textSecondary, fontSize: 13.0 * scale),

                              ),

                              dropdownColor: AppStyles.backgroundEnd,

                              style: TextStyle(

                                color: AppStyles.textPrimary, 

                                fontSize: 13.0 * scale, 

                                fontWeight: FontWeight.bold,

                              ),

                              icon: Icon(Icons.arrow_drop_down, color: AppStyles.textPrimary),

                              onChanged: (String? newValue) {

                                if (newValue != null) {

                                  vm.changeVoice(newValue);

                                }

                              },

                              items: vm.availableVoices.map<DropdownMenuItem<String>>((String voice) {

                                String displayVoice = voice;

                                if (voice.contains('-')) {

                                  final parts = voice.split('-');

                                  if (parts.length > 2) {

                                    displayVoice = parts.sublist(2).join('-');

                                  }

                                }

                                return DropdownMenuItem<String>(

                                  value: voice,

                                  child: Text(

                                    displayVoice,

                                    style: TextStyle(color: AppStyles.textPrimary),

                                  ),

                                );

                              }).toList(),

                            ),

                          ),

                        ),

                        ], // end if (vm.isLocalTTS)
                        SizedBox(width: 12.0 * scale),
                        // When using Online TTS (Google AI / OpenAI): show provider toggle
                        if (!vm.isLocalTTS) ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 14.0 * scale, vertical: 2.0 * scale),
                            decoration: AppStyles.glassDecoration(radius: 8.0 * scale),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: vm.onlineTtsProvider,
                                dropdownColor: AppStyles.backgroundEnd,
                                style: TextStyle(color: AppStyles.textPrimary, fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                                icon: Icon(Icons.cloud, color: AppStyles.primaryAccent, size: 18.0 * scale),
                                onChanged: (String? newProvider) {
                                  if (newProvider != null) vm.changeOnlineProvider(newProvider);
                                },
                                items: const [
                                  DropdownMenuItem(value: 'GoogleAI', child: Text('Google AI')),
                                  DropdownMenuItem(value: 'OpenAI', child: Text('OpenAI')),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 12.0 * scale),
                        ], // end if (!vm.isLocalTTS)
                        // "Chuyển giọng" button
                        if (vm.showLocalVoiceOptions) ...[
                          ElevatedButton.icon(
                            onPressed: () => vm.applyVoiceAndSpeakAsync(context),
                            icon: Icon(Icons.record_voice_over, size: 18.0 * scale),
                            label: Text(
                              "CHUYỂN GIỌNG",
                              style: TextStyle(fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppStyles.primaryAccent,
                              foregroundColor: AppStyles.backgroundEnd,
                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 14.0 * scale),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                            ),
                          ),
                          SizedBox(width: 12.0 * scale),
                        ],

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

                            "CHẠY DEMO",

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

                        SizedBox(width: 12.0 * scale),



                        // Stop / Finalize Button (Moved next to Demo)

                        ElevatedButton.icon(

                          focusNode: _finalizeButtonFocusNode,

                          onPressed: () => vm.showFinalizeAsync(),

                          icon: Icon(Icons.check_circle_outline, size: 18.0 * scale),

                          label: Text(

                            "KẾT THÚC HỘI THOẠI",

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



                        const Spacer(),

                      ],

                    ),

                              const Spacer(),

                              // User text manual override input row

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

                                    padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 14.0 * scale),

                                    child: Focus(

                                      focusNode: _inputFocusNode,

                                      child: Text(

                                        _chatInputController.text.isEmpty

                                            ? "Nhập phản hồi của bệnh nhân..."

                                            : _chatInputController.text,

                                        style: _chatInputController.text.isEmpty

                                            ? AppStyles.caption.copyWith(fontSize: 12.0 * scale)

                                            : AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),

                                        maxLines: 1,

                                        overflow: TextOverflow.ellipsis,

                                      ),

                                    ),

                                  ),

                                ),

                                 SizedBox(width: 12.0 * scale),

                                SizedBox(

                                  height: 50.0 * scale,

                                  child: ElevatedButton(

                                    focusNode: _voiceButtonFocusNode,

                                    onPressed: () => vm.startVoiceInputAsync(),

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

              // OVERLAY DIALOG: Voice Input Dialog (persistent - stays open until user confirms or retries)

              if (vm.isVoiceInputActive)

                FocusScope(

                  autofocus: true,

                  child: VoiceInputDialog(
                    status: vm.hasVoiceResult && vm.voiceTranscribedText.isEmpty 
                        ? "Không nhận diện được giọng nói." 
                        : vm.voiceInputStatus,
                    isRecording: vm.isVoiceRecording,
                    isTranscribing: vm.isVoiceTranscribing,
                    hasResult: vm.hasVoiceResult && vm.voiceTranscribedText.isNotEmpty,
                    hasError: vm.hasVoiceError || (vm.hasVoiceResult && vm.voiceTranscribedText.isEmpty),
                    transcribedText: vm.voiceTranscribedText,
                    confirmFocusNode: _voiceConfirmFocusNode,
                    retryFocusNode: _voiceRetryFocusNode,
                    cancelFocusNode: _voiceCancelFocusNode,
                    finalizeFocusNode: _voiceFinalizeFocusNode,
                    isConfirmFocused: _isVoiceConfirmFocused,
                    isRetryFocused: _isVoiceRetryFocused,
                    isCancelFocused: _isVoiceCancelFocused,
                    isFinalizeFocused: _isVoiceFinalizeFocused,
                    onConfirm: (text) {
                      vm.cancelVoiceInput();
                      if (text.trim().isNotEmpty) {
                        vm.userInput = text;
                        vm.sendMessageAsync();
                        _chatInputController.clear();
                      }
                    },
                    onRetry: () => vm.retryVoiceInputAsync(),
                    onCancel: () => vm.cancelVoiceInput(),
                    onFinalize: () {
                      vm.cancelVoiceInput();
                      vm.showFinalizeAsync();
                    },
                  ),

                ),

            ],

          ),

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
  final bool hasResult;
  final bool hasError;
  final String transcribedText;
  final FocusNode confirmFocusNode;
  final FocusNode retryFocusNode;
  final FocusNode cancelFocusNode;
  final FocusNode finalizeFocusNode;
  final bool isConfirmFocused;
  final bool isRetryFocused;
  final bool isCancelFocused;
  final bool isFinalizeFocused;
  final void Function(String text) onConfirm;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onFinalize;

  const VoiceInputDialog({
    super.key,
    required this.status,
    required this.isRecording,
    required this.isTranscribing,
    required this.hasResult,
    required this.hasError,
    required this.transcribedText,
    required this.confirmFocusNode,
    required this.retryFocusNode,
    required this.cancelFocusNode,
    required this.finalizeFocusNode,
    required this.isConfirmFocused,
    required this.isRetryFocused,
    required this.isCancelFocused,
    required this.isFinalizeFocused,
    required this.onConfirm,
    required this.onRetry,
    required this.onCancel,
    required this.onFinalize,
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



    final bool isBusy = widget.isRecording || widget.isTranscribing;

    final Color accentColor = widget.hasResult

        ? AppStyles.successColor

        : widget.hasError

            ? AppStyles.errorColor

            : AppStyles.primaryAccent;



    return Container(

      color: Colors.black.withValues(alpha: 0.65),

      child: Center(

        child: AnimatedContainer(

          duration: const Duration(milliseconds: 200),

          width: 420.0 * scale, // Single unified size

          padding: EdgeInsets.all(22.0 * scale),

          decoration: AppStyles.glassDecoration(

            radius: 20.0 * scale,

            borderColor: accentColor,

          ).copyWith(

            boxShadow: [

              BoxShadow(

                color: accentColor.withValues(alpha: 0.25),

                blurRadius: 24.0 * scale,

                spreadRadius: 2.0 * scale,

              ),

            ],

          ),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              // Title row

              Row(

                mainAxisAlignment: MainAxisAlignment.center,

                children: [

                  Icon(Icons.mic, color: accentColor, size: 22.0 * scale),

                  SizedBox(width: 8.0 * scale),

                  Text(

                    "NHẬP GIỌNG NÓI",

                    style: AppStyles.bodyLarge.copyWith(

                      fontSize: 15.0 * scale,

                      fontWeight: FontWeight.bold,

                      color: accentColor,

                    ),

                  ),

                ],

              ),

              SizedBox(height: 16.0 * scale),



              // Mic animation (shown when recording or transcribing)

              if (isBusy || !widget.hasResult) ...[

                AnimatedBuilder(

                  animation: _pulseAnimation,

                  builder: (context, child) {

                    return Container(

                      width: 70.0 * scale,

                      height: 70.0 * scale,

                      decoration: BoxDecoration(

                        shape: BoxShape.circle,

                        color: AppStyles.primaryAccent.withValues(

                          alpha: widget.isRecording ? (0.4 / _pulseAnimation.value) : 0.15,

                        ),

                      ),

                      child: Center(

                        child: Container(

                          width: 50.0 * scale * (widget.isRecording ? (_pulseAnimation.value * 0.8) : 1.0),

                          height: 50.0 * scale * (widget.isRecording ? (_pulseAnimation.value * 0.8) : 1.0),

                          decoration: const BoxDecoration(

                            shape: BoxShape.circle,

                            color: AppStyles.primaryAccent,

                          ),

                          child: Icon(

                            widget.isTranscribing ? Icons.sync : Icons.mic,

                            color: AppStyles.backgroundEnd,

                            size: 24.0 * scale,

                          ),

                        ),

                      ),

                    );

                  },

                ),

                SizedBox(height: 12.0 * scale),

                Text(

                  widget.status,

                  style: AppStyles.bodyMedium.copyWith(

                    fontSize: 13.0 * scale,

                    color: AppStyles.textPrimary,

                    fontWeight: FontWeight.w600,

                  ),

                  textAlign: TextAlign.center,

                ),

                if (widget.isRecording) ...[

                  SizedBox(height: 6.0 * scale),

                  Text(

                    "Hãy nói gì đó...",

                    style: AppStyles.caption.copyWith(

                      color: AppStyles.textSecondary,

                      fontSize: 11.0 * scale,

                    ),

                  ),

                ],

              ],



              // Result display (shown after transcription)

              if (widget.hasResult) ...[

                Container(

                  width: double.infinity,

                  padding: EdgeInsets.all(14.0 * scale),

                  decoration: BoxDecoration(

                    color: AppStyles.successColor.withValues(alpha: 0.08),

                    borderRadius: BorderRadius.circular(10.0 * scale),

                    border: Border.all(color: AppStyles.successColor.withValues(alpha: 0.4)),

                  ),

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(

                        "Kết quả nhận diện:",

                        style: AppStyles.caption.copyWith(

                          color: AppStyles.successColor,

                          fontSize: 11.0 * scale,

                          fontWeight: FontWeight.bold,

                        ),

                      ),

                      SizedBox(height: 6.0 * scale),

                      Text(

                        widget.transcribedText,

                        style: AppStyles.bodyLarge.copyWith(

                          fontSize: 15.0 * scale,

                          color: AppStyles.textPrimary,

                        ),

                      ),

                    ],

                  ),

                ),

                SizedBox(height: 16.0 * scale),



                // Action buttons: [Retry] [Confirm] [Cancel]

                Row(

                  children: [

                    // Retry button

                    Expanded(

                      child: SizedBox(

                        height: 44.0 * scale,

                        child: OutlinedButton.icon(

                          focusNode: widget.retryFocusNode,

                          onPressed: widget.onRetry,

                          icon: Icon(Icons.refresh, size: 16.0 * scale),

                          label: Text(

                            "THỬ LẠI",

                            style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),

                          ),

                          style: OutlinedButton.styleFrom(

                            foregroundColor: widget.isRetryFocused ? Colors.white : AppStyles.textSecondary,

                            backgroundColor: widget.isRetryFocused ? AppStyles.glassCardBorder : Colors.transparent,

                            side: BorderSide(

                              color: widget.isRetryFocused ? Colors.white : AppStyles.glassCardBorder,

                              width: widget.isRetryFocused ? 2.5 * scale : 1.0,

                            ),

                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),

                            elevation: widget.isRetryFocused ? 8.0 : 0.0,

                          ),

                        ),

                      ),

                    ),

                    SizedBox(width: 10.0 * scale),

                    // Confirm button

                    Expanded(

                      flex: 2,

                      child: SizedBox(

                        height: 44.0 * scale,

                        child: ElevatedButton.icon(

                          focusNode: widget.confirmFocusNode,

                          onPressed: () => widget.onConfirm(widget.transcribedText),

                          icon: Icon(Icons.check, size: 16.0 * scale),

                          label: Text(

                            "XÁC NHẬN NHẬP",

                            style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),

                          ),

                          style: ElevatedButton.styleFrom(

                            backgroundColor: widget.isConfirmFocused ? AppStyles.successColor : AppStyles.successColor.withValues(alpha: 0.7),

                            foregroundColor: AppStyles.backgroundEnd,

                            side: widget.isConfirmFocused ? BorderSide(color: Colors.white, width: 2.5 * scale) : null,

                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),

                            elevation: widget.isConfirmFocused ? 10.0 : 0.0,

                          ),

                        ),

                      ),

                    ),

                    SizedBox(width: 10.0 * scale),
                    // Cancel button
                    Expanded(
                      child: SizedBox(
                        height: 44.0 * scale,
                        child: OutlinedButton.icon(
                          focusNode: widget.cancelFocusNode,
                          onPressed: widget.onCancel,
                          icon: Icon(Icons.close, size: 16.0 * scale),
                          label: Text(
                            "HỦY",
                            style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: widget.isCancelFocused ? Colors.white : AppStyles.errorColor,
                            backgroundColor: widget.isCancelFocused ? AppStyles.errorColor.withValues(alpha: 0.2) : Colors.transparent,
                            side: BorderSide(
                              color: widget.isCancelFocused ? Colors.white : AppStyles.errorColor.withValues(alpha: 0.6),
                              width: widget.isCancelFocused ? 2.5 * scale : 1.0,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),
                            elevation: widget.isCancelFocused ? 8.0 : 0.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (widget.hasError) ...[
                // Error state: show retry and cancel
                SizedBox(height: 12.0 * scale),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 44.0 * scale,
                      child: OutlinedButton.icon(
                        focusNode: widget.retryFocusNode,
                        onPressed: widget.onRetry,
                        icon: Icon(Icons.refresh, size: 16.0 * scale),
                        label: Text(
                          "THỬ LẠI",
                          style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isRetryFocused ? Colors.white : AppStyles.textSecondary,
                          backgroundColor: widget.isRetryFocused ? AppStyles.glassCardBorder : Colors.transparent,
                          side: BorderSide(
                            color: widget.isRetryFocused ? Colors.white : AppStyles.glassCardBorder,
                            width: widget.isRetryFocused ? 2.5 * scale : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),
                          elevation: widget.isRetryFocused ? 8.0 : 0.0,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.0 * scale),
                    SizedBox(
                      height: 44.0 * scale,
                      child: OutlinedButton.icon(
                        focusNode: widget.cancelFocusNode,
                        onPressed: widget.onCancel,
                        icon: Icon(Icons.close, size: 16.0 * scale),
                        label: Text(
                          "HỦY",
                          style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isCancelFocused ? Colors.white : AppStyles.errorColor,
                          backgroundColor: widget.isCancelFocused ? AppStyles.errorColor.withValues(alpha: 0.2) : Colors.transparent,
                          side: BorderSide(
                            color: widget.isCancelFocused ? Colors.white : AppStyles.errorColor.withValues(alpha: 0.6),
                            width: widget.isCancelFocused ? 2.5 * scale : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),
                          elevation: widget.isCancelFocused ? 8.0 : 0.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Recording / transcribing state: show cancel button
                SizedBox(height: 12.0 * scale),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 44.0 * scale,
                      child: OutlinedButton.icon(
                        focusNode: widget.cancelFocusNode,
                        onPressed: widget.onCancel,
                        icon: Icon(Icons.close, size: 16.0 * scale),
                        label: Text(
                          "HỦY",
                          style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.isCancelFocused ? Colors.white : AppStyles.errorColor,
                          backgroundColor: widget.isCancelFocused ? AppStyles.errorColor.withValues(alpha: 0.2) : Colors.transparent,
                          side: BorderSide(
                            color: widget.isCancelFocused ? Colors.white : AppStyles.errorColor.withValues(alpha: 0.6),
                            width: widget.isCancelFocused ? 2.5 * scale : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),
                          elevation: widget.isCancelFocused ? 8.0 : 0.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 16.0 * scale),
              const Divider(color: AppStyles.glassCardBorder, height: 1.0),
              SizedBox(height: 16.0 * scale),
              SizedBox(
                width: double.infinity,
                height: 44.0 * scale,
                child: ElevatedButton.icon(
                  focusNode: widget.finalizeFocusNode,
                  onPressed: widget.onFinalize,
                  icon: Icon(Icons.check_circle_outline, size: 16.0 * scale),
                  label: Text(
                    "KẾT THÚC HỘI THOẠI",
                    style: TextStyle(fontSize: 12.0 * scale, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isFinalizeFocused ? AppStyles.errorColor : AppStyles.errorColor.withValues(alpha: 0.7),
                    foregroundColor: AppStyles.textPrimary,
                    side: widget.isFinalizeFocused ? BorderSide(color: Colors.white, width: 2.5 * scale) : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0 * scale)),
                    elevation: widget.isFinalizeFocused ? 10.0 : 0.0,
                  ),
                ),
              ),
            ],

          ),

        ),

      ),

    );

  }

}



