import '../../../core/auth/session.dart';

/// A labelled value shown on the profile detail screens.
typedef ProfileField = ({String label, String value});

class ProfileDetails {
  const ProfileDetails({required this.personal, required this.health});

  /// Name, contact details, date of birth…
  final List<ProfileField> personal;

  /// Patient: medical record details. Doctor: professional details.
  final List<ProfileField> health;
}

/// Real version: GET /me.
abstract interface class ProfileRepository {
  Future<ProfileDetails> detailsFor(Session session);
}
