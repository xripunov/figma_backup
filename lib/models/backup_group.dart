import 'package:figma_bckp/models/backup_item.dart';
import 'package:uuid/uuid.dart';

class BackupGroup {
  String id;
  String name;
  List<BackupItem> items;
  DateTime? lastBackup;

  BackupGroup({
    String? id,
    required this.name,
    this.items = const [],
    this.lastBackup,
  }) : id = id ?? const Uuid().v4();

  factory BackupGroup.fromJson(Map<String, dynamic> json) {
    return BackupGroup(
      id: json['id'],
      name: json['name'],
      items: (json['items'] as List)
          .map((itemJson) => BackupItem.fromJson(itemJson))
          .toList(),
      lastBackup: json['lastBackup'] != null
          ? DateTime.tryParse(json['lastBackup'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((item) => item.toJson()).toList(),
      'lastBackup': lastBackup?.toIso8601String(),
    };
  }
}
