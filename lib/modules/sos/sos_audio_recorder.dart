import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';

/// GF-31/34: graba micrófono del **dueño del teléfono** durante su SOS.
///
/// Sube a Storage `sos-audio/{uid}/{sos_id}.m4a` ligado a ese evento.
/// Compañeros reproducen solo desde el banner/detalle de ese SOS (rescate).
class SosAudioRecorder {
  SosAudioRecorder({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? supabase;

  static const maxDuration = Duration(minutes: 5);
  /// Sube el tramo actual para que compañeros oigan durante el SOS activo.
  static const flushInterval = Duration(seconds: 35);
  static const storageBucket = 'sos-audio';

  final AudioRecorder _recorder = AudioRecorder();
  Timer? _maxTimer;
  Timer? _flushTimer;
  String? _activeSosId;
  String? _localPath;
  bool _starting = false;
  bool _flushing = false;

  bool get isRecording => _activeSosId != null;

  /// Inicia grabación ligada a [sosId]. Idempotente por sosId.
  Future<bool> startForSos(String sosId) async {
    final id = sosId.trim();
    if (id.isEmpty) return false;
    if (_activeSosId == id) return true;
    if (_starting) return false;
    _starting = true;
    try {
      await stop(upload: false);

      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        debugPrint('SosAudioRecorder: micrófono denegado');
        return false;
      }
      if (!await _recorder.hasPermission()) {
        debugPrint('SosAudioRecorder: record.hasPermission=false');
        return false;
      }

      final ok = await _beginSegment(id);
      if (!ok) return false;

      _maxTimer?.cancel();
      _maxTimer = Timer(maxDuration, () {
        unawaited(stop(upload: true));
      });
      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(flushInterval, (_) {
        unawaited(_flushUploadAndContinue());
      });
      return true;
    } catch (e) {
      debugPrint('SosAudioRecorder.startForSos: $e');
      _activeSosId = null;
      _localPath = null;
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<bool> _beginSegment(String sosId) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}sos_$sosId.m4a';
    try {
      final old = File(path);
      if (await old.exists()) await old.delete();
    } catch (_) {}

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _activeSosId = sosId;
    _localPath = path;
    debugPrint('SosAudioRecorder: grabando $path');
    return true;
  }

  /// Detiene el tramo, sube y reinicia (mismo sos_id) para rescate en vivo.
  Future<void> _flushUploadAndContinue() async {
    if (_flushing) return;
    final sosId = _activeSosId;
    if (sosId == null) return;
    _flushing = true;
    try {
      final path = _localPath;
      try {
        if (await _recorder.isRecording()) {
          await _recorder.stop();
        }
      } catch (e) {
        debugPrint('SosAudioRecorder.flush stop: $e');
      }
      _localPath = null;
      if (path != null) {
        await _uploadBestEffort(sosId: sosId, path: path);
      }
      if (_activeSosId == sosId) {
        await _beginSegment(sosId);
      }
    } catch (e) {
      debugPrint('SosAudioRecorder.flush: $e');
    } finally {
      _flushing = false;
    }
  }

  /// Detiene y, si [upload], intenta Storage `sos-audio/{uid}/{sosId}.m4a`.
  Future<void> stop({bool upload = true}) async {
    _maxTimer?.cancel();
    _maxTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    final sosId = _activeSosId;
    final path = _localPath;
    _activeSosId = null;
    _localPath = null;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e) {
      debugPrint('SosAudioRecorder.stop recorder: $e');
    }

    if (!upload || sosId == null || path == null) return;
    await _uploadBestEffort(sosId: sosId, path: path);
  }

  Future<void> _uploadBestEffort({
    required String sosId,
    required String path,
  }) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      final objectPath = '$uid/$sosId.m4a';
      await _sb.storage.from(storageBucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: true,
            ),
          );
      debugPrint('SosAudioRecorder: subido $storageBucket/$objectPath');
    } catch (e) {
      // Bucket/SQL no APPLY aún: grabación local sigue válida en sesión.
      debugPrint('SosAudioRecorder.upload: $e');
    }
  }

  Future<void> dispose() async {
    await stop(upload: _activeSosId != null);
    await _recorder.dispose();
  }
}
