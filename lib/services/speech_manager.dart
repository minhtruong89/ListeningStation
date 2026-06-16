import 'speech_service.dart';
import 'local_speech_service.dart';

class SpeechManager implements ISpeechService {
  final SpeechService _openaiSpeechService;
  final LocalSpeechService _localSpeechService;
  
  @override
  bool flagLocalTTS = true;

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
  bool get flagSendUART {
    return flagLocalTTS ? _localSpeechService.flagSendUART : _openaiSpeechService.flagSendUART;
  }

  @override
  set flagSendUART(bool value) {
    _openaiSpeechService.flagSendUART = value;
    _localSpeechService.flagSendUART = value;
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
