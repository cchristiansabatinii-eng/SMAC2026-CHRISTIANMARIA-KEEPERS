import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

final class MemoryViewer extends StatefulWidget {
  const MemoryViewer({required this.memory, required this.playback, super.key});

  final Future<MemoryOpenResult> memory;
  final AudioPlaybackAdapter playback;

  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

final class _MemoryViewerState extends State<MemoryViewer> {
  @override
  void dispose() {
    unawaited(widget.playback.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Memory')),
    body: SafeArea(
      child: FutureBuilder<MemoryOpenResult>(
        future: widget.memory,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Opening memory…'),
                ],
              ),
            );
          }
          final result = snapshot.data;
          if (result is! OpenedMemory) {
            final message = result is UnavailableMemory
                ? result.message
                : _unavailableMessage;
            return _UnavailableMemoryView(message: message);
          }
          return _OpenedMemoryView(memory: result, playback: widget.playback);
        },
      ),
    ),
  );
}

final class _OpenedMemoryView extends StatelessWidget {
  const _OpenedMemoryView({required this.memory, required this.playback});

  final OpenedMemory memory;
  final AudioPlaybackAdapter playback;

  @override
  Widget build(BuildContext context) {
    final caption = memory.payload.caption?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            memory.metadata.format.vaultLabel,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Created ${_formatDate(memory.metadata.createdAt)}'),
              Text(memory.metadata.privacy.vaultLabel),
            ],
          ),
          const SizedBox(height: 22),
          _memoryContent(memory, playback),
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              caption,
              key: const Key('memory-caption'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ],
      ),
    );
  }
}

Widget _memoryContent(OpenedMemory memory, AudioPlaybackAdapter playback) =>
    switch (memory.metadata.format) {
      MemoryFormat.photo => _PhotoMemoryView(
        bytes: memory.payload.primaryBytes!,
      ),
      MemoryFormat.voice => _VoiceMemoryView(
        bytes: memory.payload.primaryBytes!,
        duration: Duration(milliseconds: memory.payload.mediaDurationMs!),
        playback: playback,
      ),
      MemoryFormat.text => _TextMemoryView(text: memory.payload.text!),
    };

final class _PhotoMemoryView extends StatelessWidget {
  const _PhotoMemoryView({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 220, maxHeight: 540),
    color: Theme.of(context).extension<ObservatoryTokens>()!.memorySurface,
    child: Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: 'Photo memory',
    ),
  );
}

final class _VoiceMemoryView extends StatefulWidget {
  const _VoiceMemoryView({
    required this.bytes,
    required this.duration,
    required this.playback,
  });

  final Uint8List bytes;
  final Duration duration;
  final AudioPlaybackAdapter playback;

  @override
  State<_VoiceMemoryView> createState() => _VoiceMemoryViewState();
}

final class _VoiceMemoryViewState extends State<_VoiceMemoryView> {
  String? _error;

  Future<void> _play() async {
    try {
      await widget.playback.playBytes(widget.bytes);
    } on Object {
      if (mounted) setState(() => _error = 'Audio playback unavailable.');
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Voice memory, ${_formatDuration(widget.duration)}',
    child: Column(
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 72),
        const SizedBox(height: 12),
        Text(
          _formatDuration(widget.duration),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
          onPressed: _play,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play voice memory'),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(error),
        ],
      ],
    ),
  );
}

final class _TextMemoryView extends StatelessWidget {
  const _TextMemoryView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SelectableText(
    text,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.5),
  );
}

final class _UnavailableMemoryView extends StatelessWidget {
  const _UnavailableMemoryView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 44),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

const _unavailableMessage = 'This memory cannot be opened safely.';

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
