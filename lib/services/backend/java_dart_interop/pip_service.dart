import 'dart:async';

import 'package:bluebubbles/services/backend/java_dart_interop/method_channel_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
PipService get PipSvc => GetIt.I<PipService>();

class PipService {
  final RxBool active = false.obs;
  final StreamController<void> _dismissed = StreamController<void>.broadcast();

  Stream<void> get dismissed => _dismissed.stream;

  MethodChannelService? get _methodChannel {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    final service = MethodChannelSvc;
    if (service.headless || service.isBubble) return null;
    return service;
  }

  Future<bool> isSupported() async {
    final service = _methodChannel;
    if (service == null) return false;

    final result = await service.invokeMethod('pip-supported');
    return result is bool && result;
  }

  Future<void> enter({required double aspectRatio}) async {
    final service = _methodChannel;
    if (service == null) return;

    await service.invokeMethod('pip-enter', {'aspectRatio': aspectRatio});
  }

  Future<void> setAutoEnter({required bool enabled, double? aspectRatio}) async {
    final service = _methodChannel;
    if (service == null) return;

    await service.invokeMethod('pip-auto-enter', {'enabled': enabled, 'aspectRatio': ?aspectRatio});
  }

  void handleModeChanged(bool value) => active.value = value;

  void handleDismissed() => _dismissed.add(null);
}
