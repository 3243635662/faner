import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import 'audio_view.dart';
import 'media_source.dart';

class AudioPlayerPage extends StatelessWidget {
  const AudioPlayerPage({super.key, required this.source});

  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(source.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(child: AudioView(source: source)),
        ),
      ),
    );
  }
}
