import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Shared tokens: Forui is the source of truth; existing Material forms inherit
/// the same palette so their behaviour can be retained during the migration.
abstract final class TrafficTokens {
  static const fontFamily = 'PlusJakartaSans';
  static const fontFallback = <String>[];
  static const brand = Color(0xff20252b);
  static const lime = Color(0xffc6f36b);
  static const limeBright = Color(0xffd9fa84);
  static const radius = 24.0;
  static const page = 20.0;
  static const gap = 12.0;
  static const motion = Duration(milliseconds: 280);
  static Color blue(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? const Color(0xff9cc9ff)
      : const Color(0xff2366b5);
  static Color amber(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? const Color(0xffffcf87)
      : const Color(0xff995700);

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
        primary: dark ? const Color(0xffc6f36b) : brand,
        primaryForeground: dark ? const Color(0xff171c24) : Colors.white,
        background: dark ? const Color(0xff14171b) : const Color(0xfff5f6f2),
        card: dark ? const Color(0xff20252b) : Colors.white,
        secondary: dark ? const Color(0xff30362c) : const Color(0xffeaeee6),
        secondaryForeground: dark
            ? const Color(0xffd9fa84)
            : const Color(0xff20252b),
        border: dark ? const Color(0xff3b423b) : const Color(0xffe4e8e0),
        foreground: dark ? const Color(0xfff5f6f2) : const Color(0xff171c24),
      ),
      typography: base.typography.copyWith(
        body: _typeface(base.colors, false),
        display: _typeface(base.colors, true),
      ),
      style: base.style.copyWith(
        borderRadius: const FBorderRadius(
          lg: BorderRadius.all(Radius.circular(radius)),
        ),
      ),
    );
  }

  static FTypeface _typeface(FColors colors, bool display) {
    final type = FTypeface.inherit(
      colors: colors,
      touch: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    return type.copyWith(
      xs3: type.xs3.copyWith(fontWeight: FontWeight.w500),
      xl4: type.xl4.copyWith(fontWeight: FontWeight.w700),
      xl5: type.xl5.copyWith(fontWeight: FontWeight.w700),
      xl6: type.xl6.copyWith(fontWeight: FontWeight.w700),
      xl7: type.xl7.copyWith(fontWeight: FontWeight.w700),
      xl8: type.xl8.copyWith(fontWeight: FontWeight.w700),
      xs2: type.xs2.copyWith(fontWeight: FontWeight.w600),
      xs: type.xs.copyWith(fontWeight: FontWeight.w500),
      sm: type.sm.copyWith(fontWeight: FontWeight.w500),
      md: type.md.copyWith(fontWeight: FontWeight.w600),
      lg: type.lg.copyWith(fontWeight: FontWeight.w700),
      xl: type.xl.copyWith(fontWeight: FontWeight.w700),
      xl2: type.xl2.copyWith(fontWeight: FontWeight.w700),
      xl3: type.xl3.copyWith(fontWeight: FontWeight.w700),
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
          primary: dark ? const Color(0xffc6f36b) : brand,
          onPrimary: dark ? const Color(0xff171c24) : Colors.white,
          surface: dark ? const Color(0xff20252b) : Colors.white,
          onSurface: dark ? const Color(0xfff5f6f2) : const Color(0xff171c24),
          onSurfaceVariant: dark
              ? const Color(0xffb7bfaf)
              : const Color(0xff596477),
          outlineVariant: dark
              ? const Color(0xff3b423b)
              : const Color(0xffe4e8e0),
          primaryContainer: dark ? const Color(0xff384527) : lime,
          onPrimaryContainer: dark ? limeBright : const Color(0xff171c24),
          secondaryContainer: dark
              ? const Color(0xff30362c)
              : const Color(0xffeaeee6),
          secondary: dark ? const Color(0xff9cc9ff) : const Color(0xff2366b5),
          tertiary: dark ? const Color(0xffffcf87) : const Color(0xff995700),
        );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return base.copyWith(
      colorScheme: colors,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
      ),
      scaffoldBackgroundColor: forui(brightness).colors.background,
      textTheme: base.textTheme
          .copyWith(
            bodyLarge: const TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
            bodyMedium: const TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
            bodySmall: const TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
            titleMedium: const TextStyle(
              fontSize: 18,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: const TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
            headlineSmall: const TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
            headlineMedium: const TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
            labelSmall: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            labelMedium: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            displaySmall: const TextStyle(
              fontSize: 36,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
            displayMedium: const TextStyle(
              fontSize: 45,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
            displayLarge: const TextStyle(
              fontSize: 57,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
            labelLarge: const TextStyle(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            bodyColor: colors.onSurface,
            displayColor: colors.onSurface,
          ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: colors.onSurfaceVariant,
        indicatorColor: colors.primary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: forui(brightness).colors.background,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: colors.onSurface,
          fontSize: 26,
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
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          minimumSize: const Size(48, 48),
        ),
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
        indicatorColor: colors.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
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
