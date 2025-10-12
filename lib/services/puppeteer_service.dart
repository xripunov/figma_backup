import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:puppeteer/puppeteer.dart';
import '../models/backup_item.dart';

class PuppeteerService {
  final Function(BackupItem item)? onFileStart;
  final Function(BackupItem item)? onFileSuccess;
  final Function(BackupItem item, String error)? onFileFailure;
  final Function(String message)? onAction;
  final Function(BackupItem item)? onFileSkipped;

  final ValueNotifier<bool> _cancellationToken = ValueNotifier(false);
  Browser? _browser;

  void cancelBackup() => _cancellationToken.value = true;
  void resetCancellation() => _cancellationToken.value = false;
  bool get isCancelled => _cancellationToken.value;

  late final String _profilePath;

  final String _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  PuppeteerService({
    this.onFileStart,
    this.onFileSuccess,
    this.onFileFailure,
    this.onAction,
    this.onFileSkipped,
  });

  Future<void> forceCloseBrowser() async {
    _log('Получена команда принудительного закрытия браузера...');
    cancelBackup();
    try {
      await _browser?.close();
      _log('Браузер успешно закрыт.');
    } catch (e) {
      _log('Ошибка при принудительном закрытии браузера: $e');
    } finally {
      _browser = null;
    }
  }

  void _log(String message) {
    debugPrint('[PuppeteerService] $message');
    LoggingService().log('[PuppeteerService] $message');
    onAction?.call(message);
  }

  List<String> get _chromeArgs => [
        '--no-sandbox',
        '--disable-setuid-sandbox',
      ];

  Future<void> _initProfilePath() async {
    final appSupportDir = await getApplicationSupportDirectory();
    _profilePath = path.join(appSupportDir.path, 'figma_profile');
    _log('Профиль браузера: $_profilePath');

    final lockFiles = ['SingletonLock', 'SingletonCookie', 'SingletonSocket'];
    for (final lockFileName in lockFiles) {
      final lockFile = File(path.join(_profilePath, lockFileName));
      if (await lockFile.exists()) {
        _log('Найден старый lock-файл: $lockFileName. Удаляем...');
        try {
          await lockFile.delete();
        } catch (e) {
          _log('Не удалось удалить "$lockFileName": $e');
        }
      }
    }
  }

  String _getChromiumPath() {
    var executablePath = path.dirname(path.fromUri(Platform.resolvedExecutable));
    return path.join(executablePath, '..', 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets', 'chromium', 'Chromium.app', 'Contents', 'MacOS', 'Chromium');
  }

  /// Этап 1: Быстрая невидимая проверка, активна ли сессия Figma.
  Future<bool> _checkLoginStatus() async {
    _log('Проверяем сессию Figma в фоновом режиме...');
    Browser? checkBrowser;
    try {
      checkBrowser = await puppeteer.launch(
          executablePath: _getChromiumPath(),
          userDataDir: _profilePath,
          args: _chromeArgs,
          headless: true,
          timeout: const Duration(minutes: 1));
      final page = await checkBrowser.newPage();
      await page.goto('https://www.figma.com/files', wait: Until.domContentLoaded, timeout: const Duration(minutes: 1));
      
      final isLoggedIn = page.url?.contains('files') ?? false;
      _log(isLoggedIn ? 'Сессия активна.' : 'Сессия неактивна.');
      return isLoggedIn;
    } catch (e) {
      _log('Ошибка при проверке сессии: $e. Потребуется ручной вход.');
      return false;
    } finally {
      await checkBrowser?.close();
    }
  }

  /// Этап 2: Если нужно, запускает видимый браузер и ждет, пока пользователь войдет.
  Future<bool> _handleManualLogin() async {
    _log('Открываем браузер для входа...');
    Browser? loginBrowser;
    try {
      loginBrowser = await puppeteer.launch(
          executablePath: _getChromiumPath(),
          userDataDir: _profilePath,
          args: _chromeArgs,
          headless: false,
          defaultViewport: null);
      final page = await loginBrowser.newPage();
      await page.goto('https://www.figma.com', wait: Until.domContentLoaded);
      
      _log('Требуется ручной вход. Пожалуйста, войдите в аккаунт в открывшемся окне. Приложение продолжит автоматически.');
      
      // --- ИЗМЕНЕНИЕ: Вместо ожидания навигации, которая может не случиться,
      // мы периодически проверяем URL в цикле. Это гораздо надежнее.
      const timeout = Duration(minutes: 5);
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < timeout) {
        if (page.url?.contains('files') ?? false) {
          _log('Вход выполнен успешно.');
          return true;
        }
        // Ждем 2 секунды перед следующей проверкой
        await Future.delayed(const Duration(seconds: 2));
      }
      
      _log('Вход не был выполнен или истекло время ожидания.');
      return false;

    } catch (e) {
      _log('Не удалось дождаться входа: $e');
      return false;
    } finally {
      await loginBrowser?.close();
      _log('Окно входа закрыто. Запускаем бэкап...');
    }
  }

  /// Основной метод, который управляет всем процессом.
  Future<void> runBackup({
    required List<BackupItem> items,
    required String savePath,
  }) async {
    await _initProfilePath();
    resetCancellation();

    try {
      bool isLoggedIn = await _checkLoginStatus();
      if (!isLoggedIn) {
        isLoggedIn = await _handleManualLogin();
      }

      if (!isLoggedIn) {
        throw Exception('Авторизация в Figma не пройдена. Пожалуйста, попробуйте снова.');
      }

      // --- Этап 3: Основной цикл бэкапа в невидимом режиме ---
      _log('Запускаем бэкап в фоновом режиме...');
      _browser = await puppeteer.launch(
        executablePath: _getChromiumPath(),
        userDataDir: _profilePath,
        args: _chromeArgs,
        headless: true,
        defaultViewport: null,
        timeout: const Duration(minutes: 2),
      );
      final page = await _browser!.newPage();
      await page.setUserAgent(_userAgent);
      
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) throw Exception('Не удалось найти папку "Загрузки"');

      final manifestPath = path.join(savePath, 'backup_manifest.json');
      final manifestFile = File(manifestPath);
      Map<String, dynamic> manifest = {};
      if (await manifestFile.exists()) {
        try {
          manifest = json.decode(await manifestFile.readAsString());
        } catch (e) { _log('Ошибка чтения манифеста.'); }
      }

      for (final item in items) {
        if (isCancelled) break;
        
        onFileStart?.call(item);

        if (item.lastModified == manifest[item.key]) {
          _log('Пропускаем "${item.mainFileName}" (без изменений)');
          onFileSkipped?.call(item);
          continue;
        }

        try {
          final fileUrl = 'https://www.figma.com/file/${item.key}/';
          _log('Переходим к файлу: $fileUrl');
          await page.goto(fileUrl, wait: Until.domContentLoaded, timeout: const Duration(minutes: 3));
          _log('Страница загружена. Ожидаем 5 секунд для полной инициализации интерфейса...');
          await Future.delayed(const Duration(seconds: 5));

          if (isCancelled) break;

          final downloadedFile = await _saveLocalCopyWithRetry(page, downloadsDir, item);
          if (isCancelled) break;

          final sanitizedProjectName = _sanitizeName(item.projectName);
          final sanitizedFileName = _sanitizeName(item.mainFileName);
          final projectFolderPath = path.join(savePath, sanitizedProjectName);
          await Directory(projectFolderPath).create(recursive: true);
          final targetPath = path.join(projectFolderPath, '$sanitizedFileName.fig');
          
          _log('Перемещаем файл в: $targetPath');
          await downloadedFile.rename(targetPath);

          manifest[item.key] = item.lastModified;
          await manifestFile.writeAsString(json.encode(manifest));
          onFileSuccess?.call(item);

        } catch (e, s) {
          final errorMessage = 'Ошибка: $e\n$s';
          _log(errorMessage);
          onFileFailure?.call(item, errorMessage);
        }
      }
    } catch (e) {
      _log('Критическая ошибка: $e');
      for (final task in items) {
        onFileFailure?.call(task, 'Критическая ошибка: $e');
      }
    } finally {
      await forceCloseBrowser();
    }
  }

  String _sanitizeName(String name) => name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();

  Future<File> _saveLocalCopyWithRetry(Page page, Directory downloadsDir, BackupItem item) async {
    const maxRetries = 3;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (isCancelled) throw Exception('Отменено пользователем');
      _log('Запуск скачивания "${item.mainFileName}" (попытка $attempt/$maxRetries)...');
      
      try {
        final filesBeforeDownload = downloadsDir.listSync().map((f) => f.path).toSet();

        final commandKey = Platform.isMacOS ? Key.meta : Key.control;
        await page.keyboard.down(commandKey);
        await page.keyboard.press(Key.keyP);
        await page.keyboard.up(commandKey);
        await Future.delayed(const Duration(seconds: 2));
        await page.keyboard.type('local copy', delay: const Duration(milliseconds: 100));
        await Future.delayed(const Duration(seconds: 1));
        await page.keyboard.press(Key.enter);

        _log('Ожидаем скачивание файла...');
        final downloadedFile = await _waitForNewFile(downloadsDir, filesBeforeDownload, item);
        return downloadedFile;

      } catch (e) {
        _log('Ошибка при скачивании (попытка $attempt): $e');
        if (attempt == maxRetries) {
          rethrow; // Если это была последняя попытка, пробрасываем ошибку дальше
        }
        _log('Пауза 5 секунд перед повторной попыткой...');
        await Future.delayed(const Duration(seconds: 5)); 
      }
    }
    throw Exception('Не удалось скачать файл "${item.mainFileName}" после $maxRetries попыток.');
  }

  Future<File> _waitForNewFile(Directory dir, Set<String> filesBefore, BackupItem item) async {
    const timeout = Duration(minutes: 2);
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      if (isCancelled) throw Exception("Отменено пользователем");

      var entities = dir.listSync();
      for (final entity in entities) {
        final isNewFigFile = entity is File &&
            entity.path.endsWith('.fig') &&
            !filesBefore.contains(entity.path);

        if (isNewFigFile) {
          final fileName = path.basename(entity.path);
          // Проверяем, что имя скачанного файла начинается с имени нашего файла,
          // чтобы избежать путаницы. Это надежнее, чем contains().
          if (fileName.startsWith(_sanitizeName(item.mainFileName))) {
            _log('Найден корректный файл .fig: $fileName');
            await Future.delayed(const Duration(seconds: 2));
            return entity;
          }
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('Тайм-аут ожидания скачивания файла "${item.mainFileName}".');
  }
}
