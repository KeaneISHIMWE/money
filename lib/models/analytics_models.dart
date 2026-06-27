import 'package:intl/intl.dart';

class SpendingSummary {
  final double totalSpent;
  final double totalReceived;
  final int transactionCount;
  final int sentTransactionCount;
  final int receivedTransactionCount;
  final double averageTransaction;
  final double averageSentAmount;
  final double averageReceivedAmount;
  final Map<String, double> byCategory;
  final DateTime startDate;
  final DateTime endDate;

  SpendingSummary({
    required this.totalSpent,
    required this.totalReceived,
    required this.transactionCount,
    required this.sentTransactionCount,
    required this.receivedTransactionCount,
    required this.averageTransaction,
    required this.averageSentAmount,
    required this.averageReceivedAmount,
    required this.byCategory,
    required this.startDate,
    required this.endDate,
  });

  String get formattedTotalSpent =>
    NumberFormat('#,##0.00', 'en_US').format(totalSpent);

  String get formattedTotalReceived =>
    NumberFormat('#,##0.00', 'en_US').format(totalReceived);

  String get formattedAverageTransaction =>
    NumberFormat('#,##0.00', 'en_US').format(averageTransaction);

  String get formattedAverageSent =>
    NumberFormat('#,##0.00', 'en_US').format(averageSentAmount);

  String get formattedAverageReceived =>
    NumberFormat('#,##0.00', 'en_US').format(averageReceivedAmount);

  String get periodLabel {
    final days = endDate.difference(startDate).inDays;
    if (days == 0) return 'Today';
    if (days == 6) return 'This Week';
    if (days == 29 || days == 30) return 'This Month';
    return '$days days';
  }

  Map<String, dynamic> toFirestore() => {
    'totalSpent': totalSpent,
    'totalReceived': totalReceived,
    'transactionCount': transactionCount,
    'sentTransactionCount': sentTransactionCount,
    'receivedTransactionCount': receivedTransactionCount,
    'averageTransaction': averageTransaction,
    'averageSentAmount': averageSentAmount,
    'averageReceivedAmount': averageReceivedAmount,
    'byCategory': byCategory,
    'startDate': startDate,
    'endDate': endDate,
  };

  static SpendingSummary? fromFirestore(Map<String, dynamic> data) {
    try {
      return SpendingSummary(
        totalSpent: (data['totalSpent'] as num?)?.toDouble() ?? 0.0,
        totalReceived: (data['totalReceived'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
        sentTransactionCount: (data['sentTransactionCount'] as num?)?.toInt() ?? 0,
        receivedTransactionCount: (data['receivedTransactionCount'] as num?)?.toInt() ?? 0,
        averageTransaction: (data['averageTransaction'] as num?)?.toDouble() ?? 0.0,
        averageSentAmount: (data['averageSentAmount'] as num?)?.toDouble() ?? 0.0,
        averageReceivedAmount: (data['averageReceivedAmount'] as num?)?.toDouble() ?? 0.0,
        byCategory: Map<String, double>.from(data['byCategory'] as Map? ?? {}),
        startDate: (data['startDate'] as DateTime?) ?? DateTime.now(),
        endDate: (data['endDate'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing SpendingSummary: $e');
      return null;
    }
  }
}

class IncomeVsExpenseAnalysis {
  final double totalIncome;
  final double totalExpenses;
  final double netCashFlow;
  final double savingsRate; // (income - expenses) / income * 100
  final double spendingRate; // expenses / income * 100
  final DateTime startDate;
  final DateTime endDate;

  IncomeVsExpenseAnalysis({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netCashFlow,
    required this.savingsRate,
    required this.spendingRate,
    required this.startDate,
    required this.endDate,
  });

  String get formattedTotalIncome =>
    NumberFormat('#,##0.00', 'en_US').format(totalIncome);

  String get formattedTotalExpenses =>
    NumberFormat('#,##0.00', 'en_US').format(totalExpenses);

  String get formattedNetCashFlow =>
    NumberFormat('#,##0.00', 'en_US').format(netCashFlow);

  String get formattedSavingsRate =>
    '${savingsRate.toStringAsFixed(1)}%';

  String get formattedSpendingRate =>
    '${spendingRate.toStringAsFixed(1)}%';

  String get cashFlowStatus {
    if (netCashFlow > 0) return 'Positive';
    if (netCashFlow < 0) return 'Negative';
    return 'Neutral';
  }

  Map<String, dynamic> toFirestore() => {
    'totalIncome': totalIncome,
    'totalExpenses': totalExpenses,
    'netCashFlow': netCashFlow,
    'savingsRate': savingsRate,
    'spendingRate': spendingRate,
    'startDate': startDate,
    'endDate': endDate,
  };

  static IncomeVsExpenseAnalysis? fromFirestore(Map<String, dynamic> data) {
    try {
      return IncomeVsExpenseAnalysis(
        totalIncome: (data['totalIncome'] as num?)?.toDouble() ?? 0.0,
        totalExpenses: (data['totalExpenses'] as num?)?.toDouble() ?? 0.0,
        netCashFlow: (data['netCashFlow'] as num?)?.toDouble() ?? 0.0,
        savingsRate: (data['savingsRate'] as num?)?.toDouble() ?? 0.0,
        spendingRate: (data['spendingRate'] as num?)?.toDouble() ?? 0.0,
        startDate: (data['startDate'] as DateTime?) ?? DateTime.now(),
        endDate: (data['endDate'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing IncomeVsExpenseAnalysis: $e');
      return null;
    }
  }
}

class CategoryStats {
  final String categoryId;
  final String categoryName;
  final double totalSpent;
  final int transactionCount;
  final double percentage;
  final double averageTransaction;

  CategoryStats({
    required this.categoryId,
    required this.categoryName,
    required this.totalSpent,
    required this.transactionCount,
    required this.percentage,
    required this.averageTransaction,
  });

  String get formattedTotalSpent =>
    NumberFormat('#,##0.00', 'en_US').format(totalSpent);

  String get formattedPercentage =>
    '${percentage.toStringAsFixed(1)}%';

  String get formattedAverageTransaction =>
    NumberFormat('#,##0.00', 'en_US').format(averageTransaction);

  Map<String, dynamic> toFirestore() => {
    'categoryId': categoryId,
    'categoryName': categoryName,
    'totalSpent': totalSpent,
    'transactionCount': transactionCount,
    'percentage': percentage,
    'averageTransaction': averageTransaction,
  };

  static CategoryStats? fromFirestore(Map<String, dynamic> data) {
    try {
      return CategoryStats(
        categoryId: data['categoryId'] ?? '',
        categoryName: data['categoryName'] ?? '',
        totalSpent: (data['totalSpent'] as num?)?.toDouble() ?? 0.0,
        transactionCount: (data['transactionCount'] as num?)?.toInt() ?? 0,
        percentage: (data['percentage'] as num?)?.toDouble() ?? 0.0,
        averageTransaction: (data['averageTransaction'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      print('Error parsing CategoryStats: $e');
      return null;
    }
  }
}

class BalanceAnalysis {
  final double currentBalance;
  final double averageBalance;
  final double minBalance;
  final double maxBalance;
  final DateTime analysisDate;

  BalanceAnalysis({
    required this.currentBalance,
    required this.averageBalance,
    required this.minBalance,
    required this.maxBalance,
    required this.analysisDate,
  });

  String get formattedCurrentBalance =>
    NumberFormat('#,##0.00', 'en_US').format(currentBalance);

  String get formattedAverageBalance =>
    NumberFormat('#,##0.00', 'en_US').format(averageBalance);

  String get formattedMinBalance =>
    NumberFormat('#,##0.00', 'en_US').format(minBalance);

  String get formattedMaxBalance =>
    NumberFormat('#,##0.00', 'en_US').format(maxBalance);

  String get balanceHealth {
    if (currentBalance > averageBalance * 1.5) return 'Excellent';
    if (currentBalance > averageBalance) return 'Good';
    if (currentBalance > minBalance * 2) return 'Fair';
    return 'Low';
  }

  Map<String, dynamic> toFirestore() => {
    'currentBalance': currentBalance,
    'averageBalance': averageBalance,
    'minBalance': minBalance,
    'maxBalance': maxBalance,
    'analysisDate': analysisDate,
  };

  static BalanceAnalysis? fromFirestore(Map<String, dynamic> data) {
    try {
      return BalanceAnalysis(
        currentBalance: (data['currentBalance'] as num?)?.toDouble() ?? 0.0,
        averageBalance: (data['averageBalance'] as num?)?.toDouble() ?? 0.0,
        minBalance: (data['minBalance'] as num?)?.toDouble() ?? 0.0,
        maxBalance: (data['maxBalance'] as num?)?.toDouble() ?? 0.0,
        analysisDate: (data['analysisDate'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing BalanceAnalysis: $e');
      return null;
    }
  }
}

class LowBalanceStats {
  final int timesBelow;
  final int averageDaysBelow;
  final int longestPeriodDays;
  final List<LowBalancePeriod> periods;
  final String insight;
  final double threshold;

  LowBalanceStats({
    required this.timesBelow,
    required this.averageDaysBelow,
    required this.longestPeriodDays,
    required this.periods,
    required this.insight,
    required this.threshold,
  });

  String get formattedThreshold =>
    NumberFormat('#,##0.00', 'en_US').format(threshold);

  Map<String, dynamic> toFirestore() => {
    'timesBelow': timesBelow,
    'averageDaysBelow': averageDaysBelow,
    'longestPeriodDays': longestPeriodDays,
    'periods': periods.map((p) => p.toFirestore()).toList(),
    'insight': insight,
    'threshold': threshold,
  };

  static LowBalanceStats? fromFirestore(Map<String, dynamic> data) {
    try {
      final periodsList = data['periods'] as List<dynamic>? ?? [];
      final periods = periodsList
        .map((p) => LowBalancePeriod.fromFirestore(p as Map<String, dynamic>))
        .whereType<LowBalancePeriod>()
        .toList();

      return LowBalanceStats(
        timesBelow: (data['timesBelow'] as num?)?.toInt() ?? 0,
        averageDaysBelow: (data['averageDaysBelow'] as num?)?.toInt() ?? 0,
        longestPeriodDays: (data['longestPeriodDays'] as num?)?.toInt() ?? 0,
        periods: periods,
        insight: data['insight'] ?? '',
        threshold: (data['threshold'] as num?)?.toDouble() ?? 20000.0,
      );
    } catch (e) {
      print('Error parsing LowBalanceStats: $e');
      return null;
    }
  }
}

class LowBalancePeriod {
  final DateTime startDate;
  final DateTime endDate;
  final int daysBelow;
  final double lowestBalance;

  LowBalancePeriod({
    required this.startDate,
    required this.endDate,
    required this.daysBelow,
    required this.lowestBalance,
  });

  String get formattedDateRange =>
    '${DateFormat('MMM dd').format(startDate)}-${DateFormat('MMM dd').format(endDate)}';

  String get formattedLowestBalance =>
    NumberFormat('#,##0.00', 'en_US').format(lowestBalance);

  Map<String, dynamic> toFirestore() => {
    'startDate': startDate,
    'endDate': endDate,
    'daysBelow': daysBelow,
    'lowestBalance': lowestBalance,
  };

  static LowBalancePeriod? fromFirestore(Map<String, dynamic> data) {
    try {
      return LowBalancePeriod(
        startDate: (data['startDate'] as DateTime?) ?? DateTime.now(),
        endDate: (data['endDate'] as DateTime?) ?? DateTime.now(),
        daysBelow: (data['daysBelow'] as num?)?.toInt() ?? 0,
        lowestBalance: (data['lowestBalance'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      print('Error parsing LowBalancePeriod: $e');
      return null;
    }
  }
}

class DailyTrend {
  final DateTime date;
  final double totalSpent;
  final double totalReceived;
  final int transactionCount;

  DailyTrend({
    required this.date,
    required this.totalSpent,
    required this.totalReceived,
    required this.transactionCount,
  });

  String get formattedDate => DateFormat('MMM dd').format(date);
  String get formattedSpent => NumberFormat('#,##0', 'en_US').format(totalSpent);
  String get formattedReceived => NumberFormat('#,##0', 'en_US').format(totalReceived);
}

class WeeklyTrend {
  final DateTime weekStart;
  final double totalSpent;
  final double totalReceived;
  final int transactionCount;

  WeeklyTrend({
    required this.weekStart,
    required this.totalSpent,
    required this.totalReceived,
    required this.transactionCount,
  });

  String get formattedWeek =>
    'Week of ${DateFormat('MMM dd').format(weekStart)}';

  String get formattedSpent => NumberFormat('#,##0', 'en_US').format(totalSpent);
  String get formattedReceived => NumberFormat('#,##0', 'en_US').format(totalReceived);
}
