import 'dart:math';

/// Great-circle distance in kilometres between two lat/lng points.
///
/// Used by the greedy nearest-driver matcher to rank drivers by proximity
/// to a ride's pickup. Accurate enough for our 0–5 km service radius;
/// no need for Vincenty over such short distances.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * pow(sin(dLng / 2), 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * pi / 180.0;
