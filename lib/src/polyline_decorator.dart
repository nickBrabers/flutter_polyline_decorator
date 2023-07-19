import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_polyline_decorator/src/pattern_utils.dart';
import 'package:latlong2/latlong.dart' as lat2;
import 'package:maps_toolkit/maps_toolkit.dart' as tools;

class PolylineDecoratorLayer extends StatelessWidget {
  final List<Polyline> polylines;

  final bool polylineCulling;

  final bool saveLayers;

  final DirectionOptions directionOptions;

  const PolylineDecoratorLayer({
    super.key,
    this.polylines = const [],
    this.polylineCulling = true,
    this.saveLayers = false,
    required this.directionOptions,
  });

  @override
  Widget build(BuildContext context) {
    final map = FlutterMapState.of(context);
    final size = Size(map.size.x, map.size.y);

    final List<Polyline> lines = polylineCulling
        ? polylines.where((p) {
            return p.boundingBox.isOverlapping(map.bounds);
          }).toList()
        : polylines;

    return Stack(
      children: <Widget>[
        CustomPaint(
          painter: PolylineDecoratorPainter(lines, saveLayers, map, directionOptions),
          size: size,
          isComplex: true,
        ),
      ],
    );
  }
}

class PolylineDecoratorPainter extends CustomPainter {
  final List<Polyline> lines;

  final bool saveLayers;

  final DirectionOptions directionOptions;

  final FlutterMapState map;
  final double zoom;
  final double rotation;

  PolylineDecoratorPainter(this.lines, this.saveLayers, this.map, this.directionOptions)
      : zoom = map.zoom,
        rotation = map.rotation;

  int get hash {
    _hash ??= Object.hashAll(lines);
    return _hash!;
  }

  int? _hash;

  List<Offset> getOffsets(List<lat2.LatLng> points) {
    return List.generate(
      points.length,
      (index) {
        return getOffset(points[index]);
      },
      growable: false,
    );
  }

  Offset getOffset(lat2.LatLng point) {
    return map.getOffsetFromOrigin(point);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    var path = ui.Path();
    var borderPath = ui.Path();
    var filterPath = ui.Path();
    var paint = Paint();
    Paint? borderPaint;
    Paint? filterPaint;
    int? lastHash;

    void drawPaths() {
      canvas.drawPath(path, paint);
      path = ui.Path();
      paint = Paint();

      if (borderPaint != null) {
        canvas.drawPath(borderPath, borderPaint!);
        borderPath = ui.Path();
        borderPaint = null;
      }

      if (filterPaint != null) {
        canvas.drawPath(filterPath, filterPaint!);
        filterPath = ui.Path();
        filterPaint = null;
      }
    }

    for (final polyline in lines) {
      final offsets = getOffsets(polyline.points);
      if (offsets.isEmpty) {
        continue;
      }

      final hash = polyline.renderHashCode;
      if (lastHash != null && lastHash != hash) {
        drawPaths();
      }
      lastHash = hash;

      late final double strokeWidth;
      if (polyline.useStrokeWidthInMeter) {
        final firstPoint = polyline.points.first;
        final firstOffset = offsets.first;
        final r = const lat2.Distance().offset(
          firstPoint,
          polyline.strokeWidth,
          180,
        );
        final delta = firstOffset - getOffset(r);

        strokeWidth = delta.distance;
      } else {
        strokeWidth = polyline.strokeWidth;
      }

      final isDotted = polyline.isDotted;
      paint = Paint()
        ..strokeWidth = strokeWidth
        ..strokeCap = polyline.strokeCap
        ..strokeJoin = polyline.strokeJoin
        ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
        ..blendMode = BlendMode.srcOver;

      if (polyline.gradientColors == null) {
        paint.color = polyline.color;
      } else {
        polyline.gradientColors!.isNotEmpty
            ? paint.shader = _paintGradient(polyline, offsets)
            : paint.color = polyline.color;
      }

      if (polyline.borderColor != null) {
        filterPaint = Paint()
          ..color = polyline.borderColor!.withAlpha(255)
          ..strokeWidth = strokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.dstOut;
      }

      if (polyline.borderStrokeWidth > 0.0) {
        borderPaint = Paint()
          ..color = polyline.borderColor ?? const Color(0x00000000)
          ..strokeWidth = strokeWidth + polyline.borderStrokeWidth
          ..strokeCap = polyline.strokeCap
          ..strokeJoin = polyline.strokeJoin
          ..style = isDotted ? PaintingStyle.fill : PaintingStyle.stroke
          ..blendMode = BlendMode.srcOver;
      }

      final radius = paint.strokeWidth / 2;
      final borderRadius = (borderPaint?.strokeWidth ?? 0) / 2;

      if (saveLayers) canvas.saveLayer(rect, Paint());
      if (isDotted) {
        final spacing = strokeWidth * 1.5;
        if (borderPaint != null && filterPaint != null) {
          _paintDottedLine(borderPath, offsets, borderRadius, spacing);
          _paintDottedLine(filterPath, offsets, radius, spacing);
        }
        _paintDottedLine(path, offsets, radius, spacing);
      } else {
        if (borderPaint != null && filterPaint != null) {
          _paintLine(borderPath, offsets);
          _paintLine(filterPath, offsets);
        }
        _paintLine(path, offsets);
      }

      _paintArrowHead(polyline, canvas);

      if (saveLayers) canvas.restore();
    }

    drawPaths();
  }

  void _paintArrowHead(Polyline polyline, Canvas canvas) {
    final points = projectPatternOnPointPath(
      polyline.points,
      directionOptions,
      map,
    );

    final indicatorPaint = Paint()..color = polyline.color;
    for (int i = 0; i < points.length; i++) {
      ProjectedPoint point = points[i];

      final heading =
          tools.SphericalUtil.computeHeading(point.pointA.toMapsToolkit, point.pointB.toMapsToolkit).toDouble();

      final arrowHeadPoints = _buildArrowPath(point.offset, heading);
      final arrowHeadPath = Path();
      arrowHeadPath.moveTo(arrowHeadPoints[0].dx, arrowHeadPoints[0].dy);
      arrowHeadPath.lineTo(arrowHeadPoints[1].dx, arrowHeadPoints[1].dy);
      arrowHeadPath.lineTo(arrowHeadPoints[2].dx, arrowHeadPoints[2].dy);
      arrowHeadPath.close();

      canvas.drawPath(arrowHeadPath, indicatorPaint);
    }
  }

  List<Offset> _buildArrowPath(Offset point, double heading) {
    const d2r = math.pi / 180;
    const headAngle = 90;
    const pixelSize = 15;
    const radianArrowAngle = headAngle / 2 * d2r;

    final tipPoint = point;
    final direction = (-(heading - 90)) * d2r;

    final headAngle1 = direction + radianArrowAngle;
    final headAngle2 = direction - radianArrowAngle;
    final arrowHead1 = Offset(
      tipPoint.dx - pixelSize * math.cos(headAngle1),
      tipPoint.dy + pixelSize * math.sin(headAngle1),
    );
    final arrowHead2 = Offset(
      tipPoint.dx - pixelSize * math.cos(headAngle2),
      tipPoint.dy + pixelSize * math.sin(headAngle2),
    );

    return [
      arrowHead1,
      tipPoint,
      arrowHead2,
    ];
  }

  void _paintDottedLine(ui.Path path, List<Offset> offsets, double radius, double stepLength) {
    var startDistance = 0.0;
    for (int i = 0; i < offsets.length - 1; i++) {
      final o0 = offsets[i];
      final o1 = offsets[i + 1];
      final totalDistance = (o0 - o1).distance;
      var distance = startDistance;
      while (distance < totalDistance) {
        final f1 = distance / totalDistance;
        final f0 = 1.0 - f1;
        final offset = Offset(o0.dx * f0 + o1.dx * f1, o0.dy * f0 + o1.dy * f1);
        path.addOval(Rect.fromCircle(center: offset, radius: radius));
        distance += stepLength;
      }
      startDistance = distance < totalDistance ? stepLength - (totalDistance - distance) : distance - totalDistance;
    }
    path.addOval(Rect.fromCircle(center: offsets.last, radius: radius));
  }

  void _paintLine(ui.Path path, List<Offset> offsets) {
    if (offsets.isEmpty) {
      return;
    }
    path.addPolygon(offsets, false);
  }

  ui.Gradient _paintGradient(Polyline polyline, List<Offset> offsets) =>
      ui.Gradient.linear(offsets.first, offsets.last, polyline.gradientColors!, _getColorsStop(polyline));

  List<double>? _getColorsStop(Polyline polyline) =>
      (polyline.colorsStop != null && polyline.colorsStop!.length == polyline.gradientColors!.length)
          ? polyline.colorsStop
          : _calculateColorsStop(polyline);

  List<double> _calculateColorsStop(Polyline polyline) {
    final colorsStopInterval = 1.0 / polyline.gradientColors!.length;
    return polyline.gradientColors!
        .map((gradientColor) => polyline.gradientColors!.indexOf(gradientColor) * colorsStopInterval)
        .toList();
  }

  @override
  bool shouldRepaint(PolylineDecoratorPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.rotation != rotation ||
        oldDelegate.lines.length != lines.length ||
        oldDelegate.hash != hash;
  }
}

extension _Lat2Extension on lat2.LatLng {
  tools.LatLng get toMapsToolkit {
    return tools.LatLng(latitude, longitude);
  }
}
