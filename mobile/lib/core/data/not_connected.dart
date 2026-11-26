import 'user_facing_error.dart';

/// Thrown by repository providers when demo data is off and the real
/// backend repositories have not been written yet. Screens show it as an error
/// state instead of inventing data.
class NotConnectedException implements UserFacingError {
  const NotConnectedException();

  @override
  String toString() => "The NeuroSense server isn't connected yet.";
}
