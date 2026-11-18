import 'dart:typed_data';

import 'package:bluebubbles/helpers/network/metadata/models/metadata_fetch_result.dart';
import 'package:bluebubbles/helpers/network/metadata/network/url_safety_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_io/io.dart';

void main() {
  group('embedded IPv4 classification', () {
    final cases = <(List<int>, bool)>[
      ([0, 1, 2, 3], true),
      ([10, 0, 0, 1], true),
      ([127, 0, 0, 1], true),
      ([169, 254, 1, 1], true),
      ([172, 15, 0, 1], false),
      ([172, 16, 0, 1], true),
      ([172, 31, 0, 1], true),
      ([172, 32, 0, 1], false),
      ([192, 168, 1, 1], true),
      ([192, 0, 2, 1], true),
      ([100, 63, 0, 1], false),
      ([100, 64, 0, 1], true),
      ([100, 127, 0, 1], true),
      ([100, 128, 0, 1], false),
      ([198, 18, 0, 1], true),
      ([198, 19, 0, 1], true),
      ([198, 20, 0, 1], false),
      ([224, 0, 0, 1], true),
      ([240, 0, 0, 1], true),
      ([8, 8, 8, 8], false),
    ];

    for (final (v4, blocked) in cases) {
      test('NAT64 and 6to4 classify $v4 as ${blocked ? 'blocked' : 'public'}', () {
        final nat64 = InternetAddress.fromRawAddress(Uint8List.fromList([
          0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0, ...v4,
        ]));
        final sixToFour = InternetAddress.fromRawAddress(Uint8List.fromList([
          0x20, 0x02, ...v4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ]));
        expect(UrlSafetyGuard.isPrivateAddress(nat64), blocked);
        expect(UrlSafetyGuard.isPrivateAddress(sixToFour), blocked);
      });
    }

    test('does not classify adjacent prefixes as embedded IPv4', () {
      for (final raw in [
        [0, 0x64, 0xff, 0x9a, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 1],
        [0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 1, 10, 0, 0, 1],
        [0x20, 0x03, 10, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      ]) {
        expect(UrlSafetyGuard.isPrivateAddress(InternetAddress.fromRawAddress(Uint8List.fromList(raw))), isFalse);
      }
    });
  });

  test('literal checks preserve existing blocked and public behavior', () {
    for (final host in ['127.0.0.1', '10.0.0.1', '[::1]', '[fc00::1]', '[::ffff:192.168.1.1]']) {
      expect(UrlSafetyGuard.check(Uri.parse('https://$host/')), MetadataFetchStatus.blockedHost, reason: host);
    }
    for (final host in ['8.8.8.8', '[2606:4700:4700::1111]']) {
      expect(UrlSafetyGuard.check(Uri.parse('https://$host/')), isNull, reason: host);
    }
  });
}
