import 'package:flutter/foundation.dart';
import 'backup_item.dart';

enum TaskStatus {
  pending,
  running,
  success,
  failure,
  skipped, // <-- НОВЫЙ СТАТУС
}

// Базовый класс для всех задач бэкапа
class BackupTask extends ChangeNotifier {
  final String title;
  TaskStatus _status = TaskStatus.pending;
  String? _message;

  BackupTask(this.title);

  TaskStatus get status => _status;
  String? get message => _message;

  // Сеттеры для обновления UI через ChangeNotifier
  set status(TaskStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }

  set message(String? newMessage) {
    if (_message != newMessage) {
      _message = newMessage;
      notifyListeners();
    }
  }
}

// Конкретная задача для проверки авторизации
class LoginCheckTask extends BackupTask {
  LoginCheckTask() : super('Проверка авторизации');
}

// Конкретная задача для скачивания файла
class DownloadFileTask extends BackupTask {
  final BackupItem item;
  DownloadFileTask(this.item) : super('Скачивание: ${item.mainFileName}');
}
