import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 皮肤定义:主色 + 渐变辅色。主色用于主按钮/选中态,
/// 渐变用于我方气泡、头部卡、关键按钮。
class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.primary,
    required this.accent,
  });

  final String id;
  final String name;
  final Color primary;
  final Color accent;

  LinearGradient get gradient =>
      LinearGradient(colors: [primary, accent], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

/// 内置皮肤(青春活力向)。
class Skins {
  static const melon = Skin(
    id: 'melon',
    name: '薄荷汽水',
    primary: Color(0xFF0EBB9C),
    accent: Color(0xFF5EE7C8),
  );
  static const soda = Skin(
    id: 'soda',
    name: '橘子汽水',
    primary: Color(0xFFFF7A3D),
    accent: Color(0xFFFFB74D),
  );
  static const blueberry = Skin(
    id: 'blueberry',
    name: '蓝莓气泡',
    primary: Color(0xFF4F7CFF),
    accent: Color(0xFF7FB5FF),
  );
  static const grape = Skin(
    id: 'grape',
    name: '葡萄碎冰',
    primary: Color(0xFF8B5CF6),
    accent: Color(0xFFC084FC),
  );
  static const peach = Skin(
    id: 'peach',
    name: '白桃乌龙',
    primary: Color(0xFFF0609E),
    accent: Color(0xFFFCA5C8),
  );
  static const forest = Skin(
    id: 'forest',
    name: '青提茉莉',
    primary: Color(0xFF4CAF50),
    accent: Color(0xFFA5D6A7),
  );

  static const all = [melon, soda, blueberry, grape, peach, forest];

  static Skin byId(String? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => melon);
}

/// 主题控制器:皮肤 + 明暗模式,持久化到本地。
class ThemeController extends ChangeNotifier {
  static const _keySkin = 'theme_skin';
  static const _keyMode = 'theme_mode';

  Skin _skin = Skins.melon;
  ThemeMode _mode = ThemeMode.system;

  Skin get skin => _skin;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _skin = Skins.byId(prefs.getString(_keySkin));
    _mode = ThemeMode.values[prefs.getInt(_keyMode) ?? 0];
    notifyListeners();
  }

  Future<void> setSkin(Skin skin) async {
    _skin = skin;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySkin, skin.id);
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, mode.index);
  }

  ThemeData light() => AppThemeFactory.build(_skin, Brightness.light);
  ThemeData dark() => AppThemeFactory.build(_skin, Brightness.dark);
}

/// 全局主题控制器实例(main.dart 初始化时 load)。
final themeController = ThemeController();

/// 统一组件语言:全应用所有页面共享这一套。
class AppThemeFactory {
  static ThemeData build(Skin skin, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: skin.primary,
      brightness: brightness,
    );

    final radius = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: scheme.surface,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
    );
  }
}
