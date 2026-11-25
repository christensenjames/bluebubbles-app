import 'dart:async';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
ScheduledMessagesService get ScheduledMsgsSvc => GetIt.I<ScheduledMessagesService>();

class ScheduledMessagesService {
  final RxList<ScheduledMessage> scheduled = <ScheduledMessage>[].obs;
  final Rx<bool?> fetching = Rx<bool?>(true);
  int _revision = 0;
  int _request = 0;
  late final StreamSubscription _events;
  late final Worker _socketWorker;

  ScheduledMessagesService() {
    _events = EventDispatcherSvc.stream.listen((event) {
      if (!event.type.startsWith('scheduled-message-')) return;
      if (event.type == 'scheduled-message-deleted' || event.data is! Map) return unawaited(refresh());
      try {
        upsert(ScheduledMessage.fromJson(Map<String, dynamic>.from(event.data)));
      } on TypeError {
        // Some server events omit fields such as status or created; the list endpoint always has them.
        unawaited(refresh());
      }
    });
    _socketWorker = ever(SocketSvc.state, (SocketState state) {
      if (state == SocketState.connected) unawaited(refresh());
    });
    if (SettingsSvc.settings.finishedSetup.value) unawaited(refresh());
  }

  List<ScheduledMessage> pendingFor(String chatGuid) {
    final items = scheduled.where((item) => item.payload.chatGuid == chatGuid && item.status == 'pending').toList();
    items.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return items;
  }

  Future<void> refresh() async {
    final revision = _revision;
    final request = ++_request;
    // Once a list has loaded, a background refresh (every reconnect) must not swap the panels to a loader or error.
    final loaded = fetching.value == false;
    if (!loaded) fetching.value = true;
    try {
      final response = await HttpSvc.message.getScheduled();
      if (request != _request) return;
      if (revision != _revision) {
        unawaited(refresh());
        return;
      }
      if (response.statusCode == 200 && response.data['data'] is List) {
        scheduled.assignAll((response.data['data'] as List).map((item) => ScheduledMessage.fromJson(item)));
        fetching.value = false;
      } else {
        if (!loaded) fetching.value = null;
        Logger.error('Failed to fetch scheduled messages: ${response.statusCode}');
      }
    } catch (e, s) {
      if (request != _request) return;
      if (!loaded) fetching.value = null;
      Logger.error('Failed to fetch scheduled messages', error: e, trace: s);
    }
  }

  void upsert(ScheduledMessage item) {
    _revision++;
    final index = scheduled.indexWhere((entry) => entry.id == item.id);
    if (index == -1) {
      scheduled.add(item);
    } else {
      scheduled[index] = item;
    }
  }

  Future<ScheduledMessage?> create(String chatGuid, String message, DateTime date, Map<String, dynamic> schedule) async {
    try {
      final response = await HttpSvc.message.createScheduled(chatGuid, message, date, schedule);
      if (response.statusCode == 200 && response.data?['data'] != null) {
        final item = ScheduledMessage.fromJson(response.data['data']);
        upsert(item);
        return item;
      }
      Logger.error('Failed to create scheduled message: ${response.statusCode}');
    } catch (e, s) {
      Logger.error('Failed to create scheduled message', error: e, trace: s);
    }
    return null;
  }

  Future<ScheduledMessage?> update(ScheduledMessage item, {DateTime? date}) async {
    final scheduledFor = date ?? item.scheduledFor;
    try {
      final response = await HttpSvc.message.updateScheduled(
        item.id,
        item.payload.chatGuid,
        item.payload.message,
        scheduledFor,
        item.schedule.toJson()..removeWhere((_, value) => value == null),
        item.payload.method,
      );
      if (response.statusCode == 200 && response.data?['data'] != null) {
        final updated = ScheduledMessage.fromJson({
          ...item.toJson(),
          'scheduledFor': scheduledFor.toIso8601String(),
          ...Map<String, dynamic>.from(response.data['data']),
        });
        upsert(updated);
        return updated;
      }
      Logger.error('Failed to update scheduled message: ${response.statusCode}');
    } catch (e, s) {
      Logger.error('Failed to update scheduled message', error: e, trace: s);
    }
    return null;
  }

  Future<bool> delete(ScheduledMessage item) async {
    try {
      final response = await HttpSvc.message.deleteScheduled(item.id);
      if (response.statusCode == 200) {
        _revision++;
        scheduled.removeWhere((entry) => entry.id == item.id);
        return true;
      }
      Logger.error('Failed to delete scheduled message: ${response.statusCode}');
    } catch (e, s) {
      Logger.error('Failed to delete scheduled message', error: e, trace: s);
    }
    return false;
  }

  void dispose() {
    _events.cancel();
    _socketWorker.dispose();
  }
}
