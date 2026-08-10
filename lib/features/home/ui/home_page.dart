import 'package:flutter/material.dart';

import '../../import/ui/import_page.dart';
import '../../memories/ui/local_ai_summary_page.dart';
import '../../memories/ui/memory_overview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex;
  int _memoryRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex < 0
        ? 0
        : widget.initialIndex > 2
            ? 2
            : widget.initialIndex;
  }

  void _handleImported() {
    setState(() => _memoryRefreshToken += 1);
  }

  void _openMemories() {
    setState(() {
      _memoryRefreshToken += 1;
      _selectedIndex = 0;
    });
  }

  void _openAi() {
    setState(() => _selectedIndex = 1);
  }

  void _openImport() {
    setState(() => _selectedIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      MemoryOverviewPage(
        refreshToken: _memoryRefreshToken,
        onOpenImport: _openImport,
        onOpenAi: _openAi,
      ),
      const LocalAiSummaryPage(),
      ImportPage(
        onImported: _handleImported,
        onOpenMemories: _openMemories,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.48),
            ),
          ),
        ),
        child: NavigationBar(
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
              label: '总结',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_rounded),
              selectedIcon: Icon(Icons.add_circle_rounded),
              label: '导入',
            ),
          ],
        ),
      ),
    );
  }
}
