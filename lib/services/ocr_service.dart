import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

abstract class IOCRService {
  Future<String> extractTextAsync(String imagePath);
  void dispose();
}

class OCRService implements IOCRService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String> extractTextAsync(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _recognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      return "Error: \$e";
    }
  }

  @override
  void dispose() {
    _recognizer.close();
  }
}
