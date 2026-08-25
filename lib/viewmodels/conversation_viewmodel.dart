import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';
import '../services/llm_service.dart';
import '../services/speech_service.dart';
import '../services/rule_engine_service.dart';
import '../services/log_service.dart';
import '../vapi/vapi_service.dart';
import '../vapi/vapi_models.dart';

class ConversationViewModel extends ChangeNotifier {
  final ILLMService _llmService;
  final ISpeechService _speechService;
  final IRuleEngineService _ruleEngine;
  final VapiService _vapiService = VapiService();

  bool flagVAPI = true; // Flag toggle VAPI integration (Default true as requested)

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

  StreamSubscription? _vapiTranscriptSub;
  StreamSubscription? _vapiStateSub;

  ConversationViewModel(this._llmService, this._speechService, this._ruleEngine) {
    _isMuted = _speechService.isMuted;
    
    // Load voices
    loadVoicesAsync();
    
    debugPrint("[ConversationVM] Initialized ConversationViewModel. flagVAPI=$flagVAPI");
  }

  Timer? _vapiTranscriptDebounce;
  File? _currentSessionLogFile;
  String? _currentSessionName;
  Timer? _saveLogFileDebounceTimer;

  String? get currentSessionFileName => _currentSessionLogFile?.path.split(Platform.pathSeparator).last;
  String? get currentSessionFilePath => _currentSessionLogFile?.path;

  static const MethodChannel _audioDevicesChannel = MethodChannel('com.soncamedia.listeningstation/audio_devices');

  /// Tạo 1 file JSON lưu xuống folder Download của thiết bị theo format conversation_YYYYMMDD_HHmm.json
  Future<void> initSessionLogAsync() async {
    try {
      final now = DateTime.now();
      final yyyy = now.year.toString().padLeft(4, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final hh = now.hour.toString().padLeft(2, '0');
      final min = now.minute.toString().padLeft(2, '0');

      // Format tên file: conversation_YYYYMMDD_HHmm (ví dụ: conversation_20260825_0901.json)
      _currentSessionName = "conversation_$yyyy$mm${dd}_${hh}m$min";
      final fileName = "$_currentSessionName.json";

      Directory? downloadDir;
      if (Platform.isAndroid) {
        final standardDownload = Directory('/storage/emulated/0/Download');
        if (await standardDownload.exists()) {
          downloadDir = standardDownload;
        } else {
          downloadDir = await getExternalStorageDirectory();
        }
      } else {
        downloadDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }
      downloadDir ??= await getApplicationDocumentsDirectory();

      _currentSessionLogFile = File("${downloadDir.path}/$fileName");
      debugPrint("[ConversationVM] Target session log: $fileName (path: ${_currentSessionLogFile?.path})");

      await _writeSessionLogNow();
    } catch (e) {
      debugPrint("[ConversationVM] Error initializing session log file: $e");
    }
  }

  void _scheduleSaveSessionLog() {
    _saveLogFileDebounceTimer?.cancel();
    _saveLogFileDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _writeSessionLogNow();
    });
  }

  Future<void> _writeSessionLogNow() async {
    final fileName = currentSessionFileName;
    if (fileName == null) return;

    try {
      final now = DateTime.now();
      final data = {
        "session": _currentSessionName ?? "conversation",
        "created_at": now.toIso8601String(),
        "total_messages": _messages.length,
        "messages": _messages.map((m) {
          final t = m.timestamp;
          final timeStr = "${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}";
          return {
            "speaker": m.sender,
            "text": m.content,
            "timestamp": timeStr,
          };
        }).toList(),
      };

      final encoder = const JsonEncoder.withIndent('  ');
      final jsonContent = encoder.convert(data);

      if (Platform.isAndroid) {
        // Sử dụng Native Android API để ghi file vào Environment.DIRECTORY_DOWNLOADS và kích hoạt MediaScanner
        final String? savedPath = await _audioDevicesChannel.invokeMethod<String>('saveJsonToDownload', {
          'fileName': fileName,
          'jsonContent': jsonContent,
        });
        debugPrint("[ConversationVM] Native saved conversation log (${_messages.length} msgs) -> $savedPath");
      } else {
        final file = _currentSessionLogFile;
        if (file != null) {
          await file.writeAsString(jsonContent, flush: true);
          debugPrint("[ConversationVM] Dart saved conversation log (${_messages.length} msgs) -> ${file.path}");
        }
      }
    } catch (e) {
      debugPrint("[ConversationVM] Error writing session log file: $e");
    }
  }

  void _initVapi() {
    debugPrint("[ConversationVM] Setting up Vapi listeners & starting call...");
    _vapiTranscriptSub?.cancel();
    _vapiStateSub?.cancel();
    _vapiTranscriptSub = _vapiService.onTranscriptUpdated.listen((vapiMessages) {
      if (!flagVAPI || vapiMessages.isEmpty) return;

      // Nếu là danh sách hội thoại hoàn chỉnh từ ConversationUpdate
      if (vapiMessages.length > 1) {
        _messages.clear();
        for (var vm in vapiMessages) {
          if (vm.text.trim().isNotEmpty) {
            _messages.add(ConversationMessage(
              sender: vm.speaker,
              content: vm.text.trim(),
              timestamp: DateTime.now(),
            ));
          }
        }
        _scheduleSaveSessionLog();
        notifyListeners();
        return;
      }

      // Xử lý từng mẩu tin Transcript thời gian thực (tức thời 0ms)
      for (var vm in vapiMessages) {
        final newText = vm.text.trim();
        if (newText.isEmpty) continue;

        // Điều khiển animation khuôn mặt Robot: SAY khi Trạm Lắng Nghe nói, SILIENCE khi người dùng nói
        if (vm.speaker == 'Trạm Lắng Nghe') {
          SpeechService.sendAnimationFace("SAY");
        } else {
          SpeechService.sendAnimationFace("SILIENCE");
        }

        if (_messages.isNotEmpty && _messages.last.sender == vm.speaker) {
          final lastText = _messages.last.content.trim();
          
          // Kiểm tra xem có phải là cùng 1 câu đang phát (cùng mở đầu hoặc câu mới chứa câu cũ)
          final isSameStream = newText.contains(lastText) || 
              lastText.contains(newText) ||
              newText.startsWith(lastText.substring(0, (lastText.length * 0.4).toInt())) ||
              (vm.speaker == 'Trạm Lắng Nghe' && !lastText.endsWith('?') && !lastText.endsWith('.') && !lastText.endsWith('!'));

          if (isSameStream) {
            // Cập nhật câu dài hơn và đầy đủ hơn vào bong bóng hiện tại
            _messages[_messages.length - 1] = ConversationMessage(
              sender: vm.speaker,
              content: newText.length >= lastText.length ? newText : lastText,
              timestamp: DateTime.now(),
            );
          } else {
            // Câu hoàn toàn mới độc lập
            _messages.add(ConversationMessage(
              sender: vm.speaker,
              content: newText,
              timestamp: DateTime.now(),
            ));
          }
        } else {
          // Người khác bắt đầu nói -> thêm ngay bong bóng mới
          _messages.add(ConversationMessage(
            sender: vm.speaker,
            content: newText,
            timestamp: DateTime.now(),
          ));
        }
        // Tự động kích hoạt nút "Kết thúc hội thoại" (Finalize) khi AI nói câu kết thúc
        if (vm.speaker == 'Trạm Lắng Nghe' &&
            newText.contains("Con sẽ gửi hồ sơ này về Quỹ Bông Sen để xem xét") &&
            !_isFinalizeVisible &&
            !_isFinalizeConfirmed) {
          LogService.log("[ConversationVM] Detected completion phrase -> Auto triggering showFinalizeAsync");
          Future.delayed(const Duration(seconds: 2), () {
            if (!_isFinalizeVisible && !_isFinalizeConfirmed) {
              SpeechService.sendAnimationFace("SILIENCE");
              showFinalizeAsync();
            }
          });
        }
      }
      _scheduleSaveSessionLog();
      notifyListeners();
    });

    _vapiStateSub = _vapiService.onCallStateChanged.listen((state) {
      if (!flagVAPI) return;
      LogService.log("[ConversationVM] OnCallStateChanged fired: $state");
      if (state == VapiCallState.connecting) {
        _isProcessing = true;
      } else if (state == VapiCallState.active) {
        _isProcessing = false;
      } else if (state == VapiCallState.ended || state == VapiCallState.error) {
        _isProcessing = false;
        SpeechService.sendAnimationFace("SILIENCE");
      }
      notifyListeners();
    });

    _vapiService.startCall(assistantId: "326d0d50-c102-446b-9fc5-90265dd901ae");
  }

  void startVapiCall() {
    _speechService.stop();
    _initVapi();
  }

  void toggleVapiFlag(bool value) {
    flagVAPI = value;
    debugPrint("[ConversationVM] Toggled flagVAPI -> $flagVAPI");
    if (flagVAPI) {
      _speechService.stop();
      _initVapi();
    } else {
      _vapiTranscriptDebounce?.cancel();
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _saveLogFileDebounceTimer?.cancel();
    _writeSessionLogNow();
    _vapiTranscriptDebounce?.cancel();
    _vapiTranscriptSub?.cancel();
    _vapiStateSub?.cancel();
    _vapiService.dispose();
    super.dispose();
  }

  List<String> get availableVoices => _availableVoices;
  String get selectedVoice => _selectedVoice;
  String get onlineTtsProvider => _speechService.onlineTtsProvider;
  bool get isLocalTTS => _speechService.flagLocalTTS;
  bool get showLocalVoiceOptions => _speechService.flagLocalTTS && _speechService.flagLocalTTS_checkSwitch;

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

  void changeOnlineProvider(String provider) {
    _speechService.onlineTtsProvider = provider;
    // Reload voices for the new provider
    loadVoicesAsync();
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
      _writeSessionLogNow();
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

    _writeSessionLogNow();
    _isProcessing = false;
    notifyListeners();

    // Play TTS and wait for it to finish
    await _speechService.speakAsync(aiResponse);
    
    // Auto-open voice input popup after TTS finishes
    startVoiceInputAsync();
  }

  Future<void> showFinalizeAsync() async {
    _isProcessing = true;
    _isFinalizeConfirmed = false;
    _finalizeResult = "Đang kiểm tra thông tin, vui lòng chờ...";
    _isFinalizeVisible = true;

    // Ngắt cuộc gọi Vapi và micro ngay khi bắt đầu kết thúc hội thoại
    if (flagVAPI) {
      _vapiTranscriptDebounce?.cancel();
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }

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

    // Tắt Vapi hoàn toàn khi rời khỏi ConversationView chuyển sang ResultView
    if (flagVAPI) {
      _vapiTranscriptDebounce?.cancel();
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }

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

    // Ngắt cuộc gọi Vapi ngay lập tức
    _vapiTranscriptSub?.cancel();
    _vapiStateSub?.cancel();
    await _vapiService.stopCall();

    _isProcessing = true;
    _messages.clear();
    notifyListeners();

    final demoMsgs = await _llmService.getDemoMessagesAsync();
    for (var msg in demoMsgs) {
      _messages.add(msg);
      _scheduleSaveSessionLog();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300)); // Smooth script population
    }

    _isProcessing = false;
    _writeSessionLogNow();
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

    // Dừng cuộc gọi Vapi khi dọn dẹp hội thoại, không tự động gọi lại ở đây để tránh phát tiếng ngoài màn hình
    if (flagVAPI) {
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }
  }

  String _recordingPath = "";
  Timer? _safetyTimer;

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
      _recordingPath = "${tempDir.path}/voice_input.m4a";
      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');

      debugPrint("[Voice Input] INVOKING startRecording on device: $deviceIndex, path: $_recordingPath");

      final String? startResult = await channel.invokeMethod<String>('startRecording', {
        'filePath': _recordingPath,
        'deviceIndex': deviceIndex,
      });

      debugPrint("[Voice Input] Method 'startRecording' returned result: '$startResult'");

      if (startResult == "OK") {
        _isVoiceRecording = true;
        _voiceInputStatus = "Đang lắng nghe...";
        notifyListeners();

        // Safety timeout to automatically stop recording after 45 seconds if user forgets
        _safetyTimer?.cancel();
        _safetyTimer = Timer(const Duration(seconds: 45), () {
          debugPrint("[Voice Input] Safety timeout reached (45s). Auto-stopping...");
          stopVoiceRecordingAsync();
        });
      } else {
        debugPrint("[Voice Input] FAILED to start recording: $startResult");
        _voiceInputStatus = startResult ?? "Không phản hồi từ thiết bị.";
        _isVoiceRecording = false;
        _hasVoiceError = true;
        notifyListeners();
      }
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

  // Manually stops recording and triggers transcription
  Future<void> stopVoiceRecordingAsync() async {
    _safetyTimer?.cancel();
    if (!_isVoiceRecording) return;

    _isVoiceRecording = false;
    _isVoiceTranscribing = true;
    _voiceInputStatus = "Đang nhận diện...";
    notifyListeners();

    try {
      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
      debugPrint("[Voice Input] INVOKING stopRecording...");
      final bool? stopSuccess = await channel.invokeMethod<bool>('stopRecording');
      debugPrint("[Voice Input] Method 'stopRecording' returned: $stopSuccess");

      if (stopSuccess == true) {
        debugPrint("[Voice Input] INVOKING transcribeAudioAsync with path: $_recordingPath");
        final String text = await _llmService.transcribeAudioAsync(_recordingPath);
        debugPrint("[Voice Input] Transcription completed. Result length: ${text.length}. Content: '$text'");

        _isVoiceTranscribing = false;
        _voiceTranscribedText = text.trim();
        _voiceInputStatus = _voiceTranscribedText.isNotEmpty
            ? "Kết quả nhận diện:"
            : "Không nhận diện được giọng nói.";
        notifyListeners();
      } else {
        debugPrint("[Voice Input] FAILED to stop recording. stopSuccess was not true.");
        _voiceInputStatus = "Lỗi dừng file thu âm.";
        _isVoiceTranscribing = false;
        _hasVoiceError = true;
        notifyListeners();
      }
    } catch (e, stack) {
      debugPrint("[Voice Input] stopVoiceRecordingAsync EXCEPTION CAUGHT: $e");
      debugPrint("[Voice Input] STACK TRACE: $stack");
      _isVoiceTranscribing = false;
      _hasVoiceError = true;
      _voiceInputStatus = "Lỗi nhận diện: $e";
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
    _safetyTimer?.cancel();
    if (_isVoiceRecording) {
      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
      channel.invokeMethod<bool>('stopRecording').catchError((e) {
        debugPrint("[Voice Input] Error stopping recording on cancel: $e");
        return false;
      });
    }
    _isVoiceInputActive = false;
    _isVoiceRecording = false;
    _isVoiceTranscribing = false;
    _hasVoiceError = false;
    _voiceTranscribedText = "";
    _voiceInputStatus = "";
    notifyListeners();
  }
}

