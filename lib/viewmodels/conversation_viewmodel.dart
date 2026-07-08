import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';
import '../services/llm_service.dart';
import '../services/speech_service.dart';
import '../services/rule_engine_service.dart';

class ConversationViewModel extends ChangeNotifier {
  final ILLMService _llmService;
  final ISpeechService _speechService;
  final IRuleEngineService _ruleEngine;

  String _userInput = "";
  bool _isProcessing = false;
  String _summaryResult = "";
  bool _isSummaryVisible = false;
  bool _isMuted = false;

  String _finalizeResult = "";
  bool _isFinalizeVisible = false;
  bool _isFinalizeConfirmed = false;

  bool _isVoiceInputActive = false;
  String _voiceInputStatus = "";
  bool _isVoiceRecording = false;
  bool _isVoiceTranscribing = false;
  bool _hasVoiceError = false;          // true only after a recording attempt fails
  String _voiceTranscribedText = ""; // holds result until user confirms or retries

  final List<ConversationMessage> _messages = [];
  int _currentRequestToken = 0;

  List<String> _availableVoices = [];
  String _selectedVoice = "";

  ConversationViewModel(this._llmService, this._speechService, this._ruleEngine) {
    _isMuted = _speechService.isMuted;
    
    // Load voices
    loadVoicesAsync();
    
    // Auto-start conversation
    sendMessageAsync(hiddenInput: "Xin chào");
  }

  List<String> get availableVoices => _availableVoices;
  String get selectedVoice => _selectedVoice;

  Future<void> loadVoicesAsync() async {
    try {
      _availableVoices = await _speechService.getVietnameseVoices();
      final currentVoice = _speechService.selectedVoiceName;
      if (_availableVoices.contains(currentVoice)) {
        _selectedVoice = currentVoice;
      } else if (_availableVoices.isNotEmpty) {
        _selectedVoice = _availableVoices.first;
        _speechService.selectedVoiceName = _selectedVoice;
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading voices: $e");
    }
  }

  void changeVoice(String newVoice) {
    _selectedVoice = newVoice;
    _speechService.selectedVoiceName = newVoice;
    notifyListeners();
  }

  Future<void> applyVoiceAndSpeakAsync(BuildContext context) async {
    if (_selectedVoice.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chưa chọn giọng nói")),
        );
      }
      return;
    }

    final String textToSpeak = _messages.isNotEmpty ? _messages.first.content : "Xin chào";
    
    _speechService.selectedVoiceName = _selectedVoice;
    
    // Play it
    await _speechService.speakAsync(textToSpeak);
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

  bool get isVoiceInputActive => _isVoiceInputActive;
  String get voiceInputStatus => _voiceInputStatus;
  bool get isVoiceRecording => _isVoiceRecording;
  bool get isVoiceTranscribing => _isVoiceTranscribing;
  bool get hasVoiceError => _hasVoiceError;
  String get voiceTranscribedText => _voiceTranscribedText;
  bool get hasVoiceResult => _voiceTranscribedText.isNotEmpty && !_isVoiceRecording && !_isVoiceTranscribing;

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
      debugPrint("[DEBUG] ExtractAmount Error: $ex");
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

  // Starts STT recording and keeps the popup open until user confirms or retries.
  // Returns immediately; popup stays visible via isVoiceInputActive flag.
  Future<void> startVoiceInputAsync() async {
    if (_isVoiceInputActive) return; // strict guard: prevent any re-entry while popup is open

    _isVoiceInputActive = true;
    _isVoiceRecording = false;
    _isVoiceTranscribing = false;
    _hasVoiceError = false;   // clear any previous error — popup is in "preparing" state
    _voiceTranscribedText = "";
    _voiceInputStatus = "Chuẩn bị micro...";
    notifyListeners();

    try {
      int deviceIndex = _ruleEngine.matchedMicrophoneIndex;
      if (deviceIndex == -1) deviceIndex = 0;

      final tempDir = await getTemporaryDirectory();
      final String path = "${tempDir.path}/voice_input.m4a";
      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');

      debugPrint("[Voice Input] INVOKING startRecording on device: $deviceIndex, path: $path");

      final String? startResult = await channel.invokeMethod<String>('startRecording', {
        'filePath': path,
        'deviceIndex': deviceIndex,
      });

      debugPrint("[Voice Input] Method 'startRecording' returned result: '$startResult'");

      if (startResult == "OK") {
        _isVoiceRecording = true;
        _voiceInputStatus = "Đang lắng nghe...";
        notifyListeners();

        await Future.delayed(const Duration(seconds: 5));

        debugPrint("[Voice Input] INVOKING stopRecording...");
        final bool? stopSuccess = await channel.invokeMethod<bool>('stopRecording');
        debugPrint("[Voice Input] Method 'stopRecording' returned: $stopSuccess");

        if (stopSuccess == true) {
          _isVoiceRecording = false;
          _isVoiceTranscribing = true;
          _voiceInputStatus = "Đang nhận diện...";
          notifyListeners();

          debugPrint("[Voice Input] INVOKING transcribeAudioAsync with path: $path");
          final String text = await _llmService.transcribeAudioAsync(path);
          debugPrint("[Voice Input] Transcription completed. Result length: ${text.length}. Content: '$text'");

          _isVoiceTranscribing = false;
          _voiceTranscribedText = text.trim();
          _voiceInputStatus = _voiceTranscribedText.isNotEmpty
              ? "Kết quả nhận diện:"
              : "Không nhận diện được giọng nói.";
          notifyListeners();
          return;
        } else {
          debugPrint("[Voice Input] FAILED to stop recording. stopSuccess was not true.");
          _voiceInputStatus = "Lỗi dừng file thu âm.";
        }
      } else {
        debugPrint("[Voice Input] FAILED to start recording: $startResult");
        _voiceInputStatus = startResult ?? "Không phản hồi từ thiết bị.";
      }

      _isVoiceRecording = false;
      _hasVoiceError = true;
      _voiceTranscribedText = "";
      notifyListeners();
    } catch (e, stack) {
      debugPrint("[Voice Input] EXCEPTION CAUGHT: $e");
      debugPrint("[Voice Input] STACK TRACE: $stack");
      _hasVoiceError = true;
      _voiceInputStatus = "Lỗi xảy ra: $e";
      _voiceTranscribedText = "";
      _isVoiceRecording = false;
      _isVoiceTranscribing = false;
      notifyListeners();
    }
  }

  // Retry STT from the voice popup — resets active flag first so guard doesn't block
  Future<void> retryVoiceInputAsync() async {
    if (_isVoiceRecording || _isVoiceTranscribing) return;
    _isVoiceInputActive = false; // temporarily reset so startVoiceInputAsync guard passes
    await startVoiceInputAsync();
  }

  // Called when user dismisses or confirms voice popup without accepting
  void cancelVoiceInput() {
    _isVoiceInputActive = false;
    _isVoiceRecording = false;
    _isVoiceTranscribing = false;
    _hasVoiceError = false;
    _voiceTranscribedText = "";
    _voiceInputStatus = "";
    notifyListeners();
  }
}

