import '../models/analytics_models.dart';
import '../models/enhanced_transaction.dart';
import '../models/insights.dart';
import '../models/transaction.dart';

/// Computes analytics from in-memory transactions (SMS or Firestore).
/// Avoids Firestore range queries that may fail without composite indexes.
class LocalAnalytics {
  LocalAnalytics._();

  static List<MonthlyTransactionSummary> monthlySummaries(
    List<EnhancedTransaction> transactions,
  ) {
    final monthlyData = <DateTime, List<EnhancedTransaction>>{};
    for (final transaction in transactions) {
      final month = DateTime(transaction.date.year, transaction.date.month);
      monthlyData.putIfAbsent(month, () => []).add(transaction);
    }

    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    monthlyData.putIfAbsent(currentMonth, () => []);

    final summaries = monthlyData.entries.map((entry) {
      final receivedAmount = entry.value
          .where((t) => t.isReceived)
          .fold<double>(0, (sum, t) => sum + t.amount);
      final sentAmount = entry.value
          .where((t) => t.isSent)
          .fold<double>(0, (sum, t) => sum + t.totalCost);
      final sentCount = entry.value.where((t) => t.isSent).length;

      return MonthlyTransactionSummary(
        month: entry.key,
        totalReceived: receivedAmount,
        totalSent: sentAmount,
        transactionCount: sentCount,
      );
    }).toList();

    summaries.sort((a, b) => a.month.compareTo(b.month));
    return summaries;
  }

  static List<EnhancedTransaction> filterByDateRange(
    List<EnhancedTransaction> transactions,
    DateTime startDate,
    DateTime endDate,
  ) {
    return transactions
        .where(
          (t) =>
              !t.date.isBefore(startDate) &&
              t.date.isBefore(endDate),
        )
        .toList();
  }

  static SpendingSummary spendingSummary({
    required List<EnhancedTransaction> transactions,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final inRange = filterByDateRange(transactions, startDate, endDate);

    double totalSpent = 0;
    double totalReceived = 0;
    int sentCount = 0;
    int receivedCount = 0;
    final byCategory = <String, double>{};

    for (final txn in inRange) {
      if (txn.isSent) {
        totalSpent += txn.totalCost;
        sentCount++;
        byCategory[txn.category] = (byCategory[txn.category] ?? 0) + txn.totalCost;
      } else {
        totalReceived += txn.amount;
        receivedCount++;
      }
    }

    final count = inRange.length;
    return SpendingSummary(
      totalSpent: totalSpent,
      totalReceived: totalReceived,
      transactionCount: count,
      sentTransactionCount: sentCount,
      receivedTransactionCount: receivedCount,
      averageTransaction: count > 0 ? (totalSpent + totalReceived) / count : 0,
      averageSentAmount: sentCount > 0 ? totalSpent / sentCount : 0,
      averageReceivedAmount: receivedCount > 0 ? totalReceived / receivedCount : 0,
      byCategory: byCategory,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static IncomeVsExpenseAnalysis incomeVsExpense({
    required List<EnhancedTransaction> transactions,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final summary = spendingSummary(
      transactions: transactions,
      startDate: startDate,
      endDate: endDate,
    );
    final totalIncome = summary.totalReceived;
    final totalExpenses = summary.totalSpent;
    final netCashFlow = totalIncome - totalExpenses;
    final savingsRate =
        totalIncome > 0 ? (netCashFlow / totalIncome) * 100 : 0.0;

    return IncomeVsExpenseAnalysis(
      totalIncome: totalIncome,
      totalExpenses: totalExpenses,
      netCashFlow: netCashFlow,
      savingsRate: savingsRate,
      spendingRate: 100 - savingsRate,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static LowBalanceStats lowBalanceStats({
    required List<EnhancedTransaction> transactions,
    double threshold = 20000,
  }) {
    if (transactions.isEmpty) {
      return LowBalanceStats(
        timesBelow: 0,
        averageDaysBelow: 0,
        longestPeriodDays: 0,
        periods: [],
        insight: 'No transaction data available.',
        threshold: threshold,
      );
    }

    final sorted = List<EnhancedTransaction>.from(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    var timesBelow = 0;
    final periods = <LowBalancePeriod>[];
    DateTime? periodStart;
    double? lowestBalance;

    for (final txn in sorted) {
      if (txn.balance <= 0) continue;

      if (txn.balance < threshold) {
        timesBelow++;
        periodStart ??= txn.date;
        lowestBalance = lowestBalance == null
            ? txn.balance
            : (txn.balance < lowestBalance ? txn.balance : lowestBalance);
      } else if (periodStart != null) {
        periods.add(
          LowBalancePeriod(
            startDate: periodStart,
            endDate: txn.date,
            daysBelow: txn.date.difference(periodStart).inDays,
            lowestBalance: lowestBalance ?? 0,
          ),
        );
        periodStart = null;
        lowestBalance = null;
      }
    }

    final longestPeriod = periods.isEmpty
        ? 0
        : periods.map((p) => p.daysBelow).reduce((a, b) => a > b ? a : b);
    final averageBelow = periods.isEmpty
        ? 0
        : periods.map((p) => p.daysBelow).reduce((a, b) => a + b) ~/
            periods.length;

    String insight;
    if (timesBelow == 0) {
      insight =
          'Your balance rarely falls below the threshold. Great job maintaining healthy balance!';
    } else if (averageBelow > 15) {
      insight =
          'You frequently maintain a low balance. Consider setting up emergency savings.';
    } else if (longestPeriod > 10) {
      insight =
          'Your longest low-balance period was over 10 days. Plan ahead for better cash flow.';
    } else {
      insight =
          'Your balance occasionally drops below the threshold. Moderate financial management.';
    }

    return LowBalanceStats(
      timesBelow: timesBelow,
      averageDaysBelow: averageBelow,
      longestPeriodDays: longestPeriod,
      periods: periods,
      insight: insight,
      threshold: threshold,
    );
  }

  static SpendingHabits? spendingHabits({
    required List<EnhancedTransaction> transactions,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final sent = filterByDateRange(transactions, startDate, endDate)
        .where((t) => t.isSent)
        .toList();

    if (sent.isEmpty) return null;

    double totalSpent = 0;
    final categoryCount = <String, int>{};
    final recipientCount = <String, int>{};
    final daySpending = <int, double>{};

    for (final txn in sent) {
      totalSpent += txn.totalCost;
      categoryCount[txn.category] = (categoryCount[txn.category] ?? 0) + 1;
      recipientCount[txn.counterparty] =
          (recipientCount[txn.counterparty] ?? 0) + 1;
      daySpending[txn.date.weekday] =
          (daySpending[txn.date.weekday] ?? 0) + txn.totalCost;
    }

    var mostCommonCategory = 'normal_transfer';
    var mostCommonRecipient = 'Unknown';
    var maxCategoryCount = 0;
    var maxRecipientCount = 0;

    categoryCount.forEach((category, count) {
      if (count > maxCategoryCount) {
        maxCategoryCount = count;
        mostCommonCategory = category;
      }
    });

    recipientCount.forEach((recipient, count) {
      if (count > maxRecipientCount) {
        maxRecipientCount = count;
        mostCommonRecipient = recipient;
      }
    });

    var peakDay = 1;
    var maxDaySpending = 0.0;
    daySpending.forEach((day, amount) {
      if (amount > maxDaySpending) {
        maxDaySpending = amount;
        peakDay = day;
      }
    });

    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final pattern = 'Peak spending on ${dayNames[peakDay - 1]}s';

    final daysCount = endDate.difference(startDate).inDays.clamp(1, 366);
    final averageDailySpend = totalSpent / daysCount;

    return SpendingHabits(
      mostCommonCategory: mostCommonCategory,
      mostCommonRecipient: mostCommonRecipient,
      averageDailySpend: averageDailySpend,
      averageWeeklySpend: averageDailySpend * 7,
      averageMonthlySpend: averageDailySpend * 30,
      pattern: pattern,
      recommendation: totalSpent > 500000
          ? 'Your spending is high for this period. Review your budget.'
          : 'Track spending regularly to stay aligned with your income.',
      analysisDate: DateTime.now(),
    );
  }

  static List<Insight> basicInsights({
    required List<EnhancedTransaction> transactions,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final summary = spendingSummary(
      transactions: transactions,
      startDate: startDate,
      endDate: endDate,
    );
    final habits = spendingHabits(
      transactions: transactions,
      startDate: startDate,
      endDate: endDate,
    );
    final insights = <Insight>[];

    if (summary.sentTransactionCount > 0 && habits != null) {
      insights.add(
        Insight(
          id: 'local-habit-${habits.mostCommonCategory}',
          type: 'spending_habit',
          title: 'Top Spending Category',
          description:
              'Your most common expense category is ${habits.mostCommonCategory}.',
          generatedAt: DateTime.now(),
          isActionable: false,
        ),
      );
    }

    if (summary.totalReceived > 0) {
      insights.add(
        Insight(
          id: 'local-income',
          type: 'pattern',
          title: 'Income This Period',
          description:
              'You received ${summary.formattedTotalReceived} RWF across ${summary.receivedTransactionCount} transaction(s).',
          generatedAt: DateTime.now(),
          isActionable: false,
        ),
      );
    }

    if (summary.sentTransactionCount == 0 && summary.receivedTransactionCount > 0) {
      insights.add(
        Insight(
          id: 'local-no-spending',
          type: 'recommendation',
          title: 'No Outgoing Payments',
          description:
              'You have incoming transfers but no outgoing payments in this period.',
          generatedAt: DateTime.now(),
          isActionable: false,
        ),
      );
    }

    return insights;
  }
}
