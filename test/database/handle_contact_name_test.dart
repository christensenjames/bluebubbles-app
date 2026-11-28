import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/actions/contact_v2_actions.dart';
import 'package:bluebubbles/services/network/api/contact_api.dart';
import 'package:bluebubbles/services/network/http_service.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

class _ContactApi extends ContactApi {
  _ContactApi() : super(HttpService());

  List<Map<String, dynamic>> contacts = [];

  @override
  Future<List<Map<String, dynamic>>> fetchAllPages({required bool isV2Server, bool withAvatars = false}) async =>
      contacts;
}

void main() {
  setUpAll(openTestDatabase);
  setUp(Database.reset);

  test('native computed name and initials take priority over the server contact', () {
    final handle = Handle(address: 'person@example.com');
    Database.handles.put(handle);
    final server = ContactV2(displayName: 'Server Person', nativeContactId: 'server');
    final native = ContactV2(
      displayName: '',
      nativeContactId: 'native',
      isNative: true,
      firstName: 'Native',
      lastName: 'Person',
    );
    for (final contact in [server, native]) {
      contact.handles.add(handle);
      Database.contactsV2.put(contact);
    }

    final storedHandle = Database.handles.get(handle.id!)!;
    storedHandle.contactsV2.sort((a, b) => (a.isNative ? 1 : 0).compareTo(b.isNative ? 1 : 0));
    expect(storedHandle.contactsV2.map((contact) => contact.nativeContactId), ['server', 'native']);
    expect(storedHandle.displayName, 'Native Person');
    expect(storedHandle.reactionDisplayName, 'Native');
    expect(storedHandle.initials, 'NP');
  });

  test('reaction name uses native computed name before the server contact', () {
    final handle = Handle(address: 'person@example.com');
    handle.contactsV2.addAll([
      ContactV2(displayName: 'Server Person', nativeContactId: 'server'),
      ContactV2(displayName: '', nativeContactId: 'native', isNative: true, lastName: 'Native'),
    ]);

    expect(handle.reactionDisplayName, 'Native');
  });

  test('clearing a native raw display name selects its computed name over a server name', () {
    final handle = Handle(address: 'person@example.com');
    final native = ContactV2(
      displayName: 'Old Name',
      nativeContactId: 'native',
      isNative: true,
      firstName: 'Jane',
      lastName: 'Doe',
    );
    handle.contactsV2.addAll([ContactV2(displayName: 'Server Name', nativeContactId: 'server'), native]);
    expect(handle.displayName, 'Old Name');
    native.displayName = '';
    expect(handle.displayName, 'Jane Doe');
  });

  test('server name and initials are used when no native contact exists', () {
    final handle = Handle(address: 'person@example.com');
    handle.contactsV2.add(ContactV2(displayName: 'Server Person', nativeContactId: 'server'));

    expect(handle.displayName, 'Server Person');
    expect(handle.reactionDisplayName, 'Server Person');
    expect(handle.initials, 'SP');
  });

  test('sync refreshes handles when raw name changes but computed name does not', () async {
    final api = _ContactApi()
      ..contacts = [
        {
          'id': 'native',
          'displayName': '',
          'firstName': 'Jane',
          'lastName': 'Doe',
          'emails': [{'address': 'person@example.com'}],
        },
      ];
    GetIt.I.registerSingleton<HttpService>(HttpService()..contact = api);
    addTearDown(() => GetIt.I.unregister<HttpService>());
    final handle = Handle(address: 'person@example.com');
    Database.handles.put(handle);
    final contact = ContactV2(
      displayName: 'Old Name',
      nativeContactId: 'native',
      firstName: 'Jane',
      lastName: 'Doe',
    )..handles.add(handle);
    Database.contactsV2.put(contact);

    expect(Database.handles.get(handle.id!)!.displayName, 'Jane Doe');
    final affected = await ContactV2Actions.syncContactsToHandles({});
    expect(affected, contains(handle.id));
    expect(Database.contactsV2.get(contact.id)!.displayName, 'Jane Doe');
  });

  test('sync refreshes handles when initials change while the visible nickname stays the same', () async {
    final api = _ContactApi()
      ..contacts = [
        {
          'id': 'native',
          'displayName': 'Alice Smith',
          'firstName': 'Jane',
          'emails': [{'address': 'person@example.com'}],
        },
      ];
    GetIt.I.registerSingleton<HttpService>(HttpService()..contact = api);
    addTearDown(() => GetIt.I.unregister<HttpService>());
    final handle = Handle(address: 'person@example.com');
    Database.handles.put(handle);
    final contact = ContactV2(
      displayName: 'Alice Smith',
      nativeContactId: 'native',
      isNative: true,
      nickname: 'Alice Smith',
      firstName: 'John',
      lastName: 'Brown',
    )..handles.add(handle);
    Database.contactsV2.put(contact);

    expect(Database.handles.get(handle.id!)!.displayName, 'Alice Smith');
    expect(Database.handles.get(handle.id!)!.initials, 'JB');
    api.contacts.first['firstName'] = 'Alice';
    api.contacts.first['lastName'] = 'Smith';
    final affected = await ContactV2Actions.syncContactsToHandles({});
    expect(affected, contains(handle.id));
    final updated = Database.handles.get(handle.id!)!;
    expect(updated.displayName, 'Alice Smith');
    expect(updated.initials, 'AS');
  });
}
