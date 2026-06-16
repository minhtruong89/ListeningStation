import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'speech_service.dart';

class LocalSpeechService implements ISpeechService {
  String engineType = "system"; // Kept for config compatibility (maps to system native TTS)
  FlutterTts? _tts;
  
  bool _isMuted = false;
  bool _flagSendUART = false;

  String languageCode = "vi"; // Vietnamese
  String voiceStyle = "default";
  double speed = 1.0;
  double pitch = 1.0;
  double volume = 1.0;

  late String _dataDir;

  LocalSpeechService() {
    _initEngine();
  }

  @override
  bool get isMuted => _isMuted;

  @override
  set isMuted(bool value) => _isMuted = value;

  @override
  bool get flagSendUART => _flagSendUART;

  @override
  set flagSendUART(bool value) => _flagSendUART = value;

  @override
  bool get flagLocalTTS => true;

  @override
  set flagLocalTTS(bool value) {}

  @override
  void setUartDevice(int vendorId, int productId) {
    SpeechService.uartVid = vendorId;
    SpeechService.uartPid = productId;
    debugPrint("[LocalSpeechService] Saved UART device: VID=0x${vendorId.toRadixString(16).toUpperCase()}, PID=0x${productId.toRadixString(16).toUpperCase()}");
  }

  Future<void> _initEngine() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _dataDir = join(appDir.path, 'ListeningStation');

      await _loadConfig();

      debugPrint("[LocalSpeechService] Initializing Native TTS engine...");
      final ttsInstance = FlutterTts();

      // Configure handlers for UART state matching speaking activity
      ttsInstance.setStartHandler(() {
        debugPrint("[LocalSpeechService] Speech started.");
        if (_flagSendUART) {
          _sendUartMessage("YES\n");
        }
      });

      ttsInstance.setCompletionHandler(() {
        debugPrint("[LocalSpeechService] Speech completed.");
        if (_flagSendUART) {
          _sendUartMessage("NO\n");
        }
      });

      ttsInstance.setCancelHandler(() {
        debugPrint("[LocalSpeechService] Speech cancelled.");
        if (_flagSendUART) {
          _sendUartMessage("NO\n");
        }
      });

      ttsInstance.setErrorHandler((message) {
        debugPrint("[LocalSpeechService] Native TTS Error: $message");
        if (_flagSendUART) {
          _sendUartMessage("NO\n");
        }
      });

      _tts = ttsInstance;
      debugPrint("[LocalSpeechService] Native TTS engine initialized successfully.");
    } catch (e) {
      debugPrint("[LocalSpeechService] Error during initialization: $e");
    }
  }

  Future<void> _loadConfig() async {
    try {
      final configFile = File(join(_dataDir, "local_tts_config.json"));
      if (configFile.existsSync()) {
        final jsonStr = await configFile.readAsString();
        final doc = jsonDecode(jsonStr);
        if (doc is Map) {
          if (doc.containsKey('engine')) engineType = doc['engine'].toString();
          if (doc.containsKey('voice_style')) voiceStyle = doc['voice_style'].toString();
          if (doc.containsKey('language_code')) languageCode = doc['language_code'].toString();
          if (doc.containsKey('speed')) speed = double.tryParse(doc['speed'].toString()) ?? 1.0;
          if (doc.containsKey('pitch')) pitch = double.tryParse(doc['pitch'].toString()) ?? 1.0;
          if (doc.containsKey('volume')) volume = double.tryParse(doc['volume'].toString()) ?? 1.0;
          debugPrint("[LocalSpeechService] Loaded config: Engine=$engineType, Voice=$voiceStyle, Speed=$speed");
        }
      } else {
        final defaultMap = {
          "engine": engineType,
          "language_code": languageCode,
          "voice_style": voiceStyle,
          "speed": speed,
          "pitch": pitch,
          "volume": volume
        };
        await configFile.writeAsString(jsonEncode(defaultMap));
        debugPrint("[LocalSpeechService] Created default config file at ${configFile.path}");
      }
    } catch (e) {
      debugPrint("[LocalSpeechService] Error loading config: $e");
    }
  }

  Future<void> _sendUartMessage(String msg) async {
    try {
      if (!Platform.isAndroid) return;

      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');

      if (SpeechService.uartVid != null && SpeechService.uartPid != null) {
        await channel.invokeMethod<Map<dynamic, dynamic>>('testUartCommunicate', {
          'vendorId': SpeechService.uartVid,
          'productId': SpeechService.uartPid,
          'baudRate': 9600,
          'testMessage': msg,
        });
        debugPrint("[LocalSpeechService UART] Sent '$msg' successfully using cached device (VID: 0x${SpeechService.uartVid!.toRadixString(16).toUpperCase()}).");
        return;
      }

      final List<dynamic>? serialDevices = await channel.invokeMethod<List<dynamic>>('getUsbSerialDevices');
      if (serialDevices != null && serialDevices.isNotEmpty) {
        final Map<dynamic, dynamic> firstDevice = serialDevices.first as Map<dynamic, dynamic>;
        SpeechService.uartVid = firstDevice['vendorId'] ?? 0;
        SpeechService.uartPid = firstDevice['productId'] ?? 0;
        final bool hasPerm = firstDevice['hasPermission'] ?? false;
        if (hasPerm) {
          await channel.invokeMethod<Map<dynamic, dynamic>>('testUartCommunicate', {
            'vendorId': SpeechService.uartVid,
            'productId': SpeechService.uartPid,
            'baudRate': 9600,
            'testMessage': msg,
          });
          debugPrint("[LocalSpeechService UART] Sent '$msg' and cached device.");
        } else {
          debugPrint("[LocalSpeechService UART] Cannot send: USB permission not granted.");
        }
      }
    } catch (e) {
      debugPrint("[LocalSpeechService UART] Error sending UART message: $e");
    }
  }

  @override
  Future<void> speakAsync(String text) async {
    if (_isMuted) return;

    if (text.trim().isEmpty) {
      debugPrint("[LocalSpeechService] TTS skipped: Text is empty.");
      return;
    }

    stop();

    try {
      await _loadConfig();

      if (_tts == null) {
        await _initEngine();
      }

      debugPrint("[LocalSpeechService] Synthesizing speech offline via Native TTS: \"$text\"");

      // Convert "vi" format to "vi-VN" which is standard for native Speech Services by Google
      String targetLang = languageCode;
      if (targetLang.toLowerCase() == "vi") {
        targetLang = "vi-VN";
      }

      await _tts!.setLanguage(targetLang);
      if (speed != 1.0) {
        await _tts!.setSpeechRate(speed);
      }
      if (pitch != 1.0) {
        await _tts!.setPitch(pitch);
      }
      if (volume != 1.0) {
        await _tts!.setVolume(volume);
      }

      await _tts!.speak(text);
    } catch (e) {
      debugPrint("[LocalSpeechService] Offline TTS Error: $e");
    }
  }

  @override
  void stop() {
    try {
      _tts?.stop();
      if (_flagSendUART) {
        _sendUartMessage("NO\n");
      }
    } catch (e) {
      debugPrint("[LocalSpeechService] Error stopping audio: $e");
    }
  }
}
