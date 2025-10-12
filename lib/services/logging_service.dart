import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  late final File _logFile;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    final appSupportDir = await getApplicationSupportDirectory();
    final logPath = path.join(appSupportDir.path, 'logs');
    await Directory(logPath).create(recursive: true);
    _logFile = File(path.join(logPath, 'app_log.txt'));
    _isInitialized = true;
  }

  void log(String message) {
    if (!_isInitialized) return;
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '$timestamp - $message\n';
    _logFile.writeAsStringSync(logMessage, mode: FileMode.append);
  }

  Future<String> getLogFilePath() async {
    if (!_isInitialized) await init();
    return _logFile.path;
  }
}
