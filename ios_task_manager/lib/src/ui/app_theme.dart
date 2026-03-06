import 'package:flutter/material.dart';

const appPagePadding = EdgeInsets.fromLTRB(18, 16, 18, 26);

ThemeData buildAppTheme() {
  const primary = Color(0xFF2D6F3A);
  const secondary = Color(0xFF20382B);
  const surface = Color(0xFFFFFFFF);
  const pageBackground = Color(0xFFEAF3E4);
  const text = Color(0xFF17241A);
  const outline = Color(0xFF9FB49F);
  const outlineSoft = Color(0xFFD8E5D8);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFCFE4C9),
        onPrimaryContainer: text,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFDCEADD),
        onSecondaryContainer: text,
        surface: surface,
        onSurface: text,
        outline: outline,
        outlineVariant: outlineSoft,
        surfaceContainerHighest: const Color(0xFFF4F8F2),
        surfaceContainerHigh: const Color(0xFFF7FBF5),
        error: const Color(0xFFBA1A1A),
      );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

  return base.copyWith(
    scaffoldBackgroundColor: pageBackground,
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(color: text),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(color: text),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: const Color(0xFF516451),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 58,
      backgroundColor: Colors.white.withValues(alpha: 0.96),
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x1F172A14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: outlineSoft, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FCF6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      labelStyle: const TextStyle(color: Color(0xFF506450)),
      hintStyle: const TextStyle(color: Color(0xFF718671)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: outlineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: outlineSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.4),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      side: const BorderSide(color: outlineSoft),
      backgroundColor: const Color(0xFFEFF6ED),
      selectedColor: const Color(0xFFD3E6D3),
      secondarySelectedColor: const Color(0xFFD3E6D3),
      checkmarkColor: text,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: text),
      secondaryLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white.withValues(alpha: 0.98),
      height: 70,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFFD9EBCD),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontWeight: FontWeight.w800,
            color: secondary,
            fontSize: 12,
            height: 1.0,
          );
        }
        return const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          height: 1.0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(size: 24, color: secondary);
        }
        return const IconThemeData(size: 23);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: secondary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: outline),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: secondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineSoft,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF11180D),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
  );
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFEAF3E4)),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x6688C75A), Color(0x0088C75A)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x554FAF66), Color(0x004FAF66)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33356B48), Color(0x00356B48)],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
