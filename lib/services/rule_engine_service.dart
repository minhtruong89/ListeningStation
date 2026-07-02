import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/operator.dart';
import '../models/patient.dart';
import 'auth_service.dart';
import 'camera_service.dart';
import 'data_service.dart';
import 'llm_service.dart';
import 'speech_service.dart';

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

  int get matchedMicrophoneIndex;
  String get matchedMicrophoneName;
}

class RuleEngineService implements IRuleEngineService {
  final ILLMService _llmService;
  final ISpeechService _speechService;
  final ICameraService _cameraService;
  final IDataService _dataService;
  final IAuthService _authService;
  final http.Client _httpClient;

  int _matchedMicrophoneIndex = -1;
  String _matchedMicrophoneName = "";

  @override
  int get matchedMicrophoneIndex => _matchedMicrophoneIndex;

  @override
  String get matchedMicrophoneName => _matchedMicrophoneName;

  late String _dataDir;

  RuleEngineService(
    this._llmService,
    this._speechService,
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
          String messageVi = rule['message_vi'] ?? "";

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
              isValid = await _checkMicrophoneDeviceAsync();
              break;
            case "SYS005":
              isValid = SpeechService.flagSendUARTGlobal ? await _checkUartSendTextNoAsync() : true;
              break;
            case "SYS006":
              isValid = File(join(_dataDir, 'listening_station.db')).existsSync();
              break;
            case "SYS007":
              isValid = await _checkFinancialLimitsAsync();
              break;
            case "SYS008":
              isValid = await _checkTtsAsync(onProgress: onProgress);
              if (!isValid) {
                messageVi = _speechService.flagLocalTTS 
                    ? "Không tìm thấy dịch vụ Google Speech Services (TTS) trên thiết bị" 
                    : "Thiếu OpenAI API Key cho TTS";
              }
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

  Future<bool> _checkMicrophoneDeviceAsync() async {
    try {
      if (Platform.isAndroid) {
        await Permission.microphone.request();
        await Permission.storage.request();

        try {
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
        } catch (e) {
          debugPrint("[Hardware Check] Error detecting audio/micro devices: $e");
        }

        const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
        final List<String> targets = ["UGREEN", "Camera", "Logi", "USB-Audio"];

        final Map<dynamic, dynamic>? devices = await channel.invokeMethod<Map<dynamic, dynamic>>('getAudioDevices');
        if (devices != null) {
          final List<dynamic>? inputs = devices['inputs'];
          if (inputs != null) {
            for (int i = 0; i < inputs.length; i++) {
              final String name = inputs[i].toString();
              bool matched = false;
              for (var target in targets) {
                if (name.toLowerCase().contains(target.toLowerCase())) {
                  matched = true;
                  break;
                }
              }
              if (matched) {
                _matchedMicrophoneIndex = i;
                _matchedMicrophoneName = name;
                debugPrint("[SYS004] Found matching micro device: $_matchedMicrophoneName at index $_matchedMicrophoneIndex");
                return true;
              }
            }
          }
        }
        debugPrint("[SYS004] No matching micro device containing UGREEN, Camera, or Logi was found.");
        return false;
      } else {
        // Mock true on other platforms (e.g. Windows)
        _matchedMicrophoneIndex = 0;
        _matchedMicrophoneName = "Microphone (Virtual Input)";
        return true;
      }
    } catch (e) {
      debugPrint("[SYS004] Error checking microphone device: $e");
      return false;
    }
  }

  Future<bool> _checkUartSendTextNoAsync() async {
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.soncamedia.listeningstation/audio_devices');
        debugPrint("[SYS005] Scanning for USB Serial devices...");
        
        try {
          final List<dynamic>? allDevices = await channel.invokeMethod<List<dynamic>>('getAllUsbDevices');
          if (allDevices != null && allDevices.isNotEmpty) {
            debugPrint("[SYS005] Connected USB hardware list (before filtering):");
            for (var dev in allDevices) {
              final d = dev as Map<dynamic, dynamic>;
              debugPrint("  -> ${d['name']} | VID: 0x${(d['vendorId'] as int).toRadixString(16).toUpperCase()} (${d['vendorId']}) | PID: 0x${(d['productId'] as int).toRadixString(16).toUpperCase()} (${d['productId']}) | Class: ${d['deviceClass']}");
            }
          } else {
            debugPrint("[SYS005] No physical USB devices detected.");
          }
        } catch (e) {
          debugPrint("[SYS005] Error querying connected USB devices: $e");
        }

        final List<dynamic>? serialDevices = await channel.invokeMethod<List<dynamic>>('getUsbSerialDevices');
        if (serialDevices != null && serialDevices.isNotEmpty) {
          final Map<dynamic, dynamic> firstDevice = serialDevices.first as Map<dynamic, dynamic>;
          final String name = firstDevice['name'] ?? "Unknown";
          final int vid = firstDevice['vendorId'] ?? 0;
          final int pid = firstDevice['productId'] ?? 0;
          bool hasPerm = firstDevice['hasPermission'] ?? false;
          
          if (!hasPerm) {
            debugPrint("[SYS005] USB Permission missing. Requesting permission for $name...");
            final bool? granted = await channel.invokeMethod<bool>('requestUsbPermission', {
              'vendorId': vid,
              'productId': pid,
            });
            hasPerm = granted ?? false;
          }

          if (!hasPerm) {
            debugPrint("[SYS005] Cannot test UART: Permission denied.");
            return false;
          }

          debugPrint("[SYS005] Running write/read UART test...");
          final Map<dynamic, dynamic>? testResult = await channel.invokeMethod<Map<dynamic, dynamic>>('testUartCommunicate', {
            'vendorId': vid,
            'productId': pid,
            'baudRate': SpeechService.uartBaudRate,
            'testMessage': "HELLO\r\n",
          });
          
          if (testResult != null) {
            final bool success = testResult['success'] ?? false;
            final String msg = testResult['message'] ?? "";
            debugPrint("[SYS005] UART test success: $success ($msg)");
            if (success) {
              SpeechService.uartVid = vid;
              SpeechService.uartPid = pid;
              debugPrint("[SYS005] Cached UART device for SpeechService: VID=0x${vid.toRadixString(16).toUpperCase()}, PID=0x${pid.toRadixString(16).toUpperCase()}");
            }
            return success;
          }
          return false;
        } else {
          debugPrint("[SYS005] No USB Serial devices detected on the Android box.");
          return false;
        }
      } else {
        debugPrint("[SYS005] Non-Android platform. Mocking SYS005 check as true.");
        return true;
      }
    } catch (e) {
      debugPrint("[SYS005] Error in UART communication check: $e");
      return false;
    }
  }

  Future<bool> _checkTtsAsync({Function(RuleCheckResult)? onProgress}) async {
    if (_speechService.flagLocalTTS) {
      if (Platform.isAndroid) {
        try {
          final tts = FlutterTts();
          final List<dynamic>? engines = await tts.getEngines;
          if (engines == null || engines.isEmpty) {
            debugPrint("[SYS008] No TTS engines found on Android.");
            return false;
          }
          debugPrint("[SYS008] Found TTS engines: $engines");
          return true;
        } catch (e) {
          debugPrint("[SYS008] Error checking TTS engines: $e");
          return false;
        }
      }
      return true; // Native TTS is always built-in on non-Android platforms
    } else {
      try {
        final keyFile = File(join(_dataDir, "openAI_key.json"));
        if (!keyFile.existsSync()) return false;
        final jsonStr = await keyFile.readAsString();
        final doc = jsonDecode(jsonStr);
        if (doc is Map && doc.containsKey('OpenAI')) {
          final apiKey = doc['OpenAI']['ApiKey']?.toString();
          return apiKey != null && apiKey.isNotEmpty;
        }
        return false;
      } catch (_) {
        return false;
      }
    }
  }
}
