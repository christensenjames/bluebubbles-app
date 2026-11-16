import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

class NetworkTasks {
  /// Deduplicates concurrent detectLocalhost() calls — callers share one result.
  static Future<void>? _detectLocalhostFuture;

  /// Isolates that should receive [HttpSvc.originOverride] syncs.
  /// Populated via [registerIsolate] — no hardcoded types here.
  static final List<GlobalIsolate> _isolateRegistry = [];

  static Future<void> onConnect() async {
    if (!SettingsSvc.settings.finishedSetup.value) return;
    Logger.info('[NetworkTasks] Handling onConnect tasks. Finished Setup: ${SettingsSvc.settings.finishedSetup.value}');

    if (kIsWeb) {
      if (ChatsSvc.isEmpty) {
        ChatsSvc.reset();
        await ChatsSvc.init();
      }
    }

    // When we re-connect, try an incremental sync.
    // The sync function has a guard based on time to ensure that it doesn't
    // get invoked multiple times in quick succession.
    unawaited(SyncSvc.startIncrementalSync());
  }

  static Future<void> detectLocalhost({bool createSnackbar = false}) {
    // Deduplicate: if already running, all callers share the same future.
    _detectLocalhostFuture ??= _detectLocalhostImpl(createSnackbar: createSnackbar).whenComplete(() {
      _detectLocalhostFuture = null;
      // Not in setOriginOverride(): the probe clears the override midway.
      if (GetIt.I.isRegistered<SocketService>()) SocketSvc.followOrigin();
    });
    return _detectLocalhostFuture!;
  }

  static Future<void> _detectLocalhostImpl({bool createSnackbar = false}) async {
    // Clear the override so fresh local IPs are queried from the remote server.
    setOriginOverride(null);
    final port = SettingsSvc.settings.localhostPort.value;
    if (port == null || kIsWeb) return;

    final status = await Connectivity().checkConnectivity();
    if (!status.contains(ConnectivityResult.wifi) && !status.contains(ConnectivityResult.ethernet)) return;

    try {
      final response = await HttpSvc.server.info();
      final data = response.data?['data'];
      final localIpv4s = ((data?['local_ipv4s'] ?? []) as List).cast<String>();
      final localIpv6s = ((data?['local_ipv6s'] ?? []) as List).cast<String>();

      // IPv6 addresses need brackets in URLs: [::1]
      final candidates = [
        if (SettingsSvc.settings.useLocalIpv6.value) ...localIpv6s.map((ip) => '[$ip]'),
        ...localIpv4s,
      ];

      setOriginOverride(await _probeAddresses(candidates, port));
    } catch (e) {
      Logger.warn('Could not fetch server info for localhost detection: $e', tag: 'NetworkTasks');
    }

    if (HttpSvc.originOverride != null) {
      Logger.debug('Localhost detected at ${HttpSvc.originOverride}', tag: 'NetworkTasks');
      if (createSnackbar) {
        showToast('Connected to ${HttpSvc.originOverride}');
      }
    }
  }

  /// Sets [HttpSvc.originOverride] and syncs the new value to registered isolates.
  static void setOriginOverride(String? originOverride) {
    HttpSvc.originOverride = originOverride;
    syncOriginOverrideToIsolate();
  }

  /// Broadcasts the current [HttpSvc.originOverride] to [isolate], or — when
  /// called with no argument — to every registered isolate that is currently
  /// running (dormant isolates with idleTimeout=zero are skipped).
  static void syncOriginOverrideToIsolate([GlobalIsolate? isolate]) {
    if (kIsWeb) return;
    if (isolate != null) {
      isolate.broadcast(IsolateRequestType.setOriginOverride, HttpSvc.originOverride);
      return;
    }
    for (final candidate in _isolateRegistry) {
      if (candidate.isRunning) {
        candidate.broadcast(IsolateRequestType.setOriginOverride, HttpSvc.originOverride);
      }
    }
  }

  /// Registers [isolate] to receive [HttpSvc.originOverride] syncs.
  /// Also wires up a started callback so the override is re-synced
  /// automatically whenever the isolate (re)starts after an idle timeout.
  static void registerIsolate(GlobalIsolate isolate) {
    _isolateRegistry.add(isolate);
    isolate.addStartedCallback(() async {
      isolate.broadcast(IsolateRequestType.setOriginOverride, HttpSvc.originOverride);
    });
  }

  /// Probes [ips] on [port] with https then http, returning the first address
  /// that responds with "pong", or null if none respond.
  ///
  /// IPv6 addresses must already be bracket-formatted, e.g. `[::1]`.
  static Future<String?> _probeAddresses(List<String> ips, String port) async {
    for (final ip in ips) {
      for (final scheme in ['https', 'http']) {
        final addr = '$scheme://$ip:$port';
        try {
          final response = await HttpSvc.server.ping(customUrl: addr);
          if (response.data.toString().contains('pong')) return addr;
        } catch (_) {
          Logger.debug('Failed to connect to local address: $addr', tag: 'NetworkTasks');
        }
      }
    }
    return null;
  }
}
