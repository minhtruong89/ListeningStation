import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/operator.dart';
import '../models/patient.dart';
import 'auth_service.dart';
import 'camera_service.dart';
import 'data_service.dart';
import 'llm_service.dart';

class RuleCheckResult {
  final String id;
  final String message;
  final bool isValid;

  RuleCheckResult({
    required this.id,
    required this.message,
    required this.isValid,
  });

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'Message': message,
      'IsValid': isValid,
    };
  }
}

abstract class IRuleEngineService {
  RuleResult evaluate(Patient patient);
  Future<List<RuleCheckResult>> evaluateSystemRulesAsync({Function(RuleCheckResult)? onProgress});
  Future<double> getSpentInPeriodAsync(String period);
  Future<bool> isWithinBudgetLimitAsync(String period, double limit);
  Future<int> getRequiredOperatorCountAsync(bool isInsideWorkingHours);
  Future<double> getMaxTransactionLimitAsync();
  Future<List<RuleCheckResult>> evaluateStaffVerificationAsync(List<Operator> operators);
}

class RuleEngineService implements IRuleEngineService {
  final ILLMService _llmService;
  final ICameraService _cameraService;
  final IDataService _dataService;
  final IAuthService _authService;
  final http.Client _httpClient;

  late String _dataDir;

  RuleEngineService(
    this._llmService,
    this._cameraService,
    this._dataService,
    this._authService, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Future<void> _initDataDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');
  }

  @override
  RuleResult evaluate(Patient patient) {
    double baseAmount = 1000.0;
    double childMultiplier = 200.0;

    double approvedAmount = baseAmount + (patient.familySize * childMultiplier);

    if (patient.monthlyIncome > 5000) approvedAmount *= 0.5;
    if (patient.monthlyIncome > 10000) approvedAmount = 0.0;

    final flags = patient.medicalConditionFlags ?? "";
    if (flags.contains("CHRONIC")) approvedAmount += 500.0;
    if (flags.contains("DISABILITY")) approvedAmount += 1000.0;

    return RuleResult(
      isEligible: approvedAmount > 0,
      approvedAmount: approvedAmount,
      explanation: approvedAmount > 0
          ? "Approved based on family size (${patient.familySize}) and medical conditions. Adjusted for income (\$${patient.monthlyIncome.toStringAsFixed(0)})."
          : "Income exceeds threshold for financial support.",
      computedAt: DateTime.now(),
    );
  }

  @override
  Future<List<RuleCheckResult>> evaluateSystemRulesAsync({Function(RuleCheckResult)? onProgress}) async {
    await _initDataDir();
    final List<RuleCheckResult> results = [];
    String jsonPath = join(_dataDir, "rule_engine.json");
    File jsonFile = File(jsonPath);

    if (!jsonFile.existsSync()) {
      return results;
    }

    try {
      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> doc = jsonDecode(jsonContent);
      final List<dynamic>? rules = doc['system_rules'];

      if (rules != null) {
        for (var rule in rules) {
          final String id = rule['id'] ?? "";
          final String messageVi = rule['message_vi'] ?? "";

          bool isValid = true;
          switch (id) {
            case "SYS001":
              isValid = await _checkInternetAsync();
              break;
            case "SYS002":
              isValid = await _checkAiConnectionAsync();
              break;
            case "SYS003":
              isValid = _cameraService.hasCamera;
              break;
            case "SYS004":
              isValid = true; // SYS004 - Cash available (always true for mobile mock)
              break;
            case "SYS005":
              isValid = true; // SYS005 - Cassette door closed (always true for mobile mock)
              break;
            case "SYS006":
              isValid = File(join(_dataDir, 'listening_station.db')).existsSync();
              break;
            case "SYS007":
              isValid = await _checkFinancialLimitsAsync();
              break;
            case "SYS008":
              isValid = true; // Hardware error allowed (mock true)
              break;
          }

          debugPrint("[RULE CHECK] ID: $id, Valid: $isValid, Message: $messageVi");
          final result = RuleCheckResult(id: id, message: messageVi, isValid: isValid);
          results.add(result);

          if (onProgress != null) {
            onProgress(result);
            await Future.delayed(const Duration(seconds: 1));
          }

          if (!isValid) break; // Terminate early on first validation failure
        }
      }
    } catch (ex) {
      results.add(RuleCheckResult(id: "JSON_ERROR", message: "Lỗi đọc file rule: $ex", isValid: false));
    }

    return results;
  }

  Future<bool> _checkInternetAsync() async {
    try {
      final response = await _httpClient.get(Uri.parse("https://www.google.com")).timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkAiConnectionAsync() async {
    return await _llmService.pingAsync();
  }

  Future<bool> _checkFinancialLimitsAsync() async {
    try {
      String jsonPath = join(_dataDir, "rule_engine.json");
      File jsonFile = File(jsonPath);
      if (!jsonFile.existsSync()) return true;

      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> doc = jsonDecode(jsonContent);
      final financialLimits = doc['financial_limits'];

      if (financialLimits != null && financialLimits['budget_limits'] != null) {
        final dailyLimitVal = financialLimits['budget_limits']['daily_limit']['value'];
        final double dailyLimit = (dailyLimitVal as num).toDouble();
        final double spentToday = await getSpentInPeriodAsync("daily");
        debugPrint("[SYS007] Daily Limit: \$dailyLimit, Spent Today: \$spentToday");
        return spentToday < dailyLimit;
      }
    } catch (ex) {
      debugPrint("Error checking financial limits: \$ex");
    }
    return true;
  }

  @override
  Future<double> getSpentInPeriodAsync(String period) async {
    DateTime start = DateTime.now();
    DateTime end = DateTime.now();

    final now = DateTime.now();
    switch (period.toLowerCase()) {
      case "daily":
        start = DateTime(now.year, now.month, now.day);
        break;
      case "weekly":
        // Start of current week (assume Sunday start)
        start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7));
        break;
      case "monthly":
        start = DateTime(now.year, now.month, 1);
        break;
    }

    return await _dataService.getTotalSpentAsync(start, end);
  }

  @override
  Future<bool> isWithinBudgetLimitAsync(String period, double limit) async {
    final spent = await getSpentInPeriodAsync(period);
    return spent < limit;
  }

  @override
  Future<int> getRequiredOperatorCountAsync(bool isInsideWorkingHours) async {
    await _initDataDir();
    String jsonPath = join(_dataDir, "rule_engine.json");
    File jsonFile = File(jsonPath);
    if (!jsonFile.existsSync()) return 1;

    try {
      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> doc = jsonDecode(jsonContent);
      final staffRules = doc['staff_verification_rules'];

      final ruleKey = isInsideWorkingHours ? "ctxh_staff_required" : "after_hours_staff_required";

      if (staffRules is List) {
        for (var rule in staffRules) {
          if (rule is Map && rule.containsKey(ruleKey)) {
            return int.tryParse(rule[ruleKey].toString()) ?? 1;
          }
        }
      } else if (staffRules is Map && staffRules.containsKey(ruleKey)) {
        final req = staffRules[ruleKey];
        if (req is num) {
          return req.toInt();
        } else if (req is Map && req.containsKey('number_of_operator_needed')) {
          return int.tryParse(req['number_of_operator_needed'].toString()) ?? 1;
        }
      }
    } catch (ex) {
      debugPrint("Error reading required operator count: \$ex");
    }
    return 1;
  }

  @override
  Future<double> getMaxTransactionLimitAsync() async {
    await _initDataDir();
    String jsonPath = join(_dataDir, "rule_engine.json");
    File jsonFile = File(jsonPath);
    if (!jsonFile.existsSync()) return 2000000.0;

    try {
      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> doc = jsonDecode(jsonContent);
      final financialLimits = doc['financial_limits'];
      if (financialLimits != null && financialLimits['max_per_transaction'] != null) {
        return (financialLimits['max_per_transaction'] as num).toDouble();
      }
    } catch (ex) {
      debugPrint("Error reading max transaction limit: \$ex");
    }
    return 2000000.0;
  }

  @override
  Future<List<RuleCheckResult>> evaluateStaffVerificationAsync(List<Operator> operators) async {
    await _initDataDir();
    final List<RuleCheckResult> results = [];
    String jsonPath = join(_dataDir, "rule_engine.json");
    File jsonFile = File(jsonPath);
    if (!jsonFile.existsSync()) return results;

    try {
      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> doc = jsonDecode(jsonContent);
      final List<dynamic>? rules = doc['staff_verification_rules'];

      if (rules != null) {
        final isInside = _authService.isInsideWorkingHours();

        for (var rule in rules) {
          final String id = rule['id'] ?? "";
          final String messageVi = rule['message_vi'] ?? "";

          bool isValid = true;
          switch (id) {
            case "STAFF001":
              isValid = true;
              break;
            case "STAFF002":
              isValid = true;
              break;
            case "STAFF003":
              isValid = true;
              break;
            case "STAFF004":
              isValid = true;
              break;
            case "STAFF005":
              if (!isInside) {
                final requiredCount = int.tryParse(rule['after_hours_staff_required']?.toString() ?? '1') ?? 1;
                isValid = operators.length >= requiredCount;
              }
              break;
            case "STAFF006":
              if (isInside) {
                final requiredCount = int.tryParse(rule['ctxh_staff_required']?.toString() ?? '1') ?? 1;
                isValid = operators.length >= requiredCount;
              }
              break;
            case "STAFF007":
              isValid = true; // SMS verification mock
              break;
            case "STAFF008":
              isValid = await _checkStaffDailyCaseLimitAsync(operators, rule);
              break;
          }

          debugPrint("[STAFF RULE] ID: \$id, Valid: \$isValid, Message: \$messageVi");
          results.add(RuleCheckResult(id: id, message: messageVi, isValid: isValid));

          if (!isValid) break;
        }
      }
    } catch (ex) {
      results.add(RuleCheckResult(id: "STAFF_JSON_ERROR", message: "Lỗi đọc file staff rule: \$ex", isValid: false));
    }
    return results;
  }

  Future<bool> _checkStaffDailyCaseLimitAsync(List<Operator> operators, Map<String, dynamic> rule) async {
    final limitVal = rule['staff_daily_case_limit'];
    if (limitVal == null) return true;
    final int limit = int.tryParse(limitVal.toString()) ?? 5;

    final today = DateTime.now();
    for (var op in operators) {
      final count = await _dataService.getOperatorVerificationCountAsync(op.id, today);
      if (count > limit) return false;
    }
    return true;
  }
}
