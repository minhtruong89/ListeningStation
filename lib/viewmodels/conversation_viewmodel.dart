import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  bool _isFinalizing = false;
  VoidCallback? onNavigateToResult;

  bool _isPendingAutoFinalize = false;
  DateTime? _autoFinalizeDetectedTime;
  DateTime? _autoFinalizeLastTextUpdate;
  String _autoFinalizeFullText = "";
  Timer? _autoFinalizeTimer;
  StreamSubscription? _vapiSpeechUpdateSub;

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

  int storytellingDurationSeconds = 180; // 3 phút tùy chỉnh trong app
  bool _isStorytellingActive = false;
  int _storytellingRemainingSeconds = 180;
  DateTime? _storytellingStartTime;
  Timer? _storytellingTimer;

  bool get isStorytellingActive => _isStorytellingActive;
  int get storytellingRemainingSeconds => _storytellingRemainingSeconds;
  String get storytellingFormattedTime {
    final minutes = (_storytellingRemainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_storytellingRemainingSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void startStorytellingPhase({int? customSeconds}) {
    _storytellingTimer?.cancel();
    _isStorytellingActive = true;
    _storytellingStartTime = DateTime.now();
    _storytellingRemainingSeconds = customSeconds ?? storytellingDurationSeconds;

    // Tắt tiếng loa trợ lý trong suốt thời gian kể tự do để bảo đảm người dùng không bị xen ngang/cắt lời
    if (flagVAPI) {
      LogService.log("[ConversationVM] Muting assistant speaker for free storytelling phase");
      _vapiService.setSpeakerMuted(true);
    }

    notifyListeners();

    _storytellingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_storytellingRemainingSeconds > 1) {
        _storytellingRemainingSeconds--;
        notifyListeners();
      } else {
        stopStorytellingPhase();
      }
    });
  }

  void stopStorytellingPhase({bool notifyServer = true}) {
    _storytellingTimer?.cancel();
    if (_isStorytellingActive) {
      _isStorytellingActive = false;

      // Mở lại tiếng loa trợ lý ngay sau khi kết thúc giai đoạn kể tự do
      if (flagVAPI) {
        LogService.log("[ConversationVM] Unmuting assistant speaker after free storytelling phase");
        _vapiService.setSpeakerMuted(false);
      }

      // Chốt dứt điểm lượt nói của người dùng trước khi trợ lý bắt đầu Giai đoạn 3
      if (_activeSpeaker == 'Người cần giúp đỡ') {
        _settleActiveTurn();
      }

      notifyListeners();

      if (notifyServer) {
        // Tự động append câu "Tôi đã kể xong." và gửi sang Vapi để bắt đầu Giai đoạn 3
        _messages.add(ConversationMessage(
          sender: "Người cần giúp đỡ",
          content: "Tôi đã kể xong.",
          timestamp: DateTime.now(),
        ));
        _writeSessionLogNow();
        notifyListeners();

        if (flagVAPI) {
          _vapiService.sendMessage("Tôi đã kể xong.");
        }
      }
    }
  }

  Timer? _vapiTranscriptDebounce;
  Timer? _transcriptDebounceTimer;
  final List<String> _currentTurnLockedSentences = [];
  String _currentTurnStreamingSentence = "";
  String _activeSpeaker = "";
  String _pendingHintSpeaker = "";

  DateTime _lastStreamingNotifyTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamingNotifyTimer;

  void _notifyListenersStreamingThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastStreamingNotifyTime).inMilliseconds >= 80) {
      _streamingNotifyTimer?.cancel();
      _streamingNotifyTimer = null;
      _lastStreamingNotifyTime = now;
      notifyListeners();
    } else {
      _streamingNotifyTimer ??= Timer(const Duration(milliseconds: 80), () {
        _streamingNotifyTimer = null;
        _lastStreamingNotifyTime = DateTime.now();
        notifyListeners();
      });
    }
  }

  String get _pendingTranscriptText => _getCurrentTurnFullText();
  File? _currentSessionLogFile;
  String? _currentSessionName;
  Timer? _saveLogFileDebounceTimer;
  Map<String, dynamic>? _scoringResult;

  String? get currentSessionFileName => _currentSessionLogFile?.path.split(Platform.pathSeparator).last;
  String? get currentSessionFilePath => _currentSessionLogFile?.path;
  Map<String, dynamic>? get scoringResult => _scoringResult;

  /// Cập nhật kết quả chấm điểm (distress score, hệ số giải ngân, breakdown...) và ghi ngay vào file log session
  Future<void> updateSessionLogWithScoring(Map<String, dynamic> data) async {
    _scoringResult = data;
    if (_currentSessionLogFile == null) {
      await initSessionLogAsync();
    } else {
      await _writeSessionLogNow();
    }
  }

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
    if (_pendingTranscriptText.trim().isNotEmpty) {
      _commitPendingTranscript();
    }
    final fileName = currentSessionFileName;
    if (fileName == null) return;

    try {
      final now = DateTime.now();
      final Map<String, dynamic> data = {
        "session": _currentSessionName ?? "conversation",
        "created_at": now.toIso8601String(),
        "total_messages": _messages.length,
        if (_scoringResult != null) "scoring_result": _scoringResult,
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

  bool _isUtteranceUpdate(String current, String incoming) {
    if (current.isEmpty) return true;
    if (incoming.isEmpty) return true;
    if (current == incoming) return true;

    final currLower = current.toLowerCase().trim();
    final incLower = incoming.toLowerCase().trim();

    // 1. Một câu bao hàm câu kia (streaming nối dài thêm hoặc chỉnh sửa)
    if (incLower.contains(currLower) || currLower.contains(incLower)) {
      return true;
    }

    // 2. Kiểm tra trùng khớp từ ở phần mở đầu (cùng 1 câu đang nói dở)
    final currWords = currLower.split(RegExp(r'\s+'));
    final incWords = incLower.split(RegExp(r'\s+'));

    if (currWords.isNotEmpty && incWords.isNotEmpty) {
      if (currWords.first == incWords.first) {
        if (currWords.length <= 2 || incWords.length <= 2) return true;
        if (currWords[1] == incWords[1]) return true;
      }

      int matchCount = 0;
      final checkLen = math.min(math.min(currWords.length, incWords.length), 4);
      for (int i = 0; i < checkLen; i++) {
        if (currWords[i] == incWords[i]) matchCount++;
      }
      if (matchCount >= 2) return true;
    }

    // 3. Trùng khớp tiền tố ký tự
    final minLen = math.min(currLower.length, incLower.length);
    final prefixCheckLen = math.min(minLen, 15);
    if (prefixCheckLen >= 5 && currLower.substring(0, prefixCheckLen) == incLower.substring(0, prefixCheckLen)) {
      return true;
    }

    return false;
  }

  String _getCurrentTurnFullText() {
    final curr = _currentTurnStreamingSentence.trim();
    final currLower = curr.toLowerCase();

    final List<String> parts = [];
    for (var s in _currentTurnLockedSentences) {
      final clean = s.trim();
      if (clean.isNotEmpty) {
        // Nếu câu đang stream dở đã bao hàm câu này từ đầu, không thêm lặp lại
        if (currLower.contains(clean.toLowerCase())) continue;
        if (parts.isEmpty || parts.last.toLowerCase() != clean.toLowerCase()) {
          parts.add(clean);
        }
      }
    }

    if (curr.isNotEmpty) {
      if (parts.isEmpty || parts.last.toLowerCase() != curr.toLowerCase()) {
        parts.add(curr);
      }
    }
    return parts.join(" ").trim();
  }

  String _determineSpeakerForIncoming(String text, {String? hintSpeaker}) {
    final lower = text.toLowerCase().trim();

    // 1. Khi chưa có tin nhắn nào trong cuộc gọi và là câu chào mở đầu -> Luôn là Trạm Lắng Nghe
    if (_messages.isEmpty && _currentTurnLockedSentences.isEmpty && _currentTurnStreamingSentence.isEmpty) {
      if (lower.contains('con chào') || lower.contains('quỹ bông sen') || lower.contains('trạm lắng nghe') || hintSpeaker == 'Trạm Lắng Nghe') {
        return 'Trạm Lắng Nghe';
      }
    }

    // 2. Nhận diện các câu nói chắc chắn của người dùng
    final bool isUserExplicit = lower.startsWith('tôi đồng ý') ||
        lower == 'đồng ý' ||
        lower == 'đồng ý.' ||
        lower.startsWith('không đồng ý') ||
        lower.startsWith('tôi tên') ||
        lower.startsWith('tôi bị') ||
        lower.startsWith('tôi đi làm') ||
        lower.startsWith('tôi ở') ||
        lower.startsWith('tôi làm') ||
        lower.startsWith('tôi đã kể xong') ||
        lower.startsWith('tôi kể xong') ||
        lower.startsWith('kể xong rồi') ||
        lower.startsWith('đã xong');

    if (isUserExplicit) {
      return 'Người cần giúp đỡ';
    }

    // 3. Nhận diện các câu chắc chắn của trợ lý
    final bool isAssistantExplicit = lower.contains('con chào') ||
        lower.contains('chào cô bác') ||
        lower.contains('chào chú') ||
        lower.contains('chào bác') ||
        lower.contains('con là') ||
        lower.contains('con xin') ||
        lower.contains('con cảm ơn') ||
        lower.contains('cho con hỏi') ||
        lower.contains('hỏi thêm') ||
        lower.contains('công việc hay nghề nghiệp') ||
        lower.contains('nghề nghiệp của') ||
        lower.contains('công việc của') ||
        lower.contains('thu nhập của') ||
        lower.contains('bao nhiêu mỗi tháng') ||
        lower.contains('bao nhiêu mỗi ngày') ||
        lower.contains('vẫn đang nghe') ||
        lower.contains('kể tiếp') ||
        lower.contains('cô bác chia sẻ') ||
        lower.contains('cô bác') ||
        lower.contains('chú ơi') ||
        lower.contains('bác ơi') ||
        lower.contains('quỹ bông sen') ||
        lower.contains('trạm lắng nghe') ||
        lower.contains('xem xét hỗ trợ') ||
        lower.contains('vui lòng nói') ||
        lower.contains('đồng ý không ạ') ||
        lower == 'được.' ||
        lower == 'được' ||
        lower == 'dạ.' ||
        lower == 'dạ' ||
        lower == 'dạ vâng.' ||
        lower == 'dạ vâng' ||
        lower == 'dạ chú.' ||
        lower == 'dạ chú' ||
        lower.endsWith('ạ?') ||
        lower.endsWith('ạ.');

    if (isAssistantExplicit) {
      return 'Trạm Lắng Nghe';
    }

    // 4. Ưu tiên phân định theo hintSpeaker từ WebRTC (track microphone của người dùng vs audio của trợ lý)
    if (hintSpeaker != null && hintSpeaker.isNotEmpty) {
      if (hintSpeaker == 'Người cần giúp đỡ') {
        return 'Người cần giúp đỡ';
      }
      if (hintSpeaker == 'Trạm Lắng Nghe') {
        return 'Trạm Lắng Nghe';
      }
    }

    // 5. Nếu không có hintSpeaker, duy trì speaker theo lượt nói hiện tại
    if (_activeSpeaker.isNotEmpty) {
      if (_activeSpeaker == 'Trạm Lắng Nghe' && !isUserExplicit) {
        return 'Trạm Lắng Nghe';
      }
      if (_activeSpeaker == 'Người cần giúp đỡ' && !isAssistantExplicit) {
        return 'Người cần giúp đỡ';
      }
    }

    // 6. Sử dụng hàm phân định tổng quát
    return _resolveSpeaker(text, hintSpeaker: hintSpeaker);
  }

  String _resolveSpeaker(String text, {String? hintSpeaker}) {
    final clean = text.trim();
    if (clean.isEmpty) return hintSpeaker ?? 'Người cần giúp đỡ';

    // 1. Nếu là câu mở đầu cuộc trò chuyện (chưa có tin nhắn nào trong danh sách), 100% là Trạm Lắng Nghe
    if (_messages.isEmpty) {
      return 'Trạm Lắng Nghe';
    }

    final lower = clean.toLowerCase();

    // 2. Các cụm từ đặc trưng chỉ Trạm Lắng Nghe sử dụng (xưng con, gọi cô bác/chú/bác, Quỹ Bông Sen, câu hỏi khảo sát...)
    final bool hasAssistantPronouns = lower.contains('con chào') ||
        lower.contains('chào cô bác') ||
        lower.contains('chào chú') ||
        lower.contains('chào bác') ||
        lower.contains('con là') ||
        lower.contains('con xin') ||
        lower.contains('con cảm ơn') ||
        lower.contains('con hiểu') ||
        lower.contains('cho con hỏi') ||
        lower.contains('giùm con') ||
        lower.contains('cô bác') ||
        lower.contains('cô/bác') ||
        lower.contains('chú ơi') ||
        lower.contains('bác ơi');

    final bool hasAssistantOrgKeywords = lower.contains('trạm lắng nghe') ||
        lower.contains('quỹ bông sen') ||
        lower.contains('bông sen') ||
        lower.contains('xem xét hỗ trợ') ||
        lower.contains('kiểm tra hoàn cảnh') ||
        lower.contains('hậu kiểm') ||
        lower.contains('hội đồng') ||
        lower.contains('chuyển hồ sơ') ||
        lower.contains('gửi hồ sơ');

    final bool hasAssistantInstructionKeywords = lower.contains('vui lòng nói') ||
        lower.contains('đồng ý không ạ') ||
        (lower.contains('không đồng ý') && lower.contains('vui lòng')) ||
        lower.contains('kể tường tận') ||
        lower.contains('kể càng chi tiết') ||
        lower.contains('thu nhập trung bình') ||
        lower.contains('thu nhập này của chú') ||
        lower.contains('chi phí sinh hoạt') ||
        lower.contains('khoản viện phí') ||
        lower.contains('số tiền nợ') ||
        lower.contains('nuôi dưỡng hay chăm sóc') ||
        lower.contains('tài sản nào có thể') ||
        lower.contains('tạm dừng và đóng ca') ||
        lower.contains('đóng ca hỗ trợ') ||
        lower.contains('tư vấn tâm lý chuyên sâu') ||
        lower.contains('kết thúc ca hỗ trợ');

    // Các từ đệm/phản hồi ngắn đặc trưng của AI Trạm Lắng Nghe khi người dùng vừa cung cấp thông tin
    final bool isShortAssistantAck = lower == 'được.' ||
        lower == 'được' ||
        lower == 'dạ.' ||
        lower == 'dạ' ||
        lower == 'dạ vâng.' ||
        lower == 'dạ vâng' ||
        lower == 'dạ chú.' ||
        lower == 'dạ chú' ||
        lower == 'dạ cô.' ||
        lower == 'dạ bác.' ||
        lower == 'dạ được.' ||
        lower == 'vâng ạ.' ||
        lower == 'vâng ạ' ||
        lower == 'vâng.';

    final bool endsWithAssistantQuestion = lower.endsWith('ạ?') ||
        lower.endsWith('ạ.') ||
        lower.endsWith('ạ') ||
        lower.endsWith('nhé?') ||
        lower.endsWith('không ạ?') ||
        lower.endsWith('đúng không ạ?') ||
        lower.endsWith('phải không ạ?');

    if (hasAssistantPronouns || hasAssistantOrgKeywords || hasAssistantInstructionKeywords) {
      return 'Trạm Lắng Nghe';
    }

    if (isShortAssistantAck) {
      return 'Trạm Lắng Nghe';
    }

    if (endsWithAssistantQuestion && !lower.startsWith('tôi') && !lower.contains('tôi đồng ý')) {
      return 'Trạm Lắng Nghe';
    }

    // 3. Các từ khóa đặc trưng của Người cần giúp đỡ (xưng tôi, câu trả lời trực tiếp)
    final bool isUserDirectResponse = lower.contains('tôi đồng ý') ||
        lower == 'đồng ý' ||
        lower == 'đồng ý.' ||
        lower.contains('không đồng ý') ||
        lower.contains('tôi đã kể xong') ||
        lower.contains('tôi kể xong') ||
        lower.contains('đã kể xong') ||
        lower.contains('kể xong rồi') ||
        lower.startsWith('tôi tên') ||
        lower.startsWith('tôi bị') ||
        lower.startsWith('tôi đi làm') ||
        lower.startsWith('tôi ở') ||
        lower.startsWith('tôi làm');

    if (isUserDirectResponse) {
      return 'Người cần giúp đỡ';
    }

    // 4. Nếu có hint từ backend WebRTC
    if (hintSpeaker != null && hintSpeaker.isNotEmpty) {
      if (hintSpeaker == 'Trạm Lắng Nghe' && (lower.contains('dạ') || endsWithAssistantQuestion || (_messages.isNotEmpty && _messages.last.sender == 'Người cần giúp đỡ'))) {
        return 'Trạm Lắng Nghe';
      }
      if (hintSpeaker == 'Người cần giúp đỡ' && !hasAssistantPronouns && !hasAssistantOrgKeywords) {
        return 'Người cần giúp đỡ';
      }
    }

    // 5. Heuristic luân phiên lượt nói (Turn alternation):
    if (_messages.isNotEmpty && _messages.last.sender == 'Người cần giúp đỡ') {
      if (lower.startsWith('dạ') || endsWithAssistantQuestion || lower.length > 30) {
        return 'Trạm Lắng Nghe';
      }
    }

    if (_messages.isNotEmpty && _messages.last.sender == 'Trạm Lắng Nghe') {
      return 'Người cần giúp đỡ';
    }

    return 'Người cần giúp đỡ';
  }

  void _settleActiveTurn() {
    _streamingNotifyTimer?.cancel();
    _streamingNotifyTimer = null;
    _transcriptDebounceTimer?.cancel();
    _transcriptDebounceTimer = null;

    final fullText = _getCurrentTurnFullText();
    final speaker = _activeSpeaker.isNotEmpty
        ? _activeSpeaker
        : _resolveSpeaker(fullText, hintSpeaker: _pendingHintSpeaker);

    _currentTurnLockedSentences.clear();
    _currentTurnStreamingSentence = "";
    _activeSpeaker = "";
    _pendingHintSpeaker = "";

    if (fullText.isEmpty) return;

    LogService.log("[ConversationVM] Turn settled (1.6s silence) -> [$speaker]: $fullText");

    // Đảm bảo tin nhắn cuối cùng trong _messages chứa trọn vẹn fullText chuẩn xác
    if (_messages.isNotEmpty && _messages.last.sender == speaker) {
      _messages[_messages.length - 1] = ConversationMessage(
        sender: speaker,
        content: fullText,
        timestamp: _messages.last.timestamp,
      );
    } else {
      _messages.add(ConversationMessage(
        sender: speaker,
        content: fullText,
        timestamp: DateTime.now(),
      ));
    }

    // Kích hoạt animation mặt robot
    if (speaker == 'Trạm Lắng Nghe') {
      SpeechService.sendAnimationFace("SAY");
    } else {
      SpeechService.sendAnimationFace("SILIENCE");
    }

    // Tự động đóng banner Kể tự do khi Người dùng kết thúc
    if (_isStorytellingActive &&
        speaker != 'Trạm Lắng Nghe' &&
        _storytellingStartTime != null &&
        DateTime.now().difference(_storytellingStartTime!).inSeconds >= 3) {
      final lower = fullText.toLowerCase();
      if (lower.contains("tôi đã kể xong") ||
          lower.contains("đã kể xong") ||
          lower.contains("tôi kể xong rồi") ||
          lower.contains("kể xong rồi") ||
          lower.contains("con đã kể xong") ||
          lower.contains("kể hết rồi") ||
          lower.contains("hết rồi") ||
          lower.contains("kể xong")) {
        LogService.log("[ConversationVM] Detected completion keyword from user -> Auto closing storytelling banner");
        stopStorytellingPhase(notifyServer: false);
      }
    }

    // Tự động kích hoạt popup Kể tự do khi AI đã đọc đến đoạn kết thúc câu mời: "con sẽ ghi nhận hết ạ"
    if (speaker == 'Trạm Lắng Nghe' &&
        (fullText.toLowerCase().contains("con sẽ ghi nhận hết") ||
            fullText.toLowerCase().contains("ghi nhận hết ạ") ||
            fullText.toLowerCase().contains("kể tường tận cho con nghe")) &&
        !_isStorytellingActive) {
      LogService.log("[ConversationVM] Detected final invitation phrase ('con sẽ ghi nhận hết') -> Auto starting startStorytellingPhase");
      startStorytellingPhase();
    }

    // Tự động kích hoạt kết thúc hội thoại khi AI nói câu kết thúc hoặc TẦNG BẢO VỆ được kích hoạt
    final String lower = fullText.toLowerCase();
    final bool isCompletionPhrase = lower.contains("con sẽ gửi hồ sơ") ||
        lower.contains("gửi hồ sơ này lên hội đồng") ||
        lower.contains("gửi hồ sơ lên hội đồng") ||
        lower.contains("chuyển hồ sơ cho quỹ") ||
        lower.contains("chuyển hồ sơ lên hội đồng") ||
        lower.contains("kết thúc buổi trao đổi") ||
        lower.contains("kết thúc cuộc trò chuyện") ||
        lower.contains("kết thúc buổi chia sẻ");

    final bool isGuardLayerTriggered = lower.contains("tạm dừng và đóng ca") ||
        lower.contains("đóng ca hỗ trợ") ||
        lower.contains("đóng ca tại đây") ||
        lower.contains("chưa có chức năng tư vấn tâm lý") ||
        lower.contains("tư vấn tâm lý chuyên sâu") ||
        lower.contains("tạm dừng cuộc gọi") ||
        lower.contains("kết thúc ca hỗ trợ") ||
        lower.contains("dừng ca hỗ trợ") ||
        lower.contains("xin phép dừng ca");

    if (speaker == 'Trạm Lắng Nghe' &&
        (isCompletionPhrase || isGuardLayerTriggered) &&
        !_isFinalizing) {
      if (!_isPendingAutoFinalize) {
        _isPendingAutoFinalize = true;
        _autoFinalizeDetectedTime = DateTime.now();
        LogService.log("[ConversationVM] Detected completion or guard layer trigger phrase -> Starting auto-finalize watcher, will wait until AI finishes full sentence...");
      }
      _autoFinalizeLastTextUpdate = DateTime.now();
      _autoFinalizeFullText = fullText;
      _scheduleAutoFinalizeCheck(fullText);
    }

    _scheduleSaveSessionLog();
    notifyListeners();
  }

  void _commitPendingTranscript() => _settleActiveTurn();

  void _initVapi() {
    debugPrint("[ConversationVM] Setting up Vapi listeners & starting call...");
    _vapiTranscriptSub?.cancel();
    _vapiStateSub?.cancel();
    _vapiSpeechUpdateSub?.cancel();
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;
    _vapiTranscriptSub = _vapiService.onTranscriptUpdated.listen((vapiMessages) {
      if (!flagVAPI || vapiMessages.isEmpty) return;

      final bool isConvUpdate = vapiMessages.any((m) => m.isConversationUpdate) || vapiMessages.length > 1;

      // Nếu là danh sách hội thoại hoàn chỉnh từ ConversationUpdate (chuẩn 100% như Vapi Dashboard)
      if (isConvUpdate) {
        _transcriptDebounceTimer?.cancel();
        _transcriptDebounceTimer = null;
        _currentTurnLockedSentences.clear();
        _currentTurnStreamingSentence = "";
        _activeSpeaker = "";
        _pendingHintSpeaker = "";

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
        if (_isStorytellingActive &&
            _storytellingStartTime != null &&
            DateTime.now().difference(_storytellingStartTime!).inSeconds >= 3) {
          for (var vm in vapiMessages) {
            if (vm.speaker != 'Trạm Lắng Nghe') {
              final lower = vm.text.toLowerCase();
              if (lower.contains("tôi đã kể xong") ||
                  lower.contains("đã xong") ||
                  lower.contains("đã kể xong") ||
                  lower.contains("tôi kể xong rồi") ||
                  lower.contains("kể xong rồi") ||
                  lower.contains("con đã kể xong") ||
                  lower.contains("kể hết rồi") ||
                  lower.contains("hết rồi") ||
                  lower.contains("kể xong")) {
                LogService.log("[ConversationVM] Detected completion keyword in ConversationUpdate from user -> Auto closing storytelling banner");
                stopStorytellingPhase(notifyServer: false);
                break;
              }
            }
          }
        }
        _streamingNotifyTimer?.cancel();
        _streamingNotifyTimer = null;
        _scheduleSaveSessionLog();
        notifyListeners();
        return;
      }

      // Xử lý từng mẩu tin Transcript thời gian thực: Hiển thị từ từ ra UI ngay lập tức
      for (var vm in vapiMessages) {
        final newText = vm.text.trim();
        if (newText.isEmpty) continue;

        // Xác định người nói cho mẩu tin mới
        final incomingSpeaker = _determineSpeakerForIncoming(newText, hintSpeaker: vm.speaker);

        // Trong giai đoạn kể tự do (Storytelling), tuyệt đối chặn mọi câu chen ngang từ trợ lý (như "Dạ con vẫn đang nghe...", "kể tiếp đi ạ...")
        if (_isStorytellingActive && incomingSpeaker == 'Trạm Lắng Nghe') {
          LogService.log("[ConversationVM] Suppressed assistant interruption during storytelling: '$newText'");
          continue;
        }

        // Kiểm tra từ khóa hoàn tất lời kể từ người dùng trong giai đoạn kể tự do
        if (_isStorytellingActive && incomingSpeaker == 'Người cần giúp đỡ') {
          final lower = newText.toLowerCase();
          final bool isFinishedKeyword = lower.contains("tôi đã kể xong") ||
              lower.contains("đã xong") ||
              lower.contains("đã kể xong") ||
              lower.contains("tôi kể xong rồi") ||
              lower.contains("kể xong rồi") ||
              lower.contains("con đã kể xong") ||
              lower.contains("kể hết rồi") ||
              lower.contains("hết rồi") ||
              lower.contains("kể xong");

          if (isFinishedKeyword &&
              _storytellingStartTime != null &&
              DateTime.now().difference(_storytellingStartTime!).inSeconds >= 2) {
            LogService.log("[ConversationVM] Detected finish keyword '$newText' during live streaming -> Stopping storytelling phase");
            stopStorytellingPhase(notifyServer: false);
          }
        }

        // Nếu người nói đổi vai (ví dụ: AI nói xong, người dùng bắt đầu nói):
        if (_activeSpeaker.isNotEmpty && _activeSpeaker != incomingSpeaker) {
          LogService.log("[ConversationVM] Speaker changed from $_activeSpeaker to $incomingSpeaker -> Settling previous turn");
          _settleActiveTurn();
        }

        // Thiết lập người nói cho lượt hiện tại
        _activeSpeaker = incomingSpeaker;
        if (vm.speaker.isNotEmpty) {
          _pendingHintSpeaker = vm.speaker;
        }

        // Cập nhật câu vào bộ đệm streaming: thay thế nếu cùng câu, thêm mới nếu sang câu kế tiếp
        if (_isUtteranceUpdate(_currentTurnStreamingSentence, newText)) {
          if (newText.length >= _currentTurnStreamingSentence.length || !newText.endsWith('...')) {
            _currentTurnStreamingSentence = newText;
          }
        } else {
          if (_currentTurnStreamingSentence.trim().isNotEmpty) {
            final finished = _currentTurnStreamingSentence.trim();
            if (_currentTurnLockedSentences.isEmpty ||
                _currentTurnLockedSentences.last.toLowerCase() != finished.toLowerCase()) {
              _currentTurnLockedSentences.add(finished);
            }
          }
          _currentTurnStreamingSentence = newText;
        }

        // Lấy nội dung tích luỹ đầy đủ của lượt nói này (bao gồm cả các câu đã qua và câu đang stream)
        final fullTurnText = _getCurrentTurnFullText();

        // Cập nhật NGAY LẬP TỨC vào _messages để UI hiển thị từ từ ra, người dùng không phải chờ hết câu
        if (_messages.isNotEmpty && _messages.last.sender == _activeSpeaker) {
          _messages[_messages.length - 1] = ConversationMessage(
            sender: _activeSpeaker,
            content: fullTurnText,
            timestamp: _messages.last.timestamp,
          );
        } else {
          _messages.add(ConversationMessage(
            sender: _activeSpeaker,
            content: fullTurnText,
            timestamp: DateTime.now(),
          ));
        }

        // Điều khiển animation hoạt ảnh khuôn mặt robot
        if (_activeSpeaker == 'Trạm Lắng Nghe') {
          SpeechService.sendAnimationFace("SAY");
        } else {
          SpeechService.sendAnimationFace("SILIENCE");
        }

        // Đặt / reset Debounce Timer (1600ms): Sau khi dứt tiếng nói 1.6s sẽ chốt lượt nói hoàn toàn
        _transcriptDebounceTimer?.cancel();
        _transcriptDebounceTimer = Timer(const Duration(milliseconds: 1600), () {
          _settleActiveTurn();
        });

        _notifyListenersStreamingThrottled();
      }
    });

    _vapiStateSub = _vapiService.onCallStateChanged.listen((state) {
      if (!flagVAPI) return;
      LogService.log("[ConversationVM] OnCallStateChanged fired: $state");
      if (state == VapiCallState.connecting) {
        _isProcessing = true;
      } else if (state == VapiCallState.active) {
        _isProcessing = false;
        _vapiService.syncVolume();
      } else if (state == VapiCallState.ended || state == VapiCallState.error) {
        _isProcessing = false;
        SpeechService.sendAnimationFace("SILIENCE");
      }
      notifyListeners();
    });

    _vapiSpeechUpdateSub = _vapiService.onSpeechUpdate.listen((event) {
      if (!flagVAPI) return;
      final status = (event['status']?.toString() ?? '').toLowerCase();
      final role = (event['role']?.toString() ?? '').toLowerCase();
      LogService.log("[ConversationVM] SpeechUpdate received: role='$role', status='$status'");

      // Nếu người dùng bắt đầu nói (role='user', status='started'), nếu trợ lý đang nói dở, chốt ngay lượt của trợ lý
      if (role == 'user' && status.contains('started')) {
        if (_activeSpeaker == 'Trạm Lắng Nghe') {
          LogService.log("[ConversationVM] User speech started -> settling assistant turn immediately");
          _settleActiveTurn();
        }
      }

      if (!_isPendingAutoFinalize || _isFinalizing) return;
      if (status.contains('stopped')) {
        final elapsedMs = _autoFinalizeDetectedTime != null
            ? DateTime.now().difference(_autoFinalizeDetectedTime!).inMilliseconds
            : 0;
        final wordCount = _autoFinalizeFullText.trim().split(RegExp(r'\s+')).length;
        // Đảm bảo trợ lý đã nói đủ thời gian tối thiểu theo số từ (ít nhất 220ms/từ hoặc 3.5s)
        if (elapsedMs >= math.max(3500, wordCount * 220)) {
          LogService.log("[ConversationVM] Speech stopped received after full sentence spoken -> completing auto-finalize");
          _completeAutoFinalize();
        }
      }
    });

    _vapiService.startCall(assistantId: "326d0d50-c102-446b-9fc5-90265dd901ae");
  }

  void _scheduleAutoFinalizeCheck(String fullText) {
    _autoFinalizeTimer?.cancel();

    final wordCount = fullText.trim().split(RegExp(r'\s+')).length;
    // Tốc độ đọc tự nhiên của tiếng Việt: ~ 2.5 - 3 từ/giây (khoảng 360ms/từ) + 2.5s đệm an toàn sau khi hết câu
    final estimatedReadingMs = (wordCount * 360) + 2500;
    final elapsedMs = _autoFinalizeDetectedTime != null
        ? DateTime.now().difference(_autoFinalizeDetectedTime!).inMilliseconds
        : 0;
    final remainingMs = math.max(3000, estimatedReadingMs - elapsedMs);

    LogService.log("[ConversationVM] Auto-finalize scheduled in ${remainingMs}ms (words: $wordCount, elapsed: ${elapsedMs}ms, estTotal: ${estimatedReadingMs}ms)");

    _autoFinalizeTimer = Timer(Duration(milliseconds: remainingMs), () {
      if (!_isPendingAutoFinalize || _isFinalizing) return;

      // Kiểm tra xem trong 2 giây vừa qua có transcript mới gửi về nữa không
      final sinceLastUpdate = _autoFinalizeLastTextUpdate != null
          ? DateTime.now().difference(_autoFinalizeLastTextUpdate!).inMilliseconds
          : 9999;

      if (sinceLastUpdate >= 2000) {
        LogService.log("[ConversationVM] Full sentence speech duration elapsed with stable transcript -> Completing finalize");
        _completeAutoFinalize();
      } else {
        // Vẫn có text mới gửi về gần đây -> Tiếp tục đợi thêm
        LogService.log("[ConversationVM] Transcript still updating (${sinceLastUpdate}ms ago) -> Extending finalize wait");
        _scheduleAutoFinalizeCheck(_autoFinalizeFullText);
      }
    });
  }

  void _completeAutoFinalize() {
    if (_isFinalizing) return;
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;

    LogService.log("[ConversationVM] AI has finished speaking the complete sentence -> Cleanly transitioning to ResultView");
    SpeechService.sendAnimationFace("SILIENCE");

    // Đợi thêm 800ms để âm thanh dứt hoàn toàn tự nhiên trước khi chuyển view
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!_isFinalizing) {
        showFinalizeAsync();
      }
    });
  }

  Future<void> startVapiCall() async {
    _speechService.stop();
    if (Platform.isAndroid) {
      try {
        final status = await Permission.microphone.status;
        if (!status.isGranted) {
          await Permission.microphone.request();
        }
      } catch (e) {
        debugPrint("[ConversationVM] Error checking microphone permission: $e");
      }
    }
    _initVapi();
  }

  void toggleVapiFlag(bool value) {
    flagVAPI = value;
    debugPrint("[ConversationVM] Toggled flagVAPI -> $flagVAPI");
    if (flagVAPI) {
      _speechService.stop();
      _initVapi();
    } else {
      _autoFinalizeTimer?.cancel();
      _autoFinalizeTimer = null;
      _isPendingAutoFinalize = false;
      _vapiSpeechUpdateSub?.cancel();
      _vapiTranscriptDebounce?.cancel();
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _streamingNotifyTimer?.cancel();
    _streamingNotifyTimer = null;
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;
    _vapiSpeechUpdateSub?.cancel();
    _storytellingTimer?.cancel();
    _saveLogFileDebounceTimer?.cancel();
    _transcriptDebounceTimer?.cancel();
    if (_pendingTranscriptText.trim().isNotEmpty) {
      _commitPendingTranscript();
    }
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

    final lowerAi = aiResponse.toLowerCase();
    final bool isCompletion = lowerAi.contains("con sẽ gửi hồ sơ") ||
        lowerAi.contains("gửi hồ sơ lên hội đồng") ||
        lowerAi.contains("kết thúc buổi trao đổi") ||
        lowerAi.contains("kết thúc cuộc trò chuyện");
    final bool isGuard = lowerAi.contains("tạm dừng và đóng ca") ||
        lowerAi.contains("đóng ca hỗ trợ") ||
        lowerAi.contains("đóng ca tại đây") ||
        lowerAi.contains("chưa có chức năng tư vấn tâm lý") ||
        lowerAi.contains("tư vấn tâm lý chuyên sâu") ||
        lowerAi.contains("tạm dừng cuộc gọi") ||
        lowerAi.contains("kết thúc ca hỗ trợ") ||
        lowerAi.contains("dừng ca hỗ trợ") ||
        lowerAi.contains("xin phép dừng ca");

    if (isCompletion || isGuard) {
      SpeechService.sendAnimationFace("SILIENCE");
      await Future.delayed(const Duration(milliseconds: 800));
      showFinalizeAsync();
    } else {
      // Auto-open voice input popup after TTS finishes
      startVoiceInputAsync();
    }
  }

  Future<void> showFinalizeAsync({VoidCallback? onNavigation}) async {
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;

    _isFinalizing = true;
    _isProcessing = false;
    _isFinalizeVisible = false;
    _isFinalizeConfirmed = false;

    _transcriptDebounceTimer?.cancel();
    if (_pendingTranscriptText.trim().isNotEmpty) {
      _commitPendingTranscript();
    }

    // Ngắt âm thanh và cuộc gọi Vapi ngay khi kết thúc hội thoại
    _speechService.stop();
    if (flagVAPI) {
      _vapiTranscriptDebounce?.cancel();
      _vapiSpeechUpdateSub?.cancel();
      _vapiService.stopCall();
      _vapiTranscriptSub?.cancel();
      _vapiStateSub?.cancel();
    }

    _llmService.lastConversationHistory = List.from(_messages);
    notifyListeners();

    // Tự động chuyển qua ResultView sau khi kết thúc / chuẩn bị dữ liệu
    if (onNavigation != null) {
      onNavigation();
    } else {
      onNavigateToResult?.call();
    }
  }

  void confirmFinalize() {
    _isFinalizeConfirmed = true;
    _isFinalizeVisible = false;
    notifyListeners();
  }

  void cancelFinalize() {
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;
    _isFinalizing = false;
    _isFinalizeVisible = false;
    notifyListeners();
  }

  void navigateToResult(VoidCallback onNavigation) {
    showFinalizeAsync(onNavigation: onNavigation);
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
    _vapiService.setMuted(_isMuted);
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
    _isFinalizing = false;
    _isSummaryVisible = false;
    _scoringResult = null;
    _currentSessionName = null;
    _currentSessionLogFile = null;
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

