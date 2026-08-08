import 'package:flutter/material.dart';

import '../features/home/ui/home_page.dart';

class DiandiMemoryApp extends StatelessWidget {
  const DiandiMemoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFD6768D);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '点滴记忆',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFFFFAF7),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFFFF3F1),
          indicatorColor: colorScheme.primaryContainer,
          height: 72,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEAD9D5),
          thickness: 1,
        ),
      ),
      home: const HomePage(),
    );
  }
}
