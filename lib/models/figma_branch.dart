// lib/models/figma_branch.dart

class FigmaBranch {
  final String key;
  final String name;
  final String lastModified;

  FigmaBranch({
    required this.key,
    required this.name,
    required this.lastModified,
  });

  factory FigmaBranch.fromJson(Map<String, dynamic> json) {
    return FigmaBranch(
      key: json['key'],
      name: json['name'],
      lastModified: json['last_modified'],
    );
  }
}