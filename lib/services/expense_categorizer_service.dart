import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/enhanced_transaction.dart';

class ExpenseCategorizerService {
  final FirebaseFirestore _firestore;
  final String userId;

  ExpenseCategorizerService({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // Keywords for automatic categorization
  static const Map<String, List<String>> categoryKeywords = {
    'airtime': [
      'airtime',
      'recharge',
      'plan',
      'bundle',
      '*165*',
      'mtc',
      'tigo',
      'rwandatel',
      'phone credit'
    ],
    'internet': [
      'internet',
      'data',
      'wifi',
      'bundle',
      'plan',
      '*143*',
      'modem',
      'connection'
    ],
    'utilities': [
      'electric',
      'water',
      'gas',
      'bill',
      'payment',
      'utility',
      'power',
      'supply'
    ],
    'merchants': [
      'amazon',
      'shop',
      'mall',
      'store',
      'market',
      'payment',
      'purchase',
      'restaurant',
      'supermarket',
      'vendor'
    ],
    'bank': [
      'bank',
      'transfer',
      'account',
      'swift',
      'branch',
      'financial',
      'banking'
    ],
    'transfers': ['transfer', 'send', 'friend', 'family', 'person', 'individual'],
    'other': [],
  };

  /// Categorize an expense based on counterparty name and description
  Future<String> categorizeExpense(
    String counterparty,
    double amount,
    String? description,
  ) async {
    try {
      // First try keyword matching
      final keywordCategory = _categorizeByKeywords(counterparty, description);
      if (keywordCategory != 'other') {
        return keywordCategory;
      }

      // Fall back to historical patterns
      final historicalCategory = await _predictCategoryFromHistory(counterparty);
      return historicalCategory;
    } catch (e) {
      print('Error categorizing expense: $e');
      return 'other';
    }
  }

  /// Categorize all uncategorized transactions
  Future<int> categorizeAllUncategorized() async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('category', isEqualTo: 'other');

      final snapshot = await query.get();
      int count = 0;

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          final category = await categorizeExpense(
            txn.counterparty,
            txn.amount,
            txn.description,
          );

          await doc.reference.update({'category': category});
          count++;
        }
      }

      return count;
    } catch (e) {
      print('Error categorizing all transactions: $e');
      return 0;
    }
  }

  /// Manually update category for a transaction
  Future<void> updateTransactionCategory(String transactionId, String category) async {
    try {
      await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .doc(transactionId)
        .update({'category': category});
    } catch (e) {
      print('Error updating transaction category: $e');
      rethrow;
    }
  }

  /// Get all transactions for a specific counterparty
  Future<List<EnhancedTransaction>> getTransactionsByCounterparty(
    String counterparty,
  ) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('counterparty', isEqualTo: counterparty)
        .where('type', isEqualTo: 'SENT');

      final snapshot = await query.get();
      final transactions = snapshot.docs
        .map((doc) => EnhancedTransaction.fromFirestore(doc.data(), doc.id))
        .whereType<EnhancedTransaction>()
        .toList();

      return transactions;
    } catch (e) {
      print('Error getting transactions by counterparty: $e');
      return [];
    }
  }

  /// Private method: Categorize using keyword matching
  String _categorizeByKeywords(String counterparty, String? description) {
    final combined = '${counterparty.toLowerCase()} ${description?.toLowerCase() ?? ''}'.trim();

    for (final entry in categoryKeywords.entries) {
      if (entry.value.isEmpty) continue; // Skip 'other'

      for (final keyword in entry.value) {
        if (combined.contains(keyword.toLowerCase())) {
          return entry.key;
        }
      }
    }

    return 'other';
  }

  /// Private method: Predict category from historical patterns
  Future<String> _predictCategoryFromHistory(String counterparty) async {
    try {
      final transactions = await getTransactionsByCounterparty(counterparty);

      if (transactions.isEmpty) {
        return 'transfers'; // Default for first-time recipient
      }

      // Find most common category for this counterparty
      final categoryCount = <String, int>{};

      for (final txn in transactions) {
        categoryCount[txn.category] = (categoryCount[txn.category] ?? 0) + 1;
      }

      String mostCommonCategory = 'transfers';
      int maxCount = 0;

      categoryCount.forEach((category, count) {
        if (count > maxCount) {
          maxCount = count;
          mostCommonCategory = category;
        }
      });

      return mostCommonCategory;
    } catch (e) {
      print('Error predicting category from history: $e');
      return 'transfers';
    }
  }

  /// Get category statistics
  Future<Map<String, int>> getCategoryDistribution() async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT');

      final snapshot = await query.get();
      final distribution = <String, int>{};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          distribution[txn.category] = (distribution[txn.category] ?? 0) + 1;
        }
      }

      return distribution;
    } catch (e) {
      print('Error getting category distribution: $e');
      return {};
    }
  }

  /// Suggest category based on AI-like pattern matching
  String suggestCategory(String counterparty, double amount, String? description) {
    // If amount matches common patterns, use that
    if (amount >= 1000 && amount <= 5000) {
      // Likely airtime or data
      if (_categorizeByKeywords(counterparty, description) == 'other') {
        return 'airtime';
      }
    }

    if (amount >= 5000 && amount <= 50000) {
      // Could be utilities, merchants, or transfers
      final keyword = _categorizeByKeywords(counterparty, description);
      if (keyword != 'other') {
        return keyword;
      }
      return 'transfers';
    }

    return _categorizeByKeywords(counterparty, description);
  }
}
