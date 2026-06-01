import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract class ISpeechService {
  Future<void> speakAsync(String text);
  void stop();
  bool get isMuted;
  set isMuted(bool value);
}

class SpeechService implements ISpeechService {
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

  Future<void> _initPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');

    final tempDir = await getTemporaryDirectory();
    _tempMp3Path = join(tempDir.path, 'ListeningStation_TTS_\${DateTime.now().microsecondsSinceEpoch}.mp3');
    
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
      debugPrint("Error loading OpenAI Key for TTS: \$e");
    }
  }

  @override
  Future<void> speakAsync(String text) async {
    if (_isMuted) return;
    
    // Lazy API key load if not loaded on constructor init
    if (_apiKey == null) {
      _loadApiKey();
    }

    if (text.trim().isEmpty || _apiKey == null || _apiKey!.isEmpty) {
      debugPrint("TTS skipped: Text is empty or API Key is missing.");
      return;
    }

    stop(); // Silently stop any active playback

    try {
      const modelName = "gpt-4o-audio-preview";
      const systemPrompt = "You are a pure Text-to-Speech engine. Your ONLY job is to repeat exactly what the user says. Do not answer questions, do not apologize, do not add any commentary. Repeat the exact text using a gentle and friendly female Southern Vietnamese voice (giọng nữ miền Nam), speak slowly and clearly, maintain a warm and caring tone, add natural pauses between sentences, and ensure the speech is easy to understand for elderly listeners.";

      final requestBody = {
        "model": modelName,
        "temperature": 0.3,
        "modalities": ["text", "audio"],
        "audio": {"voice": "nova", "format": "mp3"},
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": "Repeat this exact text: '\$text'"}
        ]
      };

      final response = await _httpClient.post(
        Uri.parse("https://api.openai.com/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer \$_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        debugPrint("OpenAI API Error for TTS (\${response.statusCode}): \${response.body}");
        return;
      }

      final doc = jsonDecode(response.body);
      final String? base64Audio = doc['choices'][0]['message']['audio']['data'];

      if (base64Audio == null || base64Audio.isEmpty) return;

      final audioBytes = base64.decode(base64Audio);
      
      final mp3File = File(_tempMp3Path);
      await mp3File.writeAsBytes(audioBytes);
      debugPrint("TTS MP3 saved to: \$_tempMp3Path");

      // Play using just_audio player
      await _audioPlayer.setFilePath(_tempMp3Path);
      
      // Delay play by a brief 200ms to ensure device channel is ready
      await Future.delayed(const Duration(milliseconds: 200));
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("OpenAI TTS Error: \$e");
    }
  }

  @override
  void stop() {
    try {
      _audioPlayer.stop();
    } catch (e) {
      debugPrint("Error stopping audio player: \$e");
    }
  }
}
