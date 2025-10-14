import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:figma_bckp/models/backup_group.dart';
import 'package:figma_bckp/models/backup_item.dart';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:figma_bckp/screens/backup_screen.dart';
import 'package:figma_bckp/screens/settings_screen.dart';
import 'package:figma_bckp/services/figma_api_service.dart';
import 'package:figma_bckp/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:figma_bckp/screens/widgets/automation_control_widget.dart';
import 'package:figma_bckp/models/automation_settings.dart';
import 'package:figma_bckp/screens/widgets/automation_settings_dialog.dart';
import 'package:figma_bckp/models/figma_url_info.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:figma_bckp/services/bookmark_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeScreen extends StatefulWidget {
  final String? startupGroupId;
  const HomeScreen({super.key, this.startupGroupId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _breakpoint = 768.0;

  late final FigmaApiService _figmaApiService;
  late final SettingsService _settingsService;
  final _urlController = TextEditingController();

  List<BackupGroup> _groups = [];
  BackupGroup? _activeGroup;
  final Map<String, FigmaFile?> _fileDetailsCache = {};

  bool _isInitialLoading = true;
  String? _errorMessage;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _figmaApiService = Provider.of<FigmaApiService>(context, listen: false);
    _settingsService = Provider.of<SettingsService>(context, listen: false);
    _urlController.addListener(() => setState(() {}));
    _loadInitialData();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startupGroupId != null && widget.startupGroupId != _activeGroup?.id) {
      final groupToActivate = _groups.firstWhereOrNull(
        (g) => g.id == widget.startupGroupId,
      );
      if (groupToActivate != null) {
        _setActiveGroup(groupToActivate);
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isInitialLoading = true;
      _errorMessage = null;
    });

    try {
      _groups = await _settingsService.getBackupGroups();
    } catch (e) {
      debugPrint("Error loading backup groups: $e");
      _groups = [];
      // Optionally, show an error message to the user
    }

    // If no groups exist after loading (and potential migration), create one.
    if (_groups.isEmpty) {
      final defaultGroup = BackupGroup(name: 'Мой бэкап');
      _groups.add(defaultGroup);
      await _settingsService.saveBackupGroups(_groups);
      _activeGroup = defaultGroup;
      await _settingsService.setActiveGroupId(defaultGroup.id);
    } else {
      String? activeGroupId;
      // --- FIX: Prioritize startupGroupId from URL scheme ---
      if (widget.startupGroupId != null && _groups.any((g) => g.id == widget.startupGroupId)) {
        activeGroupId = widget.startupGroupId;
      } else {
        activeGroupId = await _settingsService.getActiveGroupId();
      }

      if (_groups.isNotEmpty) {
        _activeGroup = _groups.firstWhere(
          (g) => g.id == activeGroupId,
          orElse: () => _groups.first,
        );
        await _settingsService.setActiveGroupId(_activeGroup!.id);
      } else {
        _activeGroup = null;
      }
    }

    setState(() {
      _isInitialLoading = false;
    });

    if (_activeGroup != null) {
      _fetchDetailsForActiveGroup();
    }
  }

  Future<void> _fetchDetailsForActiveGroup({bool force = false}) async {
    final token = await _settingsService.getToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _errorMessage = '''API токен не найден. Пожалуйста, добавьте его в настройках.

Как получить API токен:
1. Откройте Figma и перейдите в «Settings» -> «Security».
2. В разделе «Personal access tokens» создайте новый токен.
3. ВАЖНО: в списке «Scopes» выберите:
   • Files: file_metadata:read
   • Projects: projects:read
4. Скопируйте токен и вставьте его в настройках этого приложения.''';
      });
      return;
    }
    _errorMessage = null;

    if (_activeGroup == null) return;

    // Set loading state for all items in the group
    for (var item in _activeGroup!.items) {
       if (force || !_fileDetailsCache.containsKey(item.key)) {
        _fileDetailsCache[item.key] = FigmaFile(key: item.key, name: '##LOADING##', lastModified: '', projectName: '');
      }
    }
    if(mounted) setState(() {});


    final itemsToFetch = List<BackupItem>.from(_activeGroup!.items);
    for (final item in itemsToFetch) {
      if (!_activeGroup!.items.any((i) => i.key == item.key)) continue;

      try {
        // Reconstruct FigmaUrlInfo from BackupItem
        final fileKey = item.branchId != null ? item.key.split('_').first : item.key;
        final urlInfo = FigmaUrlInfo(
          fileKey: fileKey,
          branchId: item.branchId,
          fileType: item.fileType,
        );

        final details = await _figmaApiService.getFullFileInfo(urlInfo, token);
        _fileDetailsCache[item.key] = details;
      } catch (e) {
        debugPrint("Failed to fetch details for ${item.key}: $e");
        _fileDetailsCache[item.key] = null; // Error state
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<bool> _processAndAddFile(String url) async {
    if (_activeGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала создайте группу, чтобы добавить в нее файл.')),
      );
      return false;
    }

    final urlInfo = _figmaApiService.extractUrlInfo(url);
    if (urlInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверная ссылка на файл Figma.')));
      return false;
    }

    // Create a unique key for the item: filekey for main branch, filekey_branchid for others.
    final itemKey = urlInfo.branchId != null
        ? '${urlInfo.fileKey}_${urlInfo.branchId}'
        : urlInfo.fileKey;

    if (!_activeGroup!.items.any((item) => item.key == itemKey)) {
      final newItem = BackupItem(
        key: itemKey,
        mainFileName: '', // Will be filled after fetching details
        lastModified: '',
        projectName: '',
        branchId: urlInfo.branchId,
        fileType: urlInfo.fileType,
      );
      _activeGroup!.items.insert(0, newItem);
      _saveGroupsDebounced();
      setState(() {
        // Use the same unique key for the cache
        _fileDetailsCache[itemKey] = FigmaFile(key: itemKey, name: '##LOADING##', lastModified: '', projectName: '');
      });
      _fetchDetailsForActiveGroup();
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Этот файл уже в списке.')));
      return false;
    }
  }

  Future<void> _addFileFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await _processAndAddFile(url);
    _urlController.clear();
  }

  Future<void> _addFileFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final url = clipboardData?.text?.trim();
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Буфер обмена пуст.')),
      );
      return;
    }
    final success = await _processAndAddFile(url);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл добавлен из буфера обмена.')),
      );
    }
  }

  Future<void> _removeFile(String key) async {
    _activeGroup?.items.removeWhere((item) => item.key == key);
    _saveGroupsDebounced();
    setState(() {});
  }

  void _saveGroupsDebounced() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _settingsService.saveBackupGroups(_groups);
    });
  }

  void _setActiveGroup(BackupGroup? group) {
    if (group == null) {
      setState(() {
        _activeGroup = null;
      });
      return;
    }
    _settingsService.setActiveGroupId(group.id);
    setState(() {
      _activeGroup = group;
    });
    _fetchDetailsForActiveGroup();
  }

  Future<void> _startBackup() async {
    if (_activeGroup == null) return;

    final List<BackupItem> itemsToBackup = _activeGroup!.items
        .map((item) {
          final details = _fileDetailsCache[item.key];
          if (details == null || details.name == '##LOADING##') return null;
          return BackupItem(
            key: details.key,
            mainFileName: details.name,
            lastModified: details.lastModified,
            projectName: details.projectName,
            branchId: item.branchId, // Preserve from the original item
            branchName: details.branchName, // Get from fetched details
            fileType: details.fileType,
          );
        })
        .where((i) => i != null)
        .cast<BackupItem>()
        .toList();

    if (itemsToBackup.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет успешно загруженных файлов для бэкапа.')));
      return;
    }

    String? savePath = await _settingsService.getSavePath();
    if (savePath == null) {
      final result = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Выберите папку для сохранения бэкапов');
      if (result != null) {
        savePath = result;
        final bookmark = await BookmarkService().createBookmark(savePath);
        await _settingsService.setSavePath(savePath, bookmark);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Выбор папки отменен. Бэкап не запущен.')),
          );
        }
        return;
      }
    }

    if (mounted) {
      final backupResult = await Navigator.push<String?>(context, MaterialPageRoute(
        builder: (context) => BackupScreen(
          itemsToBackup: itemsToBackup,
          savePath: savePath!,
        ),
      ));

      if (!mounted) return;

      switch (backupResult) {
        case 'success':
          setState(() {
            _activeGroup!.lastBackup = DateTime.now();
          });
          _saveGroupsDebounced();
          break;
        case 'failure':
          // No snackbar needed, user saw the final state on the backup screen.
          break;
        case 'canceled':
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Бэкап отменен.')),
          );
          break;
      }
    }
  }

  void _navigateToSettings() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
    if (result == true) {
      _loadInitialData();
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _showAutomationSettingsDialog() async {
    if (_activeGroup == null) return;

    final result = await showDialog<AutomationSettings>(
      context: context,
      builder: (context) => AutomationSettingsDialog(
        initialSettings: _activeGroup!.automationSettings,
      ),
    );

    if (result != null) {
      setState(() {
        final groupIndex = _groups.indexWhere((g) => g.id == _activeGroup!.id);
        if (groupIndex != -1) {
          _groups[groupIndex] = _activeGroup!.copyWith(automationSettings: result);
          _activeGroup = _groups[groupIndex];
        }
      });
      _saveGroupsDebounced();
    }
  }

  // --- GROUP MANAGEMENT DIALOGS ---

  bool _isAnyFileLoading() {
    if (_activeGroup == null) return false;
    return _activeGroup!.items
        .any((item) => _fileDetailsCache[item.key]?.name == '##LOADING##');
  }

  int _getBackupReadyFilesCount() {
    if (_activeGroup == null) return 0;
    return _activeGroup!.items
        .map((i) => _fileDetailsCache[i.key])
        .where((f) => f != null && f.name != '##LOADING##')
        .length;
  }

  Future<void> _showAddGroupDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать новую группу'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название группы'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newGroup = BackupGroup(name: result);
      setState(() {
        _groups.add(newGroup);
      });
      _saveGroupsDebounced();
      _setActiveGroup(newGroup);
    }
  }

  Future<void> _showRenameGroupDialog(BackupGroup group, BuildContext context) async {
    // Ensure the context is valid before showing a dialog.
    if (!mounted) return;
    final nameController = TextEditingController(text: group.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать группу'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название группы'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        group.name = result;
      });
      _saveGroupsDebounced();
    }
  }

  Future<void> _showDeleteGroupDialog(BackupGroup group, BuildContext context) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: Text('Вы уверены, что хотите удалить группу "${group.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final wasActive = _activeGroup?.id == group.id;
      final currentIndex = _groups.indexOf(group);
      _groups.remove(group);

      if (wasActive) {
        BackupGroup? newActiveGroup;
        if (_groups.isNotEmpty) {
          newActiveGroup = _groups[currentIndex > 0 ? currentIndex - 1 : 0];
        }
        _setActiveGroup(newActiveGroup);
      } else {
        setState(() {});
      }
      _saveGroupsDebounced();
    }
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= _breakpoint;
        final drawerContent = _buildDrawerContent(isWideScreen);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 1, // Add shadow
            title: Text(isWideScreen ? 'Figma Backup' : (_activeGroup?.name ?? 'Figma Backup')),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchDetailsForActiveGroup(force: true)),
              IconButton(icon: const Icon(Icons.settings), onPressed: _navigateToSettings),
            ],
          ),
          drawer: isWideScreen ? null : Drawer(child: drawerContent),
          body: Row(
            children: [
              if (isWideScreen)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: SizedBox(
                    width: 280,
                    child: drawerContent,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (_activeGroup != null && _activeGroup!.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                        child: AutomationControlWidget(
                          description: _activeGroup!.automationSettings.toDescription(),
                          onPressed: _showAutomationSettingsDialog,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              decoration: InputDecoration(
                                hintText: 'Вставьте ссылку на файл Figma',
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _addFileFromUrl(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _urlController.text.isEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.assignment_outlined),
                                  onPressed: _addFileFromClipboard,
                                  tooltip: 'Вставить из буфера обмена',
                                )
                              : IconButton.filled(
                                  icon: const Icon(Icons.add),
                                  onPressed: _addFileFromUrl,
                                ),
                        ],
                      ),
                    ),
                    if (_activeGroup != null && _activeGroup!.items.isNotEmpty)
                      const Divider(height: 1),
                    Expanded(child: _buildFileList()),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _activeGroup != null && _activeGroup!.items.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _isAnyFileLoading() || _getBackupReadyFilesCount() == 0 ? null : _startBackup,
                  label: _isAnyFileLoading()
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : Text('Сохранить (${_getBackupReadyFilesCount()})'),
                  icon: _isAnyFileLoading() ? null : const Icon(Icons.download_outlined),
                )
              : null,
        );
      },
    );
  }

  Widget _buildDrawerContent(bool isWideScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
          child: Text(
            'Группы для бэкапа',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              return _GroupListItem(
                group: group,
                isActive: _activeGroup?.id == group.id,
                onTap: () {
                  _setActiveGroup(group);
                  if (!isWideScreen) Navigator.pop(context);
                },
                onRename: () {
                  // Do not pop the drawer, show the dialog directly over it.
                  _showRenameGroupDialog(group, context);
                },
                onDelete: () {
                  // Do not pop the drawer, show the dialog directly over it.
                  _showDeleteGroupDialog(group, context);
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Создать группу'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              minimumSize: const Size(double.infinity, 56), // to match ListTile height
            ),
            onPressed: () {
              if (!isWideScreen) {
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showAddGroupDialog();
                });
              } else {
                _showAddGroupDialog();
              }
            },
          ),
        ),
      ],
    );
  }

// ... (rest of the imports)

// ... (inside _HomeScreenState)

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
    if (_activeGroup == null || _activeGroup!.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50.0),
        child: Center(
          child: Text(
            _groups.isEmpty
                ? 'Создайте вашу первую группу для бэкапа.'
                : 'Список пуст. Добавьте файлы по\u00A0ссылке выше.\n\nРекомендуется добавлять и\u00A0скачивать не\u00A0более 10\u00A0файлов за\u00A0раз.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchDetailsForActiveGroup(force: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 96.0),
        itemCount: _activeGroup!.items.length,
        itemBuilder: (context, index) {
          final item = _activeGroup!.items[index];
          final details = _fileDetailsCache[item.key];

          Widget leadingWidget;
          Widget titleWidget;
          Widget subtitleWidget;

          if (details == null) {
            leadingWidget = const Icon(Icons.error_outline, color: Colors.redAccent);
            titleWidget = const Text('Ошибка загрузки информации');
            subtitleWidget = Text('Ключ: ${item.key}', style: Theme.of(context).textTheme.bodySmall);
          } else if (details.name == '##LOADING##') {
            leadingWidget = SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            );
            titleWidget = const Text('Получение информации...');
            subtitleWidget = Text('Ключ: ${item.key}', style: Theme.of(context).textTheme.bodySmall);
          } else {
            leadingWidget = _buildLeadingIcon(details);
            
            final displayName = details.branchName ?? details.name;
            titleWidget = Text(displayName, style: Theme.of(context).textTheme.titleMedium);
            
            final projectName = details.projectName.isEmpty ? 'Drafts' : details.projectName;

            subtitleWidget = Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium,
                  children: [
                    TextSpan(text: '$projectName  •  '),
                    TextSpan(
                      text: _formatDate(details.lastModified),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leadingWidget,
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        subtitleWidget,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Opacity(
                    opacity: 0.6,
                    child: IconButton(
                      icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () => _removeFile(item.key),
                    ),
                  ),
                ],
              ),
            ),
          );

        },
      ),
    );
  }
}

Widget _buildLeadingIcon(FigmaFile file) {
  String assetName;
  if (file.branchName != null) {
    assetName = 'assets/icons/branch.svg';
  } else {
    switch (file.fileType) {
      case FigmaFileType.design:
        assetName = 'assets/icons/fig.svg';
        break;
      case FigmaFileType.figjam:
        assetName = 'assets/icons/board.svg';
        break;
      case FigmaFileType.slides:
        assetName = 'assets/icons/slides.svg';
        break;
    }
  }
  return SvgPicture.asset(
    assetName,
    width: 24,
    height: 24,
  );
}

// --- Helper Widget for Drawer ---

class _GroupListItem extends StatefulWidget {
  final BackupGroup group;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _GroupListItem({
    required this.group,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_GroupListItem> createState() => _GroupListItemState();
}

class _GroupListItemState extends State<_GroupListItem> {
  bool _isHovering = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    Widget? subtitleWidget;
    if (widget.group.lastBackup != null) {
      final lastBackupText = 'Обновлено: ${DateFormat('dd.MM.yy HH:mm').format(widget.group.lastBackup!)}';
      final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
          );
      subtitleWidget = Text(lastBackupText, style: subtitleStyle);
    }

    Widget? trailingWidget;
    if (_isHovering || _isMenuOpen) {
      trailingWidget = SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            onOpened: () => setState(() => _isMenuOpen = true),
            onCanceled: () => setState(() => _isMenuOpen = false),
            onSelected: (value) {
              setState(() => _isMenuOpen = false);
              if (value == 'rename') {
                widget.onRename();
              } else if (value == 'delete') {
                widget.onDelete();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename',
                child: Text('Редактировать'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Удалить'),
              ),
            ],
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'Действия',
          ),
        ),
      );
    } else {
      trailingWidget = SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Text(
            widget.group.items.length.toString(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).textTheme.titleMedium?.color?.withOpacity(0.6),
                ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: ListTile(
        title: Text(widget.group.name),
        subtitle: subtitleWidget,
        selected: widget.isActive,
        onTap: widget.onTap,
        trailing: trailingWidget,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}
