import 'dart:math';
import '../models/operator.dart';
import 'data_service.dart';

abstract class IAuthService {
  Future<Operator?> authenticateAsync(String idNumberOrQr);
  Operator? get currentOperator;
  String get globalWorkingHourStart;
  set globalWorkingHourStart(String value);
  String get globalWorkingHourEnd;
  set globalWorkingHourEnd(String value);
  bool isInsideWorkingHours();
  void logout();
}

class AuthService implements IAuthService {
  final IDataService _dataService;
  Operator? _currentOperator;

  String _globalWorkingHourStart = "8";
  String _globalWorkingHourEnd = "17";

  AuthService(this._dataService);

  @override
  Operator? get currentOperator => _currentOperator;

  @override
  String get globalWorkingHourStart => _globalWorkingHourStart;

  @override
  set globalWorkingHourStart(String value) => _globalWorkingHourStart = value;

  @override
  String get globalWorkingHourEnd => _globalWorkingHourEnd;

  @override
  set globalWorkingHourEnd(String value) => _globalWorkingHourEnd = value;

  @override
  Future<Operator?> authenticateAsync(String idNumberOrQr) async {
    final operators = await _dataService.getAuthorizedOperatorsAsync();
    final cleanInput = _cleanString(idNumberOrQr).toUpperCase();

    Operator? matched;
    for (var op in operators) {
      if (!op.isActive) continue;

      final cleanDbId = _cleanString(op.idNumber).toUpperCase();
      final cleanDbName = _cleanString(op.name).toUpperCase();

      if (cleanDbId == cleanInput ||
          cleanInput.contains(cleanDbId) ||
          (cleanDbName.isNotEmpty && cleanInput.contains(cleanDbName)) ||
          (cleanDbId.isNotEmpty && _isFuzzyMatch(cleanDbId, cleanInput))) {
        matched = op;
        break;
      }
    }

    _currentOperator = matched;
    return matched;
  }

  @override
  void logout() {
    _currentOperator = null;
  }

  @override
  bool isInsideWorkingHours() {
    try {
      String startStr = _dataService.workingHourStart.isNotEmpty
          ? _dataService.workingHourStart
          : _globalWorkingHourStart;
      String endStr = _dataService.workingHourEnd.isNotEmpty
          ? _dataService.workingHourEnd
          : _globalWorkingHourEnd;

      final now = DateTime.now();
      final nowTime = double.parse(now.hour.toString()) + (double.parse(now.minute.toString()) / 60.0);

      double startHour = _parseHourStringToDouble(startStr);
      double endHour = _parseHourStringToDouble(endStr);

      if (startHour <= endHour) {
        return nowTime >= startHour && nowTime <= endHour;
      } else {
        // Crosses midnight
        return nowTime >= startHour || nowTime <= endHour;
      }
    } catch (_) {
      return true; // Fallback to allowed in case of error
    }
  }

  double _parseHourStringToDouble(String hourStr) {
    if (hourStr.contains(':')) {
      final parts = hourStr.split(':');
      final hour = double.tryParse(parts[0]) ?? 0.0;
      final minute = double.tryParse(parts[1]) ?? 0.0;
      return hour + (minute / 60.0);
    } else {
      return double.tryParse(hourStr) ?? 0.0;
    }
  }

  String _cleanString(String input) {
    if (input.isEmpty) return '';
    String normalized = _removeDiacritics(input);
    // Remove everything except letters and numbers
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  String _removeDiacritics(String text) {
    const vietnamese = 'aáàảãạâấầẩẫậăắằẳẵặeéèẻẽẹêếềểễệiíìỉĩịoóòỏõọôốồổỗộơớờởỡợuúùủũụưứừửữựyýỳỷỹỵdđ';
    const ascii =      'aaaaaaaaaaaaaaaaaeeeeeeeeeeeeiiiiiiioooooooooooooooooeeeeeeeeeuuuuuuuuuuuuyyyyyydd';

    String result = text.toLowerCase();
    for (int i = 0; i < vietnamese.length; i++) {
      result = result.replaceAll(vietnamese[i], ascii[i]);
    }
    // Handle uppercase version just in case
    final vietnameseUpper = vietnamese.toUpperCase();
    final asciiUpper = ascii.toUpperCase();
    for (int i = 0; i < vietnameseUpper.length; i++) {
      result = result.replaceAll(vietnameseUpper[i], asciiUpper[i]);
    }
    return result;
  }

  bool _isFuzzyMatch(String authorizedId, String scannedInput) {
    if (authorizedId.length < 8) return false;

    // Check if any part of the scanned input is close to the ID
    for (int i = 0; i <= scannedInput.length - authorizedId.length; i++) {
      final fragment = scannedInput.substring(i, i + authorizedId.length);
      if (_levenshteinDistance(authorizedId, fragment) <= 1) return true;
    }
    return false;
  }

  int _levenshteinDistance(String s, String t) {
    int n = s.length;
    int m = t.length;
    if (n == 0) return m;
    if (m == 0) return n;

    List<List<int>> d = List.generate(n + 1, (_) => List.filled(m + 1, 0));

    for (int i = 0; i <= n; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= m; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        int cost = (t[j - 1] == s[i - 1]) ? 0 : 1;
        d[i][j] = min(
          min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + cost,
        );
      }
    }
    return d[n][m];
  }
}
