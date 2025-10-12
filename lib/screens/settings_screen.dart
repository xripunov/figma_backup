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
  String? _savePath; // <-- Переменная для пути

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final token = await _settingsService.getToken();
    final savePath = await _settingsService.getSavePath(); // <-- Загружаем путь
    setState(() {
      _tokenController.text = token ?? '';
      _savePath = savePath; // <-- Сохраняем в состояние
      _isLoading = false;
    });
  }

  // <-- НОВЫЙ МЕТОД для выбора папки
  Future<void> _pickSavePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку для сохранения бэкапов',
    );

    if (result != null) {
      await _settingsService.setSavePath(result);
      setState(() {
        _savePath = result;
      });
    }
  }

  Future<void> _saveSettings() async {
    await _settingsService.saveToken(_tokenController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены!')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Путь для сохранения бэкапов',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // <-- ВИДЖЕТЫ для отображения и смены пути
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _savePath ?? 'Папка не выбрана',
                          style: TextStyle(
                            fontStyle: _savePath == null
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _pickSavePath,
                    child: const Text('Изменить папку'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  // --- Старые поля ---
                  const Text('Данные для API (чтение списка файлов)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                        labelText: 'Personal Access Token',
                        border: OutlineInputBorder()),
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    child: const Text('Сохранить и закрыть'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  const Text('Отладка',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Открыть файл логов'),
                    onPressed: () async {
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