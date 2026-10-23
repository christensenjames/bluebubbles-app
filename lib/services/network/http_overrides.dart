import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/user_certificates.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

final RxBool serverCertificateMismatch = false.obs;

/// Shared certificate validation logic for both HTTP and WebSocket connections
/// Returns true if the certificate should be accepted (override bad cert), false otherwise
bool shouldAcceptCertificate(X509Certificate cert, String host, int port) {
  String serverUrl = sanitizeServerAddress() ?? "";

  // Extract hostname from the server URL
  Uri? uri = Uri.tryParse(serverUrl);
  if (uri == null) {
    return false;
  }

  if (uri.host != host) return false;

  final fingerprint = sha256.convert(cert.der).toString();
  final settings = SettingsSvc.settings;
  final pinnedFingerprint = settings.serverCertificateFingerprint.value;
  if (pinnedFingerprint.isEmpty) {
    settings.serverCertificateFingerprint.value = fingerprint;
    unawaited(settings.saveOneAsync('serverCertificateFingerprint'));
    serverCertificateMismatch.value = false;
    return true;
  }
  if (pinnedFingerprint == fingerprint) {
    serverCertificateMismatch.value = false;
    return true;
  }

  serverCertificateMismatch.value = true;
  Logger.warn('Server certificate fingerprint mismatch: expected $pinnedFingerprint, received $fingerprint',
      tag: 'HttpOverrides');
  return false;
}

class CustomHttpContext extends HttpOverrides {
  SecurityContext? _cachedContext;

  CustomHttpContext() {
    _initContext();
  }

  Future<void> _initContext() async {
    _cachedContext = await UserCertificates().getContext();
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Use the cached context with system + user certs
    final client = super.createHttpClient(_cachedContext ?? context);

    // Add custom certificate validation for self-signed certs and hostname mismatches
    client.badCertificateCallback = shouldAcceptCertificate;

    return client;
  }
}
