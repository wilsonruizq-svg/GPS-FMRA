import 'package:flutter/foundation.dart';

/// Coordina Grupos/Historial → pestaña Mapa: centrar un punto.
///
/// AppShell escucha [revision] y pasa a índice 0; [MapShellScreen] consume
/// el request al montar (solo una pestaña activa, sin IndexedStack).
class MapPlaceFocusRequest {
  const MapPlaceFocusRequest({
    required this.lat,
    required this.lon,
    this.placeId,
    this.name,
  });

  final double lat;
  final double lon;
  final String? placeId;
  final String? name;
}

abstract final class MapPlaceFocus {
  static MapPlaceFocusRequest? _pending;

  /// Incrementa al encolar un focus (AppShell → tab Mapa).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void request(MapPlaceFocusRequest value) {
    _pending = value;
    revision.value++;
  }

  static bool get hasPending => _pending != null;

  static MapPlaceFocusRequest? take() {
    final v = _pending;
    _pending = null;
    return v;
  }
}
