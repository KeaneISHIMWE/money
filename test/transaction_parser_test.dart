import 'package:flutter_test/flutter_test.dart';
import 'package:money/models/transaction.dart';

void main() {
  group('Transaction.fromSmsMessage parser', () {
    test('parses received message with ISO datetime and FT Id', () {
      final sms = 'You have received 5,000 RWF from John Doe (+250788123456) at 2025-11-06 11:09:16. Balance: 25,000 RWF. FT Id: 123456';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.type, equals('RECEIVED'));
      expect(tx.amount, equals(5000));
      expect(tx.counterparty.toLowerCase(), contains('john doe'));
      expect(tx.transactionId, equals('123456'));
      expect(tx.balance, equals(25000));
      expect(tx.date.year, equals(2025));
      expect(tx.date.month, equals(11));
      expect(tx.date.day, equals(6));
    });

    test('parses sent USSD transfer message', () {
      final sms = '*165*S*500 RWF transferred to Jane Smith (+250788654321) at 2025-11-06 11:20:54';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.type, equals('SENT'));
      expect(tx.amount, equals(500));
      expect(tx.counterparty.toLowerCase(), contains('jane smith'));
      // no tx id in this message
      expect(tx.transactionId, anyOf('', isNull));
    });
    

    test('parses payment message with Ref id', () {
      final sms = 'Your payment of 12,345 RWF to ACME Store was completed at 2025-12-01 09:15:00. Ref: ABC123';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.type, equals('SENT'));
      expect(tx.amount, equals(12345));
      expect(tx.counterparty.toLowerCase(), contains('acme'));
      expect(tx.transactionId?.toLowerCase(), contains('abc123'));
      expect(tx.date.year, equals(2025));
      expect(tx.date.month, equals(12));
      expect(tx.date.day, equals(1));
    });

    test('parses dmy date with phone as counterparty', () {
      final sms = 'You received 2,000 RWF from +250788000111 on 06/11/2025 11:09';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.type, equals('RECEIVED'));
      expect(tx.amount, equals(2000));
      expect(tx.counterparty, contains('+250788000111'));
      expect(tx.date.year, equals(2025));
      
      expect(tx.date.month, equals(11));
      expect(tx.date.day, equals(6));
    });

    test('parses message with fee and balance and TxId', () {
      final sms = 'You have paid 4,500 RWF to Electricity bill. Fee: 50 RWF. Balance: 1,500 RWF. TxId: 999888';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.type, equals('SENT'));
      expect(tx.amount, equals(4500));
      expect(tx.fee, equals(50));
      expect(tx.balance, equals(1500));
      expect(tx.transactionId, equals('999888'));
      expect(tx.counterparty.toLowerCase(), contains('electric'));
    });

    test('parses amount with spaces and dmy time format', () {
      final sms = 'Payment of 7 000 RWF to Vendor Name at 06/11/2025 10:05:30';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.amount, equals(7000));
      expect(tx.type, equals('SENT'));
      expect(tx.counterparty.toLowerCase(), contains('vendor'));
      expect(tx.date.year, equals(2025));
      expect(tx.date.month, equals(11));
      expect(tx.date.day, equals(6));
    });
    test('includes transfer fee in total cost for normal transfers', () {
      final sms =
          '*165*S*600 RWF transferred to Fabrice IRADUKUNDA (250794610891) at 2026-07-01 15:01:31 .Fee: 20RWF.Balance: 9380RWF.Dial *182*1*3# and send money abroad *RW#';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx, isNotNull);
      expect(tx!.amount, equals(600));
      expect(tx.fee, equals(20));
      expect(tx.totalCost, equals(620));
      expect(tx.expenseType, equals(ExpenseType.normalTransfer));
    });

    test('classifies airtime purchases', () {
      final sms =
          '*162*TxId:28804344117*S*Your payment of 750 RWF to Airtime with token  and ET Id: 28804344117 was completed at 2026-06-26 20:50:00. Fee 0 RWF. Balance: 21050 RWF . Message: - -. *RW#';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx!.expenseType, equals(ExpenseType.airtime));
      expect(tx.amount, equals(750));
      expect(tx.totalCost, equals(750));
    });

    test('classifies bundle and pack purchases', () {
      final sms =
          '*162*TxId:28780204274*S*Your payment of 200 RWF to Bundles and Packs with token  and ET Id: 28780204274 was completed at 2026-06-25 20:11:18. Fee 0 RWF. Balance: 80 RWF . Message: - -. *RW#';
      final tx = Transaction.fromSmsMessage(sms);
      expect(tx!.expenseType, equals(ExpenseType.bundleAndPack));
    });

    test('parses all three July 1 transfer messages from screenshot', () {
      final msgs = [
        '*165*S*600 RWF transferred to Fabrice IRADUKUNDA (250794610891) at 2026-07-01 15:01:31 .Fee: 20RWF.Balance: 9380RWF.Dial *182*1*3# and send money abroad *RW#',
        '*165*S*1000 RWF transferred to Kellen MANDELA (250798000752) at 2026-07-01 18:43:09 .Fee: 20RWF.Balance: 8360RWF.Dial *182*1*3# and send money abroad *RW#',
        '*165*S*1000 RWF transferred to Jean Claude TUYISENGE (250789626672) at 2026-07-01 19:02:18 .Fee: 20RWF.Balance: 7340RWF.Dial *182*1*3# and send money abroad *RW#',
      ];

      final parsed = msgs.map(Transaction.fromSmsMessage).whereType<Transaction>().toList();
      expect(parsed.length, equals(3));
      expect(parsed.where((t) => t.date.month == 7 && t.date.day == 1).length, equals(3));
      expect(
        parsed.fold<double>(0, (sum, t) => sum + t.amount),
        equals(2600),
      );
    });
  });
}
