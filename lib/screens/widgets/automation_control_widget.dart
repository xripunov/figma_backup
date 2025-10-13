import 'package:flutter/material.dart';

class AutomationControlWidget extends StatelessWidget {
  final String description;
  final VoidCallback onPressed;

  const AutomationControlWidget({
    super.key,
    required this.description,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Автоматический бэкап',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onPressed,
            child: const Text('Настроить'),
          ),
        ],
      ),
    );
  }
}

