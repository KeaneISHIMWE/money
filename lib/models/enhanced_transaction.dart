import 'package:intl/intl.dart';

class EnhancedTransaction {
  final String id;
  final String userId;
  final double amount;
  final DateTime date;
  final String type; // SENT, RECEIVED
  final String counterparty;
  final String? counterpartyPhone;
  final double fee;
  final double balance;
  final String category; // Expense category for sent transactions
  final String? description;
  final String source; // SMS, MANUAL, API
  final String transactionId; // MoMo transaction ID
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  EnhancedTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.date,
    required this.type,
    required this.counterparty,
    this.counterpartyPhone,
    required this.fee,
    required this.balance,
    required this.category,
    this.description,
    required this.source,
    required this.transactionId,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isReceived => type == 'RECEIVED';
  bool get isSent => type == 'SENT';

  String get formattedDate => DateFormat('MMM dd, yyyy HH:mm').format(date);
  String get formattedAmount => NumberFormat('#,##0.00', 'en_US').format(amount);
  String get formattedBalance => NumberFormat('#,##0.00', 'en_US').format(balance);

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'userId': userId,
    'amount': amount,
    'date': date,
    'type': type,
    'counterparty': counterparty,
    'counterpartyPhone': counterpartyPhone,
    'fee': fee,
    'balance': balance,
    'category': category,
    'description': description,
    'source': source,
    'transactionId': transactionId,
    'metadata': metadata,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  static EnhancedTransaction? fromFirestore(Map<String, dynamic> data, String docId) {
    try {
      return EnhancedTransaction(
        id: docId,
        userId: data['userId'] ?? '',
        amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
        date: (data['date'] as DateTime?) ?? DateTime.now(),
        type: data['type'] ?? 'UNKNOWN',
        counterparty: data['counterparty'] ?? 'Unknown',
        counterpartyPhone: data['counterpartyPhone'],
        fee: (data['fee'] as num?)?.toDouble() ?? 0.0,
        balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
        category: data['category'] ?? 'other',
        description: data['description'],
        source: data['source'] ?? 'MANUAL',
        transactionId: data['transactionId'] ?? '',
        metadata: data['metadata'] as Map<String, dynamic>?,
        createdAt: (data['createdAt'] as DateTime?) ?? DateTime.now(),
        updatedAt: (data['updatedAt'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing EnhancedTransaction: $e');
      return null;
    }
  }

  @override
  String toString() =>
    'EnhancedTransaction(id: $id, amount: $amount, counterparty: $counterparty, category: $category)';
}

class ExpenseCategory {
  final String id;
  final String name;
  final String description;
  final String color;
  final String icon;
  final double? monthlyBudget;
  final DateTime createdAt;

  ExpenseCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    this.monthlyBudget,
    required this.createdAt,
  });

  static const List<ExpenseCategory> defaults = [
    ExpenseCategory(
      id: 'transfers',
      name: 'Transfers to Individuals',
      description: 'Money sent to people',
      color: '#3498db',
      icon: 'person',
      monthlyBudget: null,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'airtime',
      name: 'Airtime Purchases',
      description: 'Mobile phone airtime',
      color: '#2ecc71',
      icon: 'phone',
      monthlyBudget: 10000,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'internet',
      name: 'Internet/Data Bundles',
      description: 'Internet and data services',
      color: '#e74c3c',
      icon: 'wifi',
      monthlyBudget: 15000,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'utilities',
      name: 'Utility Payments',
      description: 'Electricity, water, gas bills',
      color: '#f39c12',
      icon: 'lightbulb',
      monthlyBudget: 20000,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'merchants',
      name: 'Merchant Payments',
      description: 'Shops, stores, vendors',
      color: '#9b59b6',
      icon: 'shopping-cart',
      monthlyBudget: null,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'bank',
      name: 'Bank Transfers',
      description: 'Bank and financial transfers',
      color: '#34495e',
      icon: 'bank',
      monthlyBudget: null,
      createdAt: null,
    ),
    ExpenseCategory(
      id: 'other',
      name: 'Other Expenses',
      description: 'Miscellaneous expenses',
      color: '#95a5a6',
      icon: 'dots-horizontal',
      monthlyBudget: null,
      createdAt: null,
    ),
  ];

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
    'icon': icon,
    'monthlyBudget': monthlyBudget,
    'createdAt': createdAt,
  };

  static ExpenseCategory? fromFirestore(Map<String, dynamic> data) {
    try {
      return ExpenseCategory(
        id: data['id'] ?? '',
        name: data['name'] ?? '',
        description: data['description'] ?? '',
        color: data['color'] ?? '#95a5a6',
        icon: data['icon'] ?? 'dots-horizontal',
        monthlyBudget: (data['monthlyBudget'] as num?)?.toDouble(),
        createdAt: (data['createdAt'] as DateTime?) ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing ExpenseCategory: $e');
      return null;
    }
  }
}
