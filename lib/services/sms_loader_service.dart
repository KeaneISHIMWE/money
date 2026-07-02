import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

/// Loads M-Money SMS from the device inbox.
class SmsLoaderService {
  SmsLoaderService._();

  static bool isMMoneyMessage(SmsMessage message) {
    final address = (message.address ?? '').toLowerCase().trim();
    final body = message.body ?? '';
    if (address == 'm-money' || address.contains('m-money')) {
      return true;
    }
    return body.contains('*165*') ||
        body.contains('*162*') ||
        body.toLowerCase().contains('rwf');
  }

  /// Reads the full M-Money inbox. Tries the sender filter first, then scans
  /// the inbox so no messages are missed on devices with odd sender labels.
  static Future<List<SmsMessage>> loadMMoneyInbox() async {
    final query = SmsQuery();

    var messages = await query.querySms(
      kinds: [SmsQueryKind.inbox],
      address: 'M-Money',
    );

    if (messages.length < 2) {
      final inbox = await query.querySms(kinds: [SmsQueryKind.inbox]);
      final filtered = inbox.where(isMMoneyMessage).toList();
      if (filtered.length > messages.length) {
        messages = filtered;
      }
    }

    messages.sort(
      (a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)),
    );
    return messages;
  }
}
