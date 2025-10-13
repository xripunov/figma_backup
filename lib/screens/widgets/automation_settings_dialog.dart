import 'package:figma_bckp/models/automation_settings.dart';
import 'package:flutter/material.dart';

class AutomationSettingsDialog extends StatefulWidget {
  final AutomationSettings initialSettings;

  const AutomationSettingsDialog({super.key, required this.initialSettings});

  @override
  State<AutomationSettingsDialog> createState() => _AutomationSettingsDialogState();
}

class _AutomationSettingsDialogState extends State<AutomationSettingsDialog> {
  late Frequency _frequency;
  late TimeOfDay _time;
  late List<int> _selectedWeekdays;
  late int _dayOfMonth;

  @override
  void initState() {
    super.initState();
    _frequency = widget.initialSettings.frequency;
    _time = widget.initialSettings.timeOfDay;
    _selectedWeekdays = List<int>.from(widget.initialSettings.weekdays ?? []);
    _dayOfMonth = widget.initialSettings.dayOfMonth ?? 1;
  }

  void _onSave() {
    if (_frequency == Frequency.weekly && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, выберите хотя бы один день недели.')),
      );
      return;
    }

    // Sort weekdays before saving
    if (_frequency == Frequency.weekly) {
      _selectedWeekdays.sort();
    }

    final newSettings = AutomationSettings(
      frequency: _frequency,
      time: '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      weekdays: _frequency == Frequency.weekly ? _selectedWeekdays : null,
      dayOfMonth: _frequency == Frequency.monthly ? _dayOfMonth : null,
    );
    Navigator.of(context).pop(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настроить расписание'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Frequency>(
              value: _frequency,
              onChanged: (Frequency? newValue) {
                setState(() {
                  _frequency = newValue!;
                });
              },
              items: const [
                DropdownMenuItem(value: Frequency.off, child: Text('Выключено')),
                DropdownMenuItem(value: Frequency.daily, child: Text('Ежедневно')),
                DropdownMenuItem(value: Frequency.weekly, child: Text('Еженедельно')),
                DropdownMenuItem(value: Frequency.monthly, child: Text('Ежемесячно')),
              ],
              decoration: const InputDecoration(labelText: 'Частота'),
            ),
            if (_frequency != Frequency.off) ...[
              const SizedBox(height: 20),
              _buildFrequencySpecificControls(),
              const SizedBox(height: 20),
              ListTile(
                title: const Text('Время выполнения'),
                subtitle: Text(_time.format(context)),
                onTap: () async {
                  final newTime = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (newTime != null) {
                    setState(() {
                      _time = newTime;
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildFrequencySpecificControls() {
    switch (_frequency) {
      case Frequency.weekly:
        return _buildWeekdaySelector();
      case Frequency.monthly:
        return _buildMonthDaySelector();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWeekdaySelector() {
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Дни недели', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: List.generate(7, (index) {
            final dayIndex = index + 1;
            final isSelected = _selectedWeekdays.contains(dayIndex);
            return FilterChip(
              label: Text(days[index]),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedWeekdays.add(dayIndex);
                  } else {
                    _selectedWeekdays.remove(dayIndex);
                  }
                });
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMonthDaySelector() {
    return DropdownButtonFormField<int>(
      value: _dayOfMonth,
      onChanged: (int? newValue) {
        setState(() {
          _dayOfMonth = newValue!;
        });
      },
      items: List.generate(31, (index) {
        final day = index + 1;
        return DropdownMenuItem(
          value: day,
          child: Text('$day число'),
        );
      }),
      decoration: const InputDecoration(labelText: 'День месяца'),
    );
  }
}
