import 'package:flutter/material.dart';

import '../features/import/ui/import_page.dart';

class DiandiMemoryApp extends StatelessWidget {
  const DiandiMemoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '点滴记忆',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F6F5F)),
        useMaterial3: true,
      ),
      home: const ImportPage(),
    );
  }
}
