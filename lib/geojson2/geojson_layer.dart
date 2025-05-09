import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_geojson2/geojson2/default_features.dart';
import 'package:flutter_map_geojson2/geojson2/geojson_provider.dart';
import 'package:latlong2/latlong.dart';

/// A callback function that creates a [Marker] instance from a [point]
/// geometry and GeoJSON object [properties].
typedef OnPointCallback = Marker Function(
    LatLng point, Map<String, dynamic> properties);

/// A callback function that creates a [Polyline] instance from
/// [points] making up the line, and GeoJSON object [properties].
typedef OnPolylineCallback = Polyline Function(
    List<LatLng> points, Map<String, dynamic> properties);

/// A callback function that creates a [Polygon] instance from
/// [points] that make up the outer ring, a list of [holes], and
/// GeoJSON object [properties].
typedef OnPolygonCallback = Polygon Function(List<LatLng> points,
    List<List<LatLng>>? holes, Map<String, dynamic> properties);

/// A filtering function that receives a GeoJSON object [geometryType]
/// (can be "Point", "LineString" etc) and its [properties]. Return
/// `false` to skip the object.
typedef FeatureFilterCallback = bool Function(
    String geometryType, Map<String, dynamic> properties);

/// Creates a layer that displays contents of a GeoJSON source.
class GeoJsonLayer extends StatefulWidget {
  /// GeoJSON data source. Just like with [ImageProvider], it's
  /// possible to do network calls or use an asset-bundled file.
  /// Use [MemoryGeoJson] to supply a [Map] if you don't need
  /// any of that.
  final GeoJsonProvider data;

  /// This function receives a marker location and feature properties,
  /// and builds a flutter_map [Marker]. See [defaultOnPoint] for an example.
  /// You can call that function first to process styles, and then adjust
  /// the returned marker.
  final OnPointCallback? onPoint;

  /// This function takes a list of points and feature properties to build
  /// a flutter_map [Polyline]. See [defaultOnPolyline] for an example.
  final OnPolylineCallback? onPolyline;

  /// This function takes feature properties and some other parameters to build
  /// a flutter_map [Polygon]. See [defaultOnPolygon] for an example.
  final OnPolygonCallback? onPolygon;

  /// A function to exclude some features from the GeoJSON. It takes
  /// a geometryType and feature properties to make that decision. Return
  /// `false` when you don't need the feature.
  final FeatureFilterCallback? filter;

  /// Hit notifier for polylines and polygons. See [LayerHitNotifier]
  /// documentation for explanations and an example.
  final LayerHitNotifier? hitNotifier;

  /// For a polyline, a change to adjust its hit box. The default is the
  /// same as in [Polyline], 10 pixels.
  final double polylineHitbox;

  /// When not overriding callbacks, this layer uses the default builders.
  /// Those use object properties to determine colors and dimensions.
  /// To change default values, use this property.
  final GeoJsonStyleDefaults? styleDefaults;

  /// Creates a layer instance. You might be better off using a specialized
  /// constructor:
  ///
  /// * [GeoJsonLayer.memory] for already loaded data.
  /// * [GeoJsonLayer.file] for loading GeoJSON from files.
  /// * [GeoJsonLayer.asset] for GeoJSON files bundled in assets.
  /// * [GeoJsonLayer.network] for downloading GeoJSON files over the network.
  const GeoJsonLayer({
    super.key,
    required this.data,
    this.onPoint,
    this.onPolyline,
    this.onPolygon,
    this.filter,
    this.styleDefaults,
    this.hitNotifier,
    this.polylineHitbox = 10,
  });

  GeoJsonLayer.memory(
    Map<String, dynamic> data, {
    super.key,
    this.onPoint,
    this.onPolyline,
    this.onPolygon,
    this.filter,
    this.styleDefaults,
    this.hitNotifier,
    this.polylineHitbox = 10,
  }) : data = MemoryGeoJson(data);

  GeoJsonLayer.file(
    File file, {
    super.key,
    this.onPoint,
    this.onPolyline,
    this.onPolygon,
    this.filter,
    this.styleDefaults,
    this.hitNotifier,
    this.polylineHitbox = 10,
  }) : data = FileGeoJson(file);

  GeoJsonLayer.asset(
    String name, {
    super.key,
    AssetBundle? bundle,
    this.onPoint,
    this.onPolyline,
    this.onPolygon,
    this.filter,
    this.styleDefaults,
    this.hitNotifier,
    this.polylineHitbox = 10,
  }) : data = AssetGeoJson(name, bundle: bundle);

  GeoJsonLayer.network(
    String url, {
    super.key,
    this.onPoint,
    this.onPolyline,
    this.onPolygon,
    this.filter,
    this.styleDefaults,
    this.hitNotifier,
    this.polylineHitbox = 10,
  }) : data = NetworkGeoJson(url);

  @override
  State<GeoJsonLayer> createState() => _GeoJsonLayerState();
}

class _GeoJsonLayerState extends State<GeoJsonLayer> {
  final List<Marker> _markers = [];
  final List<Polyline> _polylines = [];
  final List<Polygon> _polygons = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _clear() {
    _markers.clear();
    _polylines.clear();
    _polygons.clear();
  }

  Future<void> _loadData() async {
    try {
      final data = await widget.data.loadData();
      _clear();
      _parseGeoJson(data);
    } on Exception {
      if (mounted) setState(() {});
    }
  }

  void _parseGeoJson(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'FeatureCollection' || data['features'] is List) {
      for (final f in data['features'] ?? []) {
        if (f is Map<String, dynamic>) {
          _parseFeature(f);
        }
      }
    } else if (type != null) {
      _parseFeature(data);
    }
    if (mounted) setState(() {});
  }

  LatLng? _parseCoordinate(List<dynamic> data) {
    final doubles = data.whereType<double>();
    if (doubles.length < 2) return null;
    return LatLng(doubles.elementAt(1), doubles.first);
  }

  List<LatLng>? _parseLineString(List<dynamic> coordinates) {
    final points = coordinates
        .map((list) => _parseCoordinate(list))
        .whereType<LatLng>()
        .toList();
    if (points.length >= 2) {
      return points;
    }
    return null;
  }

  List<List<LatLng>>? _parsePolygon(List<dynamic> coordinates) {
    bool first = true;
    final List<List<LatLng>> result = [];
    final rings = coordinates.whereType<List>();
    for (final ring in rings) {
      final points = _parseLineString(ring);
      if (points != null && points.length >= 3) {
        result.add(points);
      } else if (first) {
        // We can skip holes, but not the outer ring.
        return null;
      }
      first = false;
    }
    return result.isEmpty ? null : result;
  }

  Marker _buildMarker(LatLng point, Map<String, dynamic> properties) {
    if (widget.onPoint != null) {
      return widget.onPoint!(point, properties);
    } else {
      return defaultOnPoint(point, properties, defaults: widget.styleDefaults);
    }
  }

  Polyline _buildLine(List<LatLng> points, Map<String, dynamic> properties) {
    if (widget.onPolyline != null) {
      return widget.onPolyline!(points, properties);
    } else {
      return defaultOnPolyline(points, properties,
          defaults: widget.styleDefaults);
    }
  }

  Polygon _buildPolygon(
      List<List<LatLng>> rings, Map<String, dynamic> properties) {
    if (widget.onPolygon != null) {
      return widget.onPolygon!(
        rings.first,
        rings.length == 1 ? null : rings.sublist(1),
        properties,
      );
    } else {
      return defaultOnPolygon(
        rings.first,
        rings.length == 1 ? null : rings.sublist(1),
        properties,
        defaults: widget.styleDefaults,
      );
    }
  }

  void _parseFeature(Map<String, dynamic> data) {
    if (data['type'] != 'Feature') return;
    final geometry = data['geometry'];
    if (geometry == null || geometry is! Map<String, dynamic>) return;
    final String? geometryType = geometry['type'];
    if (geometryType == null) return;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return;
    final Map<String, dynamic> properties = data['properties'] ?? {};

    if (widget.filter != null && !widget.filter!(geometryType, properties)) {
      return;
    }

    switch (geometryType) {
      case 'Point':
        final point = _parseCoordinate(coordinates);
        if (point != null) {
          _markers.add(_buildMarker(point, properties));
        }

      case 'MultiPoint':
        coordinates.whereType<List>().forEach((p) {
          final point = _parseCoordinate(p);
          if (point != null) {
            _markers.add(_buildMarker(point, properties));
          }
        });

      case 'LineString':
        final points = _parseLineString(coordinates);
        if (points != null) {
          _polylines.add(_buildLine(points, properties));
        }

      case 'MultiLineString':
        coordinates.whereType<List>().forEach((p) {
          final points = _parseLineString(p);
          if (points != null) {
            _polylines.add(_buildLine(points, properties));
          }
        });

      case 'Polygon':
        final rings = _parsePolygon(coordinates);
        if (rings != null) {
          _polygons.add(_buildPolygon(rings, properties));
        }

      case 'MultiPolygon':
        coordinates.whereType<List>().forEach((p) {
          final rings = _parsePolygon(p);
          if (rings != null) {
            _polygons.add(_buildPolygon(rings, properties));
          }
        });
    }
  }

  @override
  void didUpdateWidget(covariant GeoJsonLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_polygons.isNotEmpty)
          PolygonLayer(
            polygons: _polygons,
            hitNotifier: widget.hitNotifier,
            drawLabelsLast: true,
          ),
        if (_polylines.isNotEmpty)
          PolylineLayer(
            polylines: _polylines,
            hitNotifier: widget.hitNotifier,
            minimumHitbox: widget.polylineHitbox,
          ),
        if (_markers.isNotEmpty)
          MarkerLayer(
            markers: _markers,
          ),
      ],
    );
  }
}
