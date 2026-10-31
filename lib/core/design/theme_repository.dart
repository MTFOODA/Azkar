import 'theme_settings.dart';

/// Contract for global or page-scoped appearance settings.
abstract class ThemeRepository {
  /// Loads the current settings, or `null` when the row is missing (for example
  /// on a fresh project before the seed migration ran).
  Future<ThemeSettings?> load();

  Future<ThemeSettings> save(ThemeSettings settings);
}
