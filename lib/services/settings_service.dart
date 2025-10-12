import 'dart:convert';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _tokenKey = 'figma_token';
  static const _savePathKey = 'save_path';
  static const _backupFileKeys = 'backup_file_keys';
  static const _fileDetailPrefix = 'file_detail_';

  Future<void> setSavePath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savePathKey, path);
    } catch (e) {
      debugPrint("Error saving save path: $e");
    }
  }

  Future<String?> getSavePath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_savePathKey);
    } catch (e) {
      debugPrint("Error getting save path: $e");
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      debugPrint("Error saving token: $e");
    }
  }

  Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      debugPrint("Error getting token: $e");
      return null;
    }
  }

  Future<void> setFileKeys(List<String> fileKeys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_backupFileKeys, fileKeys);
    } catch (e) {
      debugPrint("Error setting file keys: $e");
    }
  }

  Future<List<String>> getFileKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_backupFileKeys) ?? [];
    } catch (e) {
      debugPrint("Error getting file keys: $e");
      return []; // Return empty list on error
    }
  }

  Future<void> saveFileDetails(FigmaFile file) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_fileDetailPrefix${file.key}';
      final value = json.encode(file.toJson());
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint("Error saving file details for key ${file.key}: $e");
    }
  }

  Future<FigmaFile?> getFileDetails(String fileKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_fileDetailPrefix$fileKey';
      final value = prefs.getString(key);
      if (value != null) {
        return FigmaFile.fromJsonCache(json.decode(value));
      }
      return null;
    } catch (e) {
      debugPrint("Error getting file details for key $fileKey: $e");
      return null;
    }
  }

  Future<void> removeFileDetails(String fileKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_fileDetailPrefix$fileKey';
      await prefs.remove(key);
    } catch (e) {
      debugPrint("Error removing file details for key $fileKey: $e");
    }
  }
}