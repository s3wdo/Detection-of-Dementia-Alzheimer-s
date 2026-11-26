enum NotificationKind { review, message, appointment, analysis }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.route,
  });

  final String id;
  final String userId;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Screen to open when tapped, if any.
  final String? route;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        userId: userId,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        route: route,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        kind: NotificationKind.values.byName(json['type'] as String),
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        read: json['read_at'] != null,
        route: json['route'] as String?,
      );
}
