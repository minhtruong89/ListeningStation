import 'package:flutter/foundation.dart';
import '../models/patient.dart';
import '../services/llm_service.dart';
import '../services/rule_engine_service.dart';

class ResultViewModel extends ChangeNotifier {
  final IRuleEngineService _ruleEngine;
  final ILLMService _llmService;

  RuleResult? _decision;
  String _distressScore = "Đang tính điểm...";
  double _score = 0.0;
  bool _isResultReady = false;

  ResultViewModel(this._ruleEngine, this._llmService) {
    calculateScoreAsync();
  }

  RuleResult? get decision => _decision;
  String get distressScore => _distressScore;
  double get score => _score;
  bool get isResultReady => _isResultReady;

  Future<void> calculateScoreAsync() async {
    _isResultReady = false;
    _distressScore = "Đang tính điểm...";
    notifyListeners();

    try {
      final scoreStr = await _llmService.getDistressScoreAIAsync(_llmService.lastConversationHistory);
      _distressScore = scoreStr;

      // Extract numeric score percentage
      _score = 0.0;
      final totalScoreMatch = RegExp(
        r'(?:Total\s+Score|Score)[:\s]+(\d+)',
        caseSensitive: false,
      ).firstMatch(scoreStr);

      if (totalScoreMatch != null) {
        _score = double.tryParse(totalScoreMatch.group(1)!) ?? 0.0;
      } else {
        final allDigitMatches = RegExp(r'\d+').allMatches(scoreStr).toList();
        if (allDigitMatches.isNotEmpty) {
          _score = double.tryParse(allDigitMatches.last.group(0)!) ?? 0.0;
        }
      }

      if (_score > 0) {
        double finalAmount = 0.0;
        double minLimit = _llmService.caseOperatorMin;
        double maxLimit = _llmService.caseOperatorMax;

        if (_llmService.flagOperatorExact) {
          finalAmount = _llmService.caseOperatorExact * (_score / 100.0);
        } else {
          // 1. Get max limit from rule engine
          final double maxAmount = await _ruleEngine.getMaxTransactionLimitAsync();

          // 2. Calculate score money
          final double conversationScoreMoney = maxAmount * (_score / 100.0);

          // 3. Get operator limits
          minLimit = _llmService.caseOperatorMin;
          maxLimit = _llmService.caseOperatorMax;

          // 4. Clamped approved amount
          finalAmount = conversationScoreMoney.clamp(minLimit, maxLimit);
        }

        _decision = RuleResult(
          isEligible: finalAmount > 0,
          approvedAmount: finalAmount,
          explanation: _llmService.flagOperatorExact
              ? "Hạn mức ${_formatCurrency(finalAmount)}đ được phê duyệt dựa trên chỉ số Distress Score (${_score.toStringAsFixed(0)}%) và Hạn mức Đề ra (${_formatCurrency(_llmService.caseOperatorExact)}đ)."
              : "Hạn mức ${_formatCurrency(finalAmount)}đ được phê duyệt dựa trên chỉ số Distress Score (${_score.toStringAsFixed(0)}%) và hạn mức cho phép của nhân viên (${_formatCurrency(minLimit)}đ - ${_formatCurrency(maxLimit)}đ).",
          computedAt: DateTime.now(),
        );

        _isResultReady = true;
      } else {
        // Fallback or score is 0
        _decision = RuleResult(
          isEligible: false,
          approvedAmount: 0.0,
          explanation: "Không phát hiện Distress Score hợp lệ để tính toán mức tài trợ.",
          computedAt: DateTime.now(),
        );
        _isResultReady = true;
      }
    } catch (e) {
      _distressScore = "Lỗi tính toán: $e";
      _decision = RuleResult(
        isEligible: false,
        approvedAmount: 0.0,
        explanation: "Xảy ra lỗi trong quá trình tính điểm và duyệt hạn mức.",
        computedAt: DateTime.now(),
      );
      _isResultReady = true;
    }
    notifyListeners();
  }

  // ignore: unused_element
  String _formatCurrency(double amount) {
    // Basic comma formatter for thousands
    String val = amount.toStringAsFixed(0);
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return val.replaceAllMapped(reg, (Match m) => "${m[1]},");
  }

  void reset() {
    _decision = null;
    _distressScore = "Đang tính điểm...";
    _score = 0.0;
    _isResultReady = false;
    notifyListeners();
  }
}
