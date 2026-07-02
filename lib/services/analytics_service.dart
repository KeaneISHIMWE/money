import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/enhanced_transaction.dart';
import '../models/analytics_models.dart';
import '../models/recipient_profile.dart';
import '../models/insights.dart';

class AnalyticsService {
  final FirebaseFirestore _firestore;
  final String userId;

  AnalyticsService({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // Get spending summary for a date range
  Future<SpendingSummary?> getSpendingSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        return SpendingSummary(
          totalSpent: 0,
          totalReceived: 0,
          transactionCount: 0,
          sentTransactionCount: 0,
          receivedTransactionCount: 0,
          averageTransaction: 0,
          averageSentAmount: 0,
          averageReceivedAmount: 0,
          byCategory: {},
          startDate: startDate,
          endDate: endDate,
        );
      }

      double totalSpent = 0;
      double totalReceived = 0;
      int sentCount = 0;
      int receivedCount = 0;
      final Map<String, double> byCategory = {};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          if (txn.isSent) {
            totalSpent += txn.totalCost;
            sentCount++;
            byCategory.putIfAbsent(txn.category, () => 0);
            byCategory[txn.category] = (byCategory[txn.category] ?? 0) + txn.totalCost;
          } else {
            totalReceived += txn.amount;
            receivedCount++;
          }
        }
      }

      return SpendingSummary(
        totalSpent: totalSpent,
        totalReceived: totalReceived,
        transactionCount: snapshot.docs.length,
        sentTransactionCount: sentCount,
        receivedTransactionCount: receivedCount,
        averageTransaction:
          snapshot.docs.isNotEmpty ? (totalSpent + totalReceived) / snapshot.docs.length : 0,
        averageSentAmount: sentCount > 0 ? totalSpent / sentCount : 0,
        averageReceivedAmount: receivedCount > 0 ? totalReceived / receivedCount : 0,
        byCategory: byCategory,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      print('Error getting spending summary: $e');
      return null;
    }
  }

  // Get today's spending
  Future<SpendingSummary?> getTodaySpending() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return getSpendingSummary(startDate: today, endDate: tomorrow);
  }

  // Get this week's spending
  Future<SpendingSummary?> getThisWeekSpending() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return getSpendingSummary(startDate: weekStart, endDate: weekEnd);
  }

  // Get this month's spending
  Future<SpendingSummary?> getThisMonthSpending() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    return getSpendingSummary(startDate: monthStart, endDate: monthEnd);
  }

  // Get this year's spending
  Future<SpendingSummary?> getThisYearSpending() {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year + 1, 1, 1);
    return getSpendingSummary(startDate: yearStart, endDate: yearEnd);
  }

  // Income vs expense analysis
  Future<IncomeVsExpenseAnalysis?> getIncomeVsExpense({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final summary = await getSpendingSummary(startDate: startDate, endDate: endDate);
      if (summary == null) return null;

      final totalIncome = summary.totalReceived;
      final totalExpenses = summary.totalSpent;
      final netCashFlow = totalIncome - totalExpenses;
      final savingsRate = totalIncome > 0 ? ((netCashFlow / totalIncome) * 100).toDouble() : 0.0;
      final spendingRate = (100 - savingsRate).toDouble();

      return IncomeVsExpenseAnalysis(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        netCashFlow: netCashFlow,
        savingsRate: savingsRate,
        spendingRate: spendingRate,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      print('Error getting income vs expense analysis: $e');
      return null;
    }
  }

  // Category breakdown
  Future<Map<String, CategoryStats>> getCategoryBreakdown({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate);

      final snapshot = await query.get();
      final Map<String, CategoryStats> categoryMap = {};

      double totalSpent = 0;

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          totalSpent += txn.totalCost;
        }
      }

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          final stats = categoryMap.putIfAbsent(
            txn.category,
            () => CategoryStats(
              categoryId: txn.category,
              categoryName: _getCategoryName(txn.category),
              totalSpent: 0,
              transactionCount: 0,
              percentage: 0,
              averageTransaction: 0,
            ),
          );

          stats.totalSpent += txn.totalCost;
          stats.transactionCount += 1;
        }
      }

      // Calculate percentages and averages
      for (final stats in categoryMap.values) {
        stats.percentage = totalSpent > 0 ? (stats.totalSpent / totalSpent) * 100 : 0;
        stats.averageTransaction =
          stats.transactionCount > 0 ? stats.totalSpent / stats.transactionCount : 0;
      }

      return categoryMap;
    } catch (e) {
      print('Error getting category breakdown: $e');
      return {};
    }
  }

  // Balance analysis
  Future<BalanceAnalysis?> getBalanceAnalysis() async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .limit(1000);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      double totalBalance = 0;
      double minBalance = double.infinity;
      double maxBalance = 0;
      double currentBalance = 0;

      for (int i = 0; i < snapshot.docs.length; i++) {
        final txn = EnhancedTransaction.fromFirestore(
          snapshot.docs[i].data(),
          snapshot.docs[i].id,
        );
        if (txn != null) {
          totalBalance += txn.balance;
          minBalance = minBalance > txn.balance ? txn.balance : minBalance;
          maxBalance = maxBalance < txn.balance ? txn.balance : maxBalance;

          if (i == 0) {
            currentBalance = txn.balance;
          }
        }
      }

      final averageBalance = snapshot.docs.isNotEmpty ? (totalBalance / snapshot.docs.length).toDouble() : 0.0;

      return BalanceAnalysis(
        currentBalance: currentBalance,
        averageBalance: averageBalance,
        minBalance: minBalance == double.infinity ? 0 : minBalance,
        maxBalance: maxBalance,
        analysisDate: DateTime.now(),
      );
    } catch (e) {
      print('Error getting balance analysis: $e');
      return null;
    }
  }

  // Low balance statistics
  Future<LowBalanceStats?> getLowBalanceStats({double threshold = 20000}) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: false);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        return LowBalanceStats(
          timesBelow: 0,
          averageDaysBelow: 0,
          longestPeriodDays: 0,
          periods: [],
          insight: 'No transaction data available.',
          threshold: threshold,
        );
      }

      int timesBelow = 0;
      final List<LowBalancePeriod> periods = [];
      DateTime? periodStart;
      double? lowestBalance;

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          if (txn.balance < threshold) {
            timesBelow++;
            if (periodStart == null) {
              periodStart = txn.date;
              lowestBalance = txn.balance;
            } else {
              lowestBalance = lowestBalance! > txn.balance ? txn.balance : lowestBalance;
            }
          } else if (periodStart != null) {
            periods.add(LowBalancePeriod(
              startDate: periodStart,
              endDate: txn.date,
              daysBelow: txn.date.difference(periodStart).inDays,
              lowestBalance: lowestBalance ?? 0,
            ));
            periodStart = null;
            lowestBalance = null;
          }
        }
      }

      final longestPeriod = periods.isEmpty ? 0 : periods
        .map((p) => p.daysBelow)
        .reduce((a, b) => a > b ? a : b);

      final averageBelow = periods.isEmpty
        ? 0
        : periods.map((p) => p.daysBelow).reduce((a, b) => a + b) ~/ periods.length;

      final insight = _generateLowBalanceInsight(timesBelow, averageBelow, longestPeriod);

      return LowBalanceStats(
        timesBelow: timesBelow,
        averageDaysBelow: averageBelow,
        longestPeriodDays: longestPeriod,
        periods: periods,
        insight: insight,
        threshold: threshold,
      );
    } catch (e) {
      print('Error getting low balance stats: $e');
      return null;
    }
  }

  // Daily trends
  Future<List<DailyTrend>> getDailyTrends({required DateTime month}) async {
    try {
      final monthStart = DateTime(month.year, month.month, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 1);

      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: monthStart)
        .where('date', isLessThanOrEqualTo: monthEnd);

      final snapshot = await query.get();

      final Map<DateTime, DailyTrend> dailyMap = {};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          final date = DateTime(txn.date.year, txn.date.month, txn.date.day);
          final existing = dailyMap[date] ??
            DailyTrend(
              date: date,
              totalSpent: 0,
              totalReceived: 0,
              transactionCount: 0,
            );

          if (txn.isSent) {
            existing.totalSpent += txn.totalCost;
          } else {
            existing.totalReceived += txn.amount;
          }
          existing.transactionCount += 1;

          dailyMap[date] = existing;
        }
      }

      final trends = dailyMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      return trends;
    } catch (e) {
      print('Error getting daily trends: $e');
      return [];
    }
  }

  String _getCategoryName(String categoryId) {
    const categoryNames = {
      'normal_transfer': 'Normal Transfer',
      'airtime': 'Airtime',
      'bundle_and_pack': 'Bundle and Pack',
      'payment': 'Payment',
      'transfers': 'Normal Transfer',
      'internet': 'Bundle and Pack',
      'utilities': 'Payment',
      'merchants': 'Payment',
      'bank': 'Payment',
      'other': 'Other Expenses',
    };
    return categoryNames[categoryId] ?? 'Other';
  }

  String _generateLowBalanceInsight(int times, int avgDays, int longest) {
    if (times == 0) {
      return 'Your balance rarely falls below the threshold. Great job maintaining healthy balance!';
    }
    if (avgDays > 15) {
      return 'You frequently maintain a low balance. Consider setting up emergency savings.';
    }
    if (longest > 10) {
      return 'Your longest low-balance period was over 10 days. Plan ahead for better cash flow.';
    }
    return 'Your balance occasionally drops below the threshold. Moderate financial management.';
  }
}

// Mutable CategoryStats for easier manipulation
extension MutableCategoryStats on CategoryStats {
  void addTransaction(double amount) {
    totalSpent += amount;
    transactionCount += 1;
  }
}
