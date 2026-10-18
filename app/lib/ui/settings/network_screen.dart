import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/network/wifi_direct.dart';
import '../../core/services/app_core.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Diagnostics + Wi-Fi Direct controls. Helps users understand *why* someone isn't reachable.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});
  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  List<String> _ips = [];
  List<Map<String, dynamic>> _wdPeers = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    WifiDirect.events.listen((e) {
      if (e['type'] == 'peers') _loadWd();
      if (mounted) setState(() {});
    });
  }

  Future<void> _refresh() async {
    final ips = <String>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          if (!a.isLoopback) ips.add('${a.address}  (${i.name})');
        }
      }
    } catch (_) {}
    setState(() => _ips = ips);
  }

  Future<void> _loadWd() async {
    final p = await WifiDirect.peers();
    if (mounted) setState(() => _wdPeers = p);
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final disc = core.cm.discovery?.current ?? [];
        return Scaffold(
          appBar: AppBar(title: const Text('Network'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)]),
          body: ListView(children: [
            _h('This device'),
            ListTile(leading: const Icon(Icons.router), title: const Text('Listening port'), subtitle: Text('${core.cm.port}')),
            for (final ip in _ips) ListTile(dense: true, leading: const Icon(Icons.lan), title: Text(ip)),
            if (_ips.isEmpty)
              const ListTile(leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('Not on any network'), subtitle: Text('Join a Wi-Fi, turn on a hotspot, or use Wi-Fi Direct below.')),
            _h('Discovered (${disc.length})'),
            for (final p in disc)
              ListTile(
                leading: Icon(core.cm.isOnline(p.userId) ? Icons.link : Icons.link_off,
                    color: core.cm.isOnline(p.userId) ? AppTheme.green : Colors.grey),
                title: Text(p.name),
                subtitle: Text('${p.host ?? '-'}:${p.port ?? '-'} via ${p.via}'),
              ),
            _h('Waiting to send'),
            ListTile(leading: const Icon(Icons.outbox), title: Text('${core.db.outboxCount()} encrypted messages queued'),
                subtitle: const Text('Delivered automatically the moment the recipient is nearby')),
            if (WifiDirect.available) ...[
              _h('Wi-Fi Direct (Android ↔ Android, no router needed)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, children: [
                  FilledButton.tonal(onPressed: () async { await WifiDirect.discover(); toast(context, 'Searching…'); }, child: const Text('Search')),
                  FilledButton.tonal(onPressed: () async { await WifiDirect.createGroup(); toast(context, 'Hosting a Wi-Fi Direct group'); }, child: const Text('Host')),
                  OutlinedButton(onPressed: WifiDirect.disconnect, child: const Text('Disconnect')),
                ]),
              ),
              for (final p in _wdPeers)
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(p['name'] as String? ?? 'Device'),
                  subtitle: Text(p['address'] as String? ?? ''),
                  trailing: TextButton(onPressed: () => WifiDirect.connect(p['address'] as String), child: const Text('Connect')),
                ),
            ],
            _h('Tips'),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Text(
                '• No Wi-Fi around? One person turns on their phone\'s hotspot (mobile data can be OFF) and the other joins it.\n'
                '• Some public/hotel Wi-Fi blocks devices from seeing each other ("client isolation"). Use a hotspot instead.\n'
                '• Can\'t see someone? Scan their QR code — it contains their address and connects directly.\n'
                '• iPhone ↔ iPhone also works with no network at all (Multipeer). iPhone ↔ Android needs a shared Wi-Fi or hotspot.',
                style: TextStyle(height: 1.5),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600)),
      );
}
