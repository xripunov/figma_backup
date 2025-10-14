import 'dart:async';

import 'package:figma_bckp/models/backup_item.dart';
import 'package:figma_bckp/models/backup_task.dart';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:figma_bckp/services/puppeteer_service.dart';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:provider/provider.dart';

class BackupScreen extends StatefulWidget {
  final List<BackupItem> itemsToBackup;
  final String savePath;

  const BackupScreen({
    super.key,
    required this.itemsToBackup,
    required this.savePath,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  static const List<String> _funnyPhrases = [
    'Мы могли бы быстрее, но нам лень.',
    'Загрузка почти завершена... почти.',
    'Терпение — золото. Спасибо, что спонсируете нас.',
    'Вызываем духов Figma для ускорения процесса...',
    'Пока вы ждете, почему бы не выпить чашечку чая?',
    'Не волнуйтесь, мы все еще здесь. Наверное.',
    'Если загрузка остановилась, просто перезагрузите... Вселенную.',
    'Шлифуем пиксели, один за другим.',
    'Разгоняем процессор до сверхсветовой скорости!',
    'Наш хомяк в колесе немного устал, но он старается.',
    'Это не баг, это фича... замедленной загрузки.',
    'Ищем потерянные байты в цифровом океане.',
    'Осталось совсем чуть-чуть. Честно-честно!',
    'Проверяем, не переполнен ли интернет.',
    'Работаем быстрее, чем горят ваши дедлайны.',
    'Готовим файлы к дизайн-ревью. Прячем слои с названием "Final_final_2".',
    'Ищем, где применить эмоциональный дизайн',
  ];

  final List<BackupTask> _tasks = [];
  late final PuppeteerService _puppeteerService;

  bool _isBackupComplete = false;
  String _currentFunnyPhrase = 'Готовимся к взлету...';
  Timer? _phraseTimer;
  int _currentPhraseIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeAndRunBackup();
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    super.dispose();
  }

  void _startPhraseTimer() {
    _phraseTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_isBackupComplete) {
        setState(() {
          _currentPhraseIndex = (_currentPhraseIndex + 1) % _funnyPhrases.length;
          _currentFunnyPhrase = _funnyPhrases[_currentPhraseIndex];
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _initializeAndRunBackup() {
    final fileTasks = widget.itemsToBackup.map((item) => DownloadFileTask(item));
    _tasks.addAll(fileTasks);

    _puppeteerService = PuppeteerService(
      onFileStart: (item) {
        final task = _findTaskForItem(item);
        task?.status = TaskStatus.running;
        task?.message = 'Скачивание...';
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
    _startPhraseTimer();
  }

  DownloadFileTask? _findTaskForItem(BackupItem item) {
    for (final task in _tasks) {
      if (task is DownloadFileTask &&
          task.item.key == item.key &&
          task.item.branchId == item.branchId) {
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
    _phraseTimer?.cancel();
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
        if (didPop) return;
        _puppeteerService.forceCloseBrowser();
        _finishBackup(cancellationMessage: 'Отменено пользователем');
        Navigator.pop(context, 'canceled');
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: 1,
          title: const Text('Сохранение файлов'),
          bottom: isRunning
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4.0),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildOverallStatus(),
            ),
            const Divider(height: 1),
            Expanded(child: _buildTasksList()),
            if (_isBackupComplete)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildCompletionControls(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallStatus() {
    final processedTasks = _tasks.where((t) => t.status != TaskStatus.pending && t.status != TaskStatus.running).length;
    final progress = _tasks.isNotEmpty ? processedTasks / _tasks.length : 0.0;
    final isRunning = !_isBackupComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRunning ? _currentFunnyPhrase : 'Процесс завершен!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
            const SizedBox(width: 16),
            Text(
              '$processedTasks/${_tasks.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            const SizedBox(width: 8),
            Visibility(
              visible: isRunning,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: SizedBox(
                width: 90,
                child: IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: () {
                    _puppeteerService.forceCloseBrowser();
                    _finishBackup(cancellationMessage: 'Отменено пользователем');
                  },
                  style: IconButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTasksList() {
    return ListView.separated(
      itemCount: _tasks.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return ChangeNotifierProvider.value(
          value: task,
          child: Consumer<BackupTask>(
            builder: (context, task, child) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: _buildStatusIcon(task.status),
                title: Text(task.title, overflow: TextOverflow.ellipsis),
                subtitle: task.message != null
                    ? Text(
                        task.message!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: task.status == TaskStatus.failure
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      )
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(TaskStatus status) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: () {
          switch (status) {
            case TaskStatus.pending:
              return Icon(Icons.schedule_outlined, color: theme.colorScheme.onSurfaceVariant);
            case TaskStatus.running:
              return CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary);
            case TaskStatus.success:
              return Icon(Icons.check_circle_outline, color: Colors.green);
            case TaskStatus.failure:
              return Icon(Icons.error_outline, color: theme.colorScheme.error);
            case TaskStatus.skipped:
              return Icon(Icons.history_outlined, color: theme.colorScheme.onSurfaceVariant);
          }
        }(),
      ),
    );
  }

  Widget _buildCompletionControls() {
    final hasFailures = _tasks.any((t) => t.status == TaskStatus.failure);

    return Row(
      children: [
        OutlinedButton(
          onPressed: () => OpenFile.open(widget.savePath),
          child: const Text('Открыть папку'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.pop(context, hasFailures ? 'failure' : 'success'),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}