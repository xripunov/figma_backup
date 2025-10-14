import 'package:figma_bckp/models/figma_url_info.dart';

class BackupItem {
  final String key; // Ключ файла для скачивания
  final String mainFileName; // Имя файла (для создания папки/файла)
  final String lastModified;
  final String projectName;
  final String? branchId;
  final String? branchName;
  final FigmaFileType fileType;

  String get uniqueId => branchId != null ? '${key}_$branchId' : key;

  BackupItem({
    required this.key,
    required this.mainFileName,
    required this.lastModified,
    required this.projectName,
    this.branchId,
    this.branchName,
    this.fileType = FigmaFileType.design,
  });

  factory BackupItem.fromOnlyKey(String key) {
    return BackupItem(
      key: key,
      mainFileName: '',
      lastModified: '',
      projectName: '',
      fileType: FigmaFileType.design, // Default value
    );
  }

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      key: json['key'],
      mainFileName: json['mainFileName'] ?? '',
      lastModified: json['lastModified'] ?? '',
      projectName: json['projectName'] ?? '',
      branchId: json['branchId'],
      branchName: json['branchName'],
      fileType: FigmaFileType.values.firstWhere(
        (e) => e.toString() == json['fileType'],
        orElse: () => FigmaFileType.design,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'mainFileName': mainFileName,
      'lastModified': lastModified,
      'projectName': projectName,
      'branchId': branchId,
      'branchName': branchName,
      'fileType': fileType.toString(),
    };
  }
}