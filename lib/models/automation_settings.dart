import 'package:flutter/material.dart';

enum Frequency { off, daily, weekly, monthly }

class AutomationSettings {
  final Frequency frequency;
  final List<int>? weekdays; // 1 for Monday, 7 for Sunday
  final int? dayOfMonth;
  final String time; // "HH:mm"

  const AutomationSettings({
    required this.frequency,
    this.weekdays,
    this.dayOfMonth,
    required this.time,
  });

  const AutomationSettings.off()
      : frequency = Frequency.off,
        weekdays = null,
        dayOfMonth = null,
        time = '00:00';

  factory AutomationSettings.fromJson(Map<String, dynamic> json) {
    return AutomationSettings(
      frequency: Frequency.values[json['frequency'] ?? 0],
      weekdays: json['weekdays'] != null ? List<int>.from(json['weekdays']) : null,
      dayOfMonth: json['dayOfMonth'],
      time: json['time'] ?? '20:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frequency': frequency.index,
      'weekdays': weekdays,
      'dayOfMonth': dayOfMonth,
      'time': time,
    };
  }

  AutomationSettings copyWith({
    Frequency? frequency,
    List<int>? weekdays,
    int? dayOfMonth,
    String? time,
  }) {
    return AutomationSettings(
      frequency: frequency ?? this.frequency,
      weekdays: weekdays ?? this.weekdays,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      time: time ?? this.time,
    );
  }

  String toDescription() {
    if (frequency == Frequency.off) {
      return 'Автоматизация выключена';
    }

    final timeStr = 'в $time';
    switch (frequency) {
      case Frequency.daily:
        return 'Каждый день $timeStr';
      case Frequency.weekly:
        if (weekdays == null || weekdays!.isEmpty) return 'Еженедельно (дни не выбраны) $timeStr';
        final days = weekdays!.map((d) {
          switch (d) {
            case 1: return 'Пн';
            case 2: return 'Вт';
            case 3: return 'Ср';
            case 4: return 'Чт';
            case 5: return 'Пт';
            case 6: return 'Сб';
            case 7: return 'Вс';
            default: return '';
          }
        }).join(', ');
        return 'Каждую неделю ($days) $timeStr';
      case Frequency.monthly:
        if (dayOfMonth == null) return 'Ежемесячно (день не выбран) $timeStr';
        return 'Каждое ${dayOfMonth}е число месяца $timeStr';
      default:
        return 'Автоматизация выключена';
    }
  }

  TimeOfDay get timeOfDay {
    try {
      final parts = time.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 20, minute: 0);
    }
  }
}
