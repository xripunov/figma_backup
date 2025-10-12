// lib/models/figma_project.dart
import 'figma_file.dart'; // <-- Добавляем импорт

class FigmaProject {
  final String id;
  final String name;
  List<FigmaFile> files; // <-- Добавляем это поле

  FigmaProject({required this.id, required this.name, this.files = const []});

  factory FigmaProject.fromJson(Map<String, dynamic> json) {
    return FigmaProject(
      id: json['id'].toString(),
      name: json['name'],
    );
  }
}