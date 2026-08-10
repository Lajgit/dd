import 'package:flutter/material.dart';

import '../features/home/ui/home_page.dart';

class DiandiMemoryApp extends StatelessWidget {
  const DiandiMemoryApp({
    super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '点滴记忆',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomePage(initialIndex: initialIndex),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  const seed = Color(0xFF9F5366);
  final dark = brightness == Brightness.dark;
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  final colorScheme = generated.copyWith(
    surface: dark ? const Color(0xFF181315) : const Color(0xFFFFFBF8),
    surfaceContainerLowest: dark ? const Color(0xFF130F11) : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark ? const Color(0xFF211A1C) : const Color(0xFFFFF6F2),
    surfaceContainer: dark ? const Color(0xFF2A2225) : const Color(0xFFF8EEE9),
    outlineVariant: dark ? const Color(0xFF514348) : const Color(0xFFE8DAD5),
  );
  final baseTheme = ThemeData(
    colorScheme: colorScheme,
    brightness: brightness,
    scaffoldBackgroundColor: colorScheme.surface,
    useMaterial3: true,
  );

  return baseTheme.copyWith(
    textTheme: baseTheme.textTheme.copyWith(
      headlineLarge: baseTheme.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0,
      ),
      headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
      ),
      headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
      ),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: baseTheme.textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      height: 72,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return baseTheme.textTheme.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: states.contains(WidgetState.selected) ? 25 : 23,
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // 只约束按钮高度，不把全局最小宽度设为 Infinity；按钮可安全放入 Row/Wrap。
        minimumSize: const Size(0, 50),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.62)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
    ),
  );
}
