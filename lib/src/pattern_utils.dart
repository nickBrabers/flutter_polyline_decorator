import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

double pointDistance(Offset ptA, Offset ptB) {
  final x = ptB.dx - ptA.dx;
  final y = ptB.dy - ptA.dy;
  return math.sqrt(x * x + y * y);
}

double computeSegmentHeading(Offset a, Offset b) =>
    ((math.atan2(b.dx - a.dx, b.dy - a.dy) * 180 / math.pi) + 90 + 360) % 360;

double asRatioToPathLength(double valueInPixels, totalPathLength) {
  return valueInPixels / totalPathLength;
}

bool pointsEqual(LatLng a, LatLng b) {
  return a.latitude == b.latitude && a.longitude == b.longitude;
}

@immutable
class Segment {
  final Offset pointA;
  final Offset pointB;
  final double distanceA;
  final double distanceB;
  final double heading;

  final LatLng latLng1;
  final LatLng latLng2;

  const Segment(
    this.pointA,
    this.pointB,
    this.distanceA,
    this.distanceB,
    this.heading,
    this.latLng1,
    this.latLng2,
  );
}

List<Segment> pointsToSegments(List<LatLng> points, FlutterMapState mapState) {
  final segments = <Segment>[];
  for (int i = 0; i < points.length; i++) {
    final b = points[i];
    if (i > 0 && !pointsEqual(b, points[i - 1])) {
      final a = points[i - 1];
      final distA = segments.isNotEmpty ? segments[segments.length - 1].distanceB : 0.0;
      final offsetA = mapState.getOffsetFromOrigin(a);
      final offsetB = mapState.getOffsetFromOrigin(b);

      final distAB = pointDistance(offsetA, offsetB);

      segments.add(
        Segment(
          offsetA,
          offsetB,
          distA,
          distA + distAB,
          computeSegmentHeading(offsetA, offsetB),
          a,
          b,
        ),
      );
    }
  }
  return segments;
}

class ProjectedPoint {
  final Offset offset;
  final double heading;
  final LatLng pointA;
  final LatLng pointB;

  ProjectedPoint(this.offset, this.heading, this.pointA, this.pointB);

  @override
  String toString() {
    return 'Offset: $offset; Heading: $heading';
  }
}

@immutable
class DirectionOptions {
  final double offset;
  final double endOffset;
  final double repeat;

  const DirectionOptions({
    this.offset = 5,
    this.endOffset = 10,
    this.repeat = 200,
  });
}

List<ProjectedPoint> projectPatternOnPointPath(
  List<LatLng> pts,
  DirectionOptions options,
  FlutterMapState mapState,
) {
  // 1. split the path into segment infos
  final segments = pointsToSegments(pts, mapState);
  final nbSegments = segments.length;
  if (nbSegments == 0) {
    return [];
  }

  final totalPathLength = segments[nbSegments - 1].distanceB;

  final offset = asRatioToPathLength(options.offset, totalPathLength);
  final endOffset = asRatioToPathLength(options.endOffset, totalPathLength);
  final repeat = asRatioToPathLength(options.repeat, totalPathLength);

  final repeatIntervalPixels = totalPathLength * repeat;
  final startOffsetPixels = offset > 0 ? totalPathLength * offset : 0.0;
  final endOffsetPixels = endOffset > 0 ? totalPathLength * endOffset : 0.0;

  // 2. generate the positions of the pattern as offsets from the path start
  final positionOffsets = <double>[];
  double positionOffset = startOffsetPixels;
  do {
    positionOffsets.add(positionOffset);
    positionOffset += repeatIntervalPixels;
  } while (repeatIntervalPixels > 0 && positionOffset < totalPathLength - endOffsetPixels);

  // 3. projects offsets to segments
  int segmentIndex = 0;
  Segment segment = segments[0];
  return positionOffsets.map((offset) {
    // find the segment matching the offset,
    // starting from the previous one as offsets are ordered
    while (offset > segment.distanceB && segmentIndex < nbSegments - 1) {
      segmentIndex++;
      segment = segments[segmentIndex];
    }

    final segmentRatio = (offset - segment.distanceA) / (segment.distanceB - segment.distanceA);
    return ProjectedPoint(
      interpolateBetweenPoints(segment.pointA, segment.pointB, segmentRatio),
      segment.heading,
      segment.latLng1,
      segment.latLng2,
    );
  }).toList();
}

/// Finds the point which lies on the segment defined by points A and B,
/// at the given ratio of the distance from A to B, by linear interpolation.
Offset interpolateBetweenPoints(Offset ptA, Offset ptB, double ratio) {
  if (ptB.dy != ptA.dy) {
    return Offset(
      ptA.dx + ratio * (ptB.dx - ptA.dx),
      ptA.dy + ratio * (ptB.dy - ptA.dy),
    );
  }
  // special case where points lie on the same vertical axis
  return Offset(
    ptA.dx + (ptB.dx - ptA.dx) * ratio,
    ptA.dy,
  );
}
