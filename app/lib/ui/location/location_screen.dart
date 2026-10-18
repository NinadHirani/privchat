import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/app_core.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// GPS needs no internet. Map tiles do — so we use a compass + distance view
/// (works anywhere) and hand off to an offline maps app (OsmAnd / Organic Maps) via geo: URI.
Future<bool> ensureLocationPermission(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) toast(context, 'Turn on location (GPS) — it works without internet');
    return false;
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
    if (context.mounted) toast(context, 'Location permission denied');
    return false;
  }
  return true;
}

double distanceM(double lat1, double lng1, double lat2, double lng2) => Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

double bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180, dl = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String fmtDist(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 2 : 1)} km';

class ShareLocationScreen extends StatefulWidget {
  const ShareLocationScreen({super.key, required this.convId});
  final String convId;
  @override
  State<ShareLocationScreen> createState() => _ShareLocationScreenState();
}

class _ShareLocationScreenState extends State<ShareLocationScreen> {
  Position? _pos;
  String? _err;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await ensureLocationPermission(context)) {
      setState(() => _err = 'Location unavailable');
      return;
    }
    _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0))
        .listen((p) => setState(() => _pos = p), onError: (e) => setState(() => _err = '$e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _sendCurrent() async {
    final p = _pos!;
    await AppCore.I.messages.sendLocation(widget.convId, p.latitude, p.longitude, accuracy: p.accuracy);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _sendLive() async {
    final d = await showDialog<Duration>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Share live location for'), children: [
        for (final e in {'15 minutes': const Duration(minutes: 15), '1 hour': const Duration(hours: 1), '8 hours': const Duration(hours: 8)}.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, e.value), child: Padding(padding: const EdgeInsets.all(8), child: Text(e.key))),
      ]),
    );
    if (d == null) return;
    final positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).map((p) => (p.latitude, p.longitude, p.accuracy));
    await AppCore.I.messages.startLiveLocation(widget.convId, d, positions, lat: _pos!.latitude, lng: _pos!.longitude);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Send location')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _pos == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_err == null) const CircularProgressIndicator() else const Icon(Icons.location_off, size: 48),
                    const SizedBox(height: 16),
                    Text(_err ?? 'Getting GPS fix… (works offline, may take a minute outdoors)', textAlign: TextAlign.center),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.my_location, size: 72, color: AppTheme.teal),
                    const SizedBox(height: 16),
                    Text('${_pos!.latitude.toStringAsFixed(6)}, ${_pos!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
                    Text('Accuracy ±${_pos!.accuracy.round()} m', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(icon: const Icon(Icons.location_on), label: const Text('Send your current location'), onPressed: _sendCurrent),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(icon: const Icon(Icons.share_location), label: const Text('Share live location'), onPressed: _sendLive),
                    ),
                    const SizedBox(height: 16),
                    const Text('Live location updates are sent directly to the chat while you are near each other. '
                        'You can stop at any time.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
          ),
        ),
      );
}

class LocationViewScreen extends StatefulWidget {
  const LocationViewScreen({super.key, required this.msgId});
  final String msgId;
  @override
  State<LocationViewScreen> createState() => _LocationViewScreenState();
}

class _LocationViewScreenState extends State<LocationViewScreen> {
  Position? _me;
  double? _heading;
  StreamSubscription? _posSub, _compSub;

  @override
  void initState() {
    super.initState();
    AppCore.I.addListener(_refresh);
    _init();
  }

  void _refresh() => mounted ? setState(() {}) : null;

  Future<void> _init() async {
    _compSub = FlutterCompass.events?.listen((e) => setState(() => _heading = e.heading));
    if (await ensureLocationPermission(context)) {
      _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2))
          .listen((p) => setState(() => _me = p));
    }
  }

  @override
  void dispose() {
    AppCore.I.removeListener(_refresh);
    _posSub?.cancel();
    _compSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final m = core.db.message(widget.msgId);
    if (m == null) return const Scaffold(body: Center(child: Text('Location no longer available')));
    final lat = (m.body['lat'] as num).toDouble(), lng = (m.body['lng'] as num).toDouble();
    final live = m.kind == 'live_location';
    final active = live && m.body['active'] == true && ((m.body['until'] as num?) ?? 0) > DateTime.now().millisecondsSinceEpoch;
    final who = core.nameOf(m.senderId);
    double? dist, bearing;
    if (_me != null) {
      dist = distanceM(_me!.latitude, _me!.longitude, lat, lng);
      bearing = bearingDeg(_me!.latitude, _me!.longitude, lat, lng);
    }
    final rot = (bearing != null && _heading != null) ? (bearing - _heading!) * math.pi / 180 : null;
    final updated = (m.body['updated'] as num?)?.toInt() ?? m.ts;
    return Scaffold(
      appBar: AppBar(title: Text(live ? '$who · live location' : '$who\'s location')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (live)
          Center(
            child: Chip(
              avatar: Icon(Icons.circle, size: 12, color: active ? Colors.red : Colors.grey),
              label: Text(active ? 'Live · updated ${fmtTime(updated)}' : 'Live sharing ended · last ${fmtTime(updated)}'),
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 220, height: 220,
            child: Stack(alignment: Alignment.center, children: [
              Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.teal, width: 3))),
              if (rot != null)
                Transform.rotate(angle: rot, child: const Icon(Icons.navigation, size: 120, color: AppTheme.teal))
              else
                const Icon(Icons.explore, size: 100, color: Colors.grey),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(dist == null ? 'Finding your position…' : fmtDist(dist),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
        ),
        if (bearing != null)
          Center(child: Text('${bearing.round()}° from north${_heading == null ? ' · compass unavailable' : ''}',
              style: const TextStyle(color: Colors.grey))),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.place),
          title: SelectableText('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}', style: const TextStyle(fontFamily: 'monospace')),
          subtitle: m.body['acc'] != null ? Text('Accuracy ±${(m.body['acc'] as num).round()} m') : null,
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$lat,$lng'));
              toast(context, 'Coordinates copied');
            },
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.map),
          label: const Text('Open in maps app'),
          onPressed: () async {
            final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(who)})');
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              if (context.mounted) toast(context, 'No maps app installed. Tip: OsmAnd or Organic Maps work fully offline.');
            }
          },
        ),
        const SizedBox(height: 12),
        const Text('Tip: install OsmAnd or Organic Maps and download your region\'s map once — '
            'then maps work with zero internet too.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}
