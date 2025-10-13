import 'dart:convert';
import 'package:figma_bckp/models/automation_settings.dart';
import 'package:figma_bckp/models/backup_group.dart';
import 'package:figma_bckp/models/backup_item.dart';
import 'package:figma_bckp/services/automation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:figma_bckp/services/bookmark_service.dart';

class SettingsService {
  // --- NEW KEYS ---
  static const _backupGroupsKey = 'backup_groups_v2';
  static const _activeGroupIdKey = 'active_group_id';

  // --- OLD KEYS (for migration) ---
  static const _backupFileKeysOld = 'backup_file_keys';

  // --- COMMON KEYS ---
  static const _tokenKey = 'figma_token';
  static const _savePathKey = 'save_path';
  static const _savePathBookmarkKey = 'save_path_bookmark';

  final AutomationService _automationService = AutomationService();

  // --- TOKEN & PATH ---

  Future<void> setSavePath(String path, [String? bookmark]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savePathKey, path);
    if (bookmark != null) {
      await prefs.setString(_savePathBookmarkKey, bookmark);
    }
  }

  Future<String?> getSavePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savePathKey);
  }

  Future<String?> getSavePathBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savePathBookmarkKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // --- GROUP MANAGEMENT ---

  Future<List<BackupGroup>> getBackupGroups() async {
    final prefs = await SharedPreferences.getInstance();

    // --- MIGRATION LOGIC ---
    if (await _needsMigration(prefs)) {
      return await _migrateData(prefs);
    }
    // --- END MIGRATION ---

    final jsonString = prefs.getString(_backupGroupsKey);
    if (jsonString == null) {
      return [];
    }
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      List<BackupGroup> groups =
          jsonList.map((json) => BackupGroup.fromJson(json)).toList();

      // --- SYNC AUTOMATION STATE ---
      List<BackupGroup> syncedGroups = [];
      bool needsSaving = false;
      for (final group in groups) {
        if (group.automationSettings.frequency != Frequency.off) {
          final isActive = await _automationService.isAutomationActive(group.id);
          if (isActive) {
            syncedGroups.add(group);
          } else {
            // If launchd task is not active, update the state
            syncedGroups.add(group.copyWith(automationSettings: const AutomationSettings.off()));
            debugPrint("Sync: Automation for group '${group.name}' was disabled externally.");
            needsSaving = true;
          }
        } else {
          syncedGroups.add(group);
        }
      }
      
      if (needsSaving) {
        await saveBackupGroups(syncedGroups);
      }

      return syncedGroups;
    } catch (e) {
      debugPrint("Error decoding backup groups: $e");
      return [];
    }
  }

  Future<void> saveBackupGroups(List<BackupGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final List<Map<String, dynamic>> jsonList =
          groups.map((group) => group.toJson()).toList();
      await prefs.setString(_backupGroupsKey, json.encode(jsonList));
    } catch (e) {
      debugPrint("Error saving backup groups: $e");
    }
  }

  Future<String?> getActiveGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeGroupIdKey);
  }

  Future<void> setActiveGroupId(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGroupIdKey, groupId);
  }

  // --- AUTOMATION CONTROL ---

  Future<void> updateAutomationSettings(String groupId, AutomationSettings settings) async {
    final groups = await getBackupGroups();
    final groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = groups[groupIndex];
    final updatedGroup = group.copyWith(automationSettings: settings);

    // First, disable any existing automation to ensure a clean state
    await _automationService.disableAutomation(groupId);

    // If the new frequency is not 'off', enable it with the new settings
    if (settings.frequency != Frequency.off) {
      await _automationService.enableAutomation(updatedGroup);
    }
    
    groups[groupIndex] = updatedGroup;
    await saveBackupGroups(groups);
  }

  // --- MIGRATION ---

  Future<bool> _needsMigration(SharedPreferences prefs) async {
    // If new key exists, no migration needed
    if (prefs.containsKey(_backupGroupsKey)) {
      return false;
    }
    // If old key exists, migration is needed
    return prefs.containsKey(_backupFileKeysOld);
  }

  Future<List<BackupGroup>> _migrateData(SharedPreferences prefs) async {
    debugPrint("--- Starting data migration from v1 to v2 ---");
    try {
      final oldKeys = prefs.getStringList(_backupFileKeysOld) ?? [];
      if (oldKeys.isEmpty) {
        await prefs.remove(_backupFileKeysOld); // Clean up
        debugPrint("Migration: Old key list was empty. Nothing to migrate.");
        return [];
      }

      final List<BackupItem> items =
          oldKeys.map((key) => BackupItem.fromOnlyKey(key)).toList();

      final defaultGroup = BackupGroup(
        name: 'Мой бэкап', // Default name for the migrated group
        items: items,
      );

      await saveBackupGroups([defaultGroup]);
      await setActiveGroupId(defaultGroup.id);

      // --- CLEAN UP OLD KEYS ---
      await prefs.remove(_backupFileKeysOld);

      debugPrint("--- Migration successful ---");
      return [defaultGroup];
    } catch (e) {
      debugPrint("--- MIGRATION FAILED: $e ---");
      // In case of failure, return an empty list to avoid crashing.
      return [];
    }
  }
}
