import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/recipient_profile.dart';
import '../models/enhanced_transaction.dart';

class RecipientService {
  final FirebaseFirestore _firestore;
  final String userId;

  RecipientService({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Get top recipients by total amount sent
  Future<List<RecipientProfile>> getTopRecipientsByAmount({
    int limit = 10,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final recipients = await _getRecipientProfiles(startDate, endDate);
      final sorted = recipients.toList()
        ..sort((a, b) => b.totalAmountSent.compareTo(a.totalAmountSent));
      return sorted.take(limit).toList();
    } catch (e) {
      print('Error getting top recipients by amount: $e');
      return [];
    }
  }

  /// Get top recipients by transaction count
  Future<List<RecipientProfile>> getTopRecipientsByFrequency({
    int limit = 10,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final recipients = await _getRecipientProfiles(startDate, endDate);
      final sorted = recipients.toList()
        ..sort((a, b) => b.transactionCount.compareTo(a.transactionCount));
      return sorted.take(limit).toList();
    } catch (e) {
      print('Error getting top recipients by frequency: $e');
      return [];
    }
  }

  /// Get all recipients with their statistics
  Future<List<RecipientProfile>> getAllRecipients({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      return await _getRecipientProfiles(startDate, endDate);
    } catch (e) {
      print('Error getting all recipients: $e');
      return [];
    }
  }

  /// Get profile for a specific recipient
  Future<RecipientProfile?> getRecipientProfile(String recipientName) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('recipients')
        .doc(recipientName);

      final doc = await query.get();
      if (doc.exists) {
        return RecipientProfile.fromFirestore(doc.data()!, doc.id);
      }

      return null;
    } catch (e) {
      print('Error getting recipient profile: $e');
      return null;
    }
  }

  /// Get monthly statistics for a recipient
  Future<Map<String, RecipientMonthlyStats>> getRecipientMonthlyStats(
    String recipientName,
  ) async {
    try {
      final profile = await getRecipientProfile(recipientName);
      return profile?.monthlyStats ?? {};
    } catch (e) {
      print('Error getting recipient monthly stats: $e');
      return {};
    }
  }

  /// Get percentage of total spending that goes to a recipient
  Future<double> getRecipientSpendingPercentage(
    String recipientName,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Get total sent amount for this recipient
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('counterparty', isEqualTo: recipientName)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate);

      final recipientSnapshot = await query.get();
      double recipientTotal = 0;

      for (final doc in recipientSnapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          recipientTotal += txn.totalCost;
        }
      }

      // Get total sent amount for all recipients
      final totalQuery = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate);

      final totalSnapshot = await totalQuery.get();
      double totalSent = 0;

      for (final doc in totalSnapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          totalSent += txn.totalCost;
        }
      }

      if (totalSent == 0) return 0;
      return (recipientTotal / totalSent) * 100;
    } catch (e) {
      print('Error getting recipient spending percentage: $e');
      return 0;
    }
  }

  /// Update recipient profiles (should be called periodically)
  Future<void> updateRecipientProfiles({
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

      final recipientMap = <String, Map<String, dynamic>>{};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          final key = txn.counterparty;
          final monthKey = DateFormat('yyyy-MM').format(txn.date);

          if (!recipientMap.containsKey(key)) {
            recipientMap[key] = {
              'name': txn.counterparty,
              'phone': txn.counterpartyPhone,
              'totalAmountSent': 0.0,
              'transactionCount': 0,
              'lastTransaction': txn.date,
              'monthlyStats': <String, Map<String, dynamic>>{},
            };
          }

          final recipient = recipientMap[key]!;
          recipient['totalAmountSent'] += txn.totalCost;
          recipient['transactionCount'] += 1;

          if (txn.date.isAfter(recipient['lastTransaction'] as DateTime)) {
            recipient['lastTransaction'] = txn.date;
          }

          // Update monthly stats
          final monthlyStats = recipient['monthlyStats'] as Map<String, dynamic>;
          if (!monthlyStats.containsKey(monthKey)) {
            monthlyStats[monthKey] = {
              'month': monthKey,
              'totalAmount': 0.0,
              'transactionCount': 0,
            };
          }

          final monthlyStat = monthlyStats[monthKey] as Map<String, dynamic>;
          monthlyStat['totalAmount'] += txn.totalCost;
          monthlyStat['transactionCount'] += 1;
        }
      }

      // Save updated profiles to Firestore
      for (final entry in recipientMap.entries) {
        await _firestore
          .collection('users')
          .doc(userId)
          .collection('recipients')
          .doc(entry.key)
          .set(entry.value, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error updating recipient profiles: $e');
      rethrow;
    }
  }

  /// Get transactions for a specific recipient
  Future<List<EnhancedTransaction>> getRecipientTransactions(
    String recipientName, {
    int limit = 50,
  }) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('counterparty', isEqualTo: recipientName)
        .where('type', isEqualTo: 'SENT')
        .orderBy('date', descending: true)
        .limit(limit);

      final snapshot = await query.get();
      final transactions = snapshot.docs
        .map((doc) => EnhancedTransaction.fromFirestore(doc.data(), doc.id))
        .whereType<EnhancedTransaction>()
        .toList();

      return transactions;
    } catch (e) {
      print('Error getting recipient transactions: $e');
      return [];
    }
  }

  /// Private method: Get recipient profiles from transactions
  Future<List<RecipientProfile>> _getRecipientProfiles(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final query = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'SENT')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate);

      final snapshot = await query.get();

      final recipientMap = <String, RecipientProfile>{};

      for (final doc in snapshot.docs) {
        final txn = EnhancedTransaction.fromFirestore(doc.data(), doc.id);
        if (txn != null) {
          final existing = recipientMap[txn.counterparty];

          if (existing == null) {
            recipientMap[txn.counterparty] = RecipientProfile(
              id: txn.counterparty,
              name: txn.counterparty,
              phone: txn.counterpartyPhone,
              totalAmountSent: txn.totalCost,
              transactionCount: 1,
              lastTransaction: txn.date,
              monthlyStats: {},
              lastUpdated: DateTime.now(),
            );
          } else {
            existing.totalAmountSent += txn.totalCost;
            existing.transactionCount += 1;
            if (txn.date.isAfter(existing.lastTransaction)) {
              existing.lastTransaction = txn.date;
            }
          }
        }
      }

      return recipientMap.values.toList();
    } catch (e) {
      print('Error getting recipient profiles: $e');
      return [];
    }
  }
}

/// Extension to make RecipientProfile mutable for easier updates
extension MutableRecipientProfile on RecipientProfile {
  void addTransaction(double amount, DateTime date) {
    totalAmountSent += amount;
    transactionCount += 1;
    lastTransaction = date;
  }
}
