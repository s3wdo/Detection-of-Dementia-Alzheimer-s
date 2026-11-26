import 'package:intl/intl.dart';

/// Shared date / number formatting so every screen shows values the same way.
abstract final class Fmt {
  static final _date = DateFormat('d MMM yyyy');
  static final _shortDate = DateFormat('d MMM');
  static final _time = DateFormat('h:mm a');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _weekday = DateFormat('EEEE, d MMMM');

  static String date(DateTime d) => _date.format(d);
  static String shortDate(DateTime d) => _shortDate.format(d);
  static String time(DateTime d) => _time.format(d);
  static String dateTime(DateTime d) => '${_date.format(d)} · ${_time.format(d)}';
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String weekday(DateTime d) => _weekday.format(d);

  /// 0.914 → "91.4%"
  static String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  /// "2 h ago", "3 days ago", or a date for older items.
  static String relative(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.isNegative) return dateTime(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return diff.inDays == 1 ? 'Yesterday' : '${diff.inDays} days ago';
    return date(d);
  }

  /// Whole years between [dob] and [now].
  static int age(DateTime dob, DateTime now) {
    var years = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) years--;
    return years;
  }
}
