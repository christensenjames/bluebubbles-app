import 'package:bluebubbles/database/models.dart';

/// One participant. [name] null means no contact card, so the UI falls back to the raw address.
class FixturePerson {
  const FixturePerson(this.address, {this.name, this.first, this.last, this.formatted});

  final String address;
  final String? name;
  final String? first;
  final String? last;

  /// What the server sends as `formattedAddress` for phone numbers.
  final String? formatted;
}

class FixtureChat {
  const FixtureChat({
    required this.id,
    required this.people,
    required this.ago,
    this.displayName,
    this.text,
    this.attachments = const [],
    this.fromMe = false,
    this.unread = false,
    this.pinned = false,
    this.muted = false,
    this.spam = false,
    this.draft,
    this.error = 0,
  });

  final String id;
  final List<FixturePerson> people;

  /// Time since the latest message; negative is a message dated in the future (Mac clock ahead).
  final Duration ago;
  final String? displayName;
  final String? text;

  /// MIME types of the latest message's attachments.
  final List<String> attachments;
  final bool fromMe;
  final bool unread;
  final bool pinned;
  final bool muted;
  final bool spam;
  final String? draft;
  final int error;

  String get guid => people.length > 1 ? 'any;+;chat$id' : 'any;-;${people.first.address}';
}

class SnackbarFixture {
  const SnackbarFixture(this.title, this.message, {this.actionLabel, this.error = false});

  final String title;
  final String message;
  final String? actionLabel;
  final bool error;
}

// --- People -----------------------------------------------------------------------------------------------------

const _mom = FixturePerson('+15550100001', name: 'Mom', first: 'Mom', formatted: '+1 (555) 010-0001');
const _alex = FixturePerson('alex.chen@example.com', name: 'Alex Chen', first: 'Alex', last: 'Chen');
const _sam = FixturePerson('+15550100002', name: 'Sam Lee', first: 'Sam', last: 'Lee', formatted: '+1 (555) 010-0002');
const _priyaDemo = FixturePerson('+15550100003', name: 'Priya', first: 'Priya', formatted: '+1 (555) 010-0003');
const _jordan =
    FixturePerson('+15550100004', name: 'Jordan Park', first: 'Jordan', last: 'Park', formatted: '+1 (555) 010-0004');

const _aleksandra = FixturePerson('aleksandra.wisniewska-kowalczyk@example.com',
    name: 'Aleksandra Wiśniewska-Kowalczyk', first: 'Aleksandra', last: 'Wiśniewska-Kowalczyk');
const _bartholomewEmail = FixturePerson('bartholomew.fitzgerald@northwind-industries-holdings.example.com');
const _noor = FixturePerson('+971501234567',
    name: 'نور الهدى عبد الرحمن', first: 'نور الهدى', last: 'عبد الرحمن', formatted: '+971 50 123 4567');
const _wang = FixturePerson('+8613800138000', name: '王秀英', first: '秀英', last: '王', formatted: '+86 138 0013 8000');
const _priya = FixturePerson('+15550100010', name: '👩🏽‍💻 Priya Raman', formatted: '+1 (555) 010-0010');
const _fox = FixturePerson('+15550100011', name: '🦊 Fox', formatted: '+1 (555) 010-0011');
const _jo = FixturePerson('+15550100012', name: 'Jo', first: 'Jo', formatted: '+1 (555) 010-0012');
const _montgomery = FixturePerson('+15550100013',
    name: 'Christopher Alexander Montgomery III',
    first: 'Christopher',
    last: 'Montgomery',
    formatted: '+1 (555) 010-0013');
const _olafur = FixturePerson('olafur@example.is', name: 'Ólafur Darri Ólafsson');
const _dang = FixturePerson('+84912345678', name: 'Đặng Thị Ngọc Hân', formatted: '+84 91 234 56 78');
const _sean = FixturePerson('sean.obrien@example.ie', name: "Seán O'Brien-Ó Súilleabháin");
const _ukRaw = FixturePerson('+447700900123', formatted: '+44 7700 900123');
const _usRaw = FixturePerson('+12025550147', formatted: '+1 (202) 555-0147');
const _scamEmail = FixturePerson('usps-delivery-notice-tracking-update@secure-parcel-redelivery.example.com');

List<FixturePerson> _rawNumbers(int count, int start) => [
      for (int i = 0; i < count; i++)
        FixturePerson('+1202555${(start + i).toString().padLeft(4, '0')}',
            formatted: '+1 (202) 555-${(start + i).toString().padLeft(4, '0')}'),
    ];

/// 30 people: the three the title names first are emoji-first, long Latin, and RTL; then 27 more.
final List<FixturePerson> _thirty = [
  _priya,
  _aleksandra,
  _noor,
  _wang,
  _fox,
  _jo,
  _montgomery,
  _olafur,
  _dang,
  _sean,
  ..._rawNumbers(20, 120),
];

// --- Datasets ---------------------------------------------------------------------------------------------------

const _demo = <FixtureChat>[
  FixtureChat(id: 'mom', people: [_mom], ago: Duration(minutes: 5), text: 'See you Sunday!', unread: true),
  FixtureChat(
      id: 'bookclub',
      people: [_alex, _sam, _priyaDemo, _jordan],
      displayName: 'Book Club',
      ago: Duration(hours: 3),
      text: "I'll bring snacks"),
  FixtureChat(id: 'alex', people: [_alex], ago: Duration(days: 1), text: 'Sounds good 👍'),
  FixtureChat(id: 'sam', people: [_sam], ago: Duration(days: 2), text: 'Thanks!', fromMe: true),
  FixtureChat(id: 'jordan', people: [_jordan], ago: Duration(days: 3), attachments: ['image/jpeg']),
  FixtureChat(
      id: 'spam1',
      people: [FixturePerson('+15550100199', formatted: '+1 (555) 010-0199')],
      ago: Duration(hours: 1),
      text: 'Your package is waiting. Reply Y to confirm delivery.',
      spam: true),
];

final _worst = <FixtureChat>[
  // First, so its people get the lowest handle ids: titles list handles in id order.
  FixtureChat(id: 'thirty', people: _thirty, ago: const Duration(minutes: 40), text: '', unread: true),
  const FixtureChat(
    id: 'reunion',
    people: [_aleksandra, _sean, _olafur, _dang, _montgomery],
    displayName: 'Wiśniewska-Kowalczyk Family Reunion 2026 — Planning Committee (Kraków)',
    ago: Duration.zero,
    text: 'bartholomew.fitzgerald@northwind-industries-holdings.example.com shared the itinerary: '
        'https://example.com/workspaces/acme/projects/q3-launch/docs/9f8e7d6c5b4a?tab=comments&filter=unresolved',
    unread: true,
    pinned: true,
    muted: true,
  ),
  const FixtureChat(
    id: 'bartholomew',
    people: [_bartholomewEmail],
    ago: Duration(minutes: 12),
    attachments: ['image/heic', 'image/heic', 'image/heic', 'video/quicktime'],
    fromMe: true,
  ),
  const FixtureChat(
    id: 'noor',
    people: [_noor],
    ago: Duration(hours: 5),
    text: 'هل ستصل قبل الساعة الثامنة؟ الطريق مزدحم جدًا اليوم بسبب المطر',
    unread: true,
    muted: true,
  ),
  const FixtureChat(
    id: 'uk',
    people: [_ukRaw],
    ago: Duration(hours: 9),
    text: 'Hi, is this still the number for the flat viewing on Saturday?',
    draft: 'Running late, be there in 10',
  ),
  const FixtureChat(
    id: 'jo',
    people: [_jo],
    ago: Duration(days: 1),
    text: 'ok',
    fromMe: true,
    error: 22,
  ),
  const FixtureChat(
    id: 'wang',
    people: [_wang],
    ago: Duration(days: 4),
    text: '明天下午三点在公司楼下的咖啡店见面吧，我会把合同的最终版本打印出来带过去给你签字。',
  ),
  const FixtureChat(
    id: 'montgomery',
    people: [_montgomery],
    ago: Duration(days: 330),
    text: 'Line one of the address\nLine two: Flat 4B, 221 Baker Street',
  ),
  const FixtureChat(
    id: 'priya',
    people: [_priya],
    ago: Duration(days: 365 * 3),
    attachments: ['audio/x-m4a', 'audio/x-m4a'],
  ),
  const FixtureChat(
    id: 'pair',
    people: [_dang, _sean],
    ago: Duration(days: 9),
    attachments: ['application/zip'],
  ),
  const FixtureChat(
    id: 'fox',
    people: [_fox],
    ago: Duration(minutes: -3),
    text: '🎉🎉🎉',
  ),
  const FixtureChat(
    id: 'olafur',
    people: [_olafur],
    ago: Duration(days: 20),
    text: 'Takk fyrir síðast!',
  ),
  // Likely spam
  const FixtureChat(
    id: 'scam-email',
    people: [_scamEmail],
    ago: Duration(minutes: 2),
    text: 'USPS: Your parcel US9514901185421 could not be delivered due to an incomplete address. '
        'Update within 12 hours: https://usps.example.com/redelivery/track?id=US9514901185421&ref=sms',
    unread: true,
    spam: true,
  ),
  const FixtureChat(
    id: 'scam-number',
    people: [_usRaw],
    ago: Duration(hours: 2),
    text: 'Hi',
    spam: true,
  ),
  FixtureChat(
    id: 'scam-blast',
    people: _rawNumbers(30, 101),
    ago: const Duration(days: 2),
    attachments: ['image/jpeg'],
    unread: true,
    spam: true,
  ),
];

const _one = <FixtureChat>[
  FixtureChat(id: 'one', people: [_jo], ago: Duration(minutes: 1), attachments: ['image/jpeg'], unread: true),
  FixtureChat(
      id: 'one-spam',
      people: [FixturePerson('+15550100199', formatted: '+1 (555) 010-0199')],
      ago: Duration(hours: 1),
      text: 'Hi',
      spam: true),
];

List<FixtureChat> fixtureChats(String name) => switch (name) {
      'demo' => _demo,
      'worst' => _worst,
      'one' => _one,
      'empty' => const [],
      _ => throw ArgumentError('BB_FIXTURE must be demo, worst, one or empty, not "$name"'),
    };

/// The data each in-scope showSnackbar caller passes, worst realistic value per caller.
SnackbarFixture snackbarFixture(String name) => switch (name) {
      // list_item.dart: swipe-to-delete passes the chat title as the message.
      'delete' => SnackbarFixture('Conversation deleted', _worst.firstWhere((c) => c.id == 'reunion').displayName!,
          actionLabel: 'Undo'),
      // Same string ChatState builds for the thirty group: each name in an FSI/PDI isolate.
      'delete-thirty' => const SnackbarFixture(
          'Conversation deleted', '\u2068👩🏽‍💻\u2069, \u2068Aleksandra\u2069, \u2068نور\u2069 & 27 others',
          actionLabel: 'Undo'),
      // attachments_service.dart: desktop save passes the saved file's name.
      'save' => const SnackbarFixture(
          'Success', 'Saved attachment to Q3 Board Deck — FINAL (revised) v12 [approved by legal].pdf!',
          actionLabel: 'Open file'),
      // spam_action.dart: the "Not spam" banner's failure path names the chat.
      'spam-error' => const SnackbarFixture('Error',
          "Couldn't update spam status for usps-delivery-notice-tracking-update@secure-parcel-redelivery.example.com",
          error: true),
      _ => throw ArgumentError('BB_SNACKBAR must be delete, delete-thirty, save or spam-error, not "$name"'),
    };

/// Writes [chats] into an empty store, through the same entities sync produces.
void seedFixture(Store store, List<FixtureChat> chats) {
  final handleBox = store.box<Handle>();
  final contactBox = store.box<ContactV2>();
  final chatBox = store.box<Chat>();
  final messageBox = store.box<Message>();
  final attachmentBox = store.box<Attachment>();
  final now = DateTime.now();
  final handles = <String, Handle>{};
  var rowid = 1000;

  Handle handleFor(FixturePerson p) => handles.putIfAbsent(p.address, () {
        final isEmail = p.address.contains('@');
        final h = Handle(
          address: p.address,
          formattedAddress: isEmail ? p.address : p.formatted,
          originalROWID: rowid++,
          service: 'iMessage',
        );
        handleBox.put(h);
        if (p.name != null) {
          final c = ContactV2(
            displayName: p.name!,
            nativeContactId: 'break-ui:${p.address}',
            addresses: [isEmail ? ContactV2.normalizeEmail(p.address) : ContactV2.normalizePhoneNumber(p.address)],
            firstName: p.first,
            lastName: p.last,
          );
          c.handles.add(h);
          contactBox.put(c);
        }
        return h;
      });

  store.runInTransaction(TxMode.write, () {
    var pinIndex = 0;
    for (final f in chats) {
      final chat = Chat(
        guid: f.guid,
        chatIdentifier: f.people.length > 1 ? 'chat${f.id}' : f.people.first.address,
        displayName: f.displayName,
        hasUnreadMessage: f.unread,
        isPinned: f.pinned,
        pinnedIndex: f.pinned ? pinIndex++ : null,
        muteType: f.muted ? 'mute' : null,
        spamVerdict: f.spam ? 'spam' : null,
        textFieldText: f.draft,
        style: f.people.length > 1 ? 43 : 45,
      );
      chat.handles.addAll(f.people.map(handleFor));
      chatBox.put(chat);

      final date = now.subtract(f.ago);
      final sender = handleFor(f.people.first);
      final message = Message(
        guid: 'break-ui-${f.id}',
        text: f.text,
        dateCreated: date,
        dateDelivered: f.fromMe ? date : null,
        isFromMe: f.fromMe,
        handleId: f.fromMe ? 0 : sender.originalROWID,
        hasAttachments: f.attachments.isNotEmpty,
        error: f.error,
      );
      message.chat.target = chat;
      if (!f.fromMe) message.handleRelation.target = sender;
      messageBox.put(message);

      for (int i = 0; i < f.attachments.length; i++) {
        final mime = f.attachments[i];
        final attachment = Attachment(
          guid: 'break-ui-${f.id}-att$i',
          mimeType: mime,
          transferName: 'IMG_20250914_18302${i}_HDR_portrait_edited_edited.${mime.split('/').last.toUpperCase()}',
          isOutgoing: f.fromMe,
          totalBytes: 2400000,
          width: 3024,
          height: 4032,
        );
        attachment.message.target = message;
        attachmentBox.put(attachment);
      }

      chat.dbLatestMessage.target = message;
      chat.dbOnlyLatestMessageDate = date;
      chatBox.put(chat);
    }
  });
}
