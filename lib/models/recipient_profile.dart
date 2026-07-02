import 'package:intl/intl.dart';

class RecipientProfile {
  final String id;
  final String name;
  final String? phone;
  double totalAmountSent;
  int transactionCount;
  DateTime lastTransaction;
  final Map<String, RecipientMonthlyStats> monthlyStats;
  final DateTime lastUpdated;

  RecipientProfile({
    required this.id,
    required this.name,
    this.phone,
    required this.totalAmountSent,
    required this.transactionCount,
    required this.lastTransaction,
    required this.monthlyStats,
    required this.lastUpdated,
  });

  double get averageAmount =>
    transactionCount > 0 ? totalAmountSent / transactionCount : 0.0;

  String get frequencyLabel {
    if (transactionCount >= 20) return 'Very Frequent';
    if (transactionCount >= 10) return 'Frequent';
    if (transactionCount >= 5) return 'Regular';
    return 'Occasional';
  }

  String get formattedTotalAmount =>
    NumberFormat('#,##0.00', 'en_US').format(totalAmountSent);

  String get formattedAverageAmount =>
    NumberFormat('#,##0.00', 'en_US').format(averageAmount);

  String get formattedLastTransaction =>
    DateFormat('MMM dd, yyyy').format(lastTransaction);

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'phone': phone,
    'totalAmountSent': totalAmountSent,
    'transactionCount': transactionCount,
    'lastTransaction': lastTransaction,
    'monthlyStats': monthlyStats.map((key, value) => MapEntry(key, value.toFirestore())),
    'lastUpdated': lastUpdated,
  };

  static RecipientProfile? fromFirestore(Map<String, dynamic> data, String docId) {
    try {
      final monthlyStatsMap = data['monthlyStats'] as Map<String, dynamic>? ?? {};
      final monthlyStats = <String, RecipientMonthlyStats>{};

      monthlyStatsMap.forEach((key, value) {
        final stats = RecipientMonthlyStats.fromFirestore(value as Map<String, dynamic>);
        if (stats != null) {
          monthlyStats[key] = stats;
        }
      });

      return RecipientProfile(
        id: docId,
        name: data['name'] ?? 'Unknown',
        phone: data['phone'],
        totalAmountSent: (data['totalAmountSent'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
        lastTransaction: (data['lastTransaction'] as DateTime?) ?? DateTime.now(),
        monthlyStats: monthlyStats,
        lastUpdated: (data['lastUpdated'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing RecipientProfile: $e');
      return null;
    }
  }

  @override
  String toString() =>
    'RecipientProfile(id: $id, name: $name, totalAmountSent: $totalAmountSent, transactionCount: $transactionCount)';
}

class RecipientMonthlyStats {
  final String month; // Format: 'yyyy-MM'
  final double totalAmount;
  final int transactionCount;

  RecipientMonthlyStats({
    required this.month,
    required this.totalAmount,
    required this.transactionCount,
  });

  double get averageAmount =>
    transactionCount > 0 ? totalAmount / transactionCount : 0.0;

  Map<String, dynamic> toFirestore() => {
    'month': month,
    'totalAmount': totalAmount,
    'transactionCount': transactionCount,
  };

  static RecipientMonthlyStats? fromFirestore(Map<String, dynamic> data) {
    try {
      return RecipientMonthlyStats(
        month: data['month'] ?? '',
        totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      print('Error parsing RecipientMonthlyStats: $e');
      return null;
    }
  }
}
