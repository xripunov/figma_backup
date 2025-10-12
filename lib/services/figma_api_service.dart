import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/figma_file.dart';

class FigmaApiService {
  final String apiBaseUrl = 'https://api.figma.com/v1';
  final http.Client _client;

  FigmaApiService() : _client = http.Client();

  Future<http.Response> _getWithTimeout(Uri uri, Map<String, String> headers) {
    // Уменьшаем таймаут до 30 секунд, так как /meta должен отвечать быстро
    return _client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
  }

  String? extractFileKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host != 'figma.com' && uri.host != 'www.figma.com') return null;
    
    final pathSegments = uri.pathSegments;
    // --- ИЗМЕНЕНИЕ: Проверяем оба формата ссылок ---
    if (pathSegments.length >= 2 && (pathSegments[0] == 'file' || pathSegments[0] == 'design')) {
      return pathSegments[1];
    }
    return null;
  }

  Future<List<FigmaFile>> getFilesDetails(List<String> fileKeys, String token) async {
    if (fileKeys.isEmpty) return [];
    
    List<FigmaFile> successfullyFetchedFiles = [];
    
    for (String key in fileKeys) {
      debugPrint("[getFilesDetails] Processing key: $key");
      try {
        final fileInfo = await getFullFileInfo(key, token);
        successfullyFetchedFiles.add(fileInfo);
        debugPrint("[getFilesDetails] Successfully processed key: $key");
      } catch (e) {
        debugPrint('[getFilesDetails] Failed to fetch details for key $key: $e');
      }
    }
    
    return successfullyFetchedFiles;
  }

  Future<FigmaFile> getFullFileInfo(String fileKey, String token) async {
    // ВОЗВРАЩАЕМ ПРАВИЛЬНЫЙ ЭНДПОИНТ /meta
    final uri = Uri.parse('$apiBaseUrl/files/$fileKey/meta');
    debugPrint("[getFullFileInfo] Requesting URL: $uri");

    try {
      final response = await _getWithTimeout(uri, {'X-Figma-Token': token});
      debugPrint("[getFullFileInfo] Received response for key $fileKey with status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Модель FigmaFile.fromJson ожидает именно этот формат
        final file = FigmaFile.fromJson(data)..key = fileKey;
        return file;
      } else if (response.statusCode == 403) {
        throw Exception('Неверный API токен или нет доступа к файлу.');
      } else if (response.statusCode == 404) {
        throw Exception('Файл с ключом $fileKey не найден.');
      } else {
        throw Exception('Ошибка Figma API. Статус: ${response.statusCode}, Тело: ${response.body}');
      }
    } on TimeoutException {
      debugPrint("[getFullFileInfo] Timeout for key $fileKey");
      throw Exception('Тайм-аут запроса к Figma API для файла $fileKey.');
    } catch (e) {
      debugPrint("[getFullFileInfo] Generic error for key $fileKey: $e");
      throw Exception('An error occurred for $fileKey: $e');
    }
  }
}