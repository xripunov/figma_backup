import 'dart:convert';
import 'package:figma_bckp/models/backup_group.dart';
import 'package:figma_bckp/models/backup_item.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  // --- NEW KEYS ---
  static const _backupGroupsKey = 'backup_groups_v2';
  static const _activeGroupIdKey = 'active_group_id';

  // --- OLD KEYS (for migration) ---
  static const _backupFileKeysOld = 'backup_file_keys';

  // --- COMMON KEYS ---
  static const _tokenKey = 'figma_token';
  static const _savePathKey = 'save_path';

  // --- TOKEN & PATH ---

  Future<void> setSavePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savePathKey, path);
  }

  Future<String?> getSavePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savePathKey);
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
      return jsonList.map((json) => BackupGroup.fromJson(json)).toList();
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
