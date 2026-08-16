import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/data/entry_persistence_failure.dart';
import 'package:keepers/features/capture/data/photo_capture_adapter.dart';
import 'package:keepers/features/capture/data/voice_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureDraft>(CaptureController.new);

final class CaptureController extends Notifier<CaptureDraft> {
  CaptureDraft _last = const CaptureDraft();
  late final PhotoCaptureAdapter _photos;
  late final VoiceCaptureAdapter _voice;
  late final AudioPlaybackAdapter _playback;
  late final CaptureFileAccess _files;
  late final Future<LocalIdentity?> _identity;
  late final String Function() _idFactory;
  late final DateTime Function() _utcNow;
  late final EntrySave _saveEntry;
  var _generation = 0;
  var _busy = false;
  var _disposed = false;
  var _recordingOwned = false;
  var _mandatoryCleanup = false;
  final _pendingMedia = <CaptureMedia>[];
  final _orphanedPaths = <String>{};
  final _activeOperations = <Future<void>>{};

  Stream<double> get amplitudes => _voice.amplitudes;

  @override
  CaptureDraft build() {
    _photos = ref.read(photoCaptureAdapterProvider);
    _voice = ref.read(voiceCaptureAdapterProvider);
    _playback = ref.read(audioPlaybackAdapterProvider);
    _files = ref.read(captureFileAccessProvider);
    _identity = ref.read(localIdentityProvider.future);
    _idFactory = ref.read(idFactoryProvider);
    _utcNow = ref.read(utcNowProvider);
    _saveEntry = ref.read(entrySaveProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      unawaited(_disposeResources());
    });
    _last = const CaptureDraft(phase: CapturePhase.recovering);
    unawaited(_trackOperation(() => _startupRecovery(_generation)));
    return _last;
  }

  bool get _terminal =>
      state.phase == CapturePhase.saved ||
      state.phase == CapturePhase.committedCleanup;
  bool _current(int token) => !_disposed && token == _generation;

  void _emit(CaptureDraft next) {
    if (_disposed) return;
    final cleanupRequired =
        _mandatoryCleanup ||
        _pendingMedia.isNotEmpty ||
        _orphanedPaths.isNotEmpty;
    var normalized = next.cleanupRequired == cleanupRequired
        ? next
        : next.copyWith(cleanupRequired: cleanupRequired);
    if (cleanupRequired &&
        next.phase == CapturePhase.editing &&
        next.errorMessage == null) {
      normalized = normalized.copyWith(
        phase: CapturePhase.failed,
        errorMessage: 'Temporary media cleanup needs attention before this capture can close.',
        retryIntent: CaptureRetryIntent.pendingCleanup,
      );
    }
    _last = normalized;
    state = normalized;
  }

  void updateText(String value) {
    if (_busy ||
        _terminal ||
        state.retryRequiresCleanup ||
        state.format != MemoryFormat.text) {
      return;
    }
    _generation++;
    _emit(
      state.copyWith(
        text: value,
        phase: state.phase == CapturePhase.failed
            ? CapturePhase.editing
            : state.phase,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
  }

  void updateCaption(String value) {
    if (_busy || _terminal || state.retryRequiresCleanup) return;
    _generation++;
    _emit(
      state.copyWith(
        caption: value,
        phase: state.phase == CapturePhase.failed
            ? CapturePhase.editing
            : state.phase,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
  }

  void setPrivacy(PrivacyTier value) {
    if (_busy || _terminal || state.retryRequiresCleanup) return;
    _generation++;
    _emit(
      state.copyWith(
        privacy: value,
        phase: state.phase == CapturePhase.failed
            ? CapturePhase.editing
            : state.phase,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
  }

  void resetAfterCompletion() {
    if (_busy || state.phase != CapturePhase.saved) return;
    _generation++;
    _emit(const CaptureDraft());
  }

  Future<void> finalizeDismissal() => discard();

  Future<void> selectFormat(MemoryFormat format) async {
    if (_busy || _terminal || state.isRecording || state.format == format) {
      return;
    }
    final token = ++_generation;
    final before = state;
    if (_mediaPaths(before).isEmpty) {
      _emit(
        CaptureDraft(
          format: format,
          privacy: before.privacy,
          caption: before.caption,
        ),
      );
      return;
    }
    _busy = true;
    _emit(before.copyWith(phase: CapturePhase.cleaning));
    final error = await _cleanupPaths(_mediaPaths(before));
    if (!_current(token)) return;
    _busy = false;
    if (error != null) {
      _emit(
        before.copyWith(
          phase: CapturePhase.failed,
          retryIntent: _formatRetryIntent(format),
          errorMessage:
              'The previous draft could not be cleaned up. Try again.',
        ),
      );
    } else {
      _emit(
        CaptureDraft(
          format: format,
          privacy: before.privacy,
          caption: before.caption,
        ),
      );
    }
  }

  Future<void> acceptPhoto(String path) =>
      _trackOperation(() => _acceptPhoto(path));

  Future<void> _acceptPhoto(String path) async {
    if (_busy || _terminal || state.isRecording) {
      await _deleteStale(path);
      return;
    }
    final token = ++_generation;
    final before = state;
    final oldPaths = _mediaPaths(before).where((old) => old != path).toList();
    if (oldPaths.isEmpty) {
      _emit(
        CaptureDraft(
          format: MemoryFormat.photo,
          privacy: before.privacy,
          caption: before.caption,
          photoPath: path,
        ),
      );
      return;
    }
    _busy = true;
    _emit(before.copyWith(phase: CapturePhase.cleaning));
    final error = await _cleanupPaths(oldPaths);
    if (!_current(token)) {
      await _deleteStale(path);
      return;
    }
    _busy = false;
    if (error != null) {
      await _deleteStale(path);
      if (!_current(token)) return;
      _emit(
        before.copyWith(
          phase: CapturePhase.failed,
          retryIntent: CaptureRetryIntent.replacePrimary,
          errorMessage:
              'The previous draft could not be cleaned up. Try again.',
        ),
      );
    } else {
      _emit(
        CaptureDraft(
          format: MemoryFormat.photo,
          privacy: before.privacy,
          caption: before.caption,
          photoPath: path,
        ),
      );
    }
  }

  Future<void> pickPhoto(PhotoSource source) =>
      _trackOperation(() => _pickPhoto(source));

  Future<void> _pickPhoto(PhotoSource source) async {
    if (_busy || _terminal || state.isRecording) return;
    final token = ++_generation;
    final before = state;
    _busy = true;
    _emit(
      before.copyWith(
        phase: CapturePhase.picking,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
    try {
      final path = await _photos.pick(source);
      if (!_current(token)) {
        if (path != null) await _deleteStale(path);
        return;
      }
      _busy = false;
      if (path == null) {
        _emit(before);
      } else {
        await _acceptPhoto(path);
      }
    } on CapturePermissionException catch (error) {
      if (_current(token)) {
        _busy = false;
        _emit(
          before.copyWith(
            phase: CapturePhase.failed,
            retryIntent: _photoRetryIntent(source),
            errorMessage: _permissionMessage(error.source),
          ),
        );
      }
    } on Object {
      if (_current(token)) {
        _busy = false;
        _emit(
          before.copyWith(
            phase: CapturePhase.failed,
            retryIntent: _photoRetryIntent(source),
            errorMessage: 'This photo could not be added. You can try again or choose another format.',
          ),
        );
      }
    }
  }

  Future<void> recoverLostPhoto() =>
      _trackOperation(() => _recoverLost(startup: false));

  Future<void> _startupRecovery(int initialToken) async {
    try {
      final path = await _photos.recoverLostPhoto();
      if (!_current(initialToken) || state.hasDraft) {
        if (path != null) await _deleteStale(path);
      } else if (path != null) {
        await _acceptPhoto(path);
      } else {
        _emit(
          state.copyWith(
            phase: CapturePhase.editing,
            clearErrorMessage: true,
            clearRetryIntent: true,
          ),
        );
      }
    } on Object {
      if (_current(initialToken) && !state.hasDraft) {
        _emit(
          state.copyWith(
            phase: CapturePhase.failed,
            retryIntent: CaptureRetryIntent.recoverLostPhoto,
            errorMessage: 'The interrupted photo could not be recovered.',
          ),
        );
      }
    }
  }

  Future<void> _recoverLost({required bool startup, int? expectedToken}) async {
    if (_busy || _terminal || state.isRecording || state.hasDraft) return;
    if (expectedToken != null && !_current(expectedToken)) return;
    final token = ++_generation;
    final before = state;
    _busy = true;
    if (!startup) {
      _emit(
        before.copyWith(
          phase: CapturePhase.recovering,
          clearErrorMessage: true,
          clearRetryIntent: true,
        ),
      );
    }
    try {
      final path = await _photos.recoverLostPhoto();
      if (!_current(token) || state.hasDraft) {
        if (path != null) await _deleteStale(path);
        return;
      }
      _busy = false;
      if (path == null) {
        _emit(before);
      } else {
        await _acceptPhoto(path);
      }
    } on Object {
      if (_current(token)) {
        _busy = false;
        _emit(
          before.copyWith(
            phase: CapturePhase.failed,
            retryIntent: CaptureRetryIntent.recoverLostPhoto,
            errorMessage: 'The interrupted photo could not be recovered.',
          ),
        );
      }
    }
  }

  Future<void> toggleRecording() {
    if (_busy || _terminal || state.format != MemoryFormat.voice) {
      return Future<void>.value();
    }
    if (!_recordingOwned && _orphanedPaths.isNotEmpty) {
      return Future<void>.value();
    }
    return _trackOperation(_recordingOwned ? _stopRecording : _startRecording);
  }

  Future<void> _startRecording() async {
    final token = ++_generation;
    _busy = true;
    _emit(
      state.copyWith(
        phase: CapturePhase.starting,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
    try {
      if (!await _voice.hasPermission()) {
        throw const CapturePermissionException(
          CapturePermissionSource.microphone,
        );
      }
      if (!_current(token) || state.format != MemoryFormat.voice) return;
      await _voice.start();
      _recordingOwned = _voice.ownsPlaintext;
      if (!_current(token) || state.format != MemoryFormat.voice) {
        await _cancelVoice();
        return;
      }
      _busy = false;
      _emit(
        state.copyWith(
          phase: CapturePhase.recording,
          recordingActive: true,
          clearVoicePath: true,
          voiceDuration: Duration.zero,
        ),
      );
    } on CapturePermissionException catch (error) {
      if (_current(token)) {
        _busy = false;
        _emit(
          state.copyWith(
            phase: CapturePhase.failed,
            retryIntent: CaptureRetryIntent.recording,
            recordingActive: false,
            errorMessage: _permissionMessage(error.source),
          ),
        );
      }
    } on Object {
      _recordingOwned = _recordingOwned || _voice.ownsPlaintext;
      await _cancelVoice();
      if (_current(token)) {
        _busy = false;
        _emit(
          state.copyWith(
            phase: CapturePhase.failed,
            retryIntent: CaptureRetryIntent.recording,
            recordingActive: _recordingOwned,
            errorMessage: 'Recording could not start. You can try again or choose another format.',
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final token = ++_generation;
    _busy = true;
    _emit(state.copyWith(phase: CapturePhase.stopping));
    try {
      final recording = await _voice.stop();
      _recordingOwned = _voice.ownsPlaintext;
      if (!_current(token)) {
        if (_recordingOwned) await _cancelVoice();
        if (recording != null) await _deleteStale(recording.path);
        return;
      }
      if (_recordingOwned) {
        final cleanupFailures = <Object>[];
        if (recording != null) {
          // The native result is not the adapter-owned path. Register it
          // before any await so every failure path retains cleanup authority.
          _orphanedPaths.add(recording.path);
        }
        final voiceError = await _cancelVoice();
        if (voiceError != null) cleanupFailures.add(voiceError);
        if (recording != null) {
          final returnedPathError = await _deleteStale(recording.path);
          if (returnedPathError != null) {
            cleanupFailures.add(returnedPathError);
          }
        }
        final cleanupError = cleanupFailures.isEmpty
            ? null
            : CaptureFileAccessFailure(cleanupFailures);
        if (!_current(token)) return;
        _busy = false;
        if (cleanupError != null) {
          _emit(
            state.copyWith(
              recordingActive: _recordingOwned,
              phase: CapturePhase.failed,
              retryIntent: CaptureRetryIntent.discard,
              errorMessage: 'Recording cleanup is incomplete. Try discard before recording again.',
            ),
          );
        } else {
          _emit(
            state.copyWith(
              clearVoicePath: true,
              voiceDuration: Duration.zero,
              recordingActive: false,
              phase: CapturePhase.editing,
            ),
          );
        }
        return;
      }
      _busy = false;
      _emit(
        state.copyWith(
          voicePath: recording?.path,
          clearVoicePath: recording == null,
          voiceDuration: recording?.duration ?? Duration.zero,
          recordingActive: false,
          phase: CapturePhase.editing,
        ),
      );
    } on Object {
      await _cancelVoice();
      if (_current(token)) {
        _busy = false;
        _emit(
          state.copyWith(
            recordingActive: _recordingOwned,
            phase: CapturePhase.failed,
            retryIntent: _recordingOwned
                ? CaptureRetryIntent.discard
                : CaptureRetryIntent.recording,
            errorMessage: 'Recording stopped unexpectedly. Your draft details are still here.',
          ),
        );
      }
    }
  }

  Future<void> playVoice() async {
    if (_busy || _terminal || _recordingOwned) return;
    final path = state.voicePath;
    if (path != null) await _playback.playFile(path);
  }

  Future<void> replacePrimary() async {
    if (_busy || _terminal || _recordingOwned) return;
    final before = state;
    final token = ++_generation;
    _busy = true;
    _emit(before.copyWith(phase: CapturePhase.cleaning));
    final error = await _cleanupPaths(_mediaPaths(before));
    if (!_current(token)) return;
    _busy = false;
    if (error != null) {
      _emit(
        before.copyWith(
          phase: CapturePhase.failed,
          retryIntent: CaptureRetryIntent.replacePrimary,
          errorMessage: 'The draft file could not be removed. Try again.',
        ),
      );
    } else {
      _emit(
        CaptureDraft(
          format: before.format,
          privacy: before.privacy,
          caption: before.caption,
        ),
      );
    }
  }

  Future<void> discard() async {
    if (_terminal ||
        state.phase == CapturePhase.saving ||
        state.phase == CapturePhase.cleaning) {
      return;
    }
    final before = state;
    final superseded = List<Future<void>>.of(_activeOperations);
    final token = ++_generation;
    _busy = true;
    _emit(before.copyWith(phase: CapturePhase.cleaning));
    if (superseded.isNotEmpty) {
      await Future.wait(
        superseded.map((operation) => operation.catchError((Object _) {})),
      );
      if (!_current(token)) return;
    }
    Object? error;
    if (_recordingOwned) error = await _cancelVoice();
    if (!_current(token)) return;
    final cleanupError = await _cleanupPaths(
      <String>{..._mediaPaths(before), ..._orphanedPaths}.toList(),
    );
    error ??= cleanupError;
    final pendingError = await _drainPendingCleanup();
    error ??= pendingError;
    if (!_current(token)) return;
    _busy = false;
    if (error != null) {
      _emit(
        before.copyWith(
          phase: CapturePhase.failed,
          recordingActive: _recordingOwned,
          retryIntent: CaptureRetryIntent.discard,
          errorMessage:
              'Some draft plaintext could not be removed. Try discard again.',
        ),
      );
    } else {
      _orphanedPaths.clear();
      _emit(const CaptureDraft());
    }
  }

  Future<void> save() async {
    if (_busy || _terminal || !state.canSave) return;
    final token = ++_generation;
    final frozen = state;
    _busy = true;
    CaptureMedia? snapshot;
    EntryMetadata? metadata;
    EntryMetadata? savedEntry;
    var outcomePhase = CapturePhase.failed;
    String? outcomeMessage =
        'This memory could not be kept. Your draft is still here.';
    CaptureRetryIntent? outcomeRetry = CaptureRetryIntent.save;
    _emit(
      frozen.copyWith(
        phase: CapturePhase.saving,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
    final pendingError = await _drainPendingCleanup();
    if (!_current(token)) return;
    if (pendingError != null) {
      _busy = false;
      _emit(
        frozen.copyWith(
          phase: CapturePhase.failed,
          errorMessage:
              'This memory was not kept, and snapshot cleanup needs attention.',
          retryIntent: CaptureRetryIntent.save,
        ),
      );
      return;
    }
    try {
      final identity = await _identity;
      if (!_current(token)) return;
      if (identity == null) throw StateError('Local identity is unavailable');
      metadata = EntryMetadata(
        id: _idFactory(),
        familyId: identity.familyId,
        authorId: identity.memberId,
        createdAt: _utcNow(),
        format: frozen.format,
        privacy: frozen.privacy,
      );
      final mediaPath = frozen.format == MemoryFormat.photo
          ? frozen.photoPath
          : frozen.format == MemoryFormat.voice
          ? frozen.voicePath
          : null;
      if (mediaPath != null) {
        // A read can allocate and register a residual snapshot before it
        // throws, so retain independent cleanup authority before awaiting it.
        _mandatoryCleanup = true;
        snapshot = await _files.read(mediaPath);
        _pendingMedia.add(snapshot);
      }
      if (!_current(token)) return;
      savedEntry = await _saveEntry(
        EntrySaveRequest(
          metadata: metadata,
          identity: identity,
          payload: EntryPayload(
            format: frozen.format,
            primaryBytes: snapshot?.bytes,
            text: frozen.format == MemoryFormat.text ? frozen.text : null,
            caption: frozen.caption.trim().isEmpty
                ? null
                : frozen.caption.trim(),
            mediaExtension: snapshot?.extension,
            mediaDurationMs: frozen.format == MemoryFormat.voice
                ? frozen.voiceDuration.inMilliseconds
                : null,
          ),
          plaintextRefs: [
            if (snapshot != null) CapturePlaintextRef(snapshot.plaintextRef),
          ],
        ),
      );
      if (!_current(token)) return;
      Object? cleanupError;
      if (mediaPath != null) cleanupError = await _cleanupPaths([mediaPath]);
      if (!_current(token)) return;
      outcomePhase = cleanupError == null
          ? CapturePhase.saved
          : CapturePhase.committedCleanup;
      outcomeMessage = cleanupError == null
          ? null
          : 'The memory is kept, but draft cleanup needs attention.';
      outcomeRetry = cleanupError == null
          ? null
          : CaptureRetryIntent.committedCleanup;
    } on EntrySaveFailure catch (error) {
      if (error.consistency.metadataCommitted) {
        savedEntry = error.committedMetadata ?? metadata;
        outcomePhase = CapturePhase.committedCleanup;
        outcomeMessage =
            'The memory is kept, but draft cleanup needs attention.';
        outcomeRetry = CaptureRetryIntent.committedCleanup;
      }
    } on Object {
      // The default failed-save outcome preserves the draft for retry.
    } finally {
      Object? snapshotCleanupError;
      if (snapshot != null) {
        try {
          await snapshot.release();
          _pendingMedia.remove(snapshot);
          _mandatoryCleanup = false;
        } on Object catch (error) {
          snapshotCleanupError = error;
        }
      }
      if (snapshot == null && _mandatoryCleanup) {
        snapshotCleanupError = await _drainPendingCleanup();
      }
      if (_current(token)) {
        if (snapshotCleanupError != null) {
          outcomePhase = savedEntry == null
              ? CapturePhase.failed
              : CapturePhase.committedCleanup;
          outcomeMessage = savedEntry == null
              ? 'This memory was not kept, and snapshot cleanup needs attention.'
              : 'The memory is kept, but draft cleanup needs attention.';
          outcomeRetry = savedEntry == null
              ? CaptureRetryIntent.save
              : CaptureRetryIntent.committedCleanup;
        }
        _busy = false;
        _emit(
          frozen.copyWith(
            phase: outcomePhase,
            savedEntry: savedEntry,
            clearSavedEntry: savedEntry == null,
            errorMessage: outcomeMessage,
            clearErrorMessage: outcomeMessage == null,
            retryIntent: outcomeRetry,
            clearRetryIntent: outcomeRetry == null,
          ),
        );
      }
    }
  }

  Future<void> retryCleanup() async {
    if (_busy || state.phase != CapturePhase.committedCleanup) return;
    final token = ++_generation;
    final committed = state;
    _busy = true;
    Object? firstError;
    final pathError = await _cleanupPaths(_mediaPaths(committed));
    firstError ??= pathError;
    if (!_current(token)) return;
    final pendingError = await _drainPendingCleanup();
    firstError ??= pendingError;
    if (!_current(token)) return;
    _busy = false;
    _emit(
      committed.copyWith(
        phase: firstError == null
            ? CapturePhase.saved
            : CapturePhase.committedCleanup,
        errorMessage: firstError == null
            ? null
            : 'The memory is kept, but draft cleanup needs attention.',
        clearErrorMessage: firstError == null,
        retryIntent: firstError == null
            ? null
            : CaptureRetryIntent.committedCleanup,
        clearRetryIntent: firstError == null,
      ),
    );
  }

  Future<void> retryPendingCleanup() async {
    if (_busy || _terminal || !state.cleanupRequired) return;
    final token = ++_generation;
    final before = state;
    _busy = true;
    _emit(
      before.copyWith(
        phase: CapturePhase.cleaning,
        clearErrorMessage: true,
        clearRetryIntent: true,
      ),
    );
    Object? firstError;
    if (_orphanedPaths.isNotEmpty) {
      final orphanError = await _cleanupPaths(_orphanedPaths.toList());
      firstError ??= orphanError;
      if (orphanError == null) _orphanedPaths.clear();
    }
    final pendingError = await _drainPendingCleanup();
    firstError ??= pendingError;
    if (!_current(token)) return;
    _busy = false;
    _emit(
      before.copyWith(
        phase: firstError == null ? CapturePhase.editing : CapturePhase.failed,
        errorMessage: firstError == null ? null : 'Temporary media cleanup needs attention before this capture can close.',
        clearErrorMessage: firstError == null,
        retryIntent: firstError == null
            ? null
            : CaptureRetryIntent.pendingCleanup,
        clearRetryIntent: firstError == null,
      ),
    );
  }

  Future<Object?> _cleanupPaths(List<String> paths) async {
    Object? first;
    try {
      await _playback.stop();
    } on Object catch (error) {
      first = error;
    }
    if (paths.isNotEmpty) {
      try {
        await _files.deleteAll(paths);
      } on Object catch (error) {
        first ??= error;
      }
    }
    return first;
  }

  Future<Object?> _cancelVoice() async {
    Object? error;
    try {
      await _voice.cancel();
    } on Object catch (caught) {
      error = caught;
    } finally {
      _recordingOwned = _voice.ownsPlaintext;
    }
    return error;
  }

  Future<Object?> _drainPendingCleanup() async {
    Object? firstError;
    try {
      await _files.retryPendingCleanup();
    } on Object catch (error) {
      firstError = error;
    }
    for (final media in List<CaptureMedia>.of(_pendingMedia)) {
      try {
        await media.release();
        _pendingMedia.remove(media);
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    _mandatoryCleanup = firstError != null;
    return firstError;
  }

  Future<Object?> _deleteStale(String path) async {
    final error = await _cleanupPaths([path]);
    if (error == null) {
      _orphanedPaths.remove(path);
    } else {
      // Keep authority over stale results for a later disposal cleanup retry.
      _orphanedPaths.add(path);
    }
    return error;
  }

  Future<void> _disposeResources() async {
    while (_activeOperations.isNotEmpty) {
      await Future.wait(
        List<Future<void>>.of(_activeOperations)
            .map((operation) => operation.catchError((Object _) {})),
      );
    }
    await _cleanupPaths(_mediaPaths(_last));
    if (_orphanedPaths.isNotEmpty) {
      final orphanError = await _cleanupPaths(_orphanedPaths.toList());
      if (orphanError == null) _orphanedPaths.clear();
    }
    await _drainPendingCleanup();
    try {
      await _voice.dispose();
    } on Object {
      _recordingOwned = _voice.ownsPlaintext;
    }
    try {
      await _playback.dispose();
    } on Object {
      // Disposal is the terminal owner and has no UI state to update.
    }
  }

  List<String> _mediaPaths(CaptureDraft draft) => [
    if (draft.photoPath != null) draft.photoPath!,
    if (draft.voicePath != null) draft.voicePath!,
  ];

  Future<void> _trackOperation(Future<void> Function() action) {
    late final Future<void> operation;
    operation = Future<void>.sync(action).whenComplete(() {
      _activeOperations.remove(operation);
    });
    _activeOperations.add(operation);
    return operation;
  }

  String _permissionMessage(CapturePermissionSource source) => switch (source) {
    CapturePermissionSource.camera =>
      'Camera access is needed to take a photo.',
    CapturePermissionSource.library =>
      'Photo library access is needed to choose a photo.',
    CapturePermissionSource.microphone =>
      'Microphone access is needed to record a memory.',
  };

  CaptureRetryIntent _photoRetryIntent(PhotoSource source) => switch (source) {
    PhotoSource.camera => CaptureRetryIntent.camera,
    PhotoSource.library => CaptureRetryIntent.library,
  };

  CaptureRetryIntent _formatRetryIntent(MemoryFormat format) =>
      switch (format) {
        MemoryFormat.photo => CaptureRetryIntent.selectPhoto,
        MemoryFormat.voice => CaptureRetryIntent.selectVoice,
        MemoryFormat.text => CaptureRetryIntent.selectText,
      };
}
