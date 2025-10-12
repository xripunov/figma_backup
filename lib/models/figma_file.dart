// lib/models/figma_file.dart

import 'dart:convert';

class FigmaFile {
  String key;
  final String name;
  final String lastModified;
  final String projectName; // <-- НОВОЕ ПОЛЕ

  FigmaFile({
    required this.key,
    required this.name,
    required this.lastModified,
    required this.projectName, // <-- ОБНОВЛЯЕМ КОНСТРУКТОР
  });

  // Конструктор для парсинга ответа от Figma API (.../meta)
  factory FigmaFile.fromJson(Map<String, dynamic> json) {
    // Данные теперь вложены в ключ "file"
    final fileData = json['file'];
    if (fileData == null) throw Exception('Invalid API response structure');

    return FigmaFile(
      key: '', // Ключ будет установлен позже
      name: fileData['name'] ?? 'Без имени',
      // API /meta отдает 'last_touched_at'
      lastModified: fileData['last_touched_at'] ?? '',
      // API /meta отдает 'folder_name'
      projectName: fileData['folder_name'] ?? 'Без проекта',
    );
  }

  // Конструктор для парсинга из нашего кэша
  factory FigmaFile.fromJsonCache(Map<String, dynamic> json) {
    return FigmaFile(
      key: json['key'] ?? '',
      name: json['name'] ?? 'Без имени',
      lastModified: json['lastModified'] ?? '',
      projectName: json['projectName'] ?? 'Без проекта', // <-- ДЛЯ КЭША
    );
  }

  // Метод для преобразования объекта в Map для сохранения в кэш
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'lastModified': lastModified,
      'projectName': projectName, // <-- ДЛЯ КЭША
    };
  }
}