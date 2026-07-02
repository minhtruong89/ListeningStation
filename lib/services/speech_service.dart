import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract class ISpeechService {
  Future<void> speakAsync(String text);
  void stop();
  bool get isMuted;
  set isMuted(bool value);
  bool get flagLocalTTS;
  set flagLocalTTS(bool value);
  void setUartDevice(int vendorId, int productId);
}

class SpeechService implements ISpeechService {
  static int? uartVid;
  static int? uartPid;
  static bool flagSendUARTGlobal = true;
  static const int uartBaudRate = 115200;

  final http.Client _httpClient;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isMuted = false;
  String? _apiKey;
  late String _dataDir;
  late String _tempMp3Path;

  SpeechService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client() {
    _initPath();
  }

  @override
  bool get isMuted => _isMuted;

  @override
  set isMuted(bool value) => _isMuted = value;

  @override
  bool get flagLocalTTS => false;

  @override
  set flagLocalTTS(bool value) {}

  @override
  void setUartDevice(int vendorId, int productId) {
    uartVid = vendorId;
    uartPid = productId;
    debugPrint("[SpeechService] Saved UART device: VID=0x${vendorId.toRadixString(16).toUpperCase()}, PID=0x${productId.toRadixString(16).toUpperCase()}");
  }

  Future<void> _initPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');

    final tempDir = await getTemporaryDirectory();
    _tempMp3Path = join(tempDir.path, 'ListeningStation_TTS_${DateTime.now().microsecondsSinceEpoch}.mp3');
    
    _loadApiKey();
  }

  void _loadApiKey() {
    try {
      final keyFile = File(join(_dataDir, "openAI_key.json"));
      if (keyFile.existsSync()) {
        final jsonStr = keyFile.readAsStringSync();
        final doc = jsonDecode(jsonStr);
        if (doc is Map && doc.containsKey('OpenAI')) {
          _apiKey = doc['OpenAI']['ApiKey']?.toString();
        }
      }
    } catch (e) {
      debugPrint("Error loading OpenAI Key for TTS: $e");
    }
  }

  Future<void> _sendUartMessage(String msg) async {
    try {
      if (!Platform.isAndroid) return;

      const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');

      // Use cached device if available
      if (uartVid != null && uartPid != null) {
        await channel.invokeMethod<Map<dynamic, dynamic>>('testUartCommunicate', {
          'vendorId': uartVid,
          'productId': uartPid,
          'baudRate': 115200,
          'testMessage': msg,
        });
        debugPrint("[SpeechService UART] Sent '$msg' successfully using cached device (VID: 0x${uartVid!.toRadixString(16).toUpperCase()}).");
        return;
      }

      // Fallback: If not cached yet, scan the bus
      final List<dynamic>? serialDevices = await channel.invokeMethod<List<dynamic>>('getUsbSerialDevices');
      if (serialDevices != null && serialDevices.isNotEmpty) {
        final Map<dynamic, dynamic> firstDevice = serialDevices.first as Map<dynamic, dynamic>;
        uartVid = firstDevice['vendorId'] ?? 0;
        uartPid = firstDevice['productId'] ?? 0;
        final bool hasPerm = firstDevice['hasPermission'] ?? false;
        if (hasPerm) {
          await channel.invokeMethod<Map<dynamic, dynamic>>('testUartCommunicate', {
            'vendorId': uartVid,
            'productId': uartPid,
            'baudRate': 115200,
            'testMessage': msg,
          });
          debugPrint("[SpeechService UART] Sent '$msg' and cached device.");
        } else {
          debugPrint("[SpeechService UART] Cannot send: USB permission not granted.");
        }
      }
    } catch (e) {
      debugPrint("[SpeechService UART] Error sending UART message: $e");
    }
  }

  @override
  Future<void> speakAsync(String text) async {
    if (_isMuted) return;
    
    // Load API key before speaking to ensure we use the latest downloaded key
    _loadApiKey();

    if (text.trim().isEmpty || _apiKey == null || _apiKey!.isEmpty) {
      debugPrint("TTS skipped: Text is empty or API Key is missing.");
      return;
    }

    stop(); // Silently stop any active playback

    try {
      final requestBody = {
        "model": "tts-1",
        "input": text,
        "voice": "nova"
      };

      final response = await _httpClient.post(
        Uri.parse("https://api.openai.com/v1/audio/speech"),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        debugPrint("OpenAI API Error for TTS (${response.statusCode}): ${response.body}");
        return;
      }

      final audioBytes = response.bodyBytes;
      if (audioBytes.isEmpty) return;
      
      final mp3File = File(_tempMp3Path);
      await mp3File.writeAsBytes(audioBytes);
      debugPrint("TTS MP3 saved to: $_tempMp3Path");

      // Play using just_audio player
      await _audioPlayer.setFilePath(_tempMp3Path);
      
      // Delay play by a brief 200ms to ensure device channel is ready
      await Future.delayed(const Duration(milliseconds: 200));

      if (flagSendUARTGlobal) {
        await _sendUartMessage("SAY\n");
      }
      await _audioPlayer.play();
      if (flagSendUARTGlobal) {
        await _sendUartMessage("SIL\n");
      }
    } catch (e) {
      debugPrint("OpenAI TTS Error: $e");
    }
  }

  @override
  void stop() {
    try {
      _audioPlayer.stop();
      if (flagSendUARTGlobal) {
        _sendUartMessage("SIL\n");
      }
    } catch (e) {
      debugPrint("Error stopping audio player: $e");
    }
  }
}
