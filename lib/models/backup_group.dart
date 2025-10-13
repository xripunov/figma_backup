import 'package:figma_bckp/models/automation_settings.dart';
import 'package:figma_bckp/models/backup_item.dart';
import 'package:uuid/uuid.dart';

class BackupGroup {
  String id;
  String name;
  List<BackupItem> items;
  DateTime? lastBackup;
  final AutomationSettings automationSettings;

  BackupGroup({
    String? id,
    required this.name,
    List<BackupItem>? items,
    this.lastBackup,
    this.automationSettings = const AutomationSettings.off(),
  })  : id = id ?? const Uuid().v4(),
        items = items ?? [];

  factory BackupGroup.fromJson(Map<String, dynamic> json) {
    // --- BACKWARDS COMPATIBILITY ---
    // If old fields exist, migrate them to the new structure.
    if (json.containsKey('isAutomationEnabled')) {
      final isEnabled = json['isAutomationEnabled'] ?? false;
      if (isEnabled && json['automationTime'] != null) {
        return BackupGroup(
          id: json['id'],
          name: json['name'],
          items: (json['items'] as List)
              .map((itemJson) => BackupItem.fromJson(itemJson))
              .toList(),
          lastBackup: json['lastBackup'] != null
              ? DateTime.tryParse(json['lastBackup'])
              : null,
          automationSettings: AutomationSettings(
            frequency: Frequency.daily,
            time: json['automationTime'],
          ),
        );
      }
    }
    // --- END COMPATIBILITY ---

    return BackupGroup(
      id: json['id'],
      name: json['name'],
      items: (json['items'] as List)
          .map((itemJson) => BackupItem.fromJson(itemJson))
          .toList(),
      lastBackup: json['lastBackup'] != null
          ? DateTime.tryParse(json['lastBackup'])
          : null,
      automationSettings: json['automationSettings'] != null
          ? AutomationSettings.fromJson(json['automationSettings'])
          : const AutomationSettings.off(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'items': items.map((item) => item.toJson()).toList(),
      'lastBackup': lastBackup?.toIso8601String(),
      'automationSettings': automationSettings.toJson(),
    };
  }

  BackupGroup copyWith({
    String? id,
    String? name,
    List<BackupItem>? items,
    DateTime? lastBackup,
    AutomationSettings? automationSettings,
  }) {
    return BackupGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      lastBackup: lastBackup ?? this.lastBackup,
      automationSettings: automationSettings ?? this.automationSettings,
    );
  }
}

