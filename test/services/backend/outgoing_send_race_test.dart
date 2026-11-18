import 'dart:async';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/backend/outgoing_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OutgoingMessageHandler handler;
  late Chat chat;
  late Completer<Map<String, dynamic>> http;
  late Completer<void> successHandled;
  late Completer<void> failureHandled;
  late List<String> events;

  setUp(() {
    handler = OutgoingMessageHandler();
    chat = Chat(guid: 'chat');
    http = Completer<Map<String, dynamic>>();
    successHandled = Completer<void>();
    failureHandled = Completer<void>();
    events = [];
  });

  Future<void> send() => handler.sendWithRaceForTesting(
        tempGuid: 'temp',
        chat: chat,
        httpCall: () => http.future,
        onSuccess: (_) async {
          events.add('reconcile');
          successHandled.complete();
        },
        onError: (error, _) async {
          events.add('mark failed');
          failureHandled.complete();
        },
      );

  void socket() => handler.completeSendProgressIfExists('temp', Origin.incomingMessageHandler);

  test('socket first releases send and HTTP success still reconciles', () async {
    final result = send();
    socket();
    await result;
    expect(events, isEmpty);
    http.complete({'data': {'guid': 'server'}});
    await successHandled.future;
    expect(events, ['reconcile']);
  });

  test('HTTP success first releases send and late socket is harmless', () async {
    final result = send();
    http.complete({'data': {'guid': 'server'}});
    await result;
    await successHandled.future;
    socket();
    expect(events, ['reconcile']);
  });

  test('socket confirmation wins over a later HTTP failure', () async {
    final result = send();
    socket();
    await result;
    http.completeError(StateError('HTTP failed'));
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    expect(failureHandled.isCompleted, isFalse);
  });

  test('HTTP failure first fails send and late socket does not undo failure', () async {
    final result = send();
    final failure = StateError('HTTP failed');
    final assertion = expectLater(result, throwsA(same(failure)));
    http.completeError(failure);
    await assertion;
    await failureHandled.future;
    socket();
    expect(events, ['mark failed']);
  });
}
