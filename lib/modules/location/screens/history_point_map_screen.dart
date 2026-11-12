import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// Mapa de solo lectura centrado en un punto del historial.
class HistoryPointMapScreen extends StatefulWidget {
  const HistoryPointMapScreen({
    super.key,
    required this.lat,
    required this.lon,
    required this.title,
    this.subtitle,
  });

  final double lat;
  final double lon;
  final String title;
  final String? subtitle;

  @override
  State<HistoryPointMapScreen> createState() => _HistoryPointMapScreenState();
}

class _HistoryPointMapScreenState extends State<HistoryPointMapScreen> {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  Circle? _circle;
  Symbol? _label;

  CameraPosition get _camera => CameraPosition(
        target: LatLng(widget.lat, widget.lon),
        zoom: 15.5,
      );

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _placeMarker();
  }

  Future<void> _placeMarker() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final geometry = LatLng(widget.lat, widget.lon);
    try {
      if (_circle != null) {
        await c.removeCircle(_circle!);
        _circle = null;
      }
      if (_label != null) {
        await c.removeSymbol(_label!);
        _label = null;
      }
      _circle = await c.addCircle(
        CircleOptions(
          geometry: geometry,
          circleRadius: 10,
          circleColor: '#1B4F72',
          circleStrokeWidth: 2.5,
          circleStrokeColor: '#FFFFFF',
          circleOpacity: 0.95,
        ),
      );
      _label = await c.addSymbol(
        SymbolOptions(
          geometry: geometry,
          textField: widget.title,
          textSize: 13,
          textOffset: const Offset(0, 1.4),
          textColor: '#1B4F72',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.2,
        ),
      );
    } catch (e) {
      debugPrint('HistoryPointMap marker: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subtitle?.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: AppStrings.historyRecenterTooltip,
            onPressed: () {
              final c = _controller;
              if (c == null) return;
              unawaited(
                c.animateCamera(CameraUpdate.newCameraPosition(_camera)),
              );
            },
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Column(
        children: [
          if (sub != null && sub.isNotEmpty)
            Material(
              color: Colors.white,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sub,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.midBlue,
                        ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: MapLibreMap(
              styleString: Env.mapStyleUrl,
              initialCameraPosition: _camera,
              compassEnabled: true,
              myLocationEnabled: false,
              trackCameraPosition: false,
              onMapCreated: (controller) {
                _controller = controller;
              },
              onStyleLoadedCallback: () {
                unawaited(_onStyleLoaded());
              },
            ),
          ),
        ],
      ),
    );
  }
}
