import 'package:flutter/material.dart';

import 'ios_theme.dart';

/// 应用主题：亮/暗两套 Material 3 主题
///
/// DESIGN.md：冷石墨中性色 + teal 强调，深浅同等第一公民。
/// 颜色/间距/圆角全部取自 [IosPalette]/[IosTheme]，
/// 这里只做 Material 主题的组装，不新增色值。
class AppTheme {
  const AppTheme._();

  /// 设计字阶（DESIGN.md §4：正文 1.5 行高，UI 标签 1.2）
  static TextTheme _textTheme(IosPalette p) => TextTheme(
        displayLarge: TextStyle(
            fontSize: IosType.largeTitle,
            fontWeight: FontWeight.w600,
            color: p.label,
            letterSpacing: -0.8),
        titleLarge: TextStyle(
            fontSize: IosType.title1,
            fontWeight: FontWeight.w600,
            color: p.label,
            letterSpacing: -0.5),
        titleMedium: TextStyle(
            fontSize: IosType.title2,
            fontWeight: FontWeight.w600,
            color: p.label,
            letterSpacing: -0.4),
        titleSmall: TextStyle(
            fontSize: IosType.title3,
            fontWeight: FontWeight.w600,
            color: p.label,
            letterSpacing: -0.3),
        bodyLarge: TextStyle(
            fontSize: IosType.callout,
            fontWeight: FontWeight.w400,
            color: p.label,
            height: 1.5),
        bodyMedium: TextStyle(
            fontSize: IosType.body,
            fontWeight: FontWeight.w400,
            color: p.label,
            height: 1.5),
        bodySmall: TextStyle(
            fontSize: IosType.footnotePlus,
            fontWeight: FontWeight.w400,
            color: p.label2,
            height: 1.4),
        labelLarge: TextStyle(
            fontSize: IosType.body,
            fontWeight: FontWeight.w500,
            color: p.label,
            height: 1.2),
        labelMedium: TextStyle(
            fontSize: IosType.footnote,
            fontWeight: FontWeight.w400,
            color: p.label2,
            height: 1.2),
        labelSmall: TextStyle(
            fontSize: IosType.caption,
            fontWeight: FontWeight.w400,
            color: p.label3,
            height: 1.2),
      );

  static ThemeData _base(IosPalette p) {
    final text = _textTheme(p);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.isDark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        secondary: p.accent,
        surface: p.surface,
        onSurface: p.label,
        error: p.bad,
        onError: p.onAccent,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.label,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.label,
          fontSize: IosType.title3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        backgroundColor: p.surface.withValues(alpha: p.isDark ? 0.96 : 0.94),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: p.accent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: p.label2,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: p.accent, size: 22);
          }
          return IconThemeData(color: p.label2, size: 22);
        }),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusCard),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.isDark ? p.surface2 : p.fill;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return p.label3;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface2,
        hintStyle: TextStyle(color: p.label3, fontSize: IosType.body),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: IosTheme.spaceM,
          vertical: IosTheme.spaceM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusInput),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.fill,
        selectedColor: p.accentSoft,
        labelStyle: TextStyle(color: p.label, fontSize: IosType.footnotePlus),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusPill),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 0.5,
        color: p.separator,
        space: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF23262C),
        contentTextStyle: const TextStyle(
          color: Color(0xFFF0F2F5),
          fontSize: IosType.body,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.elevated,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IosTheme.radiusM),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF23262C),
          borderRadius: BorderRadius.circular(IosTheme.radiusS),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFF0F2F5),
          fontSize: IosType.footnotePlus,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    );
  }

  static ThemeData light() => _base(IosPalette.light);

  static ThemeData dark() => _base(IosPalette.dark);
}
