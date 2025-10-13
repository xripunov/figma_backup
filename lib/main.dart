import 'package:figma_bckp/screens/home_screen.dart';
import 'package:figma_bckp/screens/onboarding_screen.dart';
import 'package:figma_bckp/services/figma_api_service.dart';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggingService().init();

  final settingsService = SettingsService();
  final token = await settingsService.getToken();
  
  runApp(
    MultiProvider(
      providers: [
        Provider<SettingsService>(
          create: (_) => settingsService,
        ),
        Provider<FigmaApiService>(
          create: (_) => FigmaApiService(),
        ),
      ],
      child: MyApp(isTokenProvided: token != null && token.isNotEmpty),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isTokenProvided;
  const MyApp({super.key, required this.isTokenProvided});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Figma Backup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: isTokenProvided ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}