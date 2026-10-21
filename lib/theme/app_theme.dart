import 'package:flutter/material.dart';

import 'ios_theme.dart';

/// 应用主题：亮/暗两套 Material 3 主题
///
/// 从 main.dart 抽出：入口文件只负责启动与 Provider 装配，
/// 主题细节集中在这里，改配色不用翻入口文件。
///
/// 颜色/间距/圆角全部取自 [IosTheme]（低饱和度极简风格），
/// 这里只做 Material 主题的组装，不新增色值。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => ThemeData(
        colorSchemeSeed: IosTheme.iosBlue,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: IosTheme.iosGroupedBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: IosTheme.iosGroupedBg,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 56,
          backgroundColor: Colors.white.withValues(alpha: 0.94),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          indicatorColor: IosTheme.iosBlue.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              );
            }
            return TextStyle(
              color: IosTheme.iosGray,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: IosTheme.iosBlue, size: 22);
            }
            return const IconThemeData(color: IosTheme.iosGray, size: 22);
          }),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IosTheme.iosGreen;
            }
            return IosTheme.iosGray3;
          }),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        dividerTheme: const DividerThemeData(
          thickness: 0.5,
          color: Color(0xFFC6C6C8),
          space: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusM),
          ),
        ),
      );

  static ThemeData dark() => ThemeData(
        colorSchemeSeed: IosTheme.iosBlue,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: IosTheme.iosDarkGroupedBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: IosTheme.iosDarkGroupedBg,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 56,
          backgroundColor: const Color(0xFF1C1C1E).withValues(alpha: 0.94),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          indicatorColor: IosTheme.iosBlue.withValues(alpha: 0.24),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: IosTheme.iosBlue,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              );
            }
            return TextStyle(
              color: IosTheme.iosGray2,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: IosTheme.iosBlue, size: 22);
            }
            return const IconThemeData(color: IosTheme.iosGray2, size: 22);
          }),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C1C1E),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusCard),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IosTheme.iosGreen;
            }
            return IosTheme.iosGray;
          }),
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: IosTheme.spaceL),
        ),
        dividerTheme: const DividerThemeData(
          thickness: 0.5,
          color: Color(0xFF38383A),
          space: 0.5,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2C2C2E),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusS),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF2C2C2E),
          elevation: 20,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IosTheme.radiusM),
          ),
        ),
      );
}
