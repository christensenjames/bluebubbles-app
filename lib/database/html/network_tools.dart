import 'dart:async';

Future<void> configureNetworkTools(String path, {bool enableDebugging = false}) async {}

class HostScannerService {
  static final instance = HostScannerService();

  Stream<ActiveHost> scanDevicesForSinglePort(String subnet, int port) => const Stream.empty();
}

class ActiveHost {
  String address = '';
}
