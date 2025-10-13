import 'dart:async';
import 'dart:io';

import 'package:figma_bckp/models/backup_group.dart';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:figma_bckp/screens/backup_screen.dart';
import 'package:figma_bckp/screens/home_screen.dart';
import 'package:figma_bckp/screens/onboarding_screen.dart';
import 'package:figma_bckp/services/figma_api_service.dart';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'services/settings_service.dart';
import 'package:figma_bckp/services/bookmark_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggingService().init();

  final settingsService = SettingsService();

  // --- RESTORE FILE ACCESS PERMISSION ---
  try {
    final bookmark = await settingsService.getSavePathBookmark();
    if (bookmark != null) {
      debugPrint("Restoring permission using bookmark...");
      final success = await BookmarkService().resolveBookmark(bookmark);
      if (success) {
        debugPrint("Permission restored.");
      } else {
        debugPrint("Failed to restore permission.");
      }
    }
  } catch (e) {
    debugPrint("Error restoring permission: $e");
  }
  // --- END RESTORE ---

  final token = await settingsService.getToken();

  runApp(
    MultiProvider(
      providers: [
        Provider<SettingsService>(
          create: (_) => settingsService,
        ),
        Provider<FigmaApiService>(
          create: (_) => FigmaApiService(),
        ),
        ChangeNotifierProvider<ValueNotifier<bool>>(
          create: (_) => ValueNotifier(false), // isBackupInProgress
        ),
      ],
      child: MyApp(isTokenProvided: token != null && token.isNotEmpty),
    ),
  );
}

class MyApp extends StatefulWidget {
  final bool isTokenProvided;
  const MyApp({super.key, required this.isTokenProvided});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _linkSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;
  String? _startupGroupId;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initUniLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initUniLinks() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleLink(initialLink);
      }
    } on PlatformException {
      // Handle exception
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleLink(uri);
    }, onError: (err) {
      // Handle exception
    });
  }

  void _handleLink(Uri uri) {
    if (uri.scheme == 'figma-bckp' && uri.host == 'start-backup') {
      if (uri.pathSegments.isNotEmpty) {
        final groupId = uri.pathSegments.first;
        setState(() {
          _startupGroupId = groupId;
        });
        _handleBackupFromUrl(groupId);
      }
    }
  }

  Future<void> _handleBackupFromUrl(String groupId) async {
    final isBackupInProgress = context.read<ValueNotifier<bool>>();
    if (isBackupInProgress.value) {
      debugPrint("Automation: Backup is already in progress. Ignoring request.");
      return;
    }

    debugPrint("Automation: Starting backup for group $groupId");
    isBackupInProgress.value = true;

    try {
      final settingsService = context.read<SettingsService>();
      final figmaApiService = context.read<FigmaApiService>();
      final token = await settingsService.getToken();
      final savePath = await settingsService.getSavePath();

      if (token == null || savePath == null) {
        debugPrint("Automation: Token or save path is not configured. Aborting.");
        return;
      }

      final groups = await settingsService.getBackupGroups();
      final group = groups.firstWhere((g) => g.id == groupId, orElse: () => throw Exception('Group not found'));

      final List<FigmaFile> filesToBackup = [];
      for (final item in group.items) {
        try {
          final details = await figmaApiService.getFullFileInfo(item.key, token);
          filesToBackup.add(details);
        } catch (e) {
          debugPrint("Automation: Failed to fetch info for ${item.key}, skipping. Error: $e");
        }
      }

      if (filesToBackup.isEmpty) {
        debugPrint("Automation: No files to back up for group ${group.name}.");
        return;
      }

      // Ensure we have a valid context to navigate
      var navigator = _navigatorKey.currentState;
      if (navigator == null) {
        debugPrint("Automation: Navigator not ready, waiting...");
        // Wait for the navigator to be ready
        final completer = Completer<void>();
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (_navigatorKey.currentState != null) {
            timer.cancel();
            completer.complete();
          }
          if (timer.tick > 100) { // 10 seconds timeout
            timer.cancel();
            completer.completeError('Navigator not ready after 10 seconds');
          }
        });
        await completer.future;
        navigator = _navigatorKey.currentState;
      }

      if (navigator == null) {
        debugPrint("Automation: Navigator state is not available after waiting.");
        return;
      }

      await navigator.push(MaterialPageRoute(
        builder: (context) => BackupScreen(
          selectedFiles: filesToBackup,
          savePath: savePath,
        ),
      ));

      // After backup, update the last backup time
      final updatedGroups = await settingsService.getBackupGroups();
      final groupIndex = updatedGroups.indexWhere((g) => g.id == groupId);
      if (groupIndex != -1) {
        updatedGroups[groupIndex] = updatedGroups[groupIndex].copyWith(lastBackup: DateTime.now());
        await settingsService.saveBackupGroups(updatedGroups);
      }

    } catch (e) {
      debugPrint("Automation: An error occurred during automated backup: $e");
    } finally {
      debugPrint("Automation: Backup process finished.");
      isBackupInProgress.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Figma Backup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: widget.isTokenProvided
          ? HomeScreen(startupGroupId: _startupGroupId)
          : const OnboardingScreen(),
    );
  }
}