import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _voiceTextTheme = TextTheme(
  displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
  headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
  bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
);

abstract final class VoiceRecTheme {
  static ThemeData get light {
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF087D79),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF087D79),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFC6F1E8),
          onPrimaryContainer: const Color(0xFF084D49),
          secondary: const Color(0xFF5B67AB),
          surface: const Color(0xFFF3FAF8),
          onSurface: const Color(0xFF193B3A),
          onSurfaceVariant: const Color(0xFF526E6B),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF1F9F6),
          surfaceContainer: const Color(0xFFE9F4F0),
          surfaceContainerHigh: const Color(0xFFE1F0EB),
          surfaceContainerHighest: const Color(0xFFD7EAE4),
          outline: const Color(0xFF91AEA8),
          outlineVariant: const Color(0xFFC5DCD5),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      textTheme: _voiceTextTheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white.withValues(alpha: 0.42),
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFFF1F9F6),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.64),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.64),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.58),
        selectedColor: colors.primaryContainer.withValues(alpha: 0.85),
        labelStyle: TextStyle(color: colors.onSurface),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colors.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.64),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      dividerColor: colors.outlineVariant.withValues(alpha: 0.6),
    );
  }

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF20D4CF),
      brightness: Brightness.dark,
    ),
    textTheme: _voiceTextTheme,
    scaffoldBackgroundColor: const Color(0xFF061322),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF061322),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF0B1D30),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// Lives behind the Navigator so all screens share the same soft light canvas.
class VoiceRecBackdrop extends StatelessWidget {
  const VoiceRecBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF061322), Color(0xFF061322)]
              : const [Color(0xFFE0F4ED), Color(0xFFF8FCFA), Color(0xFFE8EEF9)],
        ),
      ),
      child: child,
    );
  }
}
