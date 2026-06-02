import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import '../services/rule_engine_service.dart';
import '../services/camera_service.dart';
import '../services/data_service.dart';
import '../services/llm_service.dart';

enum AppStage {
  splash,
  auth,
  conversation,
  result
}

class MainViewModel extends ChangeNotifier {
  final IRuleEngineService _ruleEngine;
  final ICameraService _cameraService;
  final IDataService _dataService;
  final ILLMService _llmService;
  
  AppStage _currentStage = AppStage.splash;
  String _errorMessage = "";
  bool _isValidating = true;
  final List<String> _startupCheckLogs = [];

  MainViewModel(this._ruleEngine, this._cameraService, this._dataService, this._llmService) {
    runStartupChecks();
  }

  AppStage get currentStage => _currentStage;
  String get errorMessage => _errorMessage;
  bool get isValidating => _isValidating;
  List<String> get startupCheckLogs => _startupCheckLogs;

  Future<void> runStartupChecks() async {
    _isValidating = true;
    _errorMessage = "";
    _startupCheckLogs.clear();
    notifyListeners();

    // 1. Initialize local database
    _startupCheckLogs.add("SYS_DB - Đang khởi tạo CSDL...");
    notifyListeners();
    try {
      await _dataService.initializeAsync();
      await _dataService.clearOperatorVerificationsAsync();
      _startupCheckLogs.removeLast();
      _startupCheckLogs.add("SYS_DB - PASS (CSDL ok)");
    } catch (e) {
      _startupCheckLogs.removeLast();
      _startupCheckLogs.add("SYS_DB - fail - CSDL lỗi: $e");
      _errorMessage = "Không thể khởi tạo cơ sở dữ liệu";
      _isValidating = false;
      notifyListeners();
      return;
    }
    notifyListeners();

    // 2. Initialize LLM Service
    _startupCheckLogs.add("SYS_AI - Đang khởi tạo AI...");
    notifyListeners();
    try {
      await _llmService.initializeAsync();
      _startupCheckLogs.removeLast();
      _startupCheckLogs.add("SYS_AI - PASS (AI ok)");
    } catch (e) {
      _startupCheckLogs.removeLast();
      _startupCheckLogs.add("SYS_AI - fail - AI lỗi: $e");
      _errorMessage = "Không thể khởi tạo dịch vụ AI";
      _isValidating = false;
      notifyListeners();
      return;
    }
    notifyListeners();

    // 3. Request camera permission before checks
    try {
      final status = await Permission.camera.request();
      debugPrint("[MainViewModel] Camera permission status: $status");
      // Even if permission is denied, we re-initialize the camera service to try detecting.
      await _cameraService.initializeAsync();
    } catch (e) {
      debugPrint("[MainViewModel] Error requesting camera permission: $e");
    }

    // Visual pause for splash aesthetics
    await Future.delayed(const Duration(milliseconds: 800));

    final ruleResults = await _ruleEngine.evaluateSystemRulesAsync(
      onProgress: (result) {
        final status = result.isValid ? "PASS" : "fail - ${result.message}";
        _startupCheckLogs.add("${result.id} - $status");
        notifyListeners();
      },
    );
    bool allValid = true;
    for (var r in ruleResults) {
      if (!r.isValid) {
        allValid = false;
        _errorMessage = r.message;
        break;
      }
    }

    _isValidating = false;
    if (allValid) {
      _currentStage = AppStage.auth;
    } else {
      _currentStage = AppStage.splash; // Stay on splash showing error
    }

    await testOutputLine();

    //notifyListeners();
  }

  void navigateTo(AppStage stage) {
    _currentStage = stage;
    notifyListeners();
  }

  void resetApp() {
    _currentStage = AppStage.auth;
    _errorMessage = "";
    _isValidating = false;
    notifyListeners();
  }

  Future<void> testOutputLine() async {

    // STEP 1 - List all lines of audio out and micro recording detected
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
        final Map<dynamic, dynamic>? devices = await channel.invokeMethod<Map<dynamic, dynamic>>('getAudioDevices');
        if (devices != null) {
          final List<dynamic>? outputs = devices['outputs'];
          final List<dynamic>? inputs = devices['inputs'];
          debugPrint("[Hardware Check] Android Audio Outputs:");
          if (outputs != null && outputs.isNotEmpty) {
            for (var dev in outputs) {
              debugPrint("  - $dev");
            }
          } else {
            debugPrint("  None detected");
          }

          debugPrint("[Hardware Check] Android Microphone Inputs:");
          if (inputs != null && inputs.isNotEmpty) {
            for (var dev in inputs) {
              debugPrint("  - $dev");
            }
          } else {
            debugPrint("  None detected");
          }
        }
      } else {
        // Non-Android platforms (e.g. Windows development) fallback/mock
        debugPrint("[Hardware Check] Non-Android Platform. Outputting mockup devices:");
        debugPrint("  - Speakers (Virtual Output)");
        debugPrint("  - Microphone (Virtual Input)");
      }
    } catch (e) {
      debugPrint("[Hardware Check] Error detecting audio/micro devices: $e");
    }

    // STEP 2 - PLAY file mp3 at specific output targetName
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
        final String targetName = "AB13X";
        
        int targetIndex = -1;
        String targetDeviceName = "Unknown Device";
        
        final Map<dynamic, dynamic>? devices = await channel.invokeMethod<Map<dynamic, dynamic>>('getAudioDevices');
        if (devices != null) {
          final List<dynamic>? outputs = devices['outputs'];
          if (outputs != null) {
            for (int i = 0; i < outputs.length; i++) {
              final String name = outputs[i].toString();
              if (name.toLowerCase().contains(targetName.toLowerCase())) {
                targetIndex = i;
                targetDeviceName = name;
                break;
              }
            }
          }
        }

        if (targetIndex != -1) {
          final String path = "/sdcard/Eminem Ringtone.mp3";
          debugPrint("[Hardware Check] Found matching device '$targetDeviceName' at index $targetIndex. Attempting to play mp3: $path");
          final bool? success = await channel.invokeMethod<bool>('playMp3AtDevice', {
            'filePath': path,
            'deviceIndex': targetIndex,
          });
          debugPrint("[Hardware Check] Play mp3 success status: $success");
        } else {
          debugPrint("[Hardware Check] No output device containing '$targetName' was found. Skip playing.");
        }
      } else {
        debugPrint("[Hardware Check] Play mp3 skipped: Not on Android platform.");
      }
    } catch (e) {
      debugPrint("[Hardware Check] Error playing audio device at index: $e");
    }


  }

}
