import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/operator.dart';
import '../services/auth_service.dart';
import '../services/camera_service.dart';
import '../services/data_service.dart';
import '../services/llm_service.dart';
import '../services/ocr_service.dart';
import '../services/qr_service.dart';
import '../services/rule_engine_service.dart';
import '../services/speech_service.dart';

class VerifiedOperatorDisplayItem {
  final String idNumber;
  final String displayName;
  final String dailyCountText;
  bool isAlreadyVerified;

  VerifiedOperatorDisplayItem({
    required this.idNumber,
    required this.displayName,
    required this.dailyCountText,
    this.isAlreadyVerified = false,
  });
}

class AuthViewModel extends ChangeNotifier {
  final ICameraService _cameraService;
  final IOCRService _ocrService;
  final IQRService _qrService;
  final IAuthService _authService;
  final IRuleEngineService _ruleEngineService;
  final IDataService _dataService;
  final ILLMService _llmService;
  final ISpeechService _speechService;

  bool _isVerified = false;
  String _verificationInfoText = "";
  String _ruleStatusText = "";
  bool _isRangePopupVisible = false;
  
  double _caseOperatorMin = 0.0;
  double _caseOperatorMax = 2000000.0;
  double _caseOperatorExact = 2000000.0;
  double _maxTransactionAmount = 2000000.0;

  final List<VerifiedOperatorDisplayItem> _verifiedOperatorsDisplay = [];
  final List<Operator> _verifiedOperators = [];
  int _requiredCount = 1;
  bool _isProcessing = false;

  AuthViewModel(
    this._cameraService,
    this._ocrService,
    this._qrService,
    this._authService,
    this._ruleEngineService,
    this._dataService,
    this._llmService,
    this._speechService,
  ) {
    initializeAsync();
  }

  bool get isVerified => _isVerified;
  String get verificationInfoText => _verificationInfoText;
  String get ruleStatusText => _ruleStatusText;
  bool get isRangePopupVisible => _isRangePopupVisible;
  
  double get caseOperatorMin => _caseOperatorMin;
  set caseOperatorMin(double val) {
    _caseOperatorMin = val;
    if (_caseOperatorMin > _caseOperatorMax) {
      _caseOperatorMax = _caseOperatorMin;
    }
    notifyListeners();
  }

  double get caseOperatorMax => _caseOperatorMax;
  set caseOperatorMax(double val) {
    _caseOperatorMax = val;
    if (_caseOperatorMax < _caseOperatorMin) {
      _caseOperatorMin = _caseOperatorMax;
    }
    notifyListeners();
  }

  double get caseOperatorExact => _caseOperatorExact;
  set caseOperatorExact(double val) {
    _caseOperatorExact = val;
    notifyListeners();
  }

  bool get flagOperatorExact => _llmService.flagOperatorExact;

  bool get useFrontCamera {
    return !_cameraService.hasBackCamera;
  }

  double get maxTransactionAmount => _maxTransactionAmount;
  List<VerifiedOperatorDisplayItem> get verifiedOperatorsDisplay => _verifiedOperatorsDisplay;
  List<Operator> get verifiedOperators => _verifiedOperators;
  int get requiredCount => _requiredCount;
  bool get isProcessing => _isProcessing;

  Future<void> initializeAsync() async {
    final bool isInside = _authService.isInsideWorkingHours();
    _requiredCount = await _ruleEngineService.getRequiredOperatorCountAsync(isInside);
    final String statusLabel = isInside ? "Trong giờ hành chính" : "Ngoài giờ hành chính";
    _verificationInfoText = "$statusLabel - Số người bảo chứng cần xác thực: $_requiredCount";
    notifyListeners();

    await _loadMaxTransactionLimitAsync();

    // Setup camera background tasks
    try {
      await _cameraService.initializeAsync();
      await _speechService.speakAsync("Xin chào. Vui lòng xác nhận người bảo chứng");
    } catch (_) {
      await _speechService.speakAsync("Camera bị lỗi");
    }
    notifyListeners();
  }

  Future<void> _loadMaxTransactionLimitAsync() async {
    _maxTransactionAmount = await _ruleEngineService.getMaxTransactionLimitAsync();
    _caseOperatorMax = _maxTransactionAmount;
    _caseOperatorMin = 0.0;
    _caseOperatorExact = _maxTransactionAmount;
    notifyListeners();
  }

  Future<void> handleManualInput(String rawInput) async {
    if (_isProcessing || _isVerified) return;
    _isProcessing = true;
    _ruleStatusText = "Đang kiểm tra...";
    notifyListeners();

    try {
      await _verifyAndNavigateAsync(rawInput);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> handleQrScanned(String rawQr) async {
    debugPrint("[AuthViewModel] QR Scanned callback triggered. Raw QR payload: '$rawQr'");
    if (_isProcessing || _isVerified) return;
    _isProcessing = true;
    _ruleStatusText = "Đang đọc mã QR...";
    notifyListeners();
 
    try {
      final cleanQr = _qrService.decodeQrCode(rawQr);
      debugPrint("[AuthViewModel] QR Decoded result: '$cleanQr'");
      if (cleanQr != null && cleanQr.isNotEmpty) {
        await _verifyAndNavigateAsync(cleanQr);
      } else {
        debugPrint("[AuthViewModel] Warning: QR decoded result is null or empty");
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
 
  Future<void> handleOcrScanned(String imagePath) async {
    debugPrint("[AuthViewModel] OCR Image trigger. Image path: '$imagePath'");
    if (_isProcessing || _isVerified) return;
    _isProcessing = true;
    _ruleStatusText = "Đang nhận dạng văn bản...";
    notifyListeners();
 
    try {
      final ocrText = await _ocrService.extractTextAsync(imagePath);
      debugPrint("[AuthViewModel] OCR Extracted raw text length: ${ocrText.length} characters");
      debugPrint("[AuthViewModel] OCR Extracted content:\n$ocrText");
      if (ocrText.isNotEmpty && ocrText.length > 5) {
        await _verifyAndNavigateAsync(ocrText);
      } else {
        debugPrint("[AuthViewModel] Warning: OCR extracted text too short (< 5 chars) or empty. Skipping verification.");
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> handleOcrImageFrame(dynamic inputImage) async {
    if (_isProcessing || _isVerified) return;
    _isProcessing = true;
    notifyListeners();

    try {
      final ocrText = await _ocrService.extractFromInputImage(inputImage);
      if (ocrText.isNotEmpty && ocrText.length > 5) {
        debugPrint("[AuthViewModel] Live Stream OCR Extracted raw text length: ${ocrText.length} characters");
        debugPrint("[AuthViewModel] Live Stream OCR Extracted content:\n$ocrText");
        
        // Scan the extracted text for any potential operator matching info (like name or ID number)
        await _verifyAndNavigateAsync(ocrText);
      }
    } catch (e) {
      debugPrint("[AuthViewModel] Error in Live Stream OCR: $e");
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _verifyAndNavigateAsync(String rawData) async {
    if (_isVerified) return;

    final op = await _authService.authenticateAsync(rawData);
    if (op != null) {
      _ruleStatusText = "";

      // Check if already in display list
      final isDuplicate = _verifiedOperatorsDisplay.any((d) => d.idNumber == op.idNumber);
      if (isDuplicate) {
        await _speechService.speakAsync("${op.name} đã xác thực rồi");
        return;
      }

      // Record count
      final int dailyCount = await _dataService.getOperatorVerificationCountAsync(op.id, DateTime.now());

      _verifiedOperators.add(op);
      _verifiedOperatorsDisplay.add(VerifiedOperatorDisplayItem(
        idNumber: op.idNumber,
        displayName: op.name,
        dailyCountText: "(Lần $dailyCount/ngày)",
      ));

      await _speechService.speakAsync("Đã xác nhận ${op.name}");
      notifyListeners();

      if (_verifiedOperators.length >= _requiredCount) {
        // Staff Rule evaluation
        _ruleStatusText = "Đang chạy kiểm tra quy chuẩn nhân viên...";
        notifyListeners();

        final ruleResults = await _ruleEngineService.evaluateStaffVerificationAsync(_verifiedOperators);
        
        for (var ruleResult in ruleResults) {
          if (ruleResult.isValid) {
            _ruleStatusText = "Kiểm tra ${ruleResult.id}: Thành công";
            notifyListeners();
          } else {
            _ruleStatusText = ruleResult.message;
            notifyListeners();
            await _speechService.speakAsync(ruleResult.message);

            // Failure Reset
            _verifiedOperators.clear();
            _verifiedOperatorsDisplay.clear();
            notifyListeners();
            return;
          }
          await Future.delayed(const Duration(milliseconds: 400));
        }

        _ruleStatusText = "Xác nhận thành công. Đang thiết lập hạn mức...";
        notifyListeners();

        await Future.delayed(const Duration(milliseconds: 800));
        _isRangePopupVisible = true;
        notifyListeners();
      }
    } else {
      _ruleStatusText = "Mã xác thực không hợp lệ.";
      notifyListeners();
    }
  }

  Future<void> confirmRangeAsync(VoidCallback onCompletion) async {
    try {
      if (_caseOperatorMin > _caseOperatorMax) {
        final temp = _caseOperatorMin;
        _caseOperatorMin = _caseOperatorMax;
        _caseOperatorMax = temp;
      }

      // Record operator verifications in DB
      for (var op in _verifiedOperators) {
        try {
          await _dataService.recordOperatorVerificationAsync(op.id);
        } catch (dbEx) {
          debugPrint("[AuthViewModel] DB Error recording verification: $dbEx");
        }
      }

      _llmService.caseOperatorMin = _caseOperatorMin;
      _llmService.caseOperatorMax = _caseOperatorMax;
      _llmService.caseOperatorExact = _caseOperatorExact;

      _isVerified = true;
      _isRangePopupVisible = false;
      notifyListeners();

      try {
        await _cameraService.stopAsync();
      } catch (camEx) {
        debugPrint("[AuthViewModel] Camera stop error: $camEx");
      }
    } catch (ex) {
      debugPrint("[AuthViewModel] confirmRangeAsync general error: $ex");
    }

    // Trigger state coordinator navigation
    onCompletion();
  }

  void resetVerification() {
    _verifiedOperators.clear();
    _verifiedOperatorsDisplay.clear();
    _isVerified = false;
    _isRangePopupVisible = false;
    _ruleStatusText = "";
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.stopAsync();
    super.dispose();
  }
}
