import 'package:figma_bckp/models/backup_item.dart';
import 'package:figma_bckp/models/backup_task.dart';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:figma_bckp/services/puppeteer_service.dart';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:provider/provider.dart';

class BackupScreen extends StatefulWidget {
  final List<FigmaFile> selectedFiles;
  final String savePath;

  const BackupScreen({
    super.key,
    required this.selectedFiles,
    required this.savePath,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final List<BackupTask> _tasks = [];
  late final PuppeteerService _puppeteerService;

  bool _isBackupComplete = false;
  String _currentAction = 'Инициализация...';

  @override
  void initState() {
    super.initState();
    _initializeAndRunBackup();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initializeAndRunBackup() {
    final fileTasks = widget.selectedFiles.map((file) => DownloadFileTask(BackupItem(
      key: file.key,
      mainFileName: file.name,
      lastModified: file.lastModified,
      projectName: file.projectName,
    )));
    _tasks.addAll(fileTasks);

    _puppeteerService = PuppeteerService(
      onAction: (message) {
        if (mounted) setState(() => _currentAction = message);
      },
      onFileStart: (item) {
        final task = _findTaskForItem(item);
        task?.status = TaskStatus.running;
        task?.message = 'Скачивается...';
      },
      onFileSuccess: (item) {
        final task = _findTaskForItem(item);
        task?.status = TaskStatus.success;
        task?.message = 'Скачано';
      },
      onFileSkipped: (item) {
        final task = _findTaskForItem(item);
        task?.status = TaskStatus.skipped;
        task?.message = 'Без изменений';
      },
      onFileFailure: (item, error) {
        final task = _findTaskForItem(item);
        task?.status = TaskStatus.failure;
        task?.message = error;
      },
    );

    _startDownloadProcess();
  }

  DownloadFileTask? _findTaskForItem(BackupItem item) {
    for (final task in _tasks) {
      if (task is DownloadFileTask && task.item.key == item.key) {
        return task;
      }
    }
    return null;
  }

  Future<void> _startDownloadProcess() async {
    try {
      final itemsToDownload = _tasks.whereType<DownloadFileTask>().map((t) => t.item).toList();
      await _puppeteerService.runBackup(
        items: itemsToDownload,
        savePath: widget.savePath,
      );
    } finally {
      _finishBackup();
    }
  }

  void _finishBackup({String? cancellationMessage}) {
    if (cancellationMessage != null) {
      for (final task in _tasks) {
        if (task.status == TaskStatus.running || task.status == TaskStatus.pending) {
          task.status = TaskStatus.failure;
          task.message = cancellationMessage;
        }
      }
    }
    if (mounted) {
      setState(() {
        _isBackupComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRunning = !_isBackupComplete;

    return PopScope(
      canPop: !isRunning,
      onPopInvoked: (didPop) {
        if (didPop && isRunning) {
          _puppeteerService.cancelBackup();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Процесс бэкапа'),
          automaticallyImplyLeading: !isRunning,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOverallStatus(),
              const SizedBox(height: 16),
              const Divider(),
              Expanded(child: _buildTasksList()),
              if (_isBackupComplete) _buildCompletionControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverallStatus() {
    final processedTasks = _tasks.where((t) => t.status != TaskStatus.pending && t.status != TaskStatus.running).length;
    final progress = _tasks.isNotEmpty ? processedTasks / _tasks.length : 0.0;
    final isRunning = !_isBackupComplete;

    String title = isRunning ? 'Идет бэкап...' : 'Бэкап завершен';
    IconData icon = isRunning ? Icons.cloud_upload_outlined : (_tasks.any((t) => t.status == TaskStatus.failure) ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded);
    Color iconColor = isRunning ? Theme.of(context).colorScheme.primary : (_tasks.any((t) => t.status == TaskStatus.failure) ? Colors.orange : Colors.green);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 8),
            Text('$processedTasks из ${_tasks.length} файлов обработано'),
            const SizedBox(height: 16),
            Text(_currentAction, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (isRunning)
              ElevatedButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('Остановить бэкап'),
                onPressed: () {
                  _puppeteerService.forceCloseBrowser();
                  _finishBackup(cancellationMessage: 'Отменено пользователем');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList() {
    return ListView.builder(
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return ChangeNotifierProvider.value(
          value: task,
          child: Consumer<BackupTask>(
            builder: (context, task, child) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: _buildStatusIcon(task.status),
                  title: Text(task.title, overflow: TextOverflow.ellipsis),
                  subtitle: task.message != null ? Text(task.message!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: task.status == TaskStatus.failure ? Colors.redAccent : null)) : null,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case TaskStatus.running:
        return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.0));
      case TaskStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case TaskStatus.failure:
        return const Icon(Icons.error, color: Colors.red);
      // --- НОВАЯ ИКОНКА ---
      case TaskStatus.skipped:
        return const Icon(Icons.history, color: Colors.grey);
    }
  }

  Widget _buildCompletionControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Открыть папку'),
            onPressed: () => OpenFile.open(widget.savePath),
          ),
        ],
      ),
    );
  }
}