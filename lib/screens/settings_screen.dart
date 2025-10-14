import 'package:file_picker/file_picker.dart';
import 'package:figma_bckp/services/puppeteer_service.dart';
import 'package:provider/provider.dart';
import '../services/logging_service.dart';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:figma_bckp/services/bookmark_service.dart';
import '../services/settings_service.dart';

// TODO: Предполагается, что есть BackupProvider для отслеживания состояния
// import '../providers/backup_provider.dart'; 

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tokenController = TextEditingController();
  final _settingsService = SettingsService();
  bool _isLoading = true;
  String? _savePath;
  bool _isDirty = false; // Flag to track if settings have changed

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final token = await _settingsService.getToken();
    final savePath = await _settingsService.getSavePath();
    setState(() {
      _tokenController.text = token ?? '';
      _savePath = savePath;
      _isLoading = false;
    });
  }

  Future<void> _pickSavePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку для сохранения бэкапов',
    );

    if (result != null && result != _savePath) {
      final bookmark = await BookmarkService().createBookmark(result);
      await _settingsService.setSavePath(result, bookmark);
      setState(() {
        _savePath = result;
        _isDirty = true;
      });
    }
  }

  Future<void> _showTokenDialog() async {
    final tokenInputController = TextEditingController(text: _tokenController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Figma API Token'),
        content: TextField(
          controller: tokenInputController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Personal Access Token',
            helperText: 'Токен хранится локально и безопасно',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, tokenInputController.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null && result != _tokenController.text) {
      await _settingsService.saveToken(result);
      setState(() {
        _tokenController.text = result;
        _isDirty = true;
      });
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Заменить на реальный провайдер состояния
    // final isBackupInProgress = context.watch<BackupProvider>().isBackupInProgress;
    const isBackupInProgress = false;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _isDirty);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _isDirty),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  _buildSectionHeader('Хранилище'),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Путь для сохранения'),
                    subtitle: Text(_savePath ?? 'Не выбрано'),
                    onTap: _pickSavePath,
                    enabled: !isBackupInProgress,
                  ),
                  _buildSectionHeader('Данные'),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Figma API Token'),
                    subtitle: Text(_tokenController.text.isEmpty ? 'Не задан' : '••••••••••••••••••••'),
                    onTap: _showTokenDialog,
                    enabled: !isBackupInProgress,
                  ),
                  _buildSectionHeader('Аккаунт'),
                  ListTile(
                    leading: Icon(Icons.logout, color: isBackupInProgress ? Colors.grey : Theme.of(context).colorScheme.error),
                    title: Text(
                      'Выйти из аккаунта Figma',
                      style: TextStyle(color: isBackupInProgress ? Colors.grey : Theme.of(context).colorScheme.error),
                    ),
                    enabled: !isBackupInProgress,
                    onTap: _handleLogout,
                  ),
                  _buildSectionHeader('Отладка'),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Открыть файл логов'),
                    onTap: () async {
                      final logPath = await LoggingService().getLogFilePath();
                      OpenFile.open(logPath);
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта Figma?'),
        content: const Text(
          'Это действие удалит сохраненную сессию. При следующем запуске резервного копирования вам потребуется снова войти в свой аккаунт Figma.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final puppeteerService = context.read<PuppeteerService>();
      final success = await puppeteerService.logout();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Вы успешно вышли из аккаунта' : 'Не удалось удалить сессию'),
            backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}