import 'package:figma_bckp/screens/home_screen.dart';
import 'package:figma_bckp/services/figma_api_service.dart';
import 'package:figma_bckp/services/logging_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggingService().init();
  
  runApp(
    MultiProvider(
      providers: [
        Provider<SettingsService>(
          create: (_) => SettingsService(),
        ),
        Provider<FigmaApiService>(
          create: (_) => FigmaApiService(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Figma Backup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}