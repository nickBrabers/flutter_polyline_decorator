import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_decorator/flutter_polyline_decorator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const AppWidget());
}

class AppWidget extends StatelessWidget {
  const AppWidget({Key? key}) : super(key: key);

  List<Polyline> get polyline => [
        Polyline(
          color: Colors.red,
          points: [
            LatLng(-29.471818, -51.815828),
            LatLng(-29.4733316, -51.8159031),
            LatLng(-29.475307, -51.815764),
            LatLng(-29.475248, -51.813916),
            LatLng(-29.475244, -51.811104),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: MapOptions(
            center: LatLng(-29.4739022, -51.8154736),
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              tileProvider: NetworkTileProvider(),
            ),
            PolylineDecoratorLayer(
              polylines: polyline,
              directionOptions: const DirectionOptions(),
            ),
          ],
        ),
      ),
    );
  }
}
