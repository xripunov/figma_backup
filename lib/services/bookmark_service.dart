import 'package:flutter/services.dart';

class BookmarkService {
  static const _channel = MethodChannel('com.figma_bckp/bookmark');

  Future<String?> createBookmark(String path) async {
    try {
      final String? bookmark = await _channel.invokeMethod('createBookmark', {'path': path});
      return bookmark;
    } on PlatformException catch (e) {
      print("Failed to create bookmark: '${e.message}'.");
      return null;
    }
  }

  Future<bool> resolveBookmark(String bookmark) async {
    try {
      final bool result = await _channel.invokeMethod('resolveBookmark', {'bookmark': bookmark});
      return result;
    } on PlatformException catch (e) {
      print("Failed to resolve bookmark: '${e.message}'.");
      return false;
    }
  }
}
