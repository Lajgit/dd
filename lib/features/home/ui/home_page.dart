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
  final List<Widget?> _pages = List<Widget?>.filled(3, null);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex < 0
        ? 0
        : widget.initialIndex > 2
            ? 2
            : widget.initialIndex;
    _ensurePage(_selectedIndex);
  }

  void _ensurePage(int index) {
    if (index == 0) {
      _pages[0] = MemoryOverviewPage(
        key: ValueKey<int>(_memoryRefreshToken),
        refreshToken: _memoryRefreshToken,
        onOpenImport: _openImport,
        onOpenAi: _openAi,
      );
      return;
    }
    if (_pages[index] != null) return;
    _pages[index] = switch (index) {
      1 => LocalAiSummaryPage(onSummariesChanged: _handleSummariesChanged),
      _ => ImportPage(
          onImported: _handleImported,
          onOpenMemories: _openMemories,
        ),
    };
  }

  void _refreshMemories() {
    _memoryRefreshToken += 1;
    if (_pages[0] != null) _ensurePage(0);
  }

  void _handleImported() {
    setState(_refreshMemories);
  }

  void _handleSummariesChanged() {
    setState(_refreshMemories);
  }

  void _openMemories() {
    setState(() {
      _refreshMemories();
      _selectedIndex = 0;
      _ensurePage(0);
    });
  }

  void _openAi() {
    setState(() {
      _selectedIndex = 1;
      _ensurePage(1);
    });
  }

  void _openImport() {
    setState(() {
      _selectedIndex = 2;
      _ensurePage(2);
    });
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _ensurePage(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _pages[0] ?? const SizedBox.shrink(),
          _pages[1] ?? const SizedBox.shrink(),
          _pages[2] ?? const SizedBox.shrink(),
        ],
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
          onDestinationSelected: _selectTab,
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
