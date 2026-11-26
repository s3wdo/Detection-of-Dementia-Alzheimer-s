/// Errors whose `toString()` is a plain-language message that is safe to show
/// to users. Anything else is shown as a generic message, so technical details
/// (stack traces, server internals, health data in payloads) never reach the screen.
abstract interface class UserFacingError implements Exception {}

/// The text to show for [error].
String userMessage(Object error) => switch (error) {
      UserFacingError() => error.toString(),
      ArgumentError(message: final String m) => m, // validation messages from repositories
      _ => 'Something went wrong. Please try again.',
    };
