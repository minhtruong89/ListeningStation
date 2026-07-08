import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'speech_service.dart';

class LocalSpeechService implements ISpeechService {
  String engineType = "system"; // Kept for interface compatibility
  FlutterTts? _tts;
  Timer? _silTimer;
  
  bool _isMuted = false;

  // Configuration variables managed directly in code
  String languageCode = "vi"; // Vietnamese ("vi-VN")
  
  // Voice selection configuration
  @override
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

  @override
  Future<List<String>> getVietnameseVoices() async {
    if (_tts == null) {
      await _initEngine();
    }
    final List<String> viVoices = [];
    try {
      final List<dynamic>? voices = await _tts!.getVoices;
      if (voices != null) {
        for (var voice in voices) {
          if (voice is Map) {
            final name = voice['name']?.toString() ?? '';
            final locale = voice['locale']?.toString().toLowerCase() ?? '';
            if (locale.contains('vi') || name.toLowerCase().contains('vi-vn')) {
              if (name.isNotEmpty) {
                viVoices.add(name);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("[LocalSpeechService] Error getting voices: $e");
    }
    if (viVoices.isEmpty) {
      viVoices.add("vi-vn-x-vie-network");
      viVoices.add("vi-vn-x-gft-local");
    }
    return viVoices;
  }

  @override
  Future<String?> synthesizeToFileAsync(String text, String voiceName) async {
    if (_tts == null) {
      await _initEngine();
    }
    try {
      final List<dynamic>? voices = await _tts!.getVoices;
      if (voices != null) {
        final targetVoice = voices.firstWhere(
          (v) => v is Map && v['name'].toString().toLowerCase() == voiceName.toLowerCase(),
          orElse: () => null,
        );
        if (targetVoice != null) {
          await _tts!.setVoice(Map<String, String>.from(targetVoice as Map));
        }
      }

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

      final tempDir = await getTemporaryDirectory();
      final String tempPath = "${tempDir.path}/synthesized_${DateTime.now().millisecondsSinceEpoch}.wav";
      
      await _tts!.awaitSynthCompletion(true);
      final result = await _tts!.synthesizeToFile(text, tempPath, true);
      
      if (result == 1) {
        debugPrint("[LocalSpeechService] Synthesized speech file created at: $tempPath");
        return tempPath;
      } else {
        debugPrint("[LocalSpeechService] Failed to synthesize to file, result code: $result");
      }
    } catch (e) {
      debugPrint("[LocalSpeechService] Error during synthesizeToFileAsync: $e");
    }
    return null;
  }

  Future<void> _initEngine() async {
    try {
      debugPrint("[LocalSpeechService] Initializing Native TTS engine...");
      final ttsInstance = FlutterTts();

      // Configure handlers for logging
      ttsInstance.setStartHandler(() {
        debugPrint("[LocalSpeechService] Speech started.");
        _silTimer?.cancel();
        _silTimer = null;
      });

      ttsInstance.setCompletionHandler(() {
        debugPrint("[LocalSpeechService] Speech completed.");
        _silTimer?.cancel();
        _silTimer = null;
        SpeechService.sendAnimationFace("SILIENCE");
      });

      ttsInstance.setCancelHandler(() {
        debugPrint("[LocalSpeechService] Speech cancelled.");
        _silTimer?.cancel();
        _silTimer = null;
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n"); // Send SIL on cancel to be safe
        }
        SpeechService.sendAnimationFace("SILIENCE");
      });

      ttsInstance.setErrorHandler((message) {
        debugPrint("[LocalSpeechService] Native TTS Error: $message");
        _silTimer?.cancel();
        _silTimer = null;
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n"); // Send SIL on error to be safe
        }
        SpeechService.sendAnimationFace("SILIENCE");
      });

      _tts = ttsInstance;
      
      // Ensure speak() awaits completion
      await _tts!.awaitSpeakCompletion(true);

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

      // We now await the UART SAY so it doesn't overlap with audio starting too early
      if (SpeechService.flagSendUARTGlobal) {
        await _sendUartMessage("SAY\r\n");
      }
      SpeechService.sendAnimationFace("SAY");

      // Start fallback timer just in case completion is not called
      final int wordCount = text.split(RegExp(r'\s+')).length;
      final int estimatedDurationMs = ((wordCount / (2.5 * speed)) * 1000).toInt() + 1500;
      _silTimer = Timer(Duration(milliseconds: estimatedDurationMs), () {
        debugPrint("[LocalSpeechService] Fallback SIL timer fired after ${estimatedDurationMs}ms.");
        if (SpeechService.flagSendUARTGlobal) {
          _sendUartMessage("SIL\r\n");
        }
        SpeechService.sendAnimationFace("SILIENCE");
      });

      await _tts!.speak(text);

      // Now that awaitSpeakCompletion(true) is set, speak() waits until speech completes
      _silTimer?.cancel();
      if (SpeechService.flagSendUARTGlobal) {
        await _sendUartMessage("SIL\r\n");
      }
      SpeechService.sendAnimationFace("SILIENCE");
    } catch (e) {
      debugPrint("[LocalSpeechService] Offline TTS Error: $e");
      SpeechService.sendAnimationFace("SILIENCE");
    }
  }

  @override
  void stop() {
    try {
      _silTimer?.cancel();
      _silTimer = null;
      _tts?.stop();
      if (SpeechService.flagSendUARTGlobal) {
        debugPrint("[LocalSpeechService] stop()");
        _sendUartMessage("SIL\r\n");
      }
      SpeechService.sendAnimationFace("SILIENCE");
    } catch (e) {
      debugPrint("[LocalSpeechService] Error stopping audio: $e");
    }
  }
}
