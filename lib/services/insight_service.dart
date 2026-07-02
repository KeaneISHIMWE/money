import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/enhanced_transaction.dart';
import '../models/insights.dart';
import 'analytics_service.dart';
import 'recipient_service.dart';

String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';

class InsightService {
  final FirebaseFirestore _firestore;
  final String userId;
  final AnalyticsService analyticsService;
  final RecipientService recipientService;

  InsightService({
    required this.userId,
    required this.analyticsService,
    required this.recipientService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Generate all insights
  Future<List<Insight>> generateInsights({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final end = endDate ?? DateTime.now();
      final start = startDate ?? DateTime(end.year, end.month, 1);

      final insights = <Insight>[];

      // Generate different types of insights
      insights.addAll(await _generateSpendingHabitInsights(start, end));
      insights.addAll(await _generateRecipientInsights(start, end));
      insights.addAll(await _generateBalanceInsights(start, end));
      insights.addAll(await _generateRecommendationInsights(start, end));

      // Sort by actionability and type
      insights.sort((a, b) {
        if (a.isActionable != b.isActionable) {
          return a.isActionable ? -1 : 1;
        }
        return b.generatedAt.compareTo(a.generatedAt);
      });

      return insights;
    } catch (e) {
      print('Error generating insights: $e');
      return [];
    }
  }

  /// Analyze spending habits
  Future<SpendingHabits?> analyzeSpendingHabits({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final end = endDate ?? DateTime.now();
      final start = startDate ?? DateTime(end.year, end.month, 1);

      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        return SpendingHabits(
          mostCommonCategory: 'transfers',
          mostCommonRecipient: 'Unknown',
          averageDailySpend: 0,
          averageWeeklySpend: 0,
          averageMonthlySpend: 0,
          pattern: 'No spending data available.',
          recommendation: '',
          analysisDate: DateTime.now(),
        );
      }

      double totalSpent = 0;
      final categoryCount = <String, int>{};
      final recipientCount = <String, int>{};
      final daySpending = <int, double>{};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          totalSpent += txn.totalCost;
          categoryCount[txn.category] = (categoryCount[txn.category] ?? 0) + 1;
          recipientCount[txn.counterparty] = (recipientCount[txn.counterparty] ?? 0) + 1;
          daySpending[txn.date.weekday] = (daySpending[txn.date.weekday] ?? 0) + txn.totalCost;
        }
      }

      // Find most common category and recipient
      String mostCommonCategory = 'transfers';
      String mostCommonRecipient = 'Unknown';
      int maxCategoryCount = 0;
      int maxRecipientCount = 0;

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

      // Determine peak spending day
      int peakDay = 0;
      double maxDaySpending = 0;
      daySpending.forEach((day, amount) {
        if (amount > maxDaySpending) {
          maxDaySpending = amount;
          peakDay = day;
        }
      });

      final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final pattern = 'Peak spending on ${dayNames[peakDay - 1]}s';

      final daysCount = end.difference(start).inDays;
      final averageDailySpend = daysCount > 0 ? (totalSpent / daysCount).toDouble() : 0.0;
      final averageWeeklySpend = (averageDailySpend * 7).toDouble();
      final averageMonthlySpend = (averageDailySpend * 30).toDouble();

      final recommendation = _generateSpendingRecommendation(mostCommonCategory, mostCommonRecipient, averageMonthlySpend);

      return SpendingHabits(
        mostCommonCategory: mostCommonCategory,
        mostCommonRecipient: mostCommonRecipient,
        averageDailySpend: averageDailySpend,
        averageWeeklySpend: averageWeeklySpend,
        averageMonthlySpend: averageMonthlySpend,
        pattern: pattern,
        recommendation: recommendation,
        analysisDate: DateTime.now(),
      );
    } catch (e) {
      print('Error analyzing spending habits: $e');
      return null;
    }
  }

  /// Private method: Generate spending habit insights
  Future<List<Insight>> _generateSpendingHabitInsights(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final insights = <Insight>[];

    try {
      final habits = await analyzeSpendingHabits(startDate: startDate, endDate: endDate);
      if (habits == null) return insights;

      insights.add(Insight(
        id: _newId(),
        type: 'spending_habit',
        title: 'Top Spending Category',
        description:
          'Your most common expense is ${_getCategoryName(habits.mostCommonCategory)}. '
          'Consider setting a budget for this category.',
        data: {'category': habits.mostCommonCategory},
        generatedAt: DateTime.now(),
        isActionable: true,
        actionLabel: 'Set Budget',
        actionUrl: '/budget/${habits.mostCommonCategory}',
      ));

      insights.add(Insight(
        id: _newId(),
        type: 'spending_habit',
        title: 'Daily Spending Average',
        description:
          'You spend an average of ${habits.formattedAverageDailySpend} RWF per day. '
          'Monthly average: ${habits.formattedAverageMonthlySpend} RWF.',
        data: {
          'dailyAverage': habits.averageDailySpend,
          'monthlyAverage': habits.averageMonthlySpend,
        },
        generatedAt: DateTime.now(),
        isActionable: false,
      ));

      insights.add(Insight(
        id: _newId(),
        type: 'pattern',
        title: habits.pattern,
        description: 'Based on your transaction history, ${habits.pattern.toLowerCase()}.',
        data: {},
        generatedAt: DateTime.now(),
        isActionable: false,
      ));
    } catch (e) {
      print('Error generating spending habit insights: $e');
    }

    return insights;
  }

  /// Private method: Generate recipient insights
  Future<List<Insight>> _generateRecipientInsights(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final insights = <Insight>[];

    try {
      final topRecipients = await recipientService.getTopRecipientsByAmount(
        limit: 3,
        startDate: startDate,
        endDate: endDate,
      );

      if (topRecipients.isNotEmpty) {
        final topRecipient = topRecipients.first;
        final percentage = await recipientService.getRecipientSpendingPercentage(
          topRecipient.name,
          startDate,
          endDate,
        );

        insights.add(Insight(
          id: _newId(),
          type: 'recipient',
          title: 'Top Recipient',
          description:
            'You send ${percentage.toStringAsFixed(1)}% of your money to ${topRecipient.name}. '
            '(${topRecipient.transactionCount} transactions, ${topRecipient.formattedTotalAmount} RWF total)',
          data: {
            'recipientName': topRecipient.name,
            'percentage': percentage,
            'amount': topRecipient.totalAmountSent,
            'count': topRecipient.transactionCount,
          },
          generatedAt: DateTime.now(),
          isActionable: true,
          actionLabel: 'View Details',
          actionUrl: '/recipient/${topRecipient.name}',
        ));
      }

      if (topRecipients.length > 1) {
        final topThree = topRecipients.take(3).toList();
        final names = topThree.map((r) => r.name).join(', ');

        insights.add(Insight(
          id: _newId(),
          type: 'recipient',
          title: 'Top 3 Recipients',
          description:
            'Your top 3 recipients are: $names. Together they account for a significant portion of your spending.',
          data: {
            'recipients': topThree.map((r) => r.name).toList(),
          },
          generatedAt: DateTime.now(),
          isActionable: true,
          actionLabel: 'View All',
          actionUrl: '/recipients',
        ));
      }
    } catch (e) {
      print('Error generating recipient insights: $e');
    }

    return insights;
  }

  /// Private method: Generate balance insights
  Future<List<Insight>> _generateBalanceInsights(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final insights = <Insight>[];

    try {
      final lowBalanceStats = await analyticsService.getLowBalanceStats();

      if (lowBalanceStats != null && lowBalanceStats.timesBelow > 0) {
        insights.add(Insight(
          id: _newId(),
          type: 'alert',
          title: 'Low Balance Alert',
          description: lowBalanceStats.insight,
          data: {
            'timesBelow': lowBalanceStats.timesBelow,
            'averageDaysBelow': lowBalanceStats.averageDaysBelow,
            'longestPeriod': lowBalanceStats.longestPeriodDays,
          },
          generatedAt: DateTime.now(),
          isActionable: true,
          actionLabel: 'View Details',
          actionUrl: '/balance-monitor',
        ));
      }

      final balanceAnalysis = await analyticsService.getBalanceAnalysis();
      if (balanceAnalysis != null) {
        insights.add(Insight(
          id: _newId(),
          type: 'pattern',
          title: 'Current Balance Status: ${balanceAnalysis.balanceHealth}',
          description:
            'Your current balance is ${balanceAnalysis.formattedCurrentBalance} RWF. '
            'Average balance: ${balanceAnalysis.formattedAverageBalance} RWF.',
          data: {
            'currentBalance': balanceAnalysis.currentBalance,
            'averageBalance': balanceAnalysis.averageBalance,
            'health': balanceAnalysis.balanceHealth,
          },
          generatedAt: DateTime.now(),
          isActionable: false,
        ));
      }
    } catch (e) {
      print('Error generating balance insights: $e');
    }

    return insights;
  }

  /// Private method: Generate recommendation insights
  Future<List<Insight>> _generateRecommendationInsights(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final insights = <Insight>[];

    try {
      final analysis = await analyticsService.getIncomeVsExpense(
        startDate: startDate,
        endDate: endDate,
      );

      if (analysis != null) {
        if (analysis.savingsRate < 20) {
          insights.add(Insight(
            id: _newId(),
            type: 'recommendation',
            title: 'Increase Savings Rate',
            description:
              'Your savings rate is ${analysis.formattedSavingsRate}. Try to increase it to at least 30% '
              'by reducing discretionary spending or tracking expenses more carefully.',
            data: {'currentSavingsRate': analysis.savingsRate},
            generatedAt: DateTime.now(),
            isActionable: true,
            actionLabel: 'View Analytics',
            actionUrl: '/analytics',
          ));
        } else if (analysis.savingsRate > 40) {
          insights.add(Insight(
            id: _newId(),
            type: 'recommendation',
            title: 'Excellent Savings Rate!',
            description:
              'Great job! Your savings rate is ${analysis.formattedSavingsRate}. Keep up this excellent financial discipline.',
            data: {'savingsRate': analysis.savingsRate},
            generatedAt: DateTime.now(),
            isActionable: false,
          ));
        }
      }
    } catch (e) {
      print('Error generating recommendation insights: $e');
    }

    return insights;
  }

  String _getCategoryName(String categoryId) {
    const names = {
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
    return names[categoryId] ?? 'Other';
  }

  String _generateSpendingRecommendation(
    String category,
    String recipient,
    double monthlySpend,
  ) {
    if (monthlySpend > 500000) {
      return 'Your monthly spending is high. Consider reviewing your budget and finding ways to reduce expenses.';
    }
    if (monthlySpend < 100000) {
      return 'Your spending is well-controlled. Continue maintaining this financial discipline.';
    }
    return 'Your spending is moderate. Monitor it regularly to ensure it aligns with your income.';
  }
}
