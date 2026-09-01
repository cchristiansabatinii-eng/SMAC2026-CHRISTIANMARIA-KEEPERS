import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';
import 'package:keepers/ui/kept_forever_summary.dart';

@visibleForTesting
const archivePhotoPreviewMaxConcurrentLoads = 3;

const archivePhotoPreviewMaxSourceBytes = 16 * 1024 * 1024;

@immutable
final class ArchiveMemorySummary {
  const ArchiveMemorySummary({
    required this.id,
    required this.title,
    required this.authorName,
    required this.theme,
    required this.formatLabel,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String authorName;
  final String theme;
  final String formatLabel;
  final DateTime createdAt;
}

final class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    required this.familyName,
    required this.memories,
    required this.onDestinationSelected,
    required this.onOpenMemory,
    this.onCapture,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.loadPhotoPreview,
    super.key,
  });

  final String familyName;
  final List<ArchiveMemorySummary> memories;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final ValueChanged<ArchiveMemorySummary> onOpenMemory;
  final VoidCallback? onCapture;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<Uint8List?> Function(ArchiveMemorySummary)? loadPhotoPreview;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

final class _ArchiveScreenState extends State<ArchiveScreen> {
  final math.Random _random = math.Random();
  final _photoPreviewQueue = _ArchivePhotoLoadQueue(
    maxConcurrent: archivePhotoPreviewMaxConcurrentLoads,
  );
  String? _person;
  String? _theme;
  String? _lastDrawnId;

  @override
  void dispose() {
    _photoPreviewQueue.dispose();
    super.dispose();
  }

  List<ArchiveMemorySummary> get _filtered =>
      widget.memories
          .where((memory) => _person == null || memory.authorName == _person)
          .where((memory) => _theme == null || memory.theme == _theme)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _draw() {
    final memories = _filtered;
    if (memories.isEmpty) return;
    final candidates = memories.length == 1
        ? memories
        : memories
              .where((memory) => memory.id != _lastDrawnId)
              .toList(growable: false);
    final selected = candidates[_random.nextInt(candidates.length)];
    _lastDrawnId = selected.id;
    widget.onOpenMemory(selected);
  }

  Widget _archiveBody(List<ArchiveMemorySummary> memories) {
    if (widget.loading) return const _ArchiveLoading();
    final error = widget.errorMessage;
    if (error != null) {
      return _ArchiveError(message: error, onRetry: widget.onRetry);
    }
    if (memories.isEmpty) {
      return _ArchiveEmpty(
        filtered: widget.memories.isNotEmpty,
        onClear: () => setState(() {
          _person = null;
          _theme = null;
        }),
      );
    }
    return _ArchiveGallery(
      memories: memories,
      onOpen: widget.onOpenMemory,
      loadPhotoPreview: widget.loadPhotoPreview,
      photoPreviewQueue: _photoPreviewQueue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final people =
        widget.memories.map((memory) => memory.authorName).toSet().toList()
          ..sort();
    final themes =
        widget.memories.map((memory) => memory.theme).toSet().toList()..sort();
    final memories = _filtered;
    return KeepersDestinationScaffold(
      destination: KeepersNavDestination.archive,
      kicker: 'Kept memories',
      title: '${widget.familyName} archive',
      subtitle: 'Only memories the family chose to keep.',
      onDestinationSelected: widget.onDestinationSelected,
      onCapture: widget.onCapture,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
            child: _ArchiveSummarySlot(
              count: widget.memories.length,
              loading: widget.loading,
              unavailable: widget.errorMessage != null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: _RandomMemoryPill(
              memoryCount: !widget.loading && widget.errorMessage == null
                  ? memories.length
                  : 0,
              onDraw: _draw,
            ),
          ),
          if (widget.memories.isNotEmpty) ...[
            _FilterRail(
              label: 'Person',
              allLabel: 'All people',
              values: people,
              selected: _person,
              onSelected: (value) => setState(() => _person = value),
            ),
            _FilterRail(
              label: 'Theme',
              allLabel: 'All themes',
              values: themes,
              selected: _theme,
              onSelected: (value) => setState(() => _theme = value),
            ),
          ],
          Expanded(child: _archiveBody(memories)),
        ],
      ),
    );
  }
}

final class _ArchiveSummarySlot extends StatelessWidget {
  const _ArchiveSummarySlot({
    required this.count,
    required this.loading,
    required this.unavailable,
  });

  final int count;
  final bool loading;
  final bool unavailable;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: !loading && !unavailable
        ? KeptForeverSummary(count: count)
        : Semantics(
            label: loading
                ? 'Kept memory count loading'
                : 'Kept memory count unavailable',
            container: true,
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('kept-forever-summary-placeholder'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: KeepersColors.auraIvory.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: KeepersColors.homeLine.withValues(alpha: .62),
                  ),
                ),
                child: Row(
                  children: [
                    KeepersText(
                      'Kept forever',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: KeepersColors.homeTaupe,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const Spacer(),
                    KeepersText(
                      loading ? 'Counting…' : 'Unavailable',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: KeepersColors.homeTaupe,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}

final class _RandomMemoryPill extends StatelessWidget {
  const _RandomMemoryPill({required this.memoryCount, required this.onDraw});

  final int memoryCount;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('random-memory-mode'),
    label: 'Draw a random memory',
    button: true,
    enabled: memoryCount > 0,
    onTap: memoryCount > 0 ? onDraw : null,
    child: ExcludeSemantics(
      child: OutlinedButton(
        onPressed: memoryCount > 0 ? onDraw : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          minimumSize: const Size.fromHeight(48),
          maximumSize: const Size.fromHeight(48),
          foregroundColor: KeepersColors.ink,
          disabledForegroundColor: KeepersColors.inkMuted,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: KeepersColors.homeTaupe),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: const Row(
          children: [
            Expanded(
              child: KeepersText(
                'Random Memory',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KeepersType.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            SizedBox(width: 12),
            Icon(Icons.shuffle_rounded, size: 28),
          ],
        ),
      ),
    ),
  );
}

final class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.label,
    required this.allLabel,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String allLabel;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label filter',
    child: SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        children: [
          _CompactFilterChip(
            targetKey: ValueKey(
              'archive-filter-${label.toLowerCase()}-all-target',
            ),
            visualKey: ValueKey(
              'archive-filter-${label.toLowerCase()}-all-visual',
            ),
            label: allLabel,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final value in values)
            _CompactFilterChip(
              label: value,
              selected: selected == value,
              onTap: () => onSelected(value),
            ),
        ],
      ),
    ),
  );
}

final class _CompactFilterChip extends StatelessWidget {
  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.targetKey,
    this.visualKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Key? targetKey;
  final Key? visualKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Semantics(
      key: targetKey,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: ConstrainedBox(
                    key: visualKey,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 32,
                      maxHeight: 32,
                    ),
                    child: ExcludeFocus(
                      child: ChoiceChip(
                        label: KeepersText(
                          label,
                          style: TextStyle(
                            color: selected
                                ? KeepersColors.auraIvory
                                : KeepersColors.ink,
                            fontFamily: KeepersType.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .7,
                          ),
                        ),
                        selected: selected,
                        showCheckmark: true,
                        checkmarkColor: KeepersColors.auraIvory,
                        selectedColor: KeepersColors.ink,
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(color: KeepersColors.ink),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -4,
                        ),
                        onSelected: (_) => onTap(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ArchiveLoading extends StatelessWidget {
  const _ArchiveLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      height: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          KeepersText(
            'Opening family archive…',
            style: TextStyle(color: KeepersColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

final class _ArchiveError extends StatelessWidget {
  const _ArchiveError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 50,
            color: KeepersColors.inkMuted,
          ),
          const SizedBox(height: 16),
          KeepersText(
            'Archive unavailable',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 8),
          KeepersText(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRetry,
              child: const KeepersText('Try again'),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _ArchiveGallery extends StatelessWidget {
  const _ArchiveGallery({
    required this.memories,
    required this.onOpen,
    required this.loadPhotoPreview,
    required this.photoPreviewQueue,
  });
  final List<ArchiveMemorySummary> memories;
  final ValueChanged<ArchiveMemorySummary> onOpen;
  final Future<Uint8List?> Function(ArchiveMemorySummary)? loadPhotoPreview;
  final _ArchivePhotoLoadQueue photoPreviewQueue;

  @override
  Widget build(BuildContext context) {
    final years = <int, List<ArchiveMemorySummary>>{};
    for (final memory in memories) {
      years.putIfAbsent(memory.createdAt.year, () => []).add(memory);
    }
    final entries = years.entries.toList(growable: false);
    return CustomScrollView(
      key: const ValueKey('archive-gallery'),
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      slivers: [
        for (var yearIndex = 0; yearIndex < entries.length; yearIndex++) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(24, yearIndex == 0 ? 4 : 12, 24, 8),
            sliver: SliverToBoxAdapter(
              child: KeepersText(
                '${entries[yearIndex].key}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: KeepersColors.ink,
                  fontFamily: KeepersType.primary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              yearIndex == entries.length - 1 ? 28 : 0,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, memoryIndex) {
                  final memory = entries[yearIndex].value[memoryIndex];
                  return _ArchiveMemoryTile(
                    key: ValueKey('archive-memory-tile-${memory.id}'),
                    memory: memory,
                    loadPhotoPreview: loadPhotoPreview,
                    photoPreviewQueue: photoPreviewQueue,
                    onTap: () => onOpen(memory),
                  );
                },
                childCount: entries[yearIndex].value.length,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

final class _ArchivePhotoLoadQueue {
  _ArchivePhotoLoadQueue({required this.maxConcurrent})
    : assert(maxConcurrent > 0);

  final int maxConcurrent;
  final ListQueue<_ArchivePhotoLoadRequest> _pending = ListQueue();
  final Set<_ArchivePhotoLoadRequest> _active = {};
  var _disposed = false;

  _ArchivePhotoLoadRequest schedule(Future<Uint8List?> Function() loader) {
    late final _ArchivePhotoLoadRequest request;
    request = _ArchivePhotoLoadRequest(
      loader: loader,
      onCancel: () => _cancel(request),
    );
    if (_disposed) {
      request.cancel();
      return request;
    }
    _pending.add(request);
    _drain();
    return request;
  }

  void _cancel(_ArchivePhotoLoadRequest request) {
    if (_pending.remove(request)) request.completeCanceled();
  }

  void _drain() {
    while (!_disposed &&
        _active.length < maxConcurrent &&
        _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      if (request.isCanceled) {
        request.completeCanceled();
        continue;
      }
      _active.add(request);
      unawaited(
        request.run().whenComplete(() {
          _active.remove(request);
          _drain();
        }),
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final request in _pending.toList(growable: false)) {
      request.cancel();
    }
    _pending.clear();
    for (final request in _active.toList(growable: false)) {
      request.cancel();
    }
  }
}

final class _ArchivePhotoLoadRequest {
  _ArchivePhotoLoadRequest({required this.loader, required this.onCancel});

  final Future<Uint8List?> Function() loader;
  final VoidCallback onCancel;
  final Completer<Uint8List?> _completer = Completer();
  var _started = false;
  var _canceled = false;

  Future<Uint8List?> get future => _completer.future;
  bool get isCanceled => _canceled;

  Future<void> run() async {
    if (_canceled) {
      completeCanceled();
      return;
    }
    _started = true;
    Uint8List? bytes;
    try {
      bytes = await loader();
    } on Object {
      bytes = null;
    }
    if (_canceled) {
      bytes?.fillRange(0, bytes.length, 0);
      bytes = null;
    }
    if (!_completer.isCompleted) _completer.complete(bytes);
  }

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    onCancel();
    if (!_started) completeCanceled();
  }

  void completeCanceled() {
    if (!_completer.isCompleted) _completer.complete(null);
  }
}

final class _ArchiveMemoryTile extends StatefulWidget {
  const _ArchiveMemoryTile({
    required this.memory,
    required this.onTap,
    required this.loadPhotoPreview,
    required this.photoPreviewQueue,
    super.key,
  });
  final ArchiveMemorySummary memory;
  final VoidCallback onTap;
  final Future<Uint8List?> Function(ArchiveMemorySummary)? loadPhotoPreview;
  final _ArchivePhotoLoadQueue photoPreviewQueue;

  @override
  State<_ArchiveMemoryTile> createState() => _ArchiveMemoryTileState();
}

final class _ArchiveMemoryTileState extends State<_ArchiveMemoryTile> {
  Future<ResizeImage?>? _preview;
  ResizeImage? _leasedProvider;
  Uint8List? _leasedBytes;
  _ArchivePhotoLoadRequest? _loadRequest;
  var _generation = 0;
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    _preview = _startPreviewLoad();
  }

  @override
  void didUpdateWidget(covariant _ArchiveMemoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loaderAvailabilityChanged =
        (oldWidget.loadPhotoPreview == null) !=
        (widget.loadPhotoPreview == null);
    if (oldWidget.memory.id != widget.memory.id ||
        oldWidget.memory.formatLabel != widget.memory.formatLabel ||
        loaderAvailabilityChanged) {
      _generation++;
      _cancelPreviewLoad();
      _releaseLease();
      _preview = _startPreviewLoad();
    }
  }

  Future<ResizeImage?>? _startPreviewLoad() {
    final loader = widget.loadPhotoPreview;
    if (!_isPhoto(widget.memory.formatLabel) || loader == null) return null;
    final generation = ++_generation;
    final request = widget.photoPreviewQueue.schedule(
      () => loader(widget.memory),
    );
    _loadRequest = request;
    return _loadPreview(request, generation);
  }

  Future<ResizeImage?> _loadPreview(
    _ArchivePhotoLoadRequest request,
    int generation,
  ) async {
    final bytes = await request.future;
    if (identical(_loadRequest, request)) _loadRequest = null;
    if (bytes == null || bytes.isEmpty) return null;
    if (bytes.lengthInBytes > archivePhotoPreviewMaxSourceBytes) {
      bytes.fillRange(0, bytes.length, 0);
      return null;
    }

    final provider = ResizeImage(
      MemoryImage(bytes),
      width: _archivePhotoDecodeWidth,
      height: _archivePhotoDecodeHeight,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
    if (_disposed || generation != _generation) {
      await _evictAndZero(provider, bytes);
      return null;
    }
    _leasedProvider = provider;
    _leasedBytes = bytes;
    return provider;
  }

  void _cancelPreviewLoad() {
    _loadRequest?.cancel();
    _loadRequest = null;
  }

  void _releaseLease() {
    final provider = _leasedProvider;
    final bytes = _leasedBytes;
    _leasedProvider = null;
    _leasedBytes = null;
    if (provider != null && bytes != null) {
      unawaited(_evictAndZero(provider, bytes));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelPreviewLoad();
    _releaseLease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final format = _formatName(widget.memory.formatLabel);
    return Semantics(
      key: ValueKey('archive-memory-${widget.memory.id}'),
      container: true,
      button: true,
      label:
          '$format memory, ${widget.memory.title}, ${widget.memory.authorName}, '
          '${_archiveDateWithYear(widget.memory.createdAt)}',
      hint: 'Open memory',
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Material(
          color: KeepersColors.auraIvory.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: widget.onTap, child: _tileContent(format)),
        ),
      ),
    );
  }

  Widget _tileContent(String format) {
    final preview = _preview;
    if (preview == null) {
      return _ArchiveFormatCard(memory: widget.memory, format: format);
    }
    return FutureBuilder<ResizeImage?>(
      future: preview,
      builder: (context, snapshot) {
        final provider = snapshot.data;
        if (provider == null) {
          return _ArchiveFormatCard(memory: widget.memory, format: format);
        }
        return _ArchivePhotoCard(memory: widget.memory, provider: provider);
      },
    );
  }
}

final class _ArchiveFormatCard extends StatelessWidget {
  const _ArchiveFormatCard({required this.memory, required this.format});

  final ArchiveMemorySummary memory;
  final String format;

  @override
  Widget build(BuildContext context) {
    final color =
        KeepersColors.memberPalette[memory.authorName.hashCode.abs() %
            KeepersColors.memberPalette.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        border: Border.all(color: color.withValues(alpha: .52)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _formatIcon(memory.formatLabel),
                  color: KeepersColors.ink,
                  size: 28,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: KeepersText(
                    format,
                    key: ValueKey(
                      'archive-format-${format.toLowerCase()}-${memory.id}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KeepersColors.ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            KeepersText(
              memory.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KeepersColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 3),
            KeepersText(
              '${memory.authorName} · ${_archiveDate(memory.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KeepersColors.inkMuted,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ArchivePhotoCard extends StatelessWidget {
  const _ArchivePhotoCard({required this.memory, required this.provider});

  final ArchiveMemorySummary memory;
  final ResizeImage provider;

  @override
  Widget build(BuildContext context) => Image(
    key: ValueKey('archive-photo-${memory.id}'),
    image: provider,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    errorBuilder: (context, error, stackTrace) =>
        _ArchiveFormatCard(memory: memory, format: 'Photo'),
  );
}

final class _ArchiveEmpty extends StatelessWidget {
  const _ArchiveEmpty({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.history_toggle_off_rounded,
            size: 54,
            color: KeepersColors.inkMuted,
          ),
          const SizedBox(height: 18),
          KeepersText(
            filtered ? 'No matches' : 'Nothing kept yet',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 9),
          KeepersText(
            filtered
                ? 'Try another person or theme.'
                : 'Released and still-sealed memories never appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          if (filtered) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onClear,
              child: const KeepersText('Clear filters'),
            ),
          ],
        ],
      ),
    ),
  );
}

IconData _formatIcon(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('photo')) return Icons.photo_outlined;
  if (normalized.contains('voice')) return Icons.graphic_eq_rounded;
  return Icons.notes_rounded;
}

bool _isPhoto(String label) => label.toLowerCase().contains('photo');

const _archivePhotoDecodeWidth = 512;
const _archivePhotoDecodeHeight = 512;

Future<void> _evictAndZero(ResizeImage provider, Uint8List bytes) async {
  try {
    await provider.evict();
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

String _formatName(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('photo')) return 'Photo';
  if (normalized.contains('voice')) return 'Voice';
  return 'Text';
}

String _archiveDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';

String _archiveDateWithYear(DateTime date) =>
    '${_archiveDate(date)}.${date.year.toString().padLeft(4, '0')}';
