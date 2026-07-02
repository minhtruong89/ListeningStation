import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'speech_service.dart';

class LocalSpeechService implements ISpeechService {
  String engineType = "system"; // Kept for interface compatibility
  FlutterTts? _tts;
  
  bool _isMuted = false;

  // Configuration variables managed directly in code
  String languageCode = "vi"; // Vietnamese ("vi-VN")
  
  // Voice selection configuration
  String selectedVoiceName = "vi-vn-x-vie-network";
  
  double speed = 0.6;
  double pitch = 1.0;
  double volume = 1.0;

  LocalSpeechService() {
    _initEngine();
  }

  @override
  bool get isMuted => _isMuted;

  @override
  set isMuted(bool value) => _isMuted = value;

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
      debugPrint("[LocalSpeechService] Initializing Native TTS engine...");
      final ttsInstance = FlutterTts();

      // Configure handlers for UART state matching speaking activity
      ttsInstance.setStartHandler(() {
        debugPrint("[LocalSpeechService] Speech started.");
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SAY\r\n");
        }
      });

      ttsInstance.setCompletionHandler(() {
        debugPrint("[LocalSpeechService] Speech completed.");
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n");
        }
      });

      ttsInstance.setCancelHandler(() {
        debugPrint("[LocalSpeechService] Speech cancelled.");
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n");
        }
      });

      ttsInstance.setErrorHandler((message) {
        debugPrint("[LocalSpeechService] Native TTS Error: $message");
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n");
        }
      });

      _tts = ttsInstance;

      if (Platform.isAndroid) {
        try {
          final List<dynamic>? engines = await ttsInstance.getEngines;
          final String? defaultEngine = await ttsInstance.getDefaultEngine;
          debugPrint("[LocalSpeechService] Active Android TTS Engine: $defaultEngine, Available: $engines");
          
          // Query and log only Vietnamese voices on startup
          final List<dynamic>? voices = await ttsInstance.getVoices;
          if (voices != null) {
            debugPrint("[LocalSpeechService] --- Available Vietnamese TTS Voices ---");
            for (var voice in voices) {
              if (voice is Map) {
                final locale = voice['locale']?.toString().toLowerCase() ?? '';
                final name = voice['name']?.toString().toLowerCase() ?? '';
                if (locale.contains('vi') || name.contains('vi-vn')) {
                  debugPrint("[LocalSpeechService] Voice Option: $voice");
                }
              }
            }
            debugPrint("[LocalSpeechService] -----------------------------------------");
          }
        } catch (e) {
          debugPrint("[LocalSpeechService] Error querying TTS engines or voices: $e");
        }
      }
      debugPrint("[LocalSpeechService] Native TTS engine initialized successfully.");
    } catch (e) {
      debugPrint("[LocalSpeechService] Error during initialization: $e");
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
          'baudRate': SpeechService.uartBaudRate,
          'testMessage': msg,
        });
        debugPrint("[LocalSpeechService UART] Sent $msg successfully using cached device (VID: 0x${SpeechService.uartVid!.toRadixString(16).toUpperCase()}).");
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
            'baudRate': SpeechService.uartBaudRate,
            'testMessage': msg,
          });
          debugPrint("[LocalSpeechService UART] Sent $msg and cached device.");
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
      if (_tts == null) {
        await _initEngine();
      }

      debugPrint("[LocalSpeechService] Synthesizing speech offline via Native TTS: \"$text\" (Speed: $speed, Pitch: $pitch)");

      // Convert "vi" format to "vi-VN" which is standard for native Speech Services by Google
      String targetLang = languageCode;
      if (targetLang.toLowerCase() == "vi") {
        targetLang = "vi-VN";
      }

      await _tts!.setLanguage(targetLang);

      // Programmatically set voice by name if requested
      if (selectedVoiceName != "default") {
        try {
          final List<dynamic>? voices = await _tts!.getVoices;
          if (voices != null) {
            final targetVoice = voices.firstWhere(
              (v) => v is Map && v['name'].toString().toLowerCase() == selectedVoiceName.toLowerCase(),
              orElse: () => null,
            );
            if (targetVoice != null) {
              await _tts!.setVoice(Map<String, String>.from(targetVoice as Map));
              debugPrint("[LocalSpeechService] Applied custom voice: $selectedVoiceName");
            } else {
              debugPrint("[LocalSpeechService] Custom voice '$selectedVoiceName' not found on this device.");
            }
          }
        } catch (e) {
          debugPrint("[LocalSpeechService] Error setting custom voice: $e");
        }
      }

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
      if (SpeechService.flagSendUARTGlobal) {
        _sendUartMessage("SIL\r\n");
      }
    } catch (e) {
      debugPrint("[LocalSpeechService] Error stopping audio: $e");
    }
  }
}
