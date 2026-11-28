import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

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

  test('server name and initials are used when no native contact exists', () {
    final handle = Handle(address: 'person@example.com');
    handle.contactsV2.add(ContactV2(displayName: 'Server Person', nativeContactId: 'server'));

    expect(handle.displayName, 'Server Person');
    expect(handle.reactionDisplayName, 'Server Person');
    expect(handle.initials, 'SP');
  });
}
