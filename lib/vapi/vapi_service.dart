import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';
import 'vapi_models.dart';

class VapiService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.soncamedia.listeningstation/vapi_method');
  static const EventChannel _eventChannel =
      EventChannel('com.soncamedia.listeningstation/vapi_event');

  StreamSubscription? _eventSubscription;

  final StreamController<VapiCallState> _callStateController =
      StreamController<VapiCallState>.broadcast();
  final StreamController<List<VapiTranscriptMessage>> _transcriptController =
      StreamController<List<VapiTranscriptMessage>>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _speechUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<VapiCallState> get onCallStateChanged => _callStateController.stream;
  Stream<List<VapiTranscriptMessage>> get onTranscriptUpdated => _transcriptController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<Map<String, dynamic>> get onSpeechUpdate => _speechUpdateController.stream;

  VapiService() {
    initialize();
  }

  void initialize() {
    if (_eventSubscription != null) return;
    debugPrint("[VapiService] Initializing EventChannel listener...");
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (err) {
        debugPrint("[VapiService] Stream error: $err");
        _errorController.add(err.toString());
      },
    );
  }

  void _handleEvent(dynamic rawEvent) {
    if (rawEvent is! Map) return;
    final map = Map<String, dynamic>.from(rawEvent);
    final eventName = map['event'] as String?;
    //LogService.log("[VapiService] Event received: $eventName");

    switch (eventName) {
      case 'callDidStart':
        LogService.log("[VapiService] Call STARTED (active)");
        _callStateController.add(VapiCallState.active);
        break;
      case 'callDidEnd':
        LogService.log("[VapiService] Call ENDED");
        _callStateController.add(VapiCallState.ended);
        break;
      case 'conversationUpdate':
        final rawMessages = map['messages'] as List?;
        LogService.log("[VapiService] conversationUpdate payload: ${rawMessages?.length} messages -> $rawMessages");
        if (rawMessages != null) {
          final List<VapiTranscriptMessage> list = [];
          for (var item in rawMessages) {
            if (item is Map) {
              final role = item['role']?.toString().toLowerCase() ?? '';
              if (role == 'system') continue;
              final content = item['content']?.toString() ?? item['message']?.toString();
              if (content != null && content.trim().isNotEmpty) {
                final speaker = (role == 'assistant' || role == 'bot' || role == 'model')
                    ? 'Trạm Lắng Nghe'
                    : 'Người cần giúp đỡ';
                list.add(VapiTranscriptMessage(
                  speaker: speaker,
                  text: content.trim(),
                  isConversationUpdate: true,
                ));
              }
            }
          }
          if (list.isNotEmpty) {
            _transcriptController.add(list);
          }
        }
        break;
      case 'transcript':
        final rawRole = (map['role'] as String? ?? '').toLowerCase();
        final rawEventStr = (map['raw'] as String? ?? '').toLowerCase();
        final text = (map['text'] as String? ?? '').trim();
        final tType = (map['transcriptType'] as String? ?? '').toUpperCase();
        final isPartial = tType.contains('PARTIAL');

        if (text.isNotEmpty) {
          final textLower = text.toLowerCase();
          final hasExplicitAssistantPhrase = textLower.contains('con chào') ||
              textLower.contains('con là') ||
              textLower.contains('con xin') ||
              textLower.contains('con cảm ơn') ||
              textLower.contains('cho con hỏi') ||
              textLower.contains('giùm con') ||
              textLower.contains('ghi nhận thông tin') ||
              textLower.contains('quỹ bông sen') ||
              textLower.contains('trạm lắng nghe') ||
              textLower.startsWith('dạ, con') ||
              textLower.startsWith('dạ con');

          String speaker;
          if (hasExplicitAssistantPhrase) {
            speaker = 'Trạm Lắng Nghe';
          } else if (rawRole.isNotEmpty) {
            if (rawRole == 'assistant' || rawRole == 'bot' || rawRole == 'model') {
              speaker = 'Trạm Lắng Nghe';
            } else if (rawRole == 'user') {
              speaker = 'Người cần giúp đỡ';
            } else {
              speaker = rawRole.contains('assistant') ? 'Trạm Lắng Nghe' : 'Người cần giúp đỡ';
            }
          } else {
            final isAssistant = rawRole.contains('assistant') ||
                rawRole.contains('bot') ||
                rawRole.contains('model') ||
                rawEventStr.contains('role=assistant') ||
                rawEventStr.contains('role: assistant') ||
                rawEventStr.contains('speaker=assistant') ||
                textLower.contains('con') ||
                textLower.contains('cô/bác') ||
                textLower.contains('cô bác') ||
                textLower.contains('trạm lắng nghe') ||
                textLower.contains('quỹ bông sen') ||
                textLower.contains('xem xét hỗ trợ') ||
                textLower.contains('tóm tắt');
            speaker = isAssistant ? 'Trạm Lắng Nghe' : 'Người cần giúp đỡ';
          }

          LogService.log("[VapiService] Live transcript -> [$speaker] (role: '$rawRole', raw: '$rawEventStr'): $text");
          _transcriptController.add([
            VapiTranscriptMessage(
              speaker: speaker,
              text: text,
              isPartial: isPartial,
              isConversationUpdate: false,
            )
          ]);
        }
        break;
      case 'speechUpdate':
        LogService.log("[VapiService] speechUpdate: $map");
        _speechUpdateController.add(map);
        break;
      case 'error':
        final errorMsg = map['error'] as String? ?? 'Vapi Call Error';
        LogService.log("[VapiService] ERROR: $errorMsg");
        _errorController.add(errorMsg);
        _callStateController.add(VapiCallState.error);
        break;
      default:
        final info = map['info']?.toString() ?? '';
        LogService.log("[VapiService] $eventName: $info");
        break;
    }
  }

  Future<bool> startCall({String? assistantId}) async {
    try {
      LogService.log("[VapiService] Invoking Native startCall with assistantId: $assistantId");
      initialize();
      final Map<String, dynamic> params = {};
      if (assistantId != null) {
        params['assistantId'] = assistantId;
      }
      final bool? res = await _methodChannel.invokeMethod<bool>('startCall', params);
      LogService.log("[VapiService] Native startCall returned: $res");
      return res ?? false;
    } catch (e) {
      LogService.log("[VapiService] EXCEPTION starting call: $e");

      _errorController.add(e.toString());
      _callStateController.add(VapiCallState.error);
      return false;
    }
  }

  Future<void> stopCall() async {
    try {
      await _methodChannel.invokeMethod('stopCall');
      _callStateController.add(VapiCallState.ended);
    } catch (e) {
      debugPrint("[VapiService] Error stopping call: $e");
    }
  }

  Future<void> syncVolume() async {
    try {
      await _methodChannel.invokeMethod('syncVolume');
    } catch (e) {
      debugPrint("[VapiService] Error syncing volume: $e");
    }
  }

  Future<void> setMuted(bool muted) async {
    try {
      await _methodChannel.invokeMethod('setMuted', {'muted': muted});
    } catch (e) {
      debugPrint("[VapiService] Error setting muted: $e");
    }
  }

  Future<void> setSpeakerMuted(bool muted) async {
    try {
      await _methodChannel.invokeMethod('setSpeakerMuted', {'muted': muted});
    } catch (e) {
      debugPrint("[VapiService] Error setting speaker muted: $e");
    }
  }

  Future<bool> sendMessage(String message) async {
    try {
      LogService.log("[VapiService] Sending message: $message");
      final bool? res = await _methodChannel.invokeMethod<bool>('sendMessage', {
        'message': message,
      });
      return res ?? false;
    } catch (e) {
      debugPrint("[VapiService] Error sending message: $e");
      return false;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _callStateController.close();
    _transcriptController.close();
    _errorController.close();
    _speechUpdateController.close();
  }
}
