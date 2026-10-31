import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/tasbeeh_counter_store.dart';

/// The incrementing engine behind one Tasbeeh card.
///
/// Design notes:
/// * increments are **synchronous and local-first** — the UI counter updates
///   immediately and never waits for storage, so rapid taps can never be lost;
/// * persistence is debounced (default 200 ms) and the writes are serialised, so
///   a burst of taps results in one write instead of hundreds;
/// * [flush] forces the pending value to disk (used on pause/dispose);
/// * arbitrary-precision values avoid imposing a counter maximum on Web.
///
/// There is intentionally no target and no maximum: the visitor may keep
/// counting forever.
class TasbeehCounter {
  TasbeehCounter({
    required this.store,
    required this.tasbeehId,
    this.pageId,
    this.persistDebounce = const Duration(milliseconds: 200),
    this.onChanged,
    this.onError,
  });

  final TasbeehCounterStore store;

  /// Immutable Tasbeeh id — the storage key is derived from it.
  final String tasbeehId;
  final String? pageId;

  final Duration persistDebounce;
  final ValueChanged<BigInt>? onChanged;
  final ValueChanged<Object>? onError;

  BigInt _value = BigInt.zero;
  bool _loaded = false;
  bool _disposed = false;
  bool _dirty = false;
  Timer? _debounceTimer;
  Future<void> _writeQueue = Future<void>.value();

  BigInt get value => _value;

  bool get isLoaded => _loaded;

  bool get hasUnsavedChanges => _dirty;

  /// Hydrates the counter from local storage.
  Future<void> load() async {
    try {
      final stored = await store.read(tasbeehId, pageId: pageId);
      if (_disposed) return;
      _value = stored.isNegative ? BigInt.zero : stored;
      _loaded = true;
      onChanged?.call(_value);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Tasbeeh counter load failed for $tasbeehId',
        error,
        stackTrace,
      );
      onError?.call(error);
      if (!_disposed) {
        _loaded = true;
        onChanged?.call(_value);
      }
    }
  }

  /// Increments by exactly one and schedules a persisted write.
  void increment() {
    if (_disposed) return;
    _value += BigInt.one;
    _dirty = true;
    onChanged?.call(_value);
    _schedulePersist();
  }

  /// Resets this counter (and only this counter) to zero and persists at once.
  Future<void> reset() async {
    if (_disposed) return;
    _value = BigInt.zero;
    _dirty = true;
    onChanged?.call(BigInt.zero);
    await flush();
  }

  /// Writes any pending value immediately.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_dirty) return;
    _dirty = false;
    final snapshot = _value;
    _writeQueue = _writeQueue.then((_) async {
      try {
        await store.write(tasbeehId, snapshot, pageId: pageId);
      } catch (error, stackTrace) {
        AppLogger.error(
          'Tasbeeh counter persist failed for $tasbeehId',
          error,
          stackTrace,
        );
        onError?.call(error);
      }
    });
    await _writeQueue;
  }

  /// Releases resources. A final flush is attempted so a closing tab keeps the
  /// latest value.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_dirty) {
      final snapshot = _value;
      _dirty = false;
      unawaited(
        _writeQueue.then((_) async {
          try {
            await store.write(tasbeehId, snapshot, pageId: pageId);
          } catch (error) {
            AppLogger.warning('Tasbeeh final flush failed: $error');
          }
        }),
      );
    }
  }

  void _schedulePersist() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(persistDebounce, () {
      unawaited(flush());
    });
  }
}
