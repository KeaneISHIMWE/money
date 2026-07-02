import 'package:intl/intl.dart';

// Normalize a DMY date string (e.g., '06/11/2025') and optional time ('11:09:16' or '11:09')
// into an ISO 8601 datetime string parseable by DateTime.parse.
String _normalizeDmyToIso(String dmy, String? time) {
  try {
    final parts = dmy.split(RegExp(r'[\/\-]'));
    if (parts.length != 3) {
      throw FormatException('Unexpected DMY format');
    }
    final day = int.parse(parts[0].padLeft(2, '0'));
    final month = int.parse(parts[1].padLeft(2, '0'));
    final year = int.parse(parts[2]);

    String timePart = '00:00:00';
    if (time != null && time.trim().isNotEmpty) {
      final t = time.trim();
      final timeParts = t.split(':');
      final hour = int.parse(timeParts[0].padLeft(2, '0'));
      final minute = timeParts.length > 1 ? int.parse(timeParts[1].padLeft(2, '0')) : 0;
      final second = timeParts.length > 2 ? int.parse(timeParts[2].padLeft(2, '0')) : 0;
      timePart = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
    }

    final dt = DateTime(year, month, day, int.parse(timePart.split(':')[0]), int.parse(timePart.split(':')[1]), int.parse(timePart.split(':')[2]));
    return dt.toIso8601String();
  } catch (e) {
    // Fallback to current time ISO if parsing fails
    return DateTime.now().toIso8601String();
  }
}

/// M-Money expense types derived from SMS templates.
class ExpenseType {
  static const normalTransfer = 'normal_transfer';
  static const airtime = 'airtime';
  static const bundleAndPack = 'bundle_and_pack';
  static const payment = 'payment';
  static const other = 'other';

  static String label(String expenseType) {
    switch (expenseType) {
      case normalTransfer:
        return 'Normal Transfer';
      case airtime:
        return 'Airtime';
      case bundleAndPack:
        return 'Bundle and Pack';
      case payment:
        return 'Payment';
      default:
        return 'Other';
    }
  }

  /// Classifies outgoing M-Money SMS into expense types.
  static String classify(String body) {
    final lc = body.toLowerCase();

    if (lc.contains('payment of') && lc.contains('to airtime')) {
      return airtime;
    }
    if (lc.contains('payment of') && lc.contains('to bundles and packs')) {
      return bundleAndPack;
    }
    if (body.contains('*165*S*') && lc.contains('transferred to')) {
      return normalTransfer;
    }
    if (lc.contains('transferred to')) {
      return normalTransfer;
    }
    if (lc.contains('payment of') || body.contains('*162*')) {
      return payment;
    }

    return other;
  }
}

class Transaction {
  final double amount;
  final DateTime date;
  final String transactionId;
  final String counterparty;
  final String type;
  final double fee;
  final double balance;
  final String expenseType;

  Transaction({
    required this.amount,
    required this.date,
    required this.transactionId,
    required this.counterparty,
    required this.type,
    required this.fee,
    required this.balance,
    this.expenseType = ExpenseType.other,
  });

  bool get isReceived => type == 'RECEIVED';
  bool get isSent => type == 'SENT';

  /// Total debited for outgoing transactions (transfer amount + fee).
  double get totalCost => isSent ? amount + fee : amount;

  static Transaction? fromSmsMessage(String body, {DateTime? smsDate}) {
    try {
      // Robust heuristic-based parsing to support a broader set of MoMo templates.
      // Strategy: detect SENT vs RECEIVED via keywords, then extract amount, counterparty,
      // and date using targeted regexes. This approach handles ISO datetimes, common
      // local formats (dd/mm/yyyy), and messages lacking explicit timestamps.

      // Keyword-based type detection
      final lc = body.toLowerCase();
      String type = 'UNKNOWN';
      if (lc.contains('received') || lc.contains('credited') || lc.contains('you have received')) {
        type = 'RECEIVED';
      } else if (lc.contains('transferred to') || lc.contains('you sent') || lc.contains('sent') || lc.contains('paid') || lc.contains('payment of') || lc.contains('you have paid')) {
        type = 'SENT';
      }

      // Extract amount (first RWF-like amount in the body).
      // Must support 4+ digit amounts without separators (e.g. "1000 RWF").
      final amountMatch = RegExp(
        r'(\d+(?:[,\s]\d{3})*(?:\.\d+)?)\s*RWF',
        caseSensitive: false,
      ).firstMatch(body);
      final amount = amountMatch != null ? (double.tryParse(amountMatch.group(1)!.replaceAll(RegExp(r'[,\s]'), '')) ?? 0.0) : 0.0;

      // Extract counterparty using payment/transfer templates first.
      String counterparty = 'Unknown';
      final paymentToMatch = RegExp(
        r'payment of [^.]+ to (.+?)(?:\s+with token|\s+was completed|\s+at\s+)',
        caseSensitive: false,
      ).firstMatch(body);
      final transferToMatch = RegExp(
        r'transferred to\s+(.+?)(?:\s*\(|\.|\s+at\s+)',
        caseSensitive: false,
      ).firstMatch(body);

      if (transferToMatch != null) {
        counterparty = transferToMatch.group(1)!.trim();
      } else if (paymentToMatch != null) {
        counterparty = paymentToMatch.group(1)!.trim();
      } else {
      final cpRegex = RegExp(r'(?:from|to)\s+(.{2,80})(?=(?:\s*\(|\.|,|\s+at\s+|\s+was\s+|\s+on\s+|$))', caseSensitive: false);
      final cpMatch = cpRegex.firstMatch(body);
      if (cpMatch != null) {
        counterparty = cpMatch.group(1)!.trim();
      } else {
        // Fallback: try to locate a phone number near the amount or anywhere in the body
        final amountIndex = amountMatch?.start ?? -1;
        if (amountIndex >= 0 && amountIndex < body.length) {
          final tail = body.substring(amountIndex);
          final phoneNearAmount = RegExp(r'(?:\+?\d{8,15}|0\d{8,12})').firstMatch(tail);
          if (phoneNearAmount != null) {
            counterparty = phoneNearAmount.group(0)!;
          } else {
            final phoneAny = RegExp(r'(?:\+?\d{8,15}|0\d{8,12})').firstMatch(body);
            if (phoneAny != null) counterparty = phoneAny.group(0)!;
          }
        } else {
          final phoneAny = RegExp(r'(?:\+?\d{8,15}|0\d{8,12})').firstMatch(body);
          if (phoneAny != null) counterparty = phoneAny.group(0)!;
        }
      }
      }

      // Extract date using several common patterns
      DateTime date = smsDate ?? DateTime.now();
      final isoMatch = RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})').firstMatch(body);
      final dmyMatch = RegExp(r'(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}(?::\d{2})?)').firstMatch(body);
      final dmyOnly = RegExp(r'on\s+(\d{1,2}/\d{1,2}/\d{4})', caseSensitive: false).firstMatch(body);
      final timeOnDate = RegExp(r'at\s+(\d{1,2}:\d{2}(?::\d{2})?)\s+on\s+(\d{1,2}/\d{1,2}/\d{4})', caseSensitive: false).firstMatch(body);

      try {
        if (isoMatch != null) {
          date = DateTime.parse(isoMatch.group(1)!.replaceAll(' ', 'T'));
        } else if (timeOnDate != null) {
          final datePart = timeOnDate.group(2)!;
          final timePart = timeOnDate.group(1)!;
          date = DateTime.parse(_normalizeDmyToIso(datePart, timePart));
        } else if (dmyMatch != null) {
          final val = dmyMatch.group(1)!; // may contain both date and time
          final parts = val.split(RegExp(r'\s+'));
          final datePart = parts[0];
          final timePart = parts.length > 1 ? parts.sublist(1).join(' ') : null;
          date = DateTime.parse(_normalizeDmyToIso(datePart, timePart));
        } else if (dmyOnly != null) {
          date = DateTime.parse(_normalizeDmyToIso(dmyOnly.group(1)!, null));
        } else if (smsDate != null) {
          date = smsDate;
        }
      } catch (e) {
        // fallback to smsDate or now
        date = smsDate ?? DateTime.now();
      }

      // Extract fee and balance if present
      final feeMatch = RegExp(r'\.?Fee\s*:?\s*(\d+(?:[,\s]\d{3})*(?:\.\d+)?)\s*RWF', caseSensitive: false).firstMatch(body);
      final balanceMatch = RegExp(r'Balance\s*:?\s*(\d+(?:[,\s]\d{3})*(?:\.\d+)?)\s*RWF', caseSensitive: false).firstMatch(body);

      final fee = feeMatch != null ? (double.tryParse(feeMatch.group(1)!.replaceAll(RegExp(r'[,\s]'), '')) ?? 0.0) : 0.0;
      final balance = balanceMatch != null ? (double.tryParse(balanceMatch.group(1)!.replaceAll(RegExp(r'[,\s]'), '')) ?? 0.0) : 0.0;

      // Try to extract transaction ID
      final idMatch = RegExp(r'(?:FT\s*Id|TxId|Ref|Ref:)\s*[:]?\s*(\w+)', caseSensitive: false).firstMatch(body);
      final transactionId = idMatch?.group(1) ?? '';

      final expenseType =
          type == 'SENT' ? ExpenseType.classify(body) : ExpenseType.other;

      // If we have at least amount and a detected type, return a Transaction
      if (amount > 0 && type != 'UNKNOWN') {
        return Transaction(
          amount: amount,
          date: date,
          transactionId: transactionId,
          counterparty: counterparty,
          type: type,
          fee: fee,
          balance: balance,
          expenseType: expenseType,
        );
      }

    } catch (e) {
      print('Error parsing SMS message: $e');
      print('Message body: $body');
    }
    return null;
  }
}

class MonthlyTransactionSummary {
  final DateTime month;
  final double totalReceived;
  final double totalSent;
  final int transactionCount;

  MonthlyTransactionSummary({
    required this.month,
    required this.totalReceived,
    required this.totalSent,
    required this.transactionCount,
  });

  double get netAmount => totalReceived - totalSent;

  String get formattedMonth => DateFormat('MMMM yyyy').format(month);

  /// Privacy-safe serialization for Firestore public sharing.
  /// Stores ONLY aggregate values - never raw transactions, counterparties, or IDs.
  /// Month is stored as ISO8601 string normalized to the first day of the month at UTC.
  Map<String, dynamic> toMap() {
    final normalized = DateTime.utc(month.year, month.month, 1);
    return {
      'month': normalized.toIso8601String(),
      'totalReceived': totalReceived,
      'totalSent': totalSent,
      'transactionCount': transactionCount,
    };
  }

  static MonthlyTransactionSummary? fromMap(Map<String, dynamic> map) {
    try {
      final monthRaw = map['month'];
      DateTime parsedMonth;
      if (monthRaw is String) {
        parsedMonth = DateTime.parse(monthRaw);
      } else if (monthRaw is DateTime) {
        parsedMonth = monthRaw;
      } else {
        return null;
      }
      return MonthlyTransactionSummary(
        month: DateTime.utc(parsedMonth.year, parsedMonth.month, 1),
        totalReceived: (map['totalReceived'] as num?)?.toDouble() ?? 0.0,
        totalSent: (map['totalSent'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (map['transactionCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Privacy-safe weekly aggregates (Monday–Sunday, local calendar).
class WeeklyTransactionSummary {
  final DateTime weekStart;
  final double totalReceived;
  final double totalSent;
  final int transactionCount;

  WeeklyTransactionSummary({
    required this.weekStart,
    required this.totalReceived,
    required this.totalSent,
    required this.transactionCount,
  });

  static DateTime startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static List<WeeklyTransactionSummary> fromTransactions(
    List<Transaction> transactions,
  ) {
    final weeklyData = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
      final week = startOfWeek(transaction.date);
      weeklyData.putIfAbsent(week, () => []).add(transaction);
    }

    final summaries = weeklyData.entries.map((entry) {
      final receivedAmount = entry.value
          .where((t) => t.isReceived)
          .fold<double>(0, (total, t) => total + t.amount);
      final sentAmount = entry.value
          .where((t) => t.isSent)
          .fold<double>(0, (total, t) => total + t.totalCost);

      return WeeklyTransactionSummary(
        weekStart: entry.key,
        totalReceived: receivedAmount,
        totalSent: sentAmount,
        transactionCount: entry.value.length,
      );
    }).toList();

    summaries.sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return summaries;
  }

  Map<String, dynamic> toMap() {
    final normalized = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return {
      'weekStart': normalized.toIso8601String(),
      'totalReceived': totalReceived,
      'totalSent': totalSent,
      'transactionCount': transactionCount,
    };
  }

  static WeeklyTransactionSummary? fromMap(Map<String, dynamic> map) {
    try {
      final weekRaw = map['weekStart'];
      DateTime parsedWeek;
      if (weekRaw is String) {
        parsedWeek = DateTime.parse(weekRaw);
      } else if (weekRaw is DateTime) {
        parsedWeek = weekRaw;
      } else {
        return null;
      }
      final weekStart = DateTime(
        parsedWeek.year,
        parsedWeek.month,
        parsedWeek.day,
      );
      return WeeklyTransactionSummary(
        weekStart: weekStart,
        totalReceived: (map['totalReceived'] as num?)?.toDouble() ?? 0.0,
        totalSent: (map['totalSent'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (map['transactionCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}