import 'package:geolocator/geolocator.dart';

/// Outcome of asking the OS for permission. Lets the UI tell the
/// difference between "user said no" and "OS-level location is off".
enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Wrapper around `geolocator` so the dashboard never imports the SDK
/// directly. Centralises the position-stream settings — change the
/// distance filter or accuracy here and every consumer follows.
class LocationService {
  /// Asks the user for location permission, escalating only as far as
  /// needed. Returns a discriminating result so the caller can show a
  /// helpful banner ("turn on Location Services" vs. "open Settings").
  Future<LocationPermissionResult> ensurePermission() async {
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) return LocationPermissionResult.serviceDisabled;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionResult.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionResult.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionResult.denied;
    }
  }

  /// One-shot fix. Used by the commuter form to capture pickupCoords
  /// without keeping a long-lived stream open.
  Future<Position?> currentPosition() async {
    final perm = await ensurePermission();
    if (perm != LocationPermissionResult.granted) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Don't wait forever for a fix — better to write the ride
          // without coords than to keep the user staring at a spinner.
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Long-lived stream consumed by the driver presence provider.
  /// `distanceFilter: 10` keeps Firestore writes sane on a moving
  /// trike — at typical city speeds you get a write every couple of
  /// seconds, not every position sample.
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  /// Opens the OS app-settings page so the user can flip
  /// permanently-denied permission back to "ask".
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the OS location-services toggle.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
