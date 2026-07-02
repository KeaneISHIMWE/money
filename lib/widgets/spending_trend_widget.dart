import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../models/enhanced_transaction.dart';

class SpendingTrendWidget extends StatelessWidget {
  final List<EnhancedTransaction> transactions;
  final String title;
  final int daysToShow;

  const SpendingTrendWidget({
    super.key,
    required this.transactions,
    this.title = 'Spending Trend',
    this.daysToShow = 30,
  });

  Map<DateTime, double> _calculateDailySpending() {
    final daily = <DateTime, double>{};

    for (final tx in transactions.where((t) => t.isSent)) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      daily[day] = (daily[day] ?? 0) + tx.totalCost;
    }

    return daily;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final dailySpending = _calculateDailySpending();

    if (dailySpending.isEmpty) {
      return Card(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No spending trend data available',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
      );
    }

    // Sort and limit to last N days
    final sorted = dailySpending.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: daysToShow));
    final filtered = sorted
        .where((e) => e.key.isAfter(startDate) || e.key.isAtSameMomentAs(startDate))
        .toList();

    if (filtered.isEmpty) {
      return Card(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No spending data in the last $daysToShow days',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
      );
    }

    // Build chart spots (x = day index, y = amount)
    final spots = <FlSpot>[];
    for (int i = 0; i < filtered.length; i++) {
      spots.add(FlSpot(i.toDouble(), filtered[i].value));
    }

    // Calculate max Y for chart scaling
    final maxY = (filtered.map((e) => e.value).reduce((a, b) => a > b ? a : b) * 1.1);

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
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: c.cardBorder.withValues(alpha: 0.2),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: (filtered.length / 5).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= filtered.length) {
                            return const SizedBox.shrink();
                          }
                          final date = filtered[index].key;
                          return Transform.translate(
                            offset: const Offset(0, 10),
                            child: Text(
                              DateFormat('M/d').format(date),
                              style: TextStyle(
                                fontSize: 11,
                                color: c.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value / 1000).toStringAsFixed(0)}k',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(
                        color: c.cardBorder.withValues(alpha: 0.3),
                        width: 1,
                      ),
                      left: BorderSide(
                        color: c.cardBorder.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [
                          c.primary.withValues(alpha: 0.8),
                          c.primary.withValues(alpha: 0.3),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: c.primary,
                          strokeWidth: 2,
                          strokeColor: c.card,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            c.primary.withValues(alpha: 0.3),
                            c.primary.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  minX: 0,
                  maxX: (filtered.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Summary stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatBox(
                  label: 'Average',
                  value: NumberFormat.currency(symbol: '', decimalDigits: 0)
                      .format(filtered.map((e) => e.value).reduce((a, b) => a + b) /
                          filtered.length),
                  c: c,
                ),
                _buildStatBox(
                  label: 'Max',
                  value: NumberFormat.currency(symbol: '', decimalDigits: 0)
                      .format(filtered.map((e) => e.value).reduce((a, b) => a > b ? a : b)),
                  c: c,
                ),
                _buildStatBox(
                  label: 'Total',
                  value: NumberFormat.currency(symbol: '', decimalDigits: 0)
                      .format(filtered.map((e) => e.value).reduce((a, b) => a + b)),
                  c: c,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required AppColors c,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: c.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ],
    );
  }
}
