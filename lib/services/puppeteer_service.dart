import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:puppeteer/puppeteer.dart';
import '../models/backup_item.dart';
import '../models/figma_url_info.dart';

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

  String? _profilePath;
  final _random = Random();

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

  List<String> get _stealthChromeArgs => [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-blink-features=AutomationControlled',
      ];

  Future<void> _initProfilePath() async {
    if (_profilePath != null) return; // Инициализируем только один раз
    final appSupportDir = await getApplicationSupportDirectory();
    _profilePath = path.join(appSupportDir.path, 'figma_profile');
    _log('Профиль браузера: $_profilePath');

    final lockFiles = ['SingletonLock', 'SingletonCookie', 'SingletonSocket'];
    for (final lockFileName in lockFiles) {
      final lockFile = File(path.join(_profilePath!, lockFileName));
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
    return path.join(executablePath, '..', 'Resources', 'chromium', 'Chromium.app', 'Contents', 'MacOS', 'Chromium');
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
        args: _stealthChromeArgs,
        headless: false,
        defaultViewport: null,
        ignoreDefaultArgs: ['--enable-automation'], // <--- Самое важное изменение
      );
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

        final manifestKey = item.branchId != null ? '${item.key}_${item.branchId}' : item.key;

        if (item.lastModified == manifest[manifestKey]) {
          _log('Пропускаем "${item.mainFileName}" (без изменений)');
          onFileSkipped?.call(item);
          continue;
        }

        try {
          final fileUrl = _buildFigmaUrl(item);

          _log('1. Перехожу к файлу: $fileUrl');
          try {
            await page.goto(fileUrl, wait: Until.domContentLoaded, timeout: const Duration(minutes: 5));
          } catch (e, s) {
            _log('!!! Ошибка навигации page.goto(): $e\n$s');
            rethrow;
          }
          _log('2. Страница загружена. URL: ${page.url}');
          
          _log('3. Имитирую поведение пользователя...');
          await page.evaluate('window.scrollBy(0, Math.random() * 400 - 200)');
          await _randomDelay(min: 5, max: 10);


          if (isCancelled) break;

          _log('4. Начинаю процесс скачивания...');
          final downloadedFile = await _saveLocalCopyWithRetry(page, downloadsDir, item);
          if (isCancelled) break;

          final isBranch = item.branchName != null && item.branchName!.isNotEmpty;
          final sanitizedProjectName = item.projectName.isEmpty
              ? 'Drafts'
              : _sanitizeName(item.projectName);

          String fileName;
          if (isBranch) {
            // Для веток: MainFileName [BranchName] [branch_id]
            final shortBranchId = item.branchId!.length >= 6 ? item.branchId!.substring(0, 6) : item.branchId!;
            fileName = '${item.mainFileName} [${item.branchName!}] [$shortBranchId]';
          } else {
            // Для всех основных файлов: FileName [file_key]
            final shortKey = item.key.length >= 6 ? item.key.substring(0, 6) : item.key;
            fileName = '${item.mainFileName} [$shortKey]';
          }
          
          final sanitizedFileName = _sanitizeName(fileName);

          final projectFolderPath = path.join(savePath, sanitizedProjectName);
          await Directory(projectFolderPath).create(recursive: true);
          
          final extension = _getExtensionForItem(item);
          final targetPath = path.join(projectFolderPath, '$sanitizedFileName$extension');
          
          _log('9. Перемещаю файл в: $targetPath');
          await downloadedFile.rename(targetPath);

          manifest[manifestKey] = item.lastModified;
          await manifestFile.writeAsString(json.encode(manifest));
          onFileSuccess?.call(item);

        } catch (e, s) {
          final errorMessage = 'Ошибка: $e\n$s';
          _log(errorMessage);
          onFileFailure?.call(item, errorMessage);
        }
        _log('Пауза перед следующим файлом...');
        await _randomDelay(min: 2, max: 5);
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

  String _getExtensionForItem(BackupItem item) {
    switch (item.fileType) {
      case FigmaFileType.figjam:
        return '.jam';
      case FigmaFileType.slides:
        return '.deck';
      case FigmaFileType.design:
      default:
        return '.fig';
    }
  }

  String _buildFigmaUrl(BackupItem item) {
    String basePath;
    if (item.fileType == FigmaFileType.figjam) {
      basePath = 'board';
    } else if (item.fileType == FigmaFileType.slides) {
      basePath = 'slides';
    } else {
      basePath = 'file'; // Using 'file' for broader compatibility
    }

    if (item.branchId != null) {
      // Branch URLs are always under the /file/ path
      return 'https://www.figma.com/file/${item.key}/branch/${item.branchId}/';
    } else {
      return 'https://www.figma.com/$basePath/${item.key}/';
    }
  }

  String _sanitizeName(String name) => name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();

  Future<void> _randomDelay({int min = 1, int max = 3}) async {
    final seconds = min + _random.nextInt(max - min + 1);
    _log('Случайная пауза: $seconds сек.');
    await Future.delayed(Duration(seconds: seconds));
  }

  Future<File> _saveLocalCopyWithRetry(Page page, Directory downloadsDir, BackupItem item) async {
    const maxRetries = 3;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      if (isCancelled) throw Exception('Отменено пользователем');
      _log('5. Запуск скачивания "${item.mainFileName}" (попытка $attempt/$maxRetries)...');
      
      try {
        final filesBeforeDownload = downloadsDir.listSync().map((f) => f.path).toSet();

        final commandKey = Platform.isMacOS ? Key.meta : Key.control;
        _log('5.1. Нажимаю $commandKey...');
        await page.keyboard.down(commandKey);
        await page.keyboard.press(Key.keyP);
        await page.keyboard.up(commandKey);
        await _randomDelay(min: 2, max: 4);
        
        _log('5.2. Ввожу "local copy"...');
        await page.keyboard.type('local copy', delay: Duration(milliseconds: 50 + _random.nextInt(100)));
        await _randomDelay(min: 1, max: 2);

        _log('5.3. Нажимаю Enter...');
        await page.keyboard.press(Key.enter);

        _log('6. Ожидаю скачивание файла...');
        final downloadedFile = await _waitForNewFile(downloadsDir, filesBeforeDownload, item);
        _log('8. Файл успешно обнаружен!');
        return downloadedFile;

      } catch (e) {
        _log('Ошибка при скачивании (попытка $attempt): $e');
        if (attempt == maxRetries) {
          rethrow; // Если это была последняя попытка, пробрасываем ошибку дальше
        }
        if (isCancelled) break; // Добавлена проверка
        _log('Перезагружаем страницу и ждем 5 секунд перед повторной попыткой...');
        await page.reload(wait: Until.networkIdle, timeout: const Duration(minutes: 5));
        await Future.delayed(const Duration(seconds: 5)); 
      }
    }
    throw Exception('Не удалось скачать файл "${item.mainFileName}" после $maxRetries попыток.');
  }

  Future<File> _waitForNewFile(Directory dir, Set<String> filesBefore, BackupItem item) async {
    const timeout = Duration(minutes: 10);
    final stopwatch = Stopwatch()..start();
    var logTimer = Stopwatch()..start();
    final expectedExtension = _getExtensionForItem(item);

    _log('7. Начал поиск нового $expectedExtension файла...');

    while (stopwatch.elapsed < timeout) {
      if (isCancelled) throw Exception("Отменено пользователем");

      var entities = dir.listSync();

      // Логируем текущие .fig файлы раз в 5 секунд, чтобы не спамить
      if (logTimer.elapsed.inSeconds >= 5) {
        final currentFigFiles = entities.where((e) => e.path.endsWith(expectedExtension)).map((e) => path.basename(e.path)).toList();
        _log('7.1. Проверка... Текущие $expectedExtension файлы в загрузках: $currentFigFiles');
        logTimer.reset();
      }

      for (final entity in entities) {
        final isNewFile = entity is File &&
            entity.path.endsWith(expectedExtension) &&
            !filesBefore.contains(entity.path);

        if (isNewFile) {
          final fileName = path.basename(entity.path);
          
          final isBranch = item.branchName != null && item.branchName!.isNotEmpty;
          final expectedName = isBranch ? item.branchName! : item.mainFileName;

          // Проверяем, что имя скачанного файла начинается с имени нашего файла,
          // чтобы избежать путаницы. Это надежнее, чем contains().
          if (fileName.startsWith(_sanitizeName(expectedName))) {
            _log('Найден корректный файл $expectedExtension: $fileName');
            await Future.delayed(const Duration(seconds: 2));
            return entity;
          }
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException('Тайм-аут ожидания скачивания файла "${item.mainFileName}".');
  }

  /// Удаляет папку с профилем браузера, чтобы "разлогинить" пользователя.
  Future<bool> logout() async {
    try {
      // Убедимся, что путь инициализирован
      await _initProfilePath();
      if (_profilePath == null) {
        _log('Путь к профилю не удалось определить.');
        return false;
      }
      final profileDir = Directory(_profilePath!);
      if (await profileDir.exists()) {
        _log('Удаляем профиль браузера...');
        await profileDir.delete(recursive: true);
        _log('Профиль успешно удален.');
        return true;
      }
      _log('Профиль не найден, удаление не требуется.');
      return true; // Считаем успехом, если и так чисто
    } catch (e) {
      _log('Ошибка при удалении профиля: $e');
      return false;
    }
  }
}
