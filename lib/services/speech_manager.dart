import 'speech_service.dart';
import 'local_speech_service.dart';

class SpeechManager implements ISpeechService {
  final SpeechService _openaiSpeechService;
  final LocalSpeechService _localSpeechService;
  
  @override
  bool flagLocalTTS = true;
  @override
  bool flagLocalTTS_checkSwitch = false;

  SpeechManager({
    SpeechService? openaiSpeechService,
    LocalSpeechService? localSpeechService,
  })  : _openaiSpeechService = openaiSpeechService ?? SpeechService(),
        _localSpeechService = localSpeechService ?? LocalSpeechService();

  @override
  bool get isMuted {
    return flagLocalTTS ? _localSpeechService.isMuted : _openaiSpeechService.isMuted;
  }

  @override
  set isMuted(bool value) {
    _openaiSpeechService.isMuted = value;
    _localSpeechService.isMuted = value;
  }

  @override
  String get selectedVoiceName => flagLocalTTS ? _localSpeechService.selectedVoiceName : _openaiSpeechService.selectedVoiceName;

  @override
  set selectedVoiceName(String name) {
    if (flagLocalTTS) {
      _localSpeechService.selectedVoiceName = name;
    } else {
      _openaiSpeechService.selectedVoiceName = name;
    }
  }

  @override
  String get onlineTtsProvider => _openaiSpeechService.onlineTtsProvider;

  @override
  set onlineTtsProvider(String provider) {
    _openaiSpeechService.onlineTtsProvider = provider;
  }

  @override
  Future<List<String>> getVietnameseVoices() async {
    if (flagLocalTTS) {
      return await _localSpeechService.getVietnameseVoices();
    } else {
      return await _openaiSpeechService.getVietnameseVoices();
    }
  }

  @override
  Future<String?> synthesizeToFileAsync(String text, String voiceName) async {
    if (flagLocalTTS) {
      return await _localSpeechService.synthesizeToFileAsync(text, voiceName);
    } else {
      return await _openaiSpeechService.synthesizeToFileAsync(text, voiceName);
    }
  }

  @override
  void setUartDevice(int vendorId, int productId) {
    _openaiSpeechService.setUartDevice(vendorId, productId);
    _localSpeechService.setUartDevice(vendorId, productId);
  }

  @override
  Future<void> speakAsync(String text) async {
    if (flagLocalTTS) {
      await _localSpeechService.speakAsync(text);
    } else {
      await _openaiSpeechService.speakAsync(text);
    }
  }

  @override
  void stop() {
    if (flagLocalTTS) {
      _localSpeechService.stop();
    } else {
      _openaiSpeechService.stop();
    }
  }
}
