import 'package:figma_bckp/models/figma_url_info.dart';

class FigmaFile {
  String key;
  String name;
  String lastModified;
  String projectName;
  FigmaFileType fileType;
  String? branchId;
  String? branchName;

  FigmaFile({
    required this.key,
    required this.name,
    required this.lastModified,
    required this.projectName,
    this.fileType = FigmaFileType.design,
    this.branchId,
    this.branchName,
  });

  factory FigmaFile.fromJson(Map<String, dynamic> json) {
    // Data from the main /files/:key endpoint is the document object itself
    // Data from the /meta endpoint is nested in json['file']
    final fileData = json.containsKey('file') ? json['file'] : json;
    if (fileData == null) throw Exception('Invalid API response structure');

    return FigmaFile(
      key: '', // Key is set later
      name: fileData['name'] ?? 'Без имени',
      lastModified: json['last_touched_at'] ?? '', // From /meta response
      projectName: fileData['folder_name'] ?? '', // From /meta response, might be empty
    );
  }

  factory FigmaFile.fromJsonCache(Map<String, dynamic> json) {
    return FigmaFile(
      key: json['key'] ?? '',
      name: json['name'] ?? 'Без имени',
      lastModified: json['lastModified'] ?? '',
      projectName: json['projectName'] ?? 'Без проекта',
      fileType: FigmaFileType.values.firstWhere(
        (e) => e.toString() == json['fileType'],
        orElse: () => FigmaFileType.design,
      ),
      branchId: json['branchId'],
      branchName: json['branchName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'lastModified': lastModified,
      'projectName': projectName,
      'fileType': fileType.toString(),
      'branchId': branchId,
      'branchName': branchName,
    };
  }
}