/// Spacing and radius scale used everywhere instead of magic numbers.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Horizontal padding of every screen.
  static const screen = 20.0;

  /// Minimum size of anything tappable.
  static const minTouch = 48.0;
}

abstract final class AppRadii {
  static const card = 24.0;
  static const button = 28.0; // pill at the standard 54 px height
  static const input = 16.0;
  static const tile = 16.0;
  static const pill = 999.0;
}
