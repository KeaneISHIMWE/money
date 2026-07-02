import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// Exports SMS from the device to a text file.
class SmsExportService {
  static const defaultPhone = '0792431896';

  static List<String> phonePatterns(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('250')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return ['0$digits', '+250$digits', digits, '250$digits'];
  }

  static bool matchesPhone(SmsMessage message, List<String> patterns) {
    final address = (message.address ?? '').toLowerCase();
    final body = (message.body ?? '').toLowerCase();

    if (address == 'm-money') return true;

    for (final pattern in patterns) {
      final p = pattern.toLowerCase();
      if (address.contains(p) || body.contains(p)) {
        return true;
      }
    }
    return false;
  }

  /// Reads inbox + sent SMS and writes matches to [Downloads]/sms_[phone].txt.
  Future<File> exportToDownloads({String phone = defaultPhone}) async {
    if (kIsWeb) {
      throw UnsupportedError('SMS export is only available on Android.');
    }

    final query = SmsQuery();
    final inbox = await query.querySms(kinds: [SmsQueryKind.inbox]);
    final sent = await query.querySms(kinds: [SmsQueryKind.sent]);

    final seen = <String>{};
    final patterns = phonePatterns(phone);
    final matched = <SmsMessage>[];

    for (final message in [...inbox, ...sent]) {
      if (!matchesPhone(message, patterns)) continue;
      final key = '${message.date?.millisecondsSinceEpoch}-${message.body}';
      if (seen.add(key)) {
        matched.add(message);
      }
    }

    matched.sort(
      (a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)),
    );

    final dir = await getDownloadsDirectory();
    if (dir == null) {
      throw StateError('Could not access Downloads folder on this device.');
    }

    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    final local = normalized.startsWith('250')
        ? '0${normalized.substring(3)}'
        : (normalized.startsWith('0') ? normalized : '0$normalized');
    final file = File('${dir.path}/sms_$local.txt');

    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final buffer = StringBuffer()
      ..writeln('# SMS export for $local')
      ..writeln('# Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('# Messages: ${matched.length}')
      ..writeln();

    for (final message in matched) {
      final when = message.date != null
          ? fmt.format(message.date!.toLocal())
          : 'unknown-date';
      buffer
        ..writeln('----------------------------------------')
        ..writeln('Date:   $when')
        ..writeln('From:   ${message.address ?? ''}')
        ..writeln('Body:')
        ..writeln(message.body ?? '')
        ..writeln();
    }

    await file.writeAsString(buffer.toString());
    return file;
  }
}
