import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../app_colors.dart';
import '../models/enhanced_transaction.dart';
import '../models/transaction.dart';

class CategoryBreakdownWidget extends StatelessWidget {
  final List<EnhancedTransaction> transactions;
  final String title;

  const CategoryBreakdownWidget({
    super.key,
    required this.transactions,
    this.title = 'Spending by Category',
  });

  Map<String, double> _calculateCategoryTotals() {
    final totals = <String, double>{};
    for (final tx in transactions.where((t) => t.isSent)) {
      totals[tx.category] = (totals[tx.category] ?? 0) + tx.totalCost;
    }
    return totals;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'normal_transfer':
      case 'transfers':
        return const Color(0xFF3498db);
      case 'airtime':
        return const Color(0xFF2ecc71);
      case 'bundle_and_pack':
      case 'internet':
        return const Color(0xFFe74c3c);
      case 'payment':
      case 'utilities':
      case 'merchants':
        return const Color(0xFF9b59b6);
      default:
        return const Color(0xFF95a5a6);
    }
  }

  String _categoryLabel(String category) => ExpenseType.label(category);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final categoryTotals = _calculateCategoryTotals();

    if (categoryTotals.isEmpty) {
      return Card(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No spending data available',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
      );
    }

    final entries = categoryTotals.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    if (entries.isEmpty || total <= 0) {
      return Card(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No spending data available',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
      );
    }

    return Card(
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: entries.map((entry) {
                    final percentage =
                        (entry.value / total * 100).toStringAsFixed(1);
                    return PieChartSectionData(
                      color: _getCategoryColor(entry.key),
                      value: entry.value,
                      title: '$percentage%',
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Legend
            Column(
              children: entries.map((entry) {
                final percentage = (entry.value / total * 100).toStringAsFixed(1);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(entry.key),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _categoryLabel(entry.key),
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
