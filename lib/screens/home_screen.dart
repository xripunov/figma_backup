import 'package:file_picker/file_picker.dart';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:figma_bckp/screens/backup_screen.dart';
import 'package:figma_bckp/screens/settings_screen.dart';
import 'package:figma_bckp/services/figma_api_service.dart';
import 'package:figma_bckp/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FigmaApiService _figmaApiService;
  late final SettingsService _settingsService;
  final _urlController = TextEditingController();

  List<String> _fileKeys = [];
  final Map<String, FigmaFile?> _fileDetails = {};
  bool _isInitialLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _figmaApiService = Provider.of<FigmaApiService>(context, listen: false);
    _settingsService = Provider.of<SettingsService>(context, listen: false);
    _loadInitialKeysAndFetchDetails();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialKeysAndFetchDetails() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
    });

    _fileKeys = await _settingsService.getFileKeys();
    
    for (var key in _fileKeys) {
      _fileDetails[key] = FigmaFile(key: key, name: '##LOADING##', lastModified: '', projectName: '');
    }

    setState(() {
      _isInitialLoading = false;
    });

    _fetchDetailsForAllFiles();
  }

  Future<void> _fetchDetailsForAllFiles() async {
    final token = await _settingsService.getToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = '''API токен не найден. Пожалуйста, добавьте его в настройках.

Как получить API токен:
1. Откройте Figma и перейдите в «Help and account» -> «Account settings».
2. В разделе «Personal access tokens» создайте новый токен.
3. ВАЖНО: в выпадающем списке «Scopes» выберите «File Content» с разрешением «Read-only».
4. Скопируйте токен и вставьте его в настройках этого приложения.''';
      });
      return;
    }

    // --- ИСПРАВЛЕНИЕ: Создаем копию списка ключей ---
    final keysToFetch = List<String>.from(_fileKeys);
    for (final key in keysToFetch) {
      // Проверяем, не был ли ключ удален, пока мы загружали другие
      if (!_fileKeys.contains(key)) continue;

      try {
        final details = await _figmaApiService.getFullFileInfo(key, token);
        _fileDetails[key] = details;
      } catch (e) {
        debugPrint("Failed to fetch details for $key: $e");
        _fileDetails[key] = null;
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _addFileFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final key = _figmaApiService.extractFileKey(url);
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверная ссылка на файл Figma.')));
      return;
    }

    if (!_fileKeys.contains(key)) {
      _fileKeys.add(key);
      await _settingsService.setFileKeys(_fileKeys);
      _urlController.clear();
      setState(() {
        _fileDetails[key] = FigmaFile(key: key, name: '##LOADING##', lastModified: '', projectName: '');
      });
      _fetchDetailsForAllFiles();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Этот файл уже в списке.')));
    }
  }

  Future<void> _removeFile(String key) async {
    _fileKeys.remove(key);
    _fileDetails.remove(key);
    await _settingsService.setFileKeys(_fileKeys);
    setState(() {});
  }

  Future<void> _startBackup() async {
    final List<FigmaFile> selectedFiles = _fileDetails.values.where((f) => f != null && f.name != '##LOADING##').cast<FigmaFile>().toList();

    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет успешно загруженных файлов для бэкапа.')));
      return;
    }

    String? savePath = await _settingsService.getSavePath();
    if (savePath == null) {
      final result = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Выберите папку для сохранения бэкапов');
      if (result != null) {
        savePath = result;
        await _settingsService.setSavePath(savePath);
      } else {
        return;
      }
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (context) => BackupScreen(
          selectedFiles: selectedFiles,
          savePath: savePath!,
        ),
      ));
    }
  }

  void _navigateToSettings() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
    if (result == true) {
      _loadInitialKeysAndFetchDetails();
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Figma Backup'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInitialKeysAndFetchDetails),
          IconButton(icon: const Icon(Icons.settings), onPressed: _navigateToSettings),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Вставьте ссылку на файл Figma',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addFileFromUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: _addFileFromUrl,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildFileList()),
        ],
      ),
      floatingActionButton: _fileKeys.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _startBackup,
              label: Text('Бэкап (${_fileDetails.values.where((f) => f != null && f.name != '##LOADING##').length})'),
              icon: const Icon(Icons.cloud_upload_outlined),
            )
          : null,
    );
  }

  Widget _buildFileList() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
    }
    if (_fileKeys.isEmpty) {
      return const Center(child: Text('Список пуст. Добавьте файлы по ссылке выше.', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _loadInitialKeysAndFetchDetails,
      child: ListView.builder(
        itemCount: _fileKeys.length,
        itemBuilder: (context, index) {
          final key = _fileKeys[index];
          final details = _fileDetails[key];

          if (details == null) {
            return Card(
              color: Colors.red.withOpacity(0.1),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.redAccent),
                title: const Text('Ошибка загрузки информации'),
                subtitle: Text('Ключ: $key'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _removeFile(key)),
              ),
            );
          }

          if (details.name == '##LOADING##') {
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                title: const Text('Получение информации...'),
                subtitle: Text('Ключ: $key'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _removeFile(key)),
              ),
            );
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.description_outlined, color: Colors.blueAccent),
              title: Text(details.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Проект: ${details.projectName}\nОбновлено: ${_formatDate(details.lastModified)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _removeFile(key),
              ),
            ),
          );
        },
      ),
    );
  }
}
