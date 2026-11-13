/// Coordina Grupos → pestaña Mapa: centrar un lugar guardado.
///
/// AppShell cambia a índice 0; [MapShellScreen] consume el request al montar
/// (solo una pestaña activa, sin IndexedStack).
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

  static void request(MapPlaceFocusRequest value) {
    _pending = value;
  }

  static bool get hasPending => _pending != null;

  static MapPlaceFocusRequest? take() {
    final v = _pending;
    _pending = null;
    return v;
  }
}
