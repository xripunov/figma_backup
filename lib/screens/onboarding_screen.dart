
import 'package:figma_bckp/screens/home_screen.dart';
import 'package:figma_bckp/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _tokenController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveToken() async {
    if (_tokenController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, введите API токен.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final settingsService = Provider.of<SettingsService>(context, listen: false);
    await settingsService.saveToken(_tokenController.text.trim());

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Figma Backup',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Для начала работы, пожалуйста, введите ваш персональный API токен из Figma.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Figma API Token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveToken,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text('Сохранить и продолжить'),
                ),
                const SizedBox(height: 48),
                const Text(
                  '''Как получить API токен:
1. Откройте Figma и перейдите в «Settings» -> «Security».
2. В разделе «Personal access tokens» создайте новый токен.
3. ВАЖНО: в списке «Scopes» выберите:
   • Files: file_metadata:read
   • Projects: projects:read
4. Скопируйте токен и вставьте его сюда.''',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
