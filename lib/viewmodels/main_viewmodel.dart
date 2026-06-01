import 'package:flutter/foundation.dart';
import '../services/rule_engine_service.dart';

enum AppStage {
  splash,
  auth,
  conversation,
  result
}

class MainViewModel extends ChangeNotifier {
  final IRuleEngineService _ruleEngine;
  
  AppStage _currentStage = AppStage.splash;
  String _errorMessage = "";
  bool _isValidating = true;

  MainViewModel(this._ruleEngine) {
    runStartupChecks();
  }

  AppStage get currentStage => _currentStage;
  String get errorMessage => _errorMessage;
  bool get isValidating => _isValidating;

  Future<void> runStartupChecks() async {
    _isValidating = true;
    _errorMessage = "";
    notifyListeners();

    // Visual pause for splash aesthetics
    await Future.delayed(const Duration(seconds: 1500));

    final ruleResults = await _ruleEngine.evaluateSystemRulesAsync();
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
