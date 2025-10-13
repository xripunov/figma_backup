import 'dart:io';

import 'package:figma_bckp/models/automation_settings.dart';
import 'package:figma_bckp/models/backup_group.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AutomationService {
  Future<String> get _launchAgentsPath async {
    final home = await getApplicationDocumentsDirectory();
    // Typically ~/Library/LaunchAgents is not directly accessible via path_provider
    // A more robust solution might be needed, but for macOS this is a common approach.
    // We assume the standard directory structure.
    final homePath = home.path.split('/Documents').first;
    final launchAgentsDir = Directory('$homePath/Library/LaunchAgents');
    if (!await launchAgentsDir.exists()) {
      await launchAgentsDir.create(recursive: true);
    }
    return launchAgentsDir.path;
  }

  String _plistFileName(String groupId) =>
      'com.figma_bckp.scheduler.$groupId.plist';

  Future<File> _getPlistFile(String groupId) async {
    final path = await _launchAgentsPath;
    return File('$path/${_plistFileName(groupId)}');
  }

  String _generatePlistContent(BackupGroup group) {
    final settings = group.automationSettings;
    if (settings.frequency == Frequency.off) return '';

    final groupId = group.id;
    final label = 'com.figma_bckp.scheduler.$groupId';
    final url = 'figma-bckp://start-backup/$groupId';
    final time = settings.timeOfDay;

    String calendarIntervalXml;

    switch (settings.frequency) {
      case Frequency.daily:
        calendarIntervalXml = '''
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${time.hour}</integer>
        <key>Minute</key>
        <integer>${time.minute}</integer>
    </dict>''';
        break;
      case Frequency.weekly:
        if (settings.weekdays == null || settings.weekdays!.isEmpty) return '';
        final weeklyDicts = settings.weekdays!.map((weekday) => '''
        <dict>
            <key>Weekday</key>
            <integer>$weekday</integer>
            <key>Hour</key>
            <integer>${time.hour}</integer>
            <key>Minute</key>
            <integer>${time.minute}</integer>
        </dict>''').join('\n');
        calendarIntervalXml = '''
    <key>StartCalendarInterval</key>
    <array>
        $weeklyDicts
    </array>''';
        break;
      case Frequency.monthly:
        if (settings.dayOfMonth == null) return '';
        calendarIntervalXml = '''
    <key>StartCalendarInterval</key>
    <dict>
        <key>Day</key>
        <integer>${settings.dayOfMonth}</integer>
        <key>Hour</key>
        <integer>${time.hour}</integer>
        <key>Minute</key>
        <integer>${time.minute}</integer>
    </dict>''';
        break;
      case Frequency.off:
        return '';
    }

    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>open</string>
        <string>$url</string>
    </array>
    $calendarIntervalXml
</dict>
</plist>
''';
  }

  Future<void> enableAutomation(BackupGroup group) async {
    final content = _generatePlistContent(group);
    if (content.isEmpty) return;
    
    final file = await _getPlistFile(group.id);
    await file.writeAsString(content);
    await _loadLaunchAgent(file.path);
  }

  Future<void> disableAutomation(String groupId) async {
    final file = await _getPlistFile(groupId);
    if (await file.exists()) {
      await _unloadLaunchAgent(file.path);
      await file.delete();
    }
  }

  Future<bool> isAutomationActive(String groupId) async {
    final result = await Process.run(
      'launchctl',
      ['list', 'com.figma_bckp.scheduler.$groupId'],
    );
    // If the service is found, stdout will contain info about it.
    // If not found, it might return a non-zero exit code or empty stdout.
    // A simple check for the label in stdout is reliable.
    return result.stdout.toString().contains('com.figma_bckp.scheduler.$groupId');
  }


  Future<void> _loadLaunchAgent(String filePath) async {
    final result = await Process.run('launchctl', ['load', filePath]);
    if (result.exitCode != 0) {
      // Consider logging this error
      print('Error loading launch agent: ${result.stderr}');
    }
  }

  Future<void> _unloadLaunchAgent(String filePath) async {
    final result = await Process.run('launchctl', ['unload', filePath]);
    if (result.exitCode != 0) {
      // Consider logging this error
      print('Error unloading launch agent: ${result.stderr}');
    }
  }
}
