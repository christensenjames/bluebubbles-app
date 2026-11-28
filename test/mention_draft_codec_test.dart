import 'dart:convert';

import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mention drafts', () {
    late Handle alice;
    late Handle bob;
    late List<Mentionable> shared;
    late FocusNode focusNode;
    late MentionTextEditingController controller;

    setUp(() {
      GetIt.I.registerSingleton<SettingsService>(SettingsService()..settings = (Settings()..spellcheck.value = false));
      alice = Handle(address: 'alice@example.com');
      bob = Handle(address: 'bob@example.com');
      shared = [Mentionable(handle: alice), Mentionable(handle: bob)];
      focusNode = FocusNode();
      controller = MentionTextEditingController(focusNode: focusNode, mentionables: shared);
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
      GetIt.I.unregister<SettingsService>();
    });

    List<Run> persistedRuns() {
      final original = [
        Run(range: [3, 5], attributes: Attributes(mention: alice.address)),
        Run(
          range: [13, 3],
          attributes: Attributes(mention: bob.address, rawAttributes: {'__kIMTextBoldAttributeName': 1}),
        ),
      ];
      return (jsonDecode(jsonEncode(original.map((run) => run.toMap()).toList())) as List)
          .map((run) => Run.fromMap((run as Map).cast()))
          .toList();
    }

    test('restores persisted addresses after participants reorder', () {
      controller.restoreDraft('Hi Alice and Bob!', persistedRuns(), [bob, alice]);

      expect(controller.text, 'Hi Alice and Bob!');
      expect(controller.mentionRuns.map((run) => run.attributes!.mention), [alice.address, bob.address]);
      expect(controller.mentionables, same(shared));
      expect(shared.map((m) => m.address), [bob.address, alice.address]);
    });

    test('removes departed mentions but preserves text and formatting', () {
      controller.restoreDraft('Hi Alice and Bob!', persistedRuns(), [alice]);

      expect(controller.text, 'Hi Alice and Bob!');
      expect(controller.mentionRuns.map((run) => run.attributes!.mention), [alice.address]);
      expect(controller.runs.last.attributes!.isBold, isTrue);
      expect(controller.runs.last.attributes!.mention, isNull);
      expect(shared.map((m) => m.address), [alice.address]);
    });

    test('refreshes membership when restoring the same text and keeps the selection', () {
      controller.restoreDraft('Hi Alice and Bob!', persistedRuns(), [alice, bob]);
      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.restoreDraft('Hi Alice and Bob!', persistedRuns(), [bob]);

      expect(controller.selection, const TextSelection.collapsed(offset: 4));
      expect(controller.mentionRuns.map((run) => run.attributes!.mention), [bob.address]);
      expect(shared.map((m) => m.address), [bob.address]);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.restoreDraft('Hi Alice and Bob!', persistedRuns(), [alice]);
      expect(notifications, greaterThan(0));
    });

    test('restores old positional markers and makes invalid indices plain text', () {
      controller.restoreDraft('Hi ￼0￼ and ￼9￼!', null, [bob]);

      expect(controller.text, 'Hi ${shared.single.displayName} and 9!');
      expect(controller.mentionRuns.single.attributes!.mention, bob.address);
    });

    test('leaves a huge legacy index as plain text', () {
      const index = '999999999999999999999999999999999';
      controller.restoreDraft('Hi ￼$index￼!', null, [bob]);

      expect(controller.text, 'Hi $index!');
      expect(controller.mentionRuns, isEmpty);
    });
  });
}
