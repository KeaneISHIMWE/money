import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../models/enhanced_transaction.dart';

class TopRecipientsWidget extends StatelessWidget {
  final List<EnhancedTransaction> transactions;
  final String title;
  final int maxItems;

  const TopRecipientsWidget({
    super.key,
    required this.transactions,
    this.title = 'Top Recipients',
    this.maxItems = 5,
  });

  List<({String name, double totalAmount, int count})> _getTopRecipients() {
    final recipients = <String, ({double amount, int count})>{};

    for (final tx in transactions.where((t) => t.isSent)) {
      final key = tx.counterparty;
      if (recipients.containsKey(key)) {
        final existing = recipients[key]!;
        recipients[key] = (
          amount: existing.amount + tx.totalCost,
          count: existing.count + 1
        );
      } else {
        recipients[key] = (amount: tx.totalCost, count: 1);
      }
    }

    final list = recipients.entries
        .map((e) => (name: e.key, totalAmount: e.value.amount, count: e.value.count))
        .toList();
    list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return list.take(maxItems).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final topRecipients = _getTopRecipients();

    if (topRecipients.isEmpty) {
      return Card(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No recipient data available',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
      );
    }

    final total = topRecipients.fold<double>(0, (sum, r) => sum + r.totalAmount);

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
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topRecipients.length,
              separatorBuilder: (_, __) => Divider(
                color: c.cardBorder.withValues(alpha: 0.3),
                height: 1,
              ),
              itemBuilder: (context, index) {
                final recipient = topRecipients[index];
                final percentage = (recipient.totalAmount / total * 100).toStringAsFixed(1);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      // Rank circle
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: c.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name and transaction count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recipient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${recipient.count} transaction${recipient.count > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Amount and percentage
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            NumberFormat.currency(symbol: '', decimalDigits: 0)
                                .format(recipient.totalAmount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 12,
                              color: c.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
