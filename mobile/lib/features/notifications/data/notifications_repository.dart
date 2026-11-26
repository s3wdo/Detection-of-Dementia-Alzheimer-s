import 'models/app_notification.dart';

/// Real version: GET /notifications, PATCH /notifications/{id}/read.
abstract interface class NotificationsRepository {
  Future<List<AppNotification>> listFor(String userId);
  Future<void> markRead(String notificationId);
  Future<void> markAllRead(String userId);
}
