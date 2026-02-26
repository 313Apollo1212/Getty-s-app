import 'package:flutter/material.dart';

const appPagePadding = EdgeInsets.fromLTRB(16, 14, 16, 24);

ThemeData buildAppTheme() {
  const primary = Color(0xFF1F567D);
  const secondary = Color(0xFF5E7389);
  const surface = Color(0xFFFFFFFF);
  const pageBackground = Color(0xFFF2F6FB);
  const text = Color(0xFF1C2A38);
  const outline = Color(0xFFADB9C6);
  const outlineSoft = Color(0xFFD8E0EA);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFDCE9F7),
        onPrimaryContainer: text,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFE4ECF6),
        onSecondaryContainer: text,
        surface: surface,
        onSurface: text,
        outline: outline,
        outlineVariant: outlineSoft,
        error: const Color(0xFFBA1A1A),
      );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

  return base.copyWith(
    scaffoldBackgroundColor: pageBackground,
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(color: text),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(color: text),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: const Color(0xFF5A6A79),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.white.withValues(alpha: 0.92),
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x1A22405B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: outlineSoft),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7FAFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelStyle: const TextStyle(color: Color(0xFF556676)),
      hintStyle: const TextStyle(color: Color(0xFF7A8A99)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outlineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outlineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.4),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: const BorderSide(color: outlineSoft),
      backgroundColor: const Color(0xFFF0F5FB),
      selectedColor: const Color(0xFFDCE9F7),
      secondarySelectedColor: const Color(0xFFDCE9F7),
      checkmarkColor: text,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: text),
      secondaryLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFDCE9F7),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontWeight: FontWeight.w700, color: primary);
        }
        return const TextStyle(fontWeight: FontWeight.w600);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineSoft,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF22384F),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9FCFF), Color(0xFFEDF3FA)],
        ),
      ),
      child: child,
    );
  }
}
