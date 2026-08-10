import 'package:flutter/material.dart';

import '../../import/ui/import_page.dart';
import '../../memories/ui/local_ai_summary_page.dart';
import '../../memories/ui/memory_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 2;
  int _memoryRefreshToken = 0;

  void _handleImported() {
    setState(() => _memoryRefreshToken += 1);
  }

  void _openMemories() {
    setState(() {
      _memoryRefreshToken += 1;
      _selectedIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_selectedIndex) {
      0 => MemoryPage(refreshToken: _memoryRefreshToken),
      1 => const LocalAiSummaryPage(),
      _ => ImportPage(
          onImported: _handleImported,
          onOpenMemories: _openMemories,
        ),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            if (index == 0) _memoryRefreshToken += 1;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: '回忆',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'AI总结',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box_rounded),
            label: '导入',
          ),
        ],
      ),
    );
  }
}
