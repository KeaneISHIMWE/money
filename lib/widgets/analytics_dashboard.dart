import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../models/enhanced_transaction.dart';
import 'category_breakdown_widget.dart';
import 'top_recipients_widget.dart';
import 'spending_trend_widget.dart';

/// Sample analytics dashboard that combines all three widgets.
/// Can be embedded in a page or used standalone for testing.
class AnalyticsDashboard extends StatelessWidget {
  final List<EnhancedTransaction> transactions;

  const AnalyticsDashboard({
    super.key,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final sentTx = transactions.where((t) => t.isSent).toList();
    final totalSpent = sentTx.fold<double>(0, (sum, t) => sum + t.totalCost);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Card(
            color: c.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Spent',
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RWF ${totalSpent.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${sentTx.length} transactions',
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Category breakdown
          CategoryBreakdownWidget(transactions: transactions),
          const SizedBox(height: 24),
          // Top recipients
          TopRecipientsWidget(transactions: transactions),
          const SizedBox(height: 24),
          // Spending trend
          SpendingTrendWidget(transactions: transactions),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
