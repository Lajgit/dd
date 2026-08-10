import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({
    super.key,
    required this.file,
    this.title,
  });

  final File file;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171313),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF171313),
        title: Text(title?.trim().isNotEmpty == true ? title!.trim() : '查看图片'),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _MediaError(message: '图片读取失败'),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({
    super.key,
    required this.file,
    this.title,
  });

  final File file;
  final String? title;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    // 媒体已经复制到 App 私有目录，播放器只读取本地文件，不访问网络。
    _controller = VideoPlayerController.file(widget.file);
    _initializeFuture = _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171313),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF171313),
        title: Text(widget.title?.trim().isNotEmpty == true ? widget.title!.trim() : '播放视频'),
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initializeFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !_controller.value.isInitialized) {
              return const _MediaError(message: '视频无法播放，可能是当前设备不支持该编码格式。');
            }

            final aspectRatio = _controller.value.aspectRatio > 0
                ? _controller.value.aspectRatio
                : 16 / 9;
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _togglePlayback,
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 42,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
