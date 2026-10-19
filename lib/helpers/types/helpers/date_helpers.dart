import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:intl/intl.dart';
import 'package:universal_io/io.dart';

const _hour12Pattern = 'h:mm a';

DateFormat get _timeFormat => DateFormat(SettingsSvc.settings.use24HrFormat.value ? 'Hm' : _hour12Pattern);

// Must run after initializeDateFormatting(), since DateFormat.localeExists only knows initialized locales.
void setDefaultDateLocale() {
  final name = Platform.localeName.split(RegExp(r'[.@]')).first;
  if (name == 'C' || name == 'POSIX') {
    Intl.defaultLocale = 'en_US';
    return;
  }
  final locale = Intl.canonicalizedLocale(name);
  Intl.defaultLocale =
      [locale, Intl.shortLocale(locale)].firstWhere(DateFormat.localeExists, orElse: () => 'en_US');
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  if (value is DateTime) return value;
  return null;
}

String buildDate(DateTime? dateTime) {
  if (dateTime == null || dateTime.millisecondsSinceEpoch == 0) return "";
  dateTime = dateTime.toLocal();
  String time = _timeFormat.format(dateTime);
  String date;
  final elapsed = DateTime.now().difference(dateTime);
  if (SettingsSvc.settings.skin.value != Skins.iOS && elapsed.inMinutes == 0) {
    date = "Just Now";
  } else if (SettingsSvc.settings.skin.value != Skins.iOS && !elapsed.isNegative && elapsed.inHours < 1) {
    date = "${elapsed.inMinutes} min";
  } else if (dateTime.isToday()) {
    date = time;
  } else if (SettingsSvc.settings.skin.value == Skins.iOS && dateTime.isYesterday()) {
    date = "Yesterday";
  } else if (!elapsed.isNegative && elapsed.inDays <= 7) {
    date =
        "${DateFormat(SettingsSvc.settings.skin.value != Skins.iOS ? "EEE" : "EEEE").format(dateTime)}${SettingsSvc.settings.skin.value != Skins.iOS ? " $time" : ""}";
  } else if (SettingsSvc.settings.skin.value == Skins.Material && elapsed.inDays.abs() <= 365) {
    date = "${DateFormat.MMMd().format(dateTime)}, $time";
  } else if (SettingsSvc.settings.skin.value == Skins.Samsung && DateTime.now().year == dateTime.year) {
    date = DateFormat.MMMd().format(dateTime);
  } else if (SettingsSvc.settings.skin.value == Skins.Samsung && DateTime.now().year != dateTime.year) {
    date = DateFormat.yMMMd().format(dateTime);
  } else {
    date = DateFormat.yMd().format(dateTime);
  }
  return date;
}

String buildChatListDateMaterial(DateTime? dateTime) {
  if (dateTime == null || dateTime.millisecondsSinceEpoch == 0) return "";
  dateTime = dateTime.toLocal();
  String date;
  final elapsed = DateTime.now().difference(dateTime);
  if (elapsed.inMinutes == 0) {
    date = "Just Now";
  } else if (!elapsed.isNegative && elapsed.inHours < 1) {
    date = "${elapsed.inMinutes} min";
  } else if (!elapsed.isNegative && elapsed.inDays <= 7) {
    date = DateFormat("EEE").format(dateTime);
  } else if (SettingsSvc.settings.skin.value == Skins.Material && elapsed.inDays.abs() <= 365) {
    date = DateFormat.MMMd().format(dateTime);
  } else if (SettingsSvc.settings.skin.value == Skins.Samsung && DateTime.now().year == dateTime.year) {
    date = DateFormat.MMMd().format(dateTime);
  } else if (SettingsSvc.settings.skin.value == Skins.Samsung && DateTime.now().year != dateTime.year) {
    date = DateFormat.yMMMd().format(dateTime);
  } else {
    date = DateFormat.yMd().format(dateTime);
  }
  return date;
}

String buildSeparatorDateMaterial(DateTime dateTime) {
  return DateFormat.MMMEd().format(dateTime.toLocal());
}

String buildSeparatorDateSamsung(DateTime dateTime) {
  return DateFormat.yMMMMEEEEd().format(dateTime.toLocal());
}

String buildTime(DateTime? dateTime) {
  if (dateTime == null || dateTime.millisecondsSinceEpoch == 0) return "";
  dateTime = dateTime.toLocal();
  String time = _timeFormat.format(dateTime);
  return time;
}

String buildFullDate(DateTime time, {bool includeTime = true, bool useTodayYesterday = true}) {
  if (time.millisecondsSinceEpoch == 0) return "";
  time = time.toLocal();

  late String date;
  if (includeTime) {
    if (SettingsSvc.settings.use24HrFormat.value) {
      if (useTodayYesterday) {
        if (time.isToday()) {
          date = "Today, ${DateFormat.Hm().format(time)}";
        } else if (time.isYesterday()) {
          date = "Yesterday, ${DateFormat.Hm().format(time)}";
        } else {
          date = DateFormat.yMd().add_Hm().format(time);
        }
      } else {
        date = DateFormat.yMd().add_Hm().format(time);
      }
    } else {
      if (useTodayYesterday) {
        if (time.isToday()) {
          date = "Today, ${DateFormat(_hour12Pattern).format(time)}";
        } else if (time.isYesterday()) {
          date = "Yesterday, ${DateFormat(_hour12Pattern).format(time)}";
        } else {
          date = DateFormat.yMd().addPattern(_hour12Pattern).format(time);
        }
      } else {
        date = DateFormat.yMd().addPattern(_hour12Pattern).format(time);
      }
    }
  } else {
    if (useTodayYesterday) {
      if (time.isToday()) {
        date = "Today";
      } else if (time.isYesterday()) {
        date = "Yesterday";
      } else {
        date = DateFormat.yMd().format(time);
      }
    } else {
      date = DateFormat.yMd().format(time);
    }
  }

  return date;
}
