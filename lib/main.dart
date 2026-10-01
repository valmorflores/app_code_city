import 'package:flutter/material.dart';

import 'src/code_city_page.dart';

void main() {
  runApp(const CodeCityApp());
}

class CodeCityApp extends StatefulWidget {
  const CodeCityApp({super.key});

  @override
  State<CodeCityApp> createState() => _CodeCityAppState();
}

class _CodeCityAppState extends State<CodeCityApp> {
  ThemeMode _mode = ThemeMode.system;

  static ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: b,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cidade do Código',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: CodeCityPage(
        themeMode: _mode,
        onThemeModeChanged: (m) => setState(() => _mode = m),
      ),
    );
  }
}
