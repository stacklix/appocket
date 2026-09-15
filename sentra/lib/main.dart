import 'package:flutter/material.dart';
import 'core/api.dart';
import 'core/controller.dart';
import 'core/storage.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    storage: LocalStorage(),
    gateway: DirectAiGateway(),
  );
  runApp(SentraApp(controller: controller));
  controller.initialize();
}

const ink = Color(0xFF243E35);
const paper = Color(0xFFF7F7F0);
const muted = Color(0xFF7C857D);

class SentraApp extends StatelessWidget {
  const SentraApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Sentra',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansCJK',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        primary: ink,
        surface: paper,
      ),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 15, height: 1.6),
        bodyLarge: TextStyle(color: ink, fontSize: 17, height: 1.6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(18),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE3E7DD), space: 32),
    ),
    home: HomePage(controller: controller),
  );
}
