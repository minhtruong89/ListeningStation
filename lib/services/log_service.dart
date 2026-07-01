import 'package:flutter/foundation.dart';

class LogService {
  static bool flagWriteLogDevice = true;
  static final List<String> logs = [];
  static final ValueNotifier<int> logUpdateNotifier = ValueNotifier(0);

  static void initialize() {
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LogService.log(message);
      }
    };
  }

  static void log(String message) {
    final timestamp = DateTime.now().toLocal().toString().split(' ').last.substring(0, 8);
    final formatted = "[$timestamp] $message";
    
    // Print to original OS standard output
    debugPrintSynchronously(formatted);

    if (flagWriteLogDevice) {
      logs.add(formatted);
      if (logs.length > 1000) {
        logs.removeAt(0); // Keep memory footprint small
      }
      logUpdateNotifier.value++;
    }
  }

  static void clear() {
    logs.clear();
    logUpdateNotifier.value++;
  }
}
