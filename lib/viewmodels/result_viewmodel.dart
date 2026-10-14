import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/patient.dart';
import '../services/llm_service.dart';
import '../services/log_service.dart';
import '../services/rule_engine_service.dart';
import 'conversation_viewmodel.dart';

class ResultViewModel extends ChangeNotifier {
  final IRuleEngineService _ruleEngine;
  final ILLMService _llmService;
  ConversationViewModel? _conversationViewModel;

  RuleResult? _decision;
  String _distressScore = "Đang tính điểm...";
  double _score = 0.0;
  double _disbursementMultiplier = 1.0;
  bool _isResultReady = false;
  bool _isCalculating = false;
  bool _isCaseClosed = false;
  bool _isInsufficient = false;
  Map<String, dynamic>? _lastScoringData;

  ResultViewModel(this._ruleEngine, this._llmService, [this._conversationViewModel]) {
    calculateScoreAsync();
  }

  RuleResult? get decision => _decision;
  String get distressScore => _distressScore;
  double get score => _score;
  double get disbursementMultiplier => _disbursementMultiplier;
  bool get isResultReady => _isResultReady;
  bool get isCalculating => _isCalculating;
  bool get isCaseClosed => _isCaseClosed;
  bool get isInsufficient => _isInsufficient;
  Map<String, dynamic>? get lastScoringData => _lastScoringData;

  void setConversationViewModel(ConversationViewModel vm) {
    _conversationViewModel = vm;
    if (_lastScoringData != null) {
      _conversationViewModel?.updateSessionLogWithScoring(_lastScoringData!);
    }
  }

  /// Tính hệ số giải ngân dựa theo bảng quy tắc Distress/Severity Score:
  /// - Severity = 0 (hoặc TẠM DỪNG - ĐÓNG CA): 0% (0.0)
  /// - Severity từ 1 đến 20: 20% (0.20)
  /// - Severity từ 21 đến 40: 40% (0.40)
  /// - Severity từ 41 đến 60: 60% (0.60)
  /// - Severity từ 61 đến 80: 80% (0.80)
  /// - Severity từ 81 đến 100: 100% (1.00)
  double calculateDisbursementMultiplier(double severityScore) {
    if (severityScore <= 0) return 0.0;
    if (severityScore >= 81) return 1.00;
    if (severityScore >= 61) return 0.80;
    if (severityScore >= 41) return 0.60;
    if (severityScore >= 21) return 0.40;
    return 0.20;
  }

  Future<void> calculateScoreAsync() async {
    if (_isCalculating) return;
    _isCalculating = true;
    _isResultReady = false;
    _isCaseClosed = false;
    _isInsufficient = false;
    _distressScore = "Đang tính điểm...";
    notifyListeners();

    try {
      final scoreStr = await _llmService.getDistressScoreAIAsync(_llmService.lastConversationHistory);
      _distressScore = scoreStr;

      // 0. Kiểm tra Tầng bảo vệ — Sàng lọc tính chính đáng
      final statusMatch = RegExp(r'(?:Trạng thái|Status)[^\n:]*:\s*([^\n]+)', caseSensitive: false).firstMatch(scoreStr);
      final statusText = statusMatch?.group(1)?.trim() ?? "";
      final bool hasCloseSignal = statusText.toUpperCase().contains("TẠM DỪNG") ||
          statusText.toUpperCase().contains("ĐÓNG CA") ||
          scoreStr.toUpperCase().contains("TẠM DỪNG - ĐÓNG CA") ||
          scoreStr.toUpperCase().contains("KHÔNG ĐÁP ỨNG TÍNH CHÍNH ĐÁNG");

      final bool isInsufficient = statusText.toUpperCase().contains("CHƯA ĐỦ THÔNG TIN") ||
          statusText.toUpperCase().contains("KHÔNG ĐỦ THÔNG TIN") ||
          statusText.toUpperCase().contains("THIẾU THÔNG TIN") ||
          scoreStr.toUpperCase().contains("TRẠNG THÁI: CHƯA ĐỦ THÔNG TIN");

      _isCaseClosed = hasCloseSignal;
      _isInsufficient = isInsufficient;

      // Trích xuất các trường chi tiết
      final emergencyText = _extractSection(scoreStr, RegExp(r'(?:Emergency|Mức độ khẩn cấp)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final incomeText = _extractSection(scoreStr, RegExp(r'(?:Income\s*&\s*RRTC|Thu nhập & RRTC|Income)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final familyText = _extractSection(scoreStr, RegExp(r'(?:Family|Gánh nặng gia đình)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final healthText = _extractSection(scoreStr, RegExp(r'(?:Health|Sức khỏe)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final formulaText = _extractSection(scoreStr, RegExp(r'(?:Công thức|Formula)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final verificationTierText = _extractSection(scoreStr, RegExp(r'(?:Xác minh chứng cứ|Verification Tier)[^\n:]*:\s*([^\n]+)', caseSensitive: false));
      final conclusionText = _extractSection(scoreStr, RegExp(r'(?:Kết luận|Conclusion)[^\n:]*:\s*([^\n]+)', caseSensitive: false));

      int? emergencyScore = _extractScoreNumber(emergencyText, 25) ?? _extractScoreNumber(emergencyText, 35);
      int? incomeScore = _extractScoreNumber(incomeText, 35);
      int? familyScore = _extractScoreNumber(familyText, 30);
      int? healthScore = _extractScoreNumber(healthText, 30);

      // Tự động kiểm tra và hiệu chỉnh nếu AI tính nhầm phép cộng Income (Phần A + Phần B)
      final matchPartA = RegExp(r'Phần A[^\(]*\((\d+)đ?\)', caseSensitive: false).firstMatch(incomeText);
      final matchPartB = RegExp(r'Phần B[^\(]*\((\d+)đ?\)', caseSensitive: false).firstMatch(incomeText);
      if (matchPartA != null && matchPartB != null) {
        final scoreA = int.tryParse(matchPartA.group(1)!);
        final scoreB = int.tryParse(matchPartB.group(1)!);
        if (scoreA != null && scoreB != null) {
          final expectedIncome = math.min(35, scoreA + scoreB);
          if (incomeScore != expectedIncome) {
            LogService.log("[ResultVM] Detected mismatch in Income & RRTC: AI wrote $incomeScore/35 but Part A ($scoreA) + Part B ($scoreB) = $expectedIncome. Auto-correcting incomeScore to $expectedIncome.");
            incomeScore = expectedIncome;
          }
        }
      }

      double proposedAmount = 0.0;
      double finalAmount = 0.0;
      double minLimit = _llmService.caseOperatorMin;
      double maxLimit = _llmService.caseOperatorMax;

      if (_isCaseClosed) {
        // TẦNG BẢO VỆ 1 KÍCH HOẠT: TẠM DỪNG - ĐÓNG CA (Số tiền giải ngân = 0)
        _score = 0.0;
        _disbursementMultiplier = 0.0;
        proposedAmount = _llmService.flagOperatorExact ? _llmService.caseOperatorExact : 0.0;
        finalAmount = 0.0;

        final reason = conclusionText.isNotEmpty
            ? conclusionText
            : "Ca bị TẠM DỪNG - ĐÓNG CA do phát hiện dấu hiệu quậy phá, mục đích không chính đáng (trả nợ cá nhân, cờ bạc, rượu chè...), hoặc không có nhu cầu hỗ trợ tài chính (chỉ cần tư vấn tâm lý).";

        _decision = RuleResult(
          isEligible: false,
          approvedAmount: 0.0,
          explanation: reason,
          computedAt: DateTime.now(),
        );

        _isResultReady = true;
      } else if (isInsufficient) {
        // TẦNG BẢO VỆ 2 KÍCH HOẠT: CHƯA ĐỦ THÔNG TIN (Số tiền giải ngân = 0, điểm = 0)
        _score = 0.0;
        _disbursementMultiplier = 0.0;
        proposedAmount = _llmService.flagOperatorExact ? _llmService.caseOperatorExact : 0.0;
        finalAmount = 0.0;

        final reason = conclusionText.isNotEmpty
            ? conclusionText
            : "Hồ sơ chưa đủ thông tin bắt buộc để xét duyệt hỗ trợ (chưa có thông tin khó khăn cụ thể, chưa nêu nhu cầu cần giúp đỡ, hoặc chưa có mốc thời gian khẩn cấp). Cần thực hiện phỏng vấn bổ sung.";

        _decision = RuleResult(
          isEligible: false,
          approvedAmount: 0.0,
          explanation: reason,
          computedAt: DateTime.now(),
        );

        _isResultReady = true;
      } else {
        // Trích xuất điểm Severity/Distress Score từ câu trả lời của AI
        _score = 0.0;
        final totalScoreMatch = RegExp(
          r'(?:Total\s+Score|Severity\s+Score|Score)[:\s]+(\d+)',
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

        // Tự động kiểm tra và hiệu chỉnh tính toán tổng điểm theo công thức: MIN(100, Emergency + Income&RRTC + Family + Health)
        if (emergencyScore != null && incomeScore != null && familyScore != null && healthScore != null) {
          final expectedTotal = math.min(100, emergencyScore + incomeScore + familyScore + healthScore);
          if (_score != expectedTotal) {
            LogService.log("[ResultVM] Detected arithmetic mismatch in AI total score: AI had $_score, expected $expectedTotal (E:$emergencyScore + I:$incomeScore + F:$familyScore + H:$healthScore). Auto-correcting total score.");
            _score = expectedTotal.toDouble();
          }
        }

        // Xác định hệ số giải ngân dựa trên điểm đã được hiệu chỉnh chính xác
        _disbursementMultiplier = calculateDisbursementMultiplier(_score);

        if (_score > 0) {
          // 1. Lấy số tiền đề xuất
          if (_llmService.flagOperatorExact) {
            proposedAmount = _llmService.caseOperatorExact;
          } else {
            final double maxAmount = await _ruleEngine.getMaxTransactionLimitAsync();
            proposedAmount = maxAmount;
          }

          // 2. Nhân số tiền đề xuất với hệ số giải ngân
          final double calculatedMoney = proposedAmount * _disbursementMultiplier;

          // 3. Giới hạn theo minLimit và maxLimit của tác viên
          minLimit = _llmService.caseOperatorMin;
          maxLimit = _llmService.caseOperatorMax;

          finalAmount = calculatedMoney.clamp(minLimit, maxLimit);

          _decision = RuleResult(
            isEligible: finalAmount > 0,
            approvedAmount: finalAmount,
            explanation: _llmService.flagOperatorExact
                ? "Hạn mức ${_formatCurrency(finalAmount)}đ được phê duyệt dựa trên Hệ số giải ngân (${(_disbursementMultiplier * 100).toStringAsFixed(0)}% - Distress Score ${_score.toStringAsFixed(0)}) và Số tiền đề xuất (${_formatCurrency(proposedAmount)}đ)."
                : "Hạn mức ${_formatCurrency(finalAmount)}đ được phê duyệt dựa trên Hệ số giải ngân (${(_disbursementMultiplier * 100).toStringAsFixed(0)}% - Distress Score ${_score.toStringAsFixed(0)}) và hạn mức cho phép của nhân viên (${_formatCurrency(minLimit)}đ - ${_formatCurrency(maxLimit)}đ).",
            computedAt: DateTime.now(),
          );

          _isResultReady = true;
        } else {
          // Fallback khi score bằng 0
          _decision = RuleResult(
            isEligible: false,
            approvedAmount: 0.0,
            explanation: "Không phát hiện Distress Score hợp lệ để tính toán mức tài trợ.",
            computedAt: DateTime.now(),
          );
          _isResultReady = true;
        }
      }

      _lastScoringData = {
        "status": _isCaseClosed ? "TẠM DỪNG - ĐÓNG CA" : (_isInsufficient ? "CHƯA ĐỦ THÔNG TIN" : (statusText.isNotEmpty ? statusText : "HỢP LỆ")),
        "emergency": emergencyText,
        "emergency_score": emergencyScore,
        "income_rrtc": incomeScore != null && !incomeText.startsWith("$incomeScore/")
            ? "$incomeScore/35 - ${incomeText.replaceFirst(RegExp(r'^\d+\s*/\s*35\s*-\s*'), '')}"
            : incomeText,
        "income_score": incomeScore,
        "family": familyText,
        "family_score": familyScore,
        "health": healthText,
        "health_score": healthScore,
        "distress_score": _score.toInt(),
        if (formulaText.isNotEmpty) "formula": formulaText,
        "disbursement_multiplier": _disbursementMultiplier,
        "disbursement_multiplier_percent": "${(_disbursementMultiplier * 100).toStringAsFixed(0)}%",
        "proposed_amount": proposedAmount,
        "approved_amount": finalAmount,
        if (verificationTierText.isNotEmpty) "verification_tier": verificationTierText,
        if (conclusionText.isNotEmpty) "conclusion": conclusionText,
        "raw_scoring_response": scoreStr,
      };

      // Tự động ghi lại kết quả tính điểm vào file log conversation JSON
      if (_conversationViewModel != null && _lastScoringData != null) {
        await _conversationViewModel!.updateSessionLogWithScoring(_lastScoringData!);
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
    } finally {
      _isCalculating = false;
      notifyListeners();
    }
  }

  String _extractSection(String text, RegExp reg) {
    final m = reg.firstMatch(text);
    return m != null ? (m.group(1)?.trim() ?? "") : "";
  }

  int? _extractScoreNumber(String text, int maxPoints) {
    final m = RegExp('(\\d+)\\s*/\\s*$maxPoints').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
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
    _disbursementMultiplier = 1.0;
    _isResultReady = false;
    _isCalculating = false;
    _isCaseClosed = false;
    _isInsufficient = false;
    _lastScoringData = null;
    notifyListeners();
  }
}
