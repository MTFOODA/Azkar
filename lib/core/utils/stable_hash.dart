/// A tiny, dependency-free, deterministic hash.
///
/// Used to fingerprint validated Quranic text (`validation_hash`) so the admin
/// dashboard can prove that the published text is exactly the text that was
/// checked against the verified dataset. It is a djb2 variant reduced modulo
/// `2^31-1`, chosen so every intermediate value stays inside the 53-bit integer
/// range where Flutter Web and native builds behave identically.
///
/// It is not cryptographic and is never used for security.
class StableHash {
  const StableHash._();

  static const int _modulus = 2147483647; // 2^31 - 1 (Mersenne prime)
  static const int _multiplier = 33;
  static const int _seed = 5381;

  /// Returns an 8 character hexadecimal fingerprint of [input].
  static String fingerprint(String input) {
    var hash = _seed;
    for (final unit in input.codeUnits) {
      hash = (hash * _multiplier + unit) % _modulus;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Hashes a normalised version of [input].
  static String ofNormalized(
    String input,
    String Function(String) normalizer,
  ) => fingerprint(normalizer(input));
}
