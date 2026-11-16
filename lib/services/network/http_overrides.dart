import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/user_certificates.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

final RxBool serverCertificateMismatch = false.obs;

void recordValidServerCertificate(String host, int port) {
  final uri = Uri.tryParse(sanitizeServerAddress() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host != host || uri.port != port) return;
  final settings = SettingsSvc.settings;
  if (settings.serverCertificateFingerprint.value.isNotEmpty) return;
  // Reuse the trust slot so changing the server or resetting trust clears both modes.
  settings.serverCertificateFingerprint.value = 'ca:${uri.origin}';
  unawaited(settings.saveOneAsync('serverCertificateFingerprint'));
}

bool shouldAcceptCertificate(X509Certificate cert, String host, int port) {
  final uri = Uri.tryParse(sanitizeServerAddress() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host != host || uri.port != port) return false;

  final fingerprint = sha256.convert(cert.der).toString();
  final settings = SettingsSvc.settings;
  final pinnedFingerprint = settings.serverCertificateFingerprint.value;
  if (pinnedFingerprint.startsWith('ca:')) {
    serverCertificateMismatch.value = true;
    return false;
  }
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
