import 'dart:math' as math;

/// Computes the next retry delay using truncated exponential backoff.
///
/// Returns `base * 2^attempt`, capped at [maxDelay]. `attempt` is 0-based,
/// so the first retry waits roughly [base], the second 2×[base], and so on.
///
/// This matches Google's recommended retry pattern for the Mobile Ads SDK
/// and is intentionally less aggressive than a fixed delay so transient
/// failures recover quickly while persistent failures stop hammering the
/// network.
Duration nextBackoff(
  int attempt, {
  Duration base = const Duration(seconds: 2),
  Duration maxDelay = const Duration(seconds: 64),
}) {
  // Clamp the exponent so the shift can never overflow on hot retry loops.
  final clampedAttempt = attempt.clamp(0, 16);
  final shifted = base.inMilliseconds * math.pow(2, clampedAttempt).toInt();
  final ms = math.min(shifted, maxDelay.inMilliseconds);
  return Duration(milliseconds: ms);
}
