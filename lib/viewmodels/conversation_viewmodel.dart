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

  bool _isPendingStorytellingStart = false;
  DateTime? _storytellingDetectedTime;
  DateTime? _storytellingLastTextUpdate;
  String _storytellingInvitationFullText = "";
  Timer? _storytellingStartTimer;
  bool _isLastMessageStreaming = false;
  String? _lastStreamingSpeaker;

  bool get isStorytellingActive => _isStorytellingActive;
  int get storytellingRemainingSeconds => _storytellingRemainingSeconds;
  String get storytellingFormattedTime {
    final minutes = (_storytellingRemainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_storytellingRemainingSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  bool _isStorytellingInvitationText(String text) {
    final lower = text.toLowerCase();

    final bool hasStorytellingPrompt = lower.contains("kể tường tận") ||
        lower.contains("kể càng chi tiết") ||
        lower.contains("kể chi tiết") ||
        lower.contains("tường tận cho con nghe");

    final bool hasEndingKeyword = lower.contains("tôi đã kể xong") ||
        lower.contains("khi xong") ||
        lower.contains("dùm con");

    final wordCount = text.trim().split(RegExp(r'\s+')).length;

    // Trường hợp 1: Toàn bộ câu mời (hoặc cả đoạn mời) có chứa keyword kể và keyword hướng dẫn kết thúc
    if (hasStorytellingPrompt && hasEndingKeyword) {
      return true;
    }

    // Trường hợp 2: Có keyword kể và chứa "ghi nhận hết" với số lượng từ đủ dài (ít nhất 25 từ)
    if (hasStorytellingPrompt && lower.contains("ghi nhận hết") && wordCount >= 25) {
      return true;
    }

    // Trường hợp 3: Tin nhắn hiện tại là câu hướng dẫn kết thúc ("Khi xong, cô bác vui lòng nói 'tôi đã kể xong' dùm con ạ"), 
    // còn câu trước đó của Trạm Lắng Nghe chứa "kể tường tận"
    if (hasEndingKeyword) {
      final recentAssistantMsgs = _messages.reversed
          .where((m) => m.sender == 'Trạm Lắng Nghe')
          .take(2);
      for (var m in recentAssistantMsgs) {
        final prevLower = m.content.toLowerCase();
        if (prevLower.contains("kể tường tận") ||
            prevLower.contains("kể càng chi tiết") ||
            prevLower.contains("kể chi tiết") ||
            prevLower.contains("tường tận cho con nghe")) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isStorytellingAssistantClosingPhrase(String text) {
    final lower = text.toLowerCase().trim();
    return lower.contains("cô bác đã kể xong") ||
        lower.contains("bác đã kể xong") ||
        lower.contains("chú đã kể xong") ||
        lower.contains("anh đã kể xong") ||
        lower.contains("chị đã kể xong") ||
        lower.contains("đã kể xong") ||
        lower.contains("con đã ghi nhận thông tin") ||
        lower.contains("con xin ghi nhận thông tin") ||
        lower.contains("ghi nhận thông tin cô bác") ||
        lower.contains("ghi nhận những chia sẻ") ||
        lower.contains("ghi nhận hoàn cảnh");
  }

  bool _isStorytellingFinishedKeyword(String text) {
    final lower = text.toLowerCase().trim();
    return lower.contains("tôi đã kể xong") ||
        lower.contains("đã xong") ||
        lower.contains("đã kể xong") ||
        lower.contains("tôi kể xong rồi") ||
        lower.contains("kể xong rồi") ||
        lower.contains("con đã kể xong") ||
        lower.contains("kể hết rồi") ||
        lower.contains("hết rồi") ||
        lower.contains("kể xong") ||
        lower.contains("xong rồi") ||
        lower.contains("xong rồi ạ") ||
        lower.contains("tôi nói xong rồi") ||
        lower.contains("nói xong rồi") ||
        lower.contains("hết rồi ạ") ||
        lower.contains("dạ xong rồi") ||
        lower.contains("dạ hết rồi") ||
        lower.contains("xong ạ") ||
        lower.contains("tôi xong rồi") ||
        lower.contains("kể vậy thôi");
  }

  void _scheduleStorytellingStart(String fullText) {
    _storytellingStartTimer?.cancel();

    // Rút ngắn timeout an toàn xuống tối đa 4.5s sau khi transcript câu mời xuất hiện
    final elapsedMs = _storytellingDetectedTime != null
        ? DateTime.now().difference(_storytellingDetectedTime!).inMilliseconds
        : 0;
    final remainingMs = math.max(1500, 4500 - elapsedMs);

    LogService.log("[ConversationVM] Storytelling phase scheduled in ${remainingMs}ms (elapsed: ${elapsedMs}ms)");

    _storytellingStartTimer = Timer(Duration(milliseconds: remainingMs), () {
      if (!_isPendingStorytellingStart || _isStorytellingActive) return;

      final sinceLastUpdate = _storytellingLastTextUpdate != null
          ? DateTime.now().difference(_storytellingLastTextUpdate!).inMilliseconds
          : 9999;

      if (sinceLastUpdate >= 600) {
        LogService.log("[ConversationVM] Storytelling invitation speech stabilized -> Triggering startStorytellingPhase");
        _triggerStorytellingStart();
      } else {
        LogService.log("[ConversationVM] Transcript still updating (${sinceLastUpdate}ms ago) -> Extending storytelling wait");
        _scheduleStorytellingStart(_storytellingInvitationFullText);
      }
    });
  }

  void _triggerStorytellingStart() {
    if (_isStorytellingActive || !_isPendingStorytellingStart) return;
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;

    LogService.log("[ConversationVM] Assistant finished speaking full storytelling invitation -> Starting storytelling phase now");
    startStorytellingPhase();
  }

  void startStorytellingPhase({int? customSeconds}) {
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;

    _storytellingTimer?.cancel();
    _isStorytellingActive = true;
    _storytellingStartTime = DateTime.now();
    _storytellingRemainingSeconds = customSeconds ?? storytellingDurationSeconds;

    SpeechService.sendAnimationFace("SILIENCE");

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
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;

    final wasActive = _isStorytellingActive;
    _isStorytellingActive = false;

    // Luôn luôn đảm bảo mở lại tiếng loa trợ lý ngay khi thoát khỏi giai đoạn kể tự do
    if (flagVAPI) {
      LogService.log("[ConversationVM] Ensuring assistant speaker unmuted after storytelling (wasActive: $wasActive)");
      _vapiService.setSpeakerMuted(false);
    }

    notifyListeners();

    if (wasActive && notifyServer) {
      // Chỉ append câu "Tôi đã kể xong." nếu câu cuối cùng của người dùng chưa có từ kết thúc
      final lastUserMsg = _messages.reversed.firstWhere(
        (m) => m.sender == "Người cần giúp đỡ",
        orElse: () => ConversationMessage(sender: "", content: "", timestamp: DateTime.now()),
      );
      final hasFinishedInLastMsg = lastUserMsg.content.toLowerCase().contains("kể xong") ||
          lastUserMsg.content.toLowerCase().contains("xong rồi") ||
          lastUserMsg.content.toLowerCase().contains("đã xong");

      if (!hasFinishedInLastMsg) {
        _messages.add(ConversationMessage(
          sender: "Người cần giúp đỡ",
          content: "Tôi đã kể xong.",
          timestamp: DateTime.now(),
        ));
      }
      _writeSessionLogNow();
      notifyListeners();

      if (flagVAPI) {
        _vapiService.sendMessage("Tôi đã kể xong.");
      }
    }
  }

  Timer? _vapiTranscriptDebounce;
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

  void _initVapi() {
    debugPrint("[ConversationVM] Setting up Vapi listeners & starting call...");
    _vapiTranscriptSub?.cancel();
    _vapiStateSub?.cancel();
    _vapiSpeechUpdateSub?.cancel();
    _autoFinalizeTimer?.cancel();
    _autoFinalizeTimer = null;
    _isPendingAutoFinalize = false;
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;

    _vapiTranscriptSub = _vapiService.onTranscriptUpdated.listen((vapiMessages) {
      if (!flagVAPI || vapiMessages.isEmpty) return;

      final bool isConvUpdate = vapiMessages.any((m) => m.isConversationUpdate) || vapiMessages.length > 1;

      // 1. Nếu là danh sách hội thoại hoàn chỉnh từ ConversationUpdate (chuẩn 100% như Vapi Dashboard)
      if (isConvUpdate) {
        final liveUserMsgCount = _messages.where((m) => m.sender == 'Người cần giúp đỡ').length;
        final vapiUserMsgCount = vapiMessages.where((m) => m.speaker == 'Người cần giúp đỡ').length;

        // Nếu danh sách live đang lưu nhiều câu chi tiết của người dùng hơn vapiMessages (ví dụ bà con kể nhiều hàng riêng biệt),
        // giữ nguyên các câu live của người dùng để không bị mất dữ liệu
        if (liveUserMsgCount > vapiUserMsgCount && _messages.length >= vapiMessages.length) {
          LogService.log("[ConversationVM] Retaining live messages with $liveUserMsgCount user utterances (vapi had $vapiUserMsgCount)");
        } else {
          _messages.clear();
          for (var vm in vapiMessages) {
            final t = vm.text.trim();
            if (t.isNotEmpty) {
              _messages.add(ConversationMessage(
                sender: vm.speaker,
                content: t,
                timestamp: DateTime.now(),
              ));
            }
          }
          _isLastMessageStreaming = false;
          _lastStreamingSpeaker = null;
        }

        // Tự động đóng banner Kể tự do nếu user đã nói từ khóa hoàn tất hoặc AI đã phản hồi câu nội dung
        if (_isStorytellingActive &&
            _storytellingStartTime != null &&
            DateTime.now().difference(_storytellingStartTime!).inSeconds >= 2) {
          for (var vm in vapiMessages) {
            if (vm.speaker != 'Trạm Lắng Nghe') {
              if (_isStorytellingFinishedKeyword(vm.text)) {
                LogService.log("[ConversationVM] Detected completion keyword in ConversationUpdate from user -> Auto closing storytelling banner");
                stopStorytellingPhase(notifyServer: false);
                break;
              }
            } else {
              final cleanLow = vm.text.toLowerCase().trim();
              final isFiller = cleanLow == 'dạ.' ||
                  cleanLow == 'dạ' ||
                  cleanLow == 'vâng' ||
                  cleanLow == 'vâng ạ' ||
                  cleanLow == 'dạ vâng';
              if (!isFiller && (_isStorytellingAssistantClosingPhrase(cleanLow) || cleanLow.split(RegExp(r'\s+')).length >= 5 || cleanLow.contains('ghi nhận'))) {
                LogService.log("[ConversationVM] AI response detected in ConversationUpdate -> Auto closing storytelling banner and unmuting speaker");
                stopStorytellingPhase(notifyServer: false);
                break;
              }
            }
          }
        }

        // Kiểm tra câu mời kể tự do trong ConversationUpdate
        if (!_isStorytellingActive && _messages.isNotEmpty) {
          final lastVm = _messages.last;
          if (lastVm.sender == 'Trạm Lắng Nghe' && _isStorytellingInvitationText(lastVm.content)) {
            if (!_isPendingStorytellingStart) {
              _isPendingStorytellingStart = true;
              _storytellingDetectedTime = DateTime.now();
              LogService.log("[ConversationVM] ConversationUpdate detected full storytelling invitation -> Scheduling storytelling start...");
            }
            _storytellingLastTextUpdate = DateTime.now();
            _storytellingInvitationFullText = lastVm.content;
            _scheduleStorytellingStart(lastVm.content);
          }
        }

        _scheduleSaveSessionLog();
        notifyListeners();
        return;
      }

      // 2. Xử lý từng mẩu tin Transcript thời gian thực (hiển thị mượt mà từng chữ ra UI)
      for (var vm in vapiMessages) {
        final newText = vm.text.trim();
        if (newText.isEmpty) continue;

        final speaker = vm.speaker;

        // Hoạt ảnh khuôn mặt robot
        if (speaker == 'Trạm Lắng Nghe') {
          SpeechService.sendAnimationFace("SAY");
        } else {
          SpeechService.sendAnimationFace("SILIENCE");
        }

        // Trong giai đoạn kể tự do (Storytelling):
        if (_isStorytellingActive && speaker == 'Trạm Lắng Nghe') {
          final cleanLow = newText.toLowerCase().trim();
          final isFiller = cleanLow == 'dạ.' ||
              cleanLow == 'dạ' ||
              cleanLow == 'vâng' ||
              cleanLow == 'vâng ạ' ||
              cleanLow == 'dạ vâng';

          if (isFiller) {
            // Bỏ qua câu đệm ngắn vô nghĩa của AI
            continue;
          } else {
            // Kiểm tra câu kết thúc kể tự do của Trạm Lắng Nghe ("Dạ cô bác đã kể xong, con đã ghi nhận...")
            if (_isStorytellingAssistantClosingPhrase(newText)) {
              LogService.log("[ConversationVM] Assistant confirmed storytelling finished ('$newText') -> Auto ending storytelling and unmuting speaker immediately");
              stopStorytellingPhase(notifyServer: false);
            } else {
              // Nếu AI bắt đầu nói một câu đầy đủ (ví dụ: "Dạ con xin ghi nhận...", hỏi thăm tiếp theo...),
              // chứng tỏ AI đã chuyển sang Giai đoạn 3 -> Tự động kết thúc kể tự do và mở lại loa ngay lập tức!
              final wordCount = cleanLow.split(RegExp(r'\s+')).length;
              if (wordCount >= 4 ||
                  cleanLow.contains('ghi nhận') ||
                  cleanLow.contains('cảm ơn') ||
                  cleanLow.contains('hoàn cảnh') ||
                  cleanLow.contains('khó khăn')) {
                LogService.log("[ConversationVM] Assistant started speaking substantial response during storytelling ('$newText') -> Auto ending storytelling and unmuting speaker");
                stopStorytellingPhase(notifyServer: false);
              }
            }
          }
        }

        // Kiểm tra từ khóa hoàn tất lời kể trong giai đoạn kể tự do
        if (_isStorytellingActive && speaker == 'Người cần giúp đỡ') {
          if (_isStorytellingFinishedKeyword(newText) &&
              _storytellingStartTime != null &&
              DateTime.now().difference(_storytellingStartTime!).inSeconds >= 2) {
            LogService.log("[ConversationVM] Detected finish keyword '$newText' during live streaming -> Stopping storytelling phase");
            stopStorytellingPhase(notifyServer: false);
          }
        }

        final isPartial = vm.isPartial;

        // Hiển thị trực tiếp vào danh sách tin nhắn từng hàng riêng biệt:
        // Nếu là partial transcript từ cùng 1 người đang nói -> Cập nhật nội dung hàng hiện tại (hiển thị streaming mượt)
        // Nếu là final transcript -> Chốt hàng hiện tại, các câu nói tiếp theo sẽ được tạo thành hàng mới riêng biệt
        if (isPartial) {
          if (_messages.isNotEmpty &&
              _isLastMessageStreaming &&
              _lastStreamingSpeaker == speaker) {
            _messages[_messages.length - 1] = ConversationMessage(
              sender: speaker,
              content: newText,
              timestamp: _messages.last.timestamp,
            );
          } else {
            _messages.add(ConversationMessage(
              sender: speaker,
              content: newText,
              timestamp: DateTime.now(),
            ));
            _isLastMessageStreaming = true;
            _lastStreamingSpeaker = speaker;
          }
        } else {
          // Final transcript cho một câu hoàn chỉnh
          if (_messages.isNotEmpty &&
              _isLastMessageStreaming &&
              _lastStreamingSpeaker == speaker) {
            _messages[_messages.length - 1] = ConversationMessage(
              sender: speaker,
              content: newText,
              timestamp: _messages.last.timestamp,
            );
          } else if (_messages.isNotEmpty &&
              _messages.last.sender == speaker &&
              (newText.startsWith(_messages.last.content) || _messages.last.content.startsWith(newText))) {
            _messages[_messages.length - 1] = ConversationMessage(
              sender: speaker,
              content: newText,
              timestamp: _messages.last.timestamp,
            );
          } else {
            // Câu nói mới riêng biệt -> Thêm hàng mới!
            _messages.add(ConversationMessage(
              sender: speaker,
              content: newText,
              timestamp: DateTime.now(),
            ));
          }
          // Chốt câu nói này đã hoàn tất
          _isLastMessageStreaming = false;
          _lastStreamingSpeaker = null;
        }

        // Kiểm tra xem AI đã nói câu mời kể tự do đầy đủ chưa
        if (speaker == 'Trạm Lắng Nghe' &&
            _isStorytellingInvitationText(newText) &&
            !_isStorytellingActive) {
          if (!_isPendingStorytellingStart) {
            _isPendingStorytellingStart = true;
            _storytellingDetectedTime = DateTime.now();
            LogService.log("[ConversationVM] Live stream detected storytelling invitation -> Scheduling storytelling start...");
          }
          _storytellingLastTextUpdate = DateTime.now();
          _storytellingInvitationFullText = newText;
          _scheduleStorytellingStart(newText);
        }

        // Nếu người dùng bắt đầu nói trong lúc đang chờ AI kết thúc câu mời -> Kích hoạt ngay kể tự do
        if (_isPendingStorytellingStart &&
            !_isStorytellingActive &&
            speaker == 'Người cần giúp đỡ' &&
            newText.trim().length >= 4) {
          LogService.log("[ConversationVM] User started speaking during pending storytelling invitation -> Triggering storytelling phase immediately");
          _triggerStorytellingStart();
        }

        // Tự động kết thúc hội thoại khi AI nói câu kết thúc hoặc TẦNG BẢO VỆ kích hoạt
        final String lower = newText.toLowerCase();
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
            LogService.log("[ConversationVM] Detected completion or guard phrase -> Starting auto-finalize watcher");
          }
          _autoFinalizeLastTextUpdate = DateTime.now();
          _autoFinalizeFullText = newText;
          _scheduleAutoFinalizeCheck(newText);
        }
      }

      _scheduleSaveSessionLog();
      _notifyListenersStreamingThrottled();
    });

    _vapiStateSub = _vapiService.onCallStateChanged.listen((state) {
      if (!flagVAPI) return;
      LogService.log("[ConversationVM] OnCallStateChanged fired: $state");
      if (state == VapiCallState.connecting) {
        _isProcessing = true;
      } else if (state == VapiCallState.active) {
        _isProcessing = false;
        _vapiService.syncVolume();
        _vapiService.setSpeakerMuted(false);
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

      // Xử lý khi AI hoàn tất nói toàn bộ câu mời kể tự do
      if (_isPendingStorytellingStart && !_isStorytellingActive) {
        if (status.contains('stopped') && (role.isEmpty || role.contains('assistant') || role.contains('bot'))) {
          LogService.log("[ConversationVM] Speech stopped received after storytelling invitation -> Triggering storytelling phase without artificial delay");
          // Bỏ hoàn toàn chặn cứng 220ms/từ hoặc 4.5s; chỉ đệm 400ms ngắn tự nhiên
          Future.delayed(const Duration(milliseconds: 400), () {
            if (_isPendingStorytellingStart && !_isStorytellingActive) {
              _triggerStorytellingStart();
            }
          });
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
      _storytellingStartTimer?.cancel();
      _storytellingStartTimer = null;
      _isPendingStorytellingStart = false;
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
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;
    _vapiSpeechUpdateSub?.cancel();
    _storytellingTimer?.cancel();
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
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;

    _isFinalizing = true;
    _isProcessing = false;
    _isFinalizeVisible = false;
    _isFinalizeConfirmed = false;

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
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;
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
    _storytellingStartTimer?.cancel();
    _storytellingStartTimer = null;
    _isPendingStorytellingStart = false;
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

