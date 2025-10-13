import 'package:file_picker/file_picker.dart';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';
import '../services/settings_service.dart';

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
      await _settingsService.setSavePath(result);
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
                  ),
                  _buildSectionHeader('Данные'),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Figma API Token'),
                    subtitle: Text(_tokenController.text.isEmpty ? 'Не задан' : '••••••••••••••••••••'),
                    onTap: _showTokenDialog,
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
}