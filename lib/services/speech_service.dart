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
  bool get flagLocalTTS_checkSwitch;
  set flagLocalTTS_checkSwitch(bool value);
  void setUartDevice(int vendorId, int productId);
  Future<List<String>> getVietnameseVoices();
  String get selectedVoiceName;
  set selectedVoiceName(String name);
  Future<String?> synthesizeToFileAsync(String text, String voiceName);
  String get onlineTtsProvider;
  set onlineTtsProvider(String provider);
}

class SpeechService implements ISpeechService {
  static int? uartVid;
  static int? uartPid;
  static bool flagSendUARTGlobal = false;
  static const int uartBaudRate = 115200;

  static bool flagSendSignalLocal = true;

  static final ValueNotifier<String> faceAnimationNotifier = ValueNotifier<String>("HELLO");

  static void sendAnimationFace(String mode) {
    debugPrint("[SpeechService] sendAnimationFace: $mode");
    faceAnimationNotifier.value = mode;
  }

  final http.Client _httpClient;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isMuted = false;
  String? _openaiApiKey;
  String? _googleAiApiKey;
  late String _dataDir;
  String _selectedVoiceName = 'Sulafat';
  String _onlineTtsProvider = 'GoogleAI';

  @override
  String get onlineTtsProvider => _onlineTtsProvider;

  @override
  set onlineTtsProvider(String provider) {
    _onlineTtsProvider = provider;
    if (provider == 'GoogleAI') {
      _selectedVoiceName = 'Sulafat';
    } else {
      _selectedVoiceName = 'nova';
    }
  }

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
  bool get flagLocalTTS_checkSwitch => false;

  @override
  set flagLocalTTS_checkSwitch(bool value) {}

  @override
  String get selectedVoiceName => _selectedVoiceName;

  @override
  set selectedVoiceName(String name) => _selectedVoiceName = name;

  @override
  void setUartDevice(int vendorId, int productId) {
    uartVid = vendorId;
    uartPid = productId;
    debugPrint("[SpeechService] Saved UART device: VID=0x${vendorId.toRadixString(16).toUpperCase()}, PID=0x${productId.toRadixString(16).toUpperCase()}");
  }

  @override
  Future<List<String>> getVietnameseVoices() async {
    if (_onlineTtsProvider == 'GoogleAI') {
      return ['Zephyr', 'Sulafat'];
    } else {
      return ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
    }
  }

  @override
  Future<String?> synthesizeToFileAsync(String text, String voiceName) async {
    await _initPath();
    _loadApiKey();

    if (text.trim().isEmpty) {
      return null;
    }

    if (_onlineTtsProvider == "GoogleAI") {
      if (_googleAiApiKey == null || _googleAiApiKey!.isEmpty) {
        debugPrint("[SpeechService] GoogleAI API Key is missing.");
        return null;
      }
      try {
        final String promptText = "[giọng nữ miền Nam dễ thương, tình cảm dịu dàng] $text";

        final requestBody = {
          "contents": [
            {
              "parts": [
                {
                  "text": promptText
                }
              ]
            }
          ],
          "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
              "voiceConfig": {
                "prebuiltVoiceConfig": {
                  "voiceName": voiceName
                }
              }
            }
          }
        };

        final response = await _httpClient.post(
          Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-tts-preview:generateContent?key=$_googleAiApiKey"),
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode(requestBody),
        );

        if (response.statusCode != 200) {
          debugPrint("GoogleAI API Error for TTS (${response.statusCode}): ${response.body}");
          return null;
        }

        final doc = jsonDecode(response.body);
        final candidates = doc['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final inlineData = parts[0]['inlineData'];
            if (inlineData != null) {
              final base64Data = inlineData['data']?.toString();
              final mimeType = inlineData['mimeType']?.toString() ?? '';
              debugPrint('[SpeechService] GoogleAI audio mimeType: $mimeType');
              if (base64Data != null) {
                Uint8List audioBytes = base64.decode(base64Data);
                // Gemini TTS returns audio/l16 or audio/pcm — raw 16-bit little-endian PCM
                // Despite the L16 label (RFC big-endian), Gemini sends little-endian data
                // so we only need to add a WAV header, no byte-swapping needed.
                final lowerMime = mimeType.toLowerCase();
                if (lowerMime.contains('l16') || lowerMime.contains('pcm') || lowerMime.isEmpty) {
                  final sampleRate = _parseSampleRate(mimeType, 24000);
                  final numChannels = _parseChannels(mimeType, 1);
                  audioBytes = _buildWavBytes(audioBytes, sampleRate: sampleRate, numChannels: numChannels);
                  debugPrint('[SpeechService] Wrapped $mimeType -> WAV (${audioBytes.length} bytes, ${sampleRate}Hz, ${numChannels}ch)');
                }
                final tempDir = await getTemporaryDirectory();
                final String tempPath = "${tempDir.path}/synthesized_${DateTime.now().millisecondsSinceEpoch}.wav";
                final wavFile = File(tempPath);
                await wavFile.writeAsBytes(audioBytes);
                return tempPath;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("GoogleAI synthesizeToFile Error: $e");
      }
    } else {
      if (_openaiApiKey == null || _openaiApiKey!.isEmpty) {
        debugPrint("[SpeechService] OpenAI API Key is missing.");
        return null;
      }
      try {
        final requestBody = {
          "model": "tts-1",
          "input": text,
          "voice": voiceName
        };

        final response = await _httpClient.post(
          Uri.parse("https://api.openai.com/v1/audio/speech"),
          headers: {
            "Authorization": "Bearer $_openaiApiKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode(requestBody),
        );

        if (response.statusCode != 200) {
          debugPrint("OpenAI API Error for TTS (${response.statusCode}): ${response.body}");
          return null;
        }

        final audioBytes = response.bodyBytes;
        if (audioBytes.isEmpty) return null;
        
        final tempDir = await getTemporaryDirectory();
        final String tempPath = "${tempDir.path}/synthesized_${DateTime.now().millisecondsSinceEpoch}.mp3";
        final mp3File = File(tempPath);
        await mp3File.writeAsBytes(audioBytes);
        return tempPath;
      } catch (e) {
        debugPrint("OpenAI synthesizeToFile Error: $e");
      }
    }
    return null;
  }

  /// Parses sample rate from mimeType string like "audio/l16; rate = 24000"
  int _parseSampleRate(String mimeType, int defaultRate) {
    final match = RegExp(r'rate\s*=\s*(\d+)').firstMatch(mimeType);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? defaultRate;
    }
    return defaultRate;
  }

  /// Parses channel count from mimeType string like "audio/l16; channels = 1"
  int _parseChannels(String mimeType, int defaultChannels) {
    final match = RegExp(r'channels\s*=\s*(\d+)').firstMatch(mimeType);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? defaultChannels;
    }
    return defaultChannels;
  }

  /// Wraps raw 16-bit mono PCM bytes into a valid WAV file with RIFF header.
  Uint8List _buildWavBytes(Uint8List pcmBytes, {int sampleRate = 24000, int numChannels = 1, int bitsPerSample = 16}) {
    final int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final int blockAlign = numChannels * bitsPerSample ~/ 8;
    final int dataSize = pcmBytes.length;
    final int chunkSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    // RIFF chunk
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, chunkSize, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E
    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little);         // subchunk size
    buffer.setUint16(20, 1, Endian.little);          // PCM = 1
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    final result = buffer.buffer.asUint8List();
    result.setRange(44, 44 + dataSize, pcmBytes);
    return result;
  }

  Future<void> _initPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');
    _loadApiKey();
  }

  void _loadApiKey() {
    try {
      final keyFile = File(join(_dataDir, "openAI_key.json"));
      if (keyFile.existsSync()) {
        final jsonStr = keyFile.readAsStringSync();
        final doc = jsonDecode(jsonStr);
        if (doc is Map) {
          if (doc.containsKey('OpenAI')) {
            _openaiApiKey = doc['OpenAI']['ApiKey']?.toString();
          }
          if (doc.containsKey('GoogleAI')) {
            _googleAiApiKey = doc['GoogleAI']['ApiKey']?.toString();
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading API keys for TTS: $e");
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
    
    _loadApiKey();

    if (text.trim().isEmpty) {
      debugPrint("TTS skipped: Text is empty.");
      return;
    }

    stop(); // Silently stop any active playback

    try {
      final tempPath = await synthesizeToFileAsync(text, _selectedVoiceName);
      if (tempPath == null || tempPath.isEmpty) {
        debugPrint("[SpeechService] Failed to synthesize speech.");
        return;
      }

      debugPrint("TTS audio saved to: $tempPath");

      // Play using just_audio player
      await _audioPlayer.setFilePath(tempPath);
      
      // Delay play by a brief 200ms to ensure device channel is ready
      await Future.delayed(const Duration(milliseconds: 200));

      if (flagSendUARTGlobal) {
        await _sendUartMessage("SAY\n");
      }
      sendAnimationFace("SAY");
      await _audioPlayer.play();
      if (flagSendUARTGlobal) {
        await _sendUartMessage("SIL\n");
      }
      sendAnimationFace("SILIENCE");
    } catch (e) {
      debugPrint("TTS Playback Error: $e");
      sendAnimationFace("SILIENCE");
    }
  }

  @override
  void stop() {
    try {
      _audioPlayer.stop();
      if (flagSendUARTGlobal) {
        _sendUartMessage("SIL\n");
      }
      sendAnimationFace("SILIENCE");
    } catch (e) {
      debugPrint("Error stopping audio player: $e");
    }
  }
}
