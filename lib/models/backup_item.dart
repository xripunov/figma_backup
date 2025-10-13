class BackupItem {
  final String key; // Ключ файла для скачивания
  final String mainFileName; // Имя файла (для создания папки/файла)
  final String lastModified;
  final String projectName; // <-- НОВОЕ ПОЛЕ

  BackupItem({
    required this.key,
    required this.mainFileName,
    required this.lastModified,
    required this.projectName, // <-- ОБНОВЛЯЕМ КОНСТРУКТОР
  });

  factory BackupItem.fromOnlyKey(String key) {
    return BackupItem(
      key: key,
      mainFileName: '',
      lastModified: '',
      projectName: '',
    );
  }

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      key: json['key'],
      mainFileName: json['mainFileName'] ?? '',
      lastModified: json['lastModified'] ?? '',
      projectName: json['projectName'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'mainFileName': mainFileName,
      'lastModified': lastModified,
      'projectName': projectName,
    };
  }
}