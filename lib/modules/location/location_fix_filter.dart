import 'package:geolocator/geolocator.dart';

/// Filtra fixes GPS ruidosos y decide cuándo publicar a Supabase.
///
/// No inventa coordenadas: solo acepta/rechaza lecturas reales del dispositivo.
class LocationFixFilter {
  const LocationFixFilter({
    this.maxAccuracyM = 80,
    this.coldStartMaxAccuracyM = 150,
    this.maxJumpM = 250,
    this.jumpWindow = const Duration(seconds: 45),
    this.minPublishInterval = const Duration(seconds: 5),
    this.maxPublishInterval = const Duration(seconds: 8),
    this.minMoveMeters = 8,
  });

  /// Descarta fixes peores que esto (metros, ~68% horizontal).
  final double maxAccuracyM;

  /// Primer fix sin historial: umbral un poco más laxo para no quedarse ciego.
  final double coldStartMaxAccuracyM;

  /// Salto máximo aceptable en [jumpWindow] si la nueva precisión es peor.
  final double maxJumpM;
  final Duration jumpWindow;

  /// No publicar más seguido que esto (ahorro de red/batería).
  final Duration minPublishInterval;

  /// Heartbeat: publicar al menos cada este intervalo aunque no se mueva.
  final Duration maxPublishInterval;

  /// Distancia mínima para publicar antes del heartbeat.
  final double minMoveMeters;

  /// True si [next] es usable para UI / publicación.
  bool accept(Position next, {Position? previous}) {
    if (!next.latitude.isFinite || !next.longitude.isFinite) return false;
    if (!next.accuracy.isFinite || next.accuracy < 0) return false;

    final maxAcc =
        previous == null ? coldStartMaxAccuracyM : maxAccuracyM;
    if (next.accuracy > maxAcc) return false;

    if (previous == null) return true;

    final dist = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    final dt = _positionTime(next).difference(_positionTime(previous));
    if (dist > maxJumpM &&
        dt >= Duration.zero &&
        dt < jumpWindow &&
        next.accuracy > previous.accuracy + 10) {
      return false;
    }
    return true;
  }

  /// True si conviene upsert a `location_updates`.
  bool shouldPublish(
    Position next, {
    Position? lastPublished,
    DateTime? lastPublishedAt,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now().toUtc();
    if (lastPublished == null || lastPublishedAt == null) return true;

    final elapsed = at.difference(lastPublishedAt.toUtc());
    if (elapsed >= maxPublishInterval) return true;
    if (elapsed < minPublishInterval) return false;

    final dist = Geolocator.distanceBetween(
      lastPublished.latitude,
      lastPublished.longitude,
      next.latitude,
      next.longitude,
    );
    return dist >= minMoveMeters;
  }

  DateTime _positionTime(Position p) {
    final t = p.timestamp;
    return t.isUtc ? t : t.toUtc();
  }
}
