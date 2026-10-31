import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/youtube_url.dart';
import '../../../core/widgets/asymmetric_card.dart';
import '../../content/domain/content_item.dart';
import '../../content/widgets/content_style.dart';
import '../../sharing/sharing_service.dart';

/// A privacy-conscious, lazy YouTube card.
///
/// The thumbnail is rendered first; no player iframe/webview is created until
/// the visitor explicitly taps play. Videos never autoplay on page load.
class YoutubeCard extends StatefulWidget {
  const YoutubeCard({super.key, required this.item, this.preview = false});

  final ContentItem item;
  final bool preview;

  @override
  State<YoutubeCard> createState() => _YoutubeCardState();
}

class _YoutubeCardState extends State<YoutubeCard> {
  YoutubePlayerController? _controller;
  bool _playing = false;
  bool _failed = false;

  YoutubeVideoRef? get _video =>
      YoutubeUrl.parse(widget.item.videoUrl ?? widget.item.videoId);

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _start() {
    final video = _video;
    if (video == null || widget.preview) return;
    try {
      final controller = YoutubePlayerController.fromVideoId(
        videoId: video.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          privacyEnhancedMode: true,
          showControls: true,
          showFullscreenButton: true,
          interfaceLanguage: 'ar',
          playsInline: true,
        ),
      );
      setState(() {
        _controller = controller;
        _playing = true;
        _failed = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warning('YouTube player initialization failed', error, stackTrace);
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final style = item.style;
    final video = _video;
    return AsymmetricCard(
      shape: style.shape,
      backgroundColor: style.backgroundColorValue,
      decorationColor: style.textColorValue,
      showDecoration: style.decorationEnabled,
      borderColor: style.textColorValue.withValues(alpha: 0.35),
      showBorder: style.borderEnabled,
      semanticLabel: item.displayTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.title.trim().isNotEmpty) ...[
            ArabicText(
              item.title,
              style: ContentStyleResolver.titleStyle(style),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceMd),
          ],
          if (video == null)
            const InvalidVideoView()
          else if (_playing && _controller != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppPalette.radiusSm),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: YoutubePlayer(
                  controller: _controller!,
                  aspectRatio: 16 / 9,
                ),
              ),
            )
          else
            YoutubeThumbnail(video: video, failed: _failed, onPlay: _start),
          if (item.description != null && item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppPalette.spaceMd),
            ArabicText(
              item.description!,
              style: ContentStyleResolver.metaStyle(style),
              textAlign: TextAlign.center,
            ),
          ],
          if (video != null) ...[
            const SizedBox(height: AppPalette.spaceSm),
            TextButton.icon(
              onPressed: () => SharingService.openExternal(video.watchUrl),
              icon: const Icon(Icons.open_in_new_outlined, size: 18),
              label: const Text('فتح على يوتيوب'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thumbnail + play button shown before the expensive player is created.
class YoutubeThumbnail extends StatelessWidget {
  const YoutubeThumbnail({
    super.key,
    required this.video,
    required this.failed,
    required this.onPlay,
  });

  final YoutubeVideoRef video;
  final bool failed;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  video.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.ondemand_video_outlined, size: 56),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
                Container(color: Colors.black.withValues(alpha: 0.18)),
                Center(
                  child: Semantics(
                    button: true,
                    label: 'تشغيل الفيديو',
                    child: IconButton.filled(
                      onPressed: onPlay,
                      iconSize: 42,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(72, 72),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'تعذّر تشغيل الفيديو داخل الصفحة. يمكنك فتحه على يوتيوب.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class InvalidVideoView extends StatelessWidget {
  const InvalidVideoView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.video_library_outlined, size: 40),
          SizedBox(height: 8),
          Text('رابط الفيديو غير صالح', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

