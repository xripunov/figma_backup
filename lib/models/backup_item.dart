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
}