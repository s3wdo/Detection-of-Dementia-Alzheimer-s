import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Now", injectable so tests and demo data use a predictable time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
