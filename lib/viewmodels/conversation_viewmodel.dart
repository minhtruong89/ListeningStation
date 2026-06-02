import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../services/llm_service.dart';
import '../services/speech_service.dart';

class ConversationViewModel extends ChangeNotifier {
  final ILLMService _llmService;
  final ISpeechService _speechService;

  String _userInput = "";
  bool _isProcessing = false;
  String _summaryResult = "";
  bool _isSummaryVisible = false;
  bool _isMuted = false;

  String _finalizeResult = "";
  bool _isFinalizeVisible = false;
  bool _isFinalizeConfirmed = false;

  final List<ConversationMessage> _messages = [];
  int _currentRequestToken = 0;

  ConversationViewModel(this._llmService, this._speechService) {
    _isMuted = _speechService.isMuted;
    
    // Auto-start conversation
    sendMessageAsync(hiddenInput: "Xin chào");
  }

  String get userInput => _userInput;
  set userInput(String val) {
    _userInput = val;
    notifyListeners();
  }

  bool get isProcessing => _isProcessing;
  String get summaryResult => _summaryResult;
  bool get isSummaryVisible => _isSummaryVisible;
  bool get isMuted => _isMuted;

  String get finalizeResult => _finalizeResult;
  bool get isFinalizeVisible => _isFinalizeVisible;
  bool get isFinalizeConfirmed => _isFinalizeConfirmed;

  List<ConversationMessage> get messages => _messages;

  Future<void> sendMessageAsync({String? hiddenInput}) async {
    final myToken = ++_currentRequestToken;
    final isHidden = hiddenInput != null && hiddenInput.isNotEmpty;
    final textToProcess = isHidden ? hiddenInput : _userInput;

    if (textToProcess.trim().isEmpty) return;

    if (!isHidden) {
      _messages.add(ConversationMessage(
        sender: "Người cần giúp đỡ",
        content: textToProcess,
        timestamp: DateTime.now(),
      ));
      _userInput = "";
      notifyListeners();
    }

    _isProcessing = true;
    notifyListeners();

    final List<ConversationMessage> historyForLlm = List.from(_messages);
    if (isHidden) {
      historyForLlm.add(ConversationMessage(
        sender: "Người cần giúp đỡ",
        content: textToProcess,
        timestamp: DateTime.now(),
      ));
    }

    final String aiResponse = await _llmService.getResponseAsync(historyForLlm, textToProcess);
    
    // Cancel if interrupted by demo mode or newer requests
    if (myToken != _currentRequestToken) return;

    _messages.add(ConversationMessage(
      sender: "Trạm Lắng Nghe",
      content: aiResponse,
      timestamp: DateTime.now(),
    ));

    _isProcessing = false;
    notifyListeners();

    // Play TTS in background so user doesn't wait
    _speechService.speakAsync(aiResponse);
  }

  Future<void> showFinalizeAsync() async {
    _isProcessing = true;
    _isFinalizeConfirmed = false;
    _finalizeResult = "Đang kiểm tra thông tin, vui lòng chờ...";
    _isFinalizeVisible = true;
    notifyListeners();

    final response = await _llmService.getFinalizeAIAsync(_messages);
    _finalizeResult = response;

    // Parse amount from text
    final double extracted = _extractAmount(response);
    _llmService.proposedAmount = extracted;
    debugPrint("[CONVERSE] AI Response: $response");
    debugPrint("[CONVERSE] Extracted ProposedAmount: $extracted");

    _isProcessing = false;
    notifyListeners();
  }

  double _extractAmount(String text) {
    try {
      // Normalize
      String lowerText = text.toLowerCase().replaceAll(" ", "");

      // 1. Check for "triệu" (Million)
      final trieuMatch = RegExp(r'([\d\.,]+)triệu').firstMatch(lowerText);
      if (trieuMatch != null) {
        String valStr = trieuMatch.group(1)!.replaceAll(',', '.');
        double? val = double.tryParse(valStr);
        if (val != null) {
          return val * 1000000.0;
        }
      }

      // 2. Check for "ngàn/nghìn/k" (Thousand)
      final nganMatch = RegExp(r'([\d\.,]+)(ngàn|nghìn|k)').firstMatch(lowerText);
      if (nganMatch != null) {
        String valStr = nganMatch.group(1)!.replaceAll(',', '.');
        double? val = double.tryParse(valStr);
        if (val != null) {
          return val * 1000.0;
        }
      }

      // 3. Check for raw large numbers
      final rawMatches = RegExp(r'[\d\.,]{4,}').allMatches(text);
      for (var m in rawMatches) {
        String clean = m.group(0)!.replaceAll('.', '').replaceAll(',', '');
        double? val = double.tryParse(clean);
        if (val != null && val >= 10000) {
          return val;
        }
      }
    } catch (ex) {
      debugPrint("[DEBUG] ExtractAmount Error: \$ex");
    }
    return 0.0;
  }

  void confirmFinalize() {
    _finalizeResult = _llmService.finalizeConfirmMessage;
    _isFinalizeConfirmed = true;
    notifyListeners();
  }

  void cancelFinalize() {
    _isFinalizeVisible = false;
    notifyListeners();
  }

  void navigateToResult(VoidCallback onNavigation) {
    _llmService.lastConversationHistory = List.from(_messages);
    _isFinalizeVisible = false;
    _speechService.stop();
    notifyListeners();
    onNavigation();
  }

  Future<void> showSummaryAsync() async {
    _isProcessing = true;
    _summaryResult = "Đang tổng hợp, vui lòng chờ...";
    _isSummaryVisible = true;
    notifyListeners();

    _summaryResult = await _llmService.getSummaryAIAsync(_messages);
    _isProcessing = false;
    notifyListeners();
  }

  void closeSummary() {
    _isSummaryVisible = false;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _speechService.isMuted = _isMuted;
    notifyListeners();
  }

  Future<void> runDemoModeAsync() async {
    _currentRequestToken++; // Cancel any pending/running API requests from calling speakAsync
    _speechService.stop(); // Immediate silence
    _isProcessing = true;
    _messages.clear();
    notifyListeners();

    final demoMsgs = await _llmService.getDemoMessagesAsync();
    for (var msg in demoMsgs) {
      _messages.add(msg);
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300)); // Smooth script population
    }

    _isProcessing = false;
    notifyListeners();
  }

  void clearConversation() {
    _messages.clear();
    _userInput = "";
    _finalizeResult = "";
    _isFinalizeVisible = false;
    _isFinalizeConfirmed = false;
    _isSummaryVisible = false;
    notifyListeners();
  }
}
