import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Shared tokens: Forui is the source of truth; existing Material forms inherit
/// the same palette so their behaviour can be retained during the migration.
abstract final class TrafficTokens {
  static const brand = Color(0xff007c78);
  static const radius = 20.0;
  static const page = 20.0;
  static const gap = 12.0;
  static const motion = Duration(milliseconds: 180);

  static final _light = _createForui(Brightness.light);
  static final _dark = _createForui(Brightness.dark);
  static FThemeData forui(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static FThemeData _createForui(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = dark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
    return FThemeData(
      touch: true,
      colors: base.colors.copyWith(
        primary: dark ? const Color(0xff78d8ce) : brand,
        primaryForeground: dark ? const Color(0xff003c3a) : Colors.white,
        background: dark ? const Color(0xff101918) : const Color(0xfff5f8f7),
        foreground: dark ? const Color(0xffedf5f3) : const Color(0xff162b29),
      ),
      typography: base.typography.copyWith(
        body: FTypeface.inherit(
          colors: base.colors,
          touch: true,
          fontFamily: 'Roboto',
        ),
        display: FTypeface.inherit(
          colors: base.colors,
          touch: true,
          fontFamily: 'Roboto',
        ),
      ),
      style: base.style.copyWith(
        borderRadius: const FBorderRadius(
          lg: BorderRadius.all(Radius.circular(radius)),
        ),
      ),
    );
  }

  static final _materialLight = _createMaterial(Brightness.light);
  static final _materialDark = _createMaterial(Brightness.dark);
  static ThemeData material(Brightness brightness) =>
      brightness == Brightness.dark ? _materialDark : _materialLight;

  static ThemeData _createMaterial(Brightness brightness) {
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
          primary: dark ? const Color(0xff78d8ce) : brand,
          onPrimary: dark ? const Color(0xff003c3a) : Colors.white,
          surface: dark ? const Color(0xff15211f) : Colors.white,
        );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: forui(brightness).colors.background,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: forui(brightness).colors.background,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: colors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: .6),
        space: 28,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        elevation: 0,
        height: 74,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class TrafficDesignScope extends StatelessWidget {
  final Widget child;
  const TrafficDesignScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) => FTheme(
    data: TrafficTokens.forui(Theme.of(context).brightness),
    child: child,
  );
}
