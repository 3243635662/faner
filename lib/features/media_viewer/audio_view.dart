import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/format.dart';
import '../../core/tokens.dart';
import 'media_source.dart';

/// 可复用的音频播放器（本地/远程流式播放）。
class AudioView extends StatefulWidget {
  const AudioView({super.key, required this.source});

  final MediaSource source;

  @override
  State<AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<AudioView> {
  final AudioPlayer _player = AudioPlayer();
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      switch (widget.source) {
        case LocalMediaSource(:final path):
          await _player.setFilePath(path);
        case RemoteMediaSource(:final url):
          await _player.setUrl(url);
      }
      await _player.play();
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_error) {
      return Center(child: Text('无法播放该音频', style: TextStyle(color: palette.muted)));
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: palette.panel2,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.music, size: 64, color: palette.sky),
            ),
            const SizedBox(height: AppSpacing.xl),
            _AudioProgress(player: _player),
            const SizedBox(height: AppSpacing.lg),
            IconButton.filled(
              iconSize: 56,
              onPressed: () => playing ? _player.pause() : _player.play(),
              icon: Icon(playing ? LucideIcons.pause : LucideIcons.play),
            ),
          ],
        );
      },
    );
  }
}

class _AudioProgress extends StatelessWidget {
  const _AudioProgress({required this.player});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnapshot) {
        final pos = posSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnapshot) {
            final dur = durSnapshot.data ?? Duration.zero;
            final totalMs = dur.inMilliseconds;
            return Column(
              children: [
                Slider(
                  value: pos.inMilliseconds.clamp(0, totalMs).toDouble(),
                  max: totalMs > 0 ? totalMs.toDouble() : 1,
                  onChanged: (v) =>
                      player.seek(Duration(milliseconds: v.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(pos),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: palette.muted)),
                      Text(formatDuration(dur),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: palette.muted)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
