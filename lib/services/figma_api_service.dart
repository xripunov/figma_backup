import 'dart:async';
import 'dart:convert';
import 'package:figma_bckp/models/figma_file.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:figma_bckp/models/figma_branch.dart';
import '../models/figma_url_info.dart';

class FigmaApiService {
  final String apiBaseUrl = 'https://api.figma.com/v1';
  final http.Client _client;

  FigmaApiService() : _client = http.Client();

  Future<http.Response> _getWithTimeout(Uri uri, Map<String, String> headers) {
    // Увеличиваем таймаут до 90 секунд для поддержки больших файлов
    return _client.get(uri, headers: headers).timeout(const Duration(seconds: 90));
  }

  FigmaUrlInfo? extractUrlInfo(String url) {
    final regex = RegExp(
        r'figma\.com\/(file|design|board|slides)\/([a-zA-Z0-9]+)(?:\/branch\/([a-zA-Z0-9]+))?');
    final match = regex.firstMatch(url);

    if (match == null) return null;

    final typeString = match.group(1);
    final fileKey = match.group(2);
    final branchId = match.group(3);

    if (fileKey == null) return null;

    FigmaFileType fileType;
    switch (typeString) {
      case 'board':
        fileType = FigmaFileType.figjam;
        break;
      case 'slides':
        fileType = FigmaFileType.slides;
        break;
      case 'file':
      case 'design':
      default:
        fileType = FigmaFileType.design;
        break;
    }

    return FigmaUrlInfo(
      fileKey: fileKey,
      fileType: fileType,
      branchId: branchId,
    );
  }

  Future<List<FigmaFile>> getFilesDetails(List<String> fileKeys, String token) async {
    if (fileKeys.isEmpty) return [];
    
    List<FigmaFile> successfullyFetchedFiles = [];
    
    for (String key in fileKeys) {
      debugPrint("[getFilesDetails] Processing key: $key");
      try {
        // This method might need rethinking if we need to pass branch info here.
        // For now, assuming it's just the file key.
        final urlInfo = extractUrlInfo('https://www.figma.com/file/$key');
        if (urlInfo == null) continue;
        final fileInfo = await getFullFileInfo(urlInfo, token);
        successfullyFetchedFiles.add(fileInfo);
        debugPrint("[getFilesDetails] Successfully processed key: $key");
      } catch (e) {
        debugPrint('[getFilesDetails] Failed to fetch details for key $key: $e');
      }
    }
    
    return successfullyFetchedFiles;
  }

  Future<FigmaFile> getFullFileInfo(FigmaUrlInfo urlInfo, String token) async {
    final headers = {'X-Figma-Token': token};

    try {
      // For branches, we need the main file name AND the branch name.
      // The most efficient way is two parallel calls to the fast /meta endpoint.
      if (urlInfo.branchId != null) {
        final mainFileMetaUri = Uri.parse('$apiBaseUrl/files/${urlInfo.fileKey}/meta');
        final branchMetaUri = Uri.parse('$apiBaseUrl/files/${urlInfo.branchId}/meta');
        debugPrint("[getFullFileInfo] Requesting branch and main file meta in parallel: $mainFileMetaUri & $branchMetaUri");

        final responses = await Future.wait([
          _getWithTimeout(mainFileMetaUri, headers),
          _getWithTimeout(branchMetaUri, headers),
        ]);

        final mainMetaResponse = responses[0];
        final branchMetaResponse = responses[1];

        if (mainMetaResponse.statusCode != 200) throw Exception('Ошибка Figma API (main meta). Статус: ${mainMetaResponse.statusCode}');
        if (branchMetaResponse.statusCode != 200) throw Exception('Ошибка Figma API (branch meta). Статус: ${branchMetaResponse.statusCode}');

        final mainMetaData = json.decode(mainMetaResponse.body);
        final branchMetaData = json.decode(branchMetaResponse.body);

        final file = FigmaFile.fromJson(branchMetaData['file']) // Base info from branch
          ..key = urlInfo.fileKey // IMPORTANT: Always use the main file key for navigation
          ..name = mainMetaData['file']['name'] // Overwrite name with the main file's name
          ..fileType = urlInfo.fileType
          ..branchName = branchMetaData['file']['name']; // The branch's name is the "name" from this response

        return file;
      } else {
        // For all other file types, a single call is enough.
        final metaUri = Uri.parse('$apiBaseUrl/files/${urlInfo.fileKey}/meta');
        debugPrint("[getFullFileInfo] Requesting single meta URL for ${urlInfo.fileType}: $metaUri");

        final metaResponse = await _getWithTimeout(metaUri, headers);
        if (metaResponse.statusCode != 200) throw Exception('Ошибка Figma API (meta). Статус: ${metaResponse.statusCode}');

        final metaData = json.decode(metaResponse.body);
        final file = FigmaFile.fromJson(metaData['file'])
          ..key = urlInfo.fileKey
          ..fileType = urlInfo.fileType;
        return file;
      }
    } on TimeoutException {
      debugPrint("[getFullFileInfo] Timeout for key ${urlInfo.fileKey}");
      throw Exception('Тайм-аут запроса к Figma API для файла ${urlInfo.fileKey}.');
    } catch (e) {
      debugPrint("[getFullFileInfo] Generic error for key ${urlInfo.fileKey}: $e");
      rethrow;
    }
  }
}