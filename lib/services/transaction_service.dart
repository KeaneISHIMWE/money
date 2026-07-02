import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

import 'auth_service.dart';
import 'expense_categorizer_service.dart';
import '../models/enhanced_transaction.dart';
import '../models/transaction.dart' as SmsModel;

class TransactionService {
  final FirebaseFirestore _db;
  final AuthService _authService;

  TransactionService({FirebaseFirestore? firestore, AuthService? authService})
      : _db = firestore ?? FirebaseFirestore.instance,
        _authService = authService ?? AuthService();

  /// Builds enhanced transactions from SMS without touching Firestore.
  /// Used as a fallback when cloud sync is empty or unavailable.
  List<EnhancedTransaction> enhancedFromSmsMessages(
    List<SmsMessage> messages,
    String userId,
  ) {
    final results = <EnhancedTransaction>[];

    for (final msg in messages) {
      final enhanced = _enhancedFromSmsMessage(
        msg,
        userId,
      );
      if (enhanced != null) {
        results.add(enhanced);
      }
    }

    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  static const int _ingestBatchSize = 450;

  /// Ingests SMS messages into Firestore using batched writes.
  /// Safe to call in the background — UI reads SMS directly.
  Future<int> ingestSmsMessages(List<SmsMessage> messages) async {
    final phone = await _authService.getCurrentUserPhone();
    if (phone == null || messages.isEmpty) return 0;

    try {
      final col = _db.collection('users').doc(phone).collection('transactions');
      final existingIds = await _existingTransactionIds(col);

      final parsed = enhancedFromSmsMessages(messages, phone);
      final toWrite =
          parsed.where((txn) => !existingIds.contains(txn.id)).toList();
      if (toWrite.isEmpty) return 0;

      var written = 0;
      for (var i = 0; i < toWrite.length; i += _ingestBatchSize) {
        final end = (i + _ingestBatchSize).clamp(0, toWrite.length);
        final chunk = toWrite.sublist(i, end);
        final batch = _db.batch();
        for (final txn in chunk) {
          batch.set(col.doc(txn.id), txn.toFirestore());
        }
        await batch.commit();
        written += chunk.length;
      }
      return written;
    } catch (e) {
      print('Error ingesting SMS messages: $e');
      return 0;
    }
  }

  Future<Set<String>> _existingTransactionIds(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final ids = <String>{};
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      var query = col.orderBy(FieldPath.documentId).limit(_ingestBatchSize);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snap = await query.get();
      if (snap.docs.isEmpty) break;

      ids.addAll(snap.docs.map((doc) => doc.id));
      lastDoc = snap.docs.last;
      if (snap.docs.length < _ingestBatchSize) break;
    }

    return ids;
  }

  String _docIdForParsed(SmsModel.Transaction parsed) {
    if (parsed.transactionId.isNotEmpty) {
      return parsed.transactionId;
    }
    final ts = parsed.date.millisecondsSinceEpoch;
    final cleanCounter =
        parsed.counterparty.replaceAll(RegExp(r'\s+'), '_');
    final counterPart = cleanCounter.isEmpty
        ? 'unknown'
        : cleanCounter.substring(0, cleanCounter.length.clamp(0, 30));
    return 'sms-$ts-${parsed.amount.toStringAsFixed(0)}-$counterPart';
  }

  EnhancedTransaction? _enhancedFromSmsMessage(
    SmsMessage msg,
    String userId,
  ) {
    final body = msg.body ?? '';
    final parsed = SmsModel.Transaction.fromSmsMessage(body, smsDate: msg.date);
    if (parsed == null) return null;

    final docId = _docIdForParsed(parsed);
    final counterpartyPhone = _extractCounterpartyPhone(body);

    final category = parsed.isSent ? parsed.expenseType : 'other';

    final now = DateTime.now();
    return EnhancedTransaction(
      id: docId,
      userId: userId,
      amount: parsed.amount,
      date: parsed.date,
      type: parsed.type,
      counterparty: parsed.counterparty,
      counterpartyPhone: counterpartyPhone,
      fee: parsed.fee,
      balance: parsed.balance,
      category: category,
      description: body,
      source: 'SMS',
      transactionId: parsed.transactionId.isNotEmpty ? parsed.transactionId : docId,
      metadata: {'smsAddress': msg.address},
      createdAt: now,
      updatedAt: now,
    );
  }

  String? _extractCounterpartyPhone(String body) {
    final phoneMatch = RegExp(r'(\+?\d{8,15}|0\d{8,12})').firstMatch(body);
    return phoneMatch?.group(0)?.trim();
  }

  /// Re-categorizes all SENT transactions for the current user using
  /// ExpenseCategorizerService. Returns the number of documents updated.
  Future<int> reCategorizeAllTransactions({int batchSize = 450}) async {
    final phone = await _authService.getCurrentUserPhone();
    if (phone == null) return 0;

    final categorizer = ExpenseCategorizerService(userId: phone, firestore: _db);
    int updatedCount = 0;

    try {
      // Query all SENT transactions
      final colRef = _db.collection('users').doc(phone).collection('transactions');
      Query query = colRef.where('type', isEqualTo: 'SENT');

      // Paginate through results to avoid memory spikes
      String? lastDocId;
      while (true) {
        Query paged = query.orderBy(FieldPath.documentId).limit(batchSize);
        if (lastDocId != null) {
          final lastSnap = await colRef.doc(lastDocId).get();
          if (!lastSnap.exists) break;
          paged = paged.startAfterDocument(lastSnap);
        }

        final snapshot = await paged.get();
        if (snapshot.docs.isEmpty) break;

        final batch = _db.batch();
        int ops = 0;

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final currentCategory = (data['category'] as String?) ?? 'other';
          final counterparty = (data['counterparty'] as String?) ?? '';
          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

          try {
            final predicted = await categorizer.categorizeExpense(counterparty, amount, data['description'] as String?);
            if (predicted != currentCategory) {
              batch.update(doc.reference, {'category': predicted, 'updatedAt': DateTime.now()});
              updatedCount++;
              ops++;
            }
          } catch (e) {
            print('Error predicting category for ${doc.id}: $e');
            continue;
          }
        }

        if (ops > 0) {
          await batch.commit();
        }

        // Prepare for next page
        lastDocId = snapshot.docs.last.id;
        if (snapshot.docs.length < batchSize) break;
      }
    } catch (e) {
      print('Error re-categorizing transactions: $e');
    }

    return updatedCount;
  }
}
