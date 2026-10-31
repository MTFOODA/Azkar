/// A validated reference to a YouTube video.
class YoutubeVideoRef {
  const YoutubeVideoRef({required this.videoId, this.startAt});

  /// The canonical 11-character YouTube video id.
  final String videoId;

  /// Optional seek position taken from `?t=` / `#t=` / `?start=`.
  final Duration? startAt;

  String get watchUrl => YoutubeUrl.watchUrl(videoId);

  String get thumbnailUrl => YoutubeUrl.thumbnailUrl(videoId);

  @override
  bool operator ==(Object other) =>
      other is YoutubeVideoRef &&
      other.videoId == videoId &&
      other.startAt == startAt;

  @override
  int get hashCode => Object.hash(videoId, startAt);

  @override
  String toString() => 'YoutubeVideoRef($videoId, startAt: $startAt)';
}

/// Parses and validates YouTube URLs.
///
/// Only YouTube-owned hosts are accepted and the extracted id must match
/// `^[A-Za-z0-9_-]{11}$`, which makes it impossible to smuggle another scheme
/// (for example `javascript:`) or an arbitrary host into an iframe `src`.
class YoutubeUrl {
  YoutubeUrl._();

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static const Set<String> _allowedHosts = <String>{
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
    'youtu.be',
    'www.youtu.be',
  };

  /// Path prefixes that are immediately followed by the video id.
  static const List<String> _idPathPrefixes = <String>[
    'shorts',
    'embed',
    'v',
    'live',
    'watch',
  ];

  /// Returns a validated [YoutubeVideoRef], or `null` when [input] is not a
  /// supported YouTube reference.
  static YoutubeVideoRef? parse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // A bare video id is accepted because administrators often paste only the
    // id, but it must look exactly like one.
    if (_idPattern.hasMatch(trimmed)) {
      return YoutubeVideoRef(videoId: trimmed);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    // Reject every non-web scheme, including protocol-relative URLs.
    if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (!_allowedHosts.contains(host)) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    String? videoId;
    if (host.endsWith('youtu.be')) {
      if (segments.isNotEmpty) videoId = segments.first;
    } else if (uri.queryParameters['v'] != null) {
      videoId = uri.queryParameters['v'];
    } else if (segments.length >= 2 && _idPathPrefixes.contains(segments.first)) {
      videoId = segments[1];
    } else if (segments.length == 1) {
      videoId = segments.first;
    }

    if (videoId == null || !_idPattern.hasMatch(videoId)) return null;

    return YoutubeVideoRef(
      videoId: videoId,
      startAt: _parseStart(uri),
    );
  }

  /// Convenience accessor used across the app.
  static String? extractVideoId(String? input) => parse(input)?.videoId;

  static bool isValid(String? input) => parse(input) != null;

  static Duration? _parseStart(Uri uri) {
    final candidates = <String?>[
      uri.queryParameters['t'],
      uri.queryParameters['start'],
      uri.fragment.startsWith('t=') ? uri.fragment.substring(2) : null,
    ];
    for (final candidate in candidates) {
      if (candidate == null || candidate.isEmpty) continue;
      final seconds = _secondsFrom(candidate);
      if (seconds != null) return Duration(seconds: seconds);
    }
    return null;
  }

  static int? _secondsFrom(String value) {
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    // Formats such as 1m30s or 1h2m3s.
    final match = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(value);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    final total = hours * 3600 + minutes * 60 + seconds;
    return total > 0 ? total : null;
  }

  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  static String privacyEmbedUrl(String videoId) =>
      'https://www.youtube-nocookie.com/embed/$videoId';

  /// Thumbnail served by YouTube's image CDN (no cookies, no player JS).
  static String thumbnailUrl(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
}
