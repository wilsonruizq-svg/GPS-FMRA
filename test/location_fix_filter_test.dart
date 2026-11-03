import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gps_fmra/modules/location/location_fix_filter.dart';

Position _pos({
  required double lat,
  required double lon,
  required double accuracy,
  DateTime? time,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: time ?? DateTime.utc(2026, 11, 2, 20, 25),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  const filter = LocationFixFilter();

  test('accepts cold-start fix within loose accuracy', () {
    expect(
      filter.accept(_pos(lat: 4.71, lon: -74.07, accuracy: 120)),
      isTrue,
    );
  });

  test('rejects cold-start fix with terrible accuracy', () {
    expect(
      filter.accept(_pos(lat: 4.71, lon: -74.07, accuracy: 400)),
      isFalse,
    );
  });

  test('rejects follow-up fix worse than maxAccuracyM', () {
    final prev = _pos(lat: 4.71, lon: -74.07, accuracy: 20);
    final next = _pos(lat: 4.71001, lon: -74.07, accuracy: 95);
    expect(filter.accept(next, previous: prev), isFalse);
  });

  test('rejects huge jump with worse accuracy', () {
    final prev = _pos(lat: 4.71, lon: -74.07, accuracy: 15);
    // ~500 m east
    final next = _pos(
      lat: 4.71,
      lon: -74.0655,
      accuracy: 60,
      time: DateTime.utc(2026, 11, 2, 20, 25, 10),
    );
    expect(filter.accept(next, previous: prev), isFalse);
  });

  test('shouldPublish heartbeats after maxPublishInterval', () {
    final a = _pos(lat: 4.71, lon: -74.07, accuracy: 12);
    final publishedAt = DateTime.utc(2026, 11, 2, 20, 25);
    expect(
      filter.shouldPublish(
        a,
        lastPublished: a,
        lastPublishedAt: publishedAt,
        now: publishedAt.add(const Duration(seconds: 9)),
      ),
      isTrue,
    );
  });

  test('shouldPublish waits min interval when stationary', () {
    final a = _pos(lat: 4.71, lon: -74.07, accuracy: 12);
    final publishedAt = DateTime.utc(2026, 11, 2, 20, 25);
    expect(
      filter.shouldPublish(
        a,
        lastPublished: a,
        lastPublishedAt: publishedAt,
        now: publishedAt.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('shouldPublish on meaningful move after min interval', () {
    final a = _pos(lat: 4.71, lon: -74.07, accuracy: 12);
    // ~15 m north
    final b = _pos(lat: 4.710135, lon: -74.07, accuracy: 12);
    final publishedAt = DateTime.utc(2026, 11, 2, 20, 25);
    expect(
      filter.shouldPublish(
        b,
        lastPublished: a,
        lastPublishedAt: publishedAt,
        now: publishedAt.add(const Duration(seconds: 6)),
      ),
      isTrue,
    );
  });
}
