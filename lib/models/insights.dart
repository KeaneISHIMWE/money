import 'package:intl/intl.dart';

class Insight {
  final String id;
  final String type; // 'spending_habit', 'recipient', 'pattern', 'alert', 'recommendation'
  final String title;
  final String description;
  final dynamic data; // Additional context (can be any object)
  final DateTime generatedAt;
  final bool isActionable;
  final String? actionLabel;
  final String? actionUrl;

  Insight({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.data,
    required this.generatedAt,
    required this.isActionable,
    this.actionLabel,
    this.actionUrl,
  });

  String get formattedGeneratedAt => DateFormat('MMM dd, yyyy').format(generatedAt);

  String get icon {
    switch (type) {
      case 'spending_habit':
        return '📊';
      case 'recipient':
        return '👥';
      case 'pattern':
        return '📈';
      case 'alert':
        return '⚠️';
      case 'recommendation':
        return '💡';
      default:
        return 'ℹ️';
    }
  }

  String get typeLabel {
    switch (type) {
      case 'spending_habit':
        return 'Spending Habit';
      case 'recipient':
        return 'Recipient Insight';
      case 'pattern':
        return 'Pattern';
      case 'alert':
        return 'Alert';
      case 'recommendation':
        return 'Recommendation';
      default:
        return 'Insight';
    }
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'data': data,
    'generatedAt': generatedAt,
    'isActionable': isActionable,
    'actionLabel': actionLabel,
    'actionUrl': actionUrl,
  };

  static Insight? fromFirestore(Map<String, dynamic> data, String docId) {
    try {
      return Insight(
        id: docId,
        type: data['type'] ?? 'alert',
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        data: data['data'],
        generatedAt: (data['generatedAt'] as DateTime?) ?? DateTime.now(),
        isActionable: data['isActionable'] ?? false,
        actionLabel: data['actionLabel'],
        actionUrl: data['actionUrl'],
      );
    } catch (e) {
      print('Error parsing Insight: $e');
      return null;
    }
  }
}

class SpendingHabits {
  final String mostCommonCategory;
  final String mostCommonRecipient;
  final double averageDailySpend;
  final double averageWeeklySpend;
  final double averageMonthlySpend;
  final String pattern; // e.g., "Peak spending on Fridays"
  final String recommendation;
  final DateTime analysisDate;

  SpendingHabits({
    required this.mostCommonCategory,
    required this.mostCommonRecipient,
    required this.averageDailySpend,
    required this.averageWeeklySpend,
    required this.averageMonthlySpend,
    required this.pattern,
    required this.recommendation,
    required this.analysisDate,
  });

  String get formattedAverageDailySpend =>
    NumberFormat('#,##0.00', 'en_US').format(averageDailySpend);

  String get formattedAverageWeeklySpend =>
    NumberFormat('#,##0.00', 'en_US').format(averageWeeklySpend);

  String get formattedAverageMonthlySpend =>
    NumberFormat('#,##0.00', 'en_US').format(averageMonthlySpend);

  Map<String, dynamic> toFirestore() => {
    'mostCommonCategory': mostCommonCategory,
    'mostCommonRecipient': mostCommonRecipient,
    'averageDailySpend': averageDailySpend,
    'averageWeeklySpend': averageWeeklySpend,
    'averageMonthlySpend': averageMonthlySpend,
    'pattern': pattern,
    'recommendation': recommendation,
    'analysisDate': analysisDate,
  };

  static SpendingHabits? fromFirestore(Map<String, dynamic> data) {
    try {
      return SpendingHabits(
        mostCommonCategory: data['mostCommonCategory'] ?? 'transfers',
        mostCommonRecipient: data['mostCommonRecipient'] ?? 'Unknown',
        averageDailySpend: (data['averageDailySpend'] as num?)?.toDouble() ?? 0.0,
        averageWeeklySpend: (data['averageWeeklySpend'] as num?)?.toDouble() ?? 0.0,
        averageMonthlySpend: (data['averageMonthlySpend'] as num?)?.toDouble() ?? 0.0,
        pattern: data['pattern'] ?? 'No clear pattern detected',
        recommendation: data['recommendation'] ?? '',
        analysisDate: (data['analysisDate'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing SpendingHabits: $e');
      return null;
    }
  }
}

class SavingsRecommendation {
  final String id;
  final String title;
  final String description;
  final double potentialSavings;
  final String category;
  final String action;
  final String priority; // 'high', 'medium', 'low'
  final DateTime createdAt;

  SavingsRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.potentialSavings,
    required this.category,
    required this.action,
    required this.priority,
    required this.createdAt,
  });

  String get formattedPotentialSavings =>
    NumberFormat('#,##0.00', 'en_US').format(potentialSavings);

  String get priorityIcon {
    switch (priority) {
      case 'high':
        return '🔴';
      case 'medium':
        return '🟡';
      case 'low':
        return '🟢';
      default:
        return '⚪';
    }
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'title': title,
    'description': description,
    'potentialSavings': potentialSavings,
    'category': category,
    'action': action,
    'priority': priority,
    'createdAt': createdAt,
  };

  static SavingsRecommendation? fromFirestore(Map<String, dynamic> data, String docId) {
    try {
      return SavingsRecommendation(
        id: docId,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        potentialSavings: (data['potentialSavings'] as num?)?.toDouble() ?? 0.0,
        category: data['category'] ?? 'general',
        action: data['action'] ?? '',
        priority: data['priority'] ?? 'medium',
        createdAt: (data['createdAt'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing SavingsRecommendation: $e');
      return null;
    }
  }
}

class FinancialReport {
  final String month; // Format: 'yyyy-MM'
  final double totalIncome;
  final double totalExpenses;
  final double netCashFlow;
  final double savingsRate;
  final Map<String, double> categoryBreakdown;
  final List<String> topInsights;
  final List<SavingsRecommendation> recommendations;
  final DateTime generatedAt;

  FinancialReport({
    required this.month,
    required this.totalIncome,
    required this.totalExpenses,
    required this.netCashFlow,
    required this.savingsRate,
    required this.categoryBreakdown,
    required this.topInsights,
    required this.recommendations,
    required this.generatedAt,
  });

  String get formattedMonth => DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));

  String get formattedTotalIncome =>
    NumberFormat('#,##0.00', 'en_US').format(totalIncome);

  String get formattedTotalExpenses =>
    NumberFormat('#,##0.00', 'en_US').format(totalExpenses);

  String get formattedNetCashFlow =>
    NumberFormat('#,##0.00', 'en_US').format(netCashFlow);

  String get formattedSavingsRate =>
    '${savingsRate.toStringAsFixed(1)}%';

  Map<String, dynamic> toFirestore() => {
    'month': month,
    'totalIncome': totalIncome,
    'totalExpenses': totalExpenses,
    'netCashFlow': netCashFlow,
    'savingsRate': savingsRate,
    'categoryBreakdown': categoryBreakdown,
    'topInsights': topInsights,
    'recommendations': recommendations.map((r) => r.toFirestore()).toList(),
    'generatedAt': generatedAt,
  };

  static FinancialReport? fromFirestore(Map<String, dynamic> data) {
    try {
      final recommendationsList = data['recommendations'] as List<dynamic>? ?? [];
      final recommendations = recommendationsList
        .map((r) => SavingsRecommendation.fromFirestore(
          r as Map<String, dynamic>,
          data['id'] ?? '',
        ))
        .whereType<SavingsRecommendation>()
        .toList();

      return FinancialReport(
        month: data['month'] ?? '',
        totalIncome: (data['totalIncome'] as num?)?.toDouble() ?? 0.0,
        totalExpenses: (data['totalExpenses'] as num?)?.toDouble() ?? 0.0,
        netCashFlow: (data['netCashFlow'] as num?)?.toDouble() ?? 0.0,
        savingsRate: (data['savingsRate'] as num?)?.toDouble() ?? 0.0,
        categoryBreakdown: Map<String, double>.from(data['categoryBreakdown'] as Map? ?? {}),
        topInsights: List<String>.from(data['topInsights'] as List? ?? []),
        recommendations: recommendations,
        generatedAt: (data['generatedAt'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing FinancialReport: $e');
      return null;
    }
  }
}
