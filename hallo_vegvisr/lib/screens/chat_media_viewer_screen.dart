import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ChatMediaViewerArgs {
  final String mediaUrl;
  final String? contentType;

  const ChatMediaViewerArgs({required this.mediaUrl, this.contentType});

  bool get isVideo {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.startsWith('video/')) return true;
    // Fallback: treat common video extensions as video.
    final lower = mediaUrl.toLowerCase();
    return lower.endsWith('.mp4') || lower.contains('.mp4?') || lower.endsWith('.mov') || lower.contains('.mov?');
  }
}

class ChatMediaViewerScreen extends StatefulWidget {
  final ChatMediaViewerArgs args;

  const ChatMediaViewerScreen({super.key, required this.args});

  @override
  State<ChatMediaViewerScreen> createState() => _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<ChatMediaViewerScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    if (widget.args.isVideo) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.args.mediaUrl));
      _controller = controller;
      _initFuture = controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.args.isVideo ? 'Video' : 'Photo';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: widget.args.isVideo ? _buildVideo(context) : _buildImage(context),
    );
  }

  Widget _buildImage(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        child: CachedNetworkImage(
          imageUrl: widget.args.mediaUrl,
          fit: BoxFit.contain,
          placeholder: (context, imageUrl) => const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, imageUrl, error) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context) {
    final controller = _controller;
    final initFuture = _initFuture;
    if (controller == null || initFuture == null) {
      return const Center(
        child: Text('Missing video controller', style: TextStyle(color: Colors.white70)),
      );
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final aspect = controller.value.aspectRatio;
        final safeAspect = (aspect.isFinite && aspect > 0) ? aspect : (16 / 9);

        return Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: safeAspect,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 40,
                          color: Colors.white,
                          icon: Icon(controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                          onPressed: () {
                            setState(() {
                              if (controller.value.isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
