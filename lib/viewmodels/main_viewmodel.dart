import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/rule_engine_service.dart';
import '../services/camera_service.dart';

enum AppStage {
  splash,
  auth,
  conversation,
  result
}

class MainViewModel extends ChangeNotifier {
  final IRuleEngineService _ruleEngine;
  final ICameraService _cameraService;
  
  AppStage _currentStage = AppStage.splash;
  String _errorMessage = "";
  bool _isValidating = true;
  final List<String> _startupCheckLogs = [];

  MainViewModel(this._ruleEngine, this._cameraService) {
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

    // 1. Request camera permission before checks
    try {
      final status = await Permission.camera.request();
      debugPrint("[MainViewModel] Camera permission status: $status");
      // Even if permission is denied, we re-initialize the camera service to try detecting.
      await _cameraService.initializeAsync();
    } catch (e) {
      debugPrint("[MainViewModel] Error requesting camera permission: $e");
    }

    // Visual pause for splash aesthetics
    await Future.delayed(const Duration(milliseconds: 1500));

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
    notifyListeners();
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
}
