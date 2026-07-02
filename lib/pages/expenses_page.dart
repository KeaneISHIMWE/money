import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import '../app_colors.dart';
import '../theme_decorations.dart';
import '../models/analytics_models.dart';
import '../models/enhanced_transaction.dart';
import '../models/insights.dart';
import '../models/transaction.dart';
import '../services/auth_service.dart';
import '../services/local_analytics.dart';
import '../services/transaction_service.dart';
import '../widgets/category_breakdown_widget.dart';
import '../widgets/top_recipients_widget.dart';

class ExpensesPage extends StatefulWidget {
  final bool embeddedInShell;
  final List<SmsMessage> messages;

  const ExpensesPage({
    super.key,
    this.embeddedInShell = false,
    this.messages = const [],
  });

  @override
  State<ExpensesPage> createState() => ExpensesPageState();
}

class ExpensesPageState extends State<ExpensesPage>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final TransactionService _transactionService = TransactionService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: 'RWF ',
    decimalDigits: 0,
  );

  String _selectedPeriod = 'month';
  bool _loading = false;
  bool _chartsReady = false;
  bool _firestoreLoading = false;

  SpendingSummary? _spendingSummary;
  SpendingSummary? _previousPeriodSummary;
  IncomeVsExpenseAnalysis? _incomeVsExpense;
  LowBalanceStats? _lowBalanceStats;
  SpendingHabits? _spendingHabits;
  List<Insight> _insights = [];
  List<EnhancedTransaction> _allTransactions = [];
  List<MonthlyTransactionSummary> _monthlySummaries = [];
  int _selectedMonthIndex = 0;
  int _selectedProgressMonthIndex = 0;
  bool _showTargetLine = true;

  late AnimationController _staggerController;
  late ScrollController _scrollController;

  AppColors get _c => Theme.of(context).extension<AppColors>()!;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get primaryColor => _c.primary;
  Color get primaryDark => _c.primaryDark;
  Color get accentPurple => _c.accentPurple;
  Color get successColor => _c.success;
  Color get dangerColor => _c.danger;
  Color get bgColor => _c.bg;
  Color get cardColor => _c.card;
  Color get cardBorder => _c.cardBorder;
  Color get textPrimary => _c.textPrimary;
  Color get textSecondary => _c.textSecondary;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _chartsReady = true);
      _staggerController.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(ExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length) {
      _loadData(showLoading: false);
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_selectedPeriod) {
      case 'today':
        return (today, today.add(const Duration(days: 1)));
      case 'week':
        final weekStart =
            today.subtract(Duration(days: today.weekday - DateTime.monday));
        return (weekStart, weekStart.add(const Duration(days: 7)));
      case 'month':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1),
        );
      case 'year':
        return (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
      default:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1),
        );
    }
  }

  (DateTime, DateTime) _getPreviousDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_selectedPeriod) {
      case 'today':
        final yesterday = today.subtract(const Duration(days: 1));
        return (yesterday, today);
      case 'week':
        final weekStart =
            today.subtract(Duration(days: today.weekday - DateTime.monday));
        return (weekStart.subtract(const Duration(days: 7)), weekStart);
      case 'month':
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        return (prevMonth, DateTime(now.year, now.month, 1));
      case 'year':
        return (DateTime(now.year - 1, 1, 1), DateTime(now.year, 1, 1));
      default:
        return (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 1));
    }
  }

  Future<void> _loadData({
    List<SmsMessage>? messages,
    bool showLoading = false,
  }) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }

    try {
      final phone = await _authService.getCurrentUserPhone();

      if (phone == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final smsMessages = messages ?? widget.messages;

      // Show SMS data immediately — same source as the Home tab.
      var allTransactions = <EnhancedTransaction>[];
      if (smsMessages.isNotEmpty) {
        allTransactions = _transactionService.enhancedFromSmsMessages(
          smsMessages,
          phone,
        );
        if (mounted && allTransactions.isNotEmpty) {
          _applyTransactionData(allTransactions);
        }
      }

      if (mounted) setState(() => _firestoreLoading = true);

      // Merge Firestore in the background; never block the UI on this.
      try {
        final firestoreTxns = await _loadEnhancedTransactions(phone).timeout(
          const Duration(seconds: 8),
        );
        allTransactions = _mergeTransactions(firestoreTxns, allTransactions);
      } on TimeoutException {
        // Keep SMS-only data when Firestore is slow or offline.
      } catch (e) {
        print('Error loading Firestore transactions: $e');
      }

      if (!mounted) return;
      _applyTransactionData(allTransactions);
    } catch (e) {
      print('Error loading expense data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firestoreLoading = false;
        });
      }
    }
  }

  /// Rebuilds expense analytics from a fresh SMS inbox.
  void reloadFromMessages(List<SmsMessage> messages) {
    if (messages.isEmpty) return;
    _loadData(messages: messages, showLoading: false);
  }

  bool get _hasMonthlyChartData =>
      _monthlySummaries.any((s) => s.totalReceived > 0 || s.totalSent > 0);

  double _chartMaxY(double rawMax, {double? target}) {
    final values = <double>[rawMax, if (target != null) target, 1.0];
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    if (!maxVal.isFinite || maxVal <= 0) return 1.0;
    return maxVal * 1.15;
  }

  Widget _safeSection(Widget Function() builder, {Widget? fallback}) {
    try {
      return builder();
    } catch (e, st) {
      debugPrint('Expenses section error: $e\n$st');
      return fallback ??
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'This section could not be displayed.',
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          );
    }
  }

  void _applyTransactionData(List<EnhancedTransaction> allTransactions) {
    final (start, end) = _getDateRange();
    final (prevStart, prevEnd) = _getPreviousDateRange();
    final summaries = LocalAnalytics.monthlySummaries(allTransactions);

    setState(() {
      _allTransactions = allTransactions;
      _monthlySummaries = summaries;
      _spendingSummary = LocalAnalytics.spendingSummary(
        transactions: allTransactions,
        startDate: start,
        endDate: end,
      );
      _previousPeriodSummary = LocalAnalytics.spendingSummary(
        transactions: allTransactions,
        startDate: prevStart,
        endDate: prevEnd,
      );
      _incomeVsExpense = LocalAnalytics.incomeVsExpense(
        transactions: allTransactions,
        startDate: start,
        endDate: end,
      );
      _lowBalanceStats = LocalAnalytics.lowBalanceStats(
        transactions: allTransactions,
      );
      _spendingHabits = LocalAnalytics.spendingHabits(
        transactions: allTransactions,
        startDate: start,
        endDate: end,
      );
      _insights = LocalAnalytics.basicInsights(
        transactions: allTransactions,
        startDate: start,
        endDate: end,
      );
      _loading = false;

      if (summaries.isNotEmpty) {
        final now = DateTime.now();
        final sortedSummaries = List<MonthlyTransactionSummary>.from(summaries)
          ..sort((a, b) => b.month.compareTo(a.month));
        final currentMonthIndex = sortedSummaries.indexWhere(
          (summary) =>
              summary.month.year == now.year &&
              summary.month.month == now.month,
        );
        if (currentMonthIndex >= 0) {
          _selectedMonthIndex = currentMonthIndex;
          _selectedProgressMonthIndex = currentMonthIndex;
        } else {
          _selectedMonthIndex = 0;
          _selectedProgressMonthIndex = 0;
        }
      }
    });
  }

  double get _totalSpentAmount => _allTransactions
      .where((t) => t.isSent)
      .fold<double>(0, (sum, t) => sum + t.totalCost);

  double get _averageSpentAmount {
    final sent = _allTransactions.where((t) => t.isSent).toList();
    if (sent.isEmpty) return 0;
    return _totalSpentAmount / sent.length;
  }

  double get _totalFees => _allTransactions
      .where((t) => t.isSent)
      .fold<double>(0, (sum, t) => sum + t.fee);

  double get _highestSpending {
    final sent = _allTransactions.where((t) => t.isSent);
    if (sent.isEmpty) return 0;
    return sent.map((t) => t.totalCost).reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> _calculateTargetForDate(DateTime referenceDate) {
    if (_monthlySummaries.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => a.month.compareTo(b.month));

    final completedMonths = sortedSummaries
        .where((s) => s.month.isBefore(referenceDate))
        .toList();

    if (completedMonths.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final recentMonths = completedMonths.length <= 3
        ? completedMonths
        : completedMonths.sublist(completedMonths.length - 3);

    final growthRates = <double>[];
    for (int i = 1; i < recentMonths.length; i++) {
      final previous = recentMonths[i - 1].totalSent;
      final current = recentMonths[i].totalSent;
      if (previous > 0) {
        growthRates.add((current - previous) / previous);
      }
    }

    double avgGrowthRate = 0.05;
    if (growthRates.isNotEmpty) {
      avgGrowthRate = growthRates.reduce((a, b) => a + b) / growthRates.length;
      avgGrowthRate += 0.02;
      if (avgGrowthRate < 0.0) avgGrowthRate = 0.0;
    }

    final lastMonthAmount = recentMonths.last.totalSent;
    final target = lastMonthAmount * (1 + avgGrowthRate);

    return {
      'target': target,
      'growthRate': avgGrowthRate,
      'lastMonth': lastMonthAmount,
      'lastMonthDate': recentMonths.last.month,
    };
  }

  Map<String, dynamic> get _nextMonthTarget {
    if (_monthlySummaries.isEmpty) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final descendingSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    if (_selectedMonthIndex < 0 ||
        _selectedMonthIndex >= descendingSummaries.length) {
      return {'target': 0.0, 'growthRate': 0.05, 'lastMonth': 0.0};
    }

    final selectedDate = descendingSummaries[_selectedMonthIndex].month;
    return _calculateTargetForDate(selectedDate);
  }

  Map<String, dynamic> _getMonthProgress(int monthIndex) {
    if (_monthlySummaries.isEmpty) {
      return {
        'currentAmount': 0.0,
        'previousMonthAmount': 0.0,
        'previousProgress': 0.0,
        'previousRemaining': 0.0,
        'selectedMonth': DateTime.now(),
      };
    }

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    final clampedIndex = monthIndex.clamp(0, sortedSummaries.length - 1);
    final selectedMonthData = sortedSummaries[clampedIndex];

    final previousMonthDate = DateTime(
      selectedMonthData.month.year,
      selectedMonthData.month.month - 1,
    );
    final previousMonthData = _monthlySummaries.firstWhere(
      (s) =>
          s.month.year == previousMonthDate.year &&
          s.month.month == previousMonthDate.month,
      orElse: () => MonthlyTransactionSummary(
        month: previousMonthDate,
        totalReceived: 0,
        totalSent: 0,
        transactionCount: 0,
      ),
    );

    final currentAmount = selectedMonthData.totalSent;
    final previousMonthAmount = previousMonthData.totalSent;

    final previousProgress = previousMonthAmount > 0
        ? (currentAmount / previousMonthAmount * 100).clamp(0.0, 200.0)
        : 0.0;
    final previousRemaining = previousMonthAmount - currentAmount;

    final targetMap = _calculateTargetForDate(selectedMonthData.month);
    final targetAmount = targetMap['target'] as double;
    final targetProgress = targetAmount > 0
        ? (currentAmount / targetAmount * 100).clamp(0.0, 200.0)
        : 0.0;
    final targetRemaining = targetAmount - currentAmount;

    return {
      'currentAmount': currentAmount,
      'previousMonthAmount': previousMonthAmount,
      'previousProgress': previousProgress,
      'previousRemaining': previousRemaining,
      'targetAmount': targetAmount,
      'targetProgress': targetProgress,
      'targetRemaining': targetRemaining,
      'selectedMonth': selectedMonthData.month,
      'previousMonth': previousMonthDate,
    };
  }

  List<EnhancedTransaction> _mergeTransactions(
    List<EnhancedTransaction> firestore,
    List<EnhancedTransaction> fromSms,
  ) {
    if (fromSms.isEmpty) return firestore;
    if (firestore.isEmpty) return fromSms;

    final merged = <String, EnhancedTransaction>{
      for (final txn in fromSms) txn.id: txn,
    };
    for (final txn in firestore) {
      merged[txn.id] = txn;
    }
    final list = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<List<EnhancedTransaction>> _loadEnhancedTransactions(String phone) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(phone)
          .collection('transactions')
          .orderBy('date', descending: true)
          .limit(500)
          .get();

      return snap.docs
          .map((doc) => EnhancedTransaction.fromFirestore(doc.data(), doc.id))
          .whereType<EnhancedTransaction>()
          .toList();
    } catch (e) {
      print('Error loading enhanced transactions: $e');
      return [];
    }
  }

  String get _periodLabel {
    switch (_selectedPeriod) {
      case 'today':
        return 'Today';
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      case 'year':
        return 'This Year';
      default:
        return '';
    }
  }

  double get _vsPreviousPercent {
    if (_spendingSummary == null || _previousPeriodSummary == null) return 0;
    final prev = _previousPeriodSummary!.totalSpent;
    if (prev <= 0) return 0;
    return ((_spendingSummary!.totalSpent - prev) / prev) * 100;
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildPage(context);
    } catch (e, st) {
      debugPrint('Expenses page build failed: $e\n$st');
      return ColoredBox(
        color: bgColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: dangerColor, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Expenses could not load',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pull to refresh or switch tabs and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildPage(BuildContext context) {
    if (_loading) {
      return ColoredBox(
        color: bgColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              Text(
                'Loading expenses...',
                style: TextStyle(color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final body = RefreshIndicator(
      color: primaryColor,
      onRefresh: () => _loadData(showLoading: false),
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(
          bottom: widget.embeddedInShell ? 88 : 24,
        ),
        children: [
          if (!widget.embeddedInShell) const SizedBox(height: 8),
          _safeSection(_buildPeriodSelector),
          const SizedBox(height: 12),
          _safeSection(_buildHeroCard),
          const SizedBox(height: 12),
          _safeSection(_buildIncomeVsExpenseCard),
          const SizedBox(height: 12),
          if (_allTransactions.isNotEmpty) ...[
            _safeSection(_buildExpenseAnalyticsSection),
            const SizedBox(height: 12),
          ],
          if (_firestoreLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                color: primaryColor,
                backgroundColor: cardBorder.withValues(alpha: 0.3),
                minHeight: 2,
              ),
            ),
          if (_firestoreLoading) const SizedBox(height: 12),
          if (_chartsReady && _hasMonthlyChartData) ...[
            _safeSection(_buildMonthProgressChart),
            const SizedBox(height: 12),
            _safeSection(_buildIncomeVsSpendingChart),
            const SizedBox(height: 12),
            _safeSection(_buildMonthlyExpensesList),
            const SizedBox(height: 12),
            _safeSection(_buildMonthlySummaryCard),
            const SizedBox(height: 12),
            _safeSection(_buildMetricCards),
            const SizedBox(height: 12),
            _safeSection(_buildNextMonthTargetCard),
            const SizedBox(height: 16),
          ],
          _safeSection(_buildQuickStatsCard),
          const SizedBox(height: 12),
          _safeSection(_buildLowBalanceCard),
          const SizedBox(height: 12),
          _safeSection(_buildInsightsCard),
        ],
      ),
    );

    if (widget.embeddedInShell) {
      return ColoredBox(color: bgColor, child: body);
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: body,
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets? margin}) {
    return AppGlassCard(margin: margin, child: child);
  }

  Widget _buildExpenseAnalyticsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CategoryBreakdownWidget(transactions: _allTransactions),
          const SizedBox(height: 24),
          TopRecipientsWidget(transactions: _allTransactions),
        ],
      ),
    );
  }

  Widget _buildChartLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildIncomeVsSpendingChart() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final targetValue = _nextMonthTarget['target'] as double;
    final maxDataValue = _monthlySummaries.fold<double>(0, (max, summary) {
      final monthMax = summary.totalReceived > summary.totalSent
          ? summary.totalReceived
          : summary.totalSent;
      return monthMax > max ? monthMax : max;
    });
    final maxY = _showTargetLine
        ? _chartMaxY(maxDataValue, target: targetValue)
        : _chartMaxY(maxDataValue);

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Income vs Spending',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() => _showTargetLine = !_showTargetLine);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _showTargetLine
                              ? dangerColor.withValues(alpha: 0.15)
                              : textSecondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showTargetLine
                                ? dangerColor.withValues(alpha: 0.3)
                                : textSecondary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showTargetLine
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: _showTargetLine
                                  ? dangerColor
                                  : textSecondary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Budget',
                              style: TextStyle(
                                color: _showTargetLine
                                    ? dangerColor
                                    : textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: AppDecorations.iconBadge(
                        _c,
                        context,
                        [primaryColor, primaryDark],
                      ),
                      child: Text(
                        '${_monthlySummaries.length} mo',
                        style: TextStyle(
                          color: AppDecorations.iconBadgeForeground(
                            _c,
                            context,
                            [primaryColor, primaryDark],
                          ),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildChartLegendDot(successColor, 'Income'),
                const SizedBox(width: 16),
                _buildChartLegendDot(dangerColor, 'Spending'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: textSecondary.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value >= _monthlySummaries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('MMM').format(
                                _monthlySummaries[value.toInt()].month,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 32,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              value >= 1000000
                                  ? '${(value / 1000000).toStringAsFixed(1)}M'
                                  : '${(value / 1000).toStringAsFixed(0)}K',
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        reservedSize: 50,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: maxY,
                  extraLinesData: ExtraLinesData(
                    horizontalLines: _showTargetLine && targetValue > 0
                        ? [
                            HorizontalLine(
                              y: targetValue,
                              color: dangerColor,
                              strokeWidth: 2,
                              dashArray: [8, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  bottom: 4,
                                ),
                                style: TextStyle(
                                  color: dangerColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                labelResolver: (line) =>
                                    'Budget: ${_currencyFormat.format(line.y)}',
                              ),
                            ),
                          ]
                        : [],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _monthlySummaries.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.totalReceived,
                        );
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.35,
                      preventCurveOverShooting: true,
                      color: successColor,
                      barWidth: 2.4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: _isDark ? Colors.white : cardColor,
                            strokeWidth: 2,
                            strokeColor: successColor,
                          );
                        },
                      ),
                    ),
                    LineChartBarData(
                      spots: _monthlySummaries.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          entry.value.totalSent,
                        );
                      }).toList(),
                      isCurved: true,
                      curveSmoothness: 0.35,
                      preventCurveOverShooting: true,
                      color: dangerColor,
                      barWidth: 2.4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: _isDark ? Colors.white : cardColor,
                            strokeWidth: 2,
                            strokeColor: dangerColor,
                          );
                        },
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: cardColor,
                      tooltipRoundedRadius: 12,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      getTooltipItems: (touchedSpots) {
                        if (touchedSpots.isEmpty) return [];
                        final monthData =
                            _monthlySummaries[touchedSpots.first.x.toInt()];
                        return [
                          LineTooltipItem(
                            '${DateFormat('MMM yyyy').format(monthData.month)}\n',
                            TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    'Income: ${_currencyFormat.format(monthData.totalReceived)}\n',
                                style: TextStyle(
                                  color: successColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              TextSpan(
                                text:
                                    'Spending: ${_currencyFormat.format(monthData.totalSent)}',
                                style: TextStyle(
                                  color: dangerColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ];
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthProgressChart() {
    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((a, b) => b.month.compareTo(a.month));

    if (sortedSummaries.isEmpty) return const SizedBox.shrink();

    final progress = _getMonthProgress(_selectedProgressMonthIndex);
    final currentAmount = progress['currentAmount'] as double;
    final previousMonthAmount = progress['previousMonthAmount'] as double;
    final targetAmount = progress['targetAmount'] as double;
    final selectedMonth = progress['selectedMonth'] as DateTime;
    final previousMonth = progress['previousMonth'] as DateTime?;
    final previousProgress = progress['previousProgress'] as double;
    final previousRemaining = progress['previousRemaining'] as double;
    final targetProgress = progress['targetProgress'] as double;
    final targetRemaining = progress['targetRemaining'] as double;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: AppDecorations.sectionIcon(
                        _c,
                        context,
                        dangerColor,
                      ),
                      child: Icon(
                        Icons.trending_down_rounded,
                        color: AppDecorations.sectionIconForeground(
                          _c,
                          context,
                          dangerColor,
                        ),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Monthly Spending Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: AppDecorations.tintedChip(context, dangerColor),
                  child: DropdownButton<int>(
                    value: _selectedProgressMonthIndex.clamp(
                      0,
                      sortedSummaries.length - 1,
                    ),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: dangerColor,
                      size: 18,
                    ),
                    items: sortedSummaries.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(
                          DateFormat('MMM yy').format(entry.value.month),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dangerColor,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedProgressMonthIndex = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: currentAmount),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedAmount, child) {
                      return Text(
                        _currencyFormat.format(animatedAmount),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                          letterSpacing: -0.5,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Spent in ${DateFormat('MMMM yyyy').format(selectedMonth)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildProgressBar(
              label: previousMonth != null
                  ? 'vs ${DateFormat('MMM').format(previousMonth)}'
                  : 'vs Previous Month',
              current: currentAmount,
              goal: previousMonthAmount,
              progress: previousProgress,
              remaining: previousRemaining,
              color: primaryColor,
              icon: Icons.calendar_month_rounded,
              underBudgetIsGood: true,
            ),
            const SizedBox(height: 16),
            _buildProgressBar(
              label: 'vs Budget',
              current: currentAmount,
              goal: targetAmount,
              progress: targetProgress,
              remaining: targetRemaining,
              color: dangerColor,
              icon: Icons.flag_rounded,
              underBudgetIsGood: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required String label,
    required double current,
    required double goal,
    required double progress,
    required double remaining,
    required Color color,
    required IconData icon,
    bool underBudgetIsGood = false,
  }) {
    final isUnderBudget = remaining >= 0;
    final isGood = underBudgetIsGood ? isUnderBudget : !isUnderBudget;
    final displayProgress = progress.clamp(0.0, 100.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isGood
                    ? successColor.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${displayProgress.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isGood ? successColor : color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: cardBorder.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: (displayProgress / 100).clamp(0.0, 1.0),
              child: Container(
                height: 10,
                decoration: AppDecorations.progressFill(context, color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Goal: ${_currencyFormat.format(goal)}',
              style: TextStyle(
                fontSize: 11,
                color: textSecondary.withValues(alpha: 0.7),
              ),
            ),
            Text(
              underBudgetIsGood
                  ? (isUnderBudget
                      ? '${_currencyFormat.format(remaining)} under budget'
                      : '${_currencyFormat.format(-remaining)} over budget')
                  : (isGood
                      ? '✓ Exceeded by ${_currencyFormat.format(-remaining)}'
                      : '${_currencyFormat.format(remaining)} left'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isGood ? successColor : color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonthlyExpensesList() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((b, a) => a.month.compareTo(b.month));

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: AppDecorations.sectionIcon(
                    _c,
                    context,
                    dangerColor,
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppDecorations.sectionIconForeground(
                      _c,
                      context,
                      dangerColor,
                    ),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Monthly Expenses',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedSummaries.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: cardBorder.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, index) {
              final summary = sortedSummaries[index];
              final isCurrentMonth =
                  summary.month.year == DateTime.now().year &&
                  summary.month.month == DateTime.now().month;

              return Container(
                decoration: isCurrentMonth
                    ? BoxDecoration(
                        color: _isDark
                            ? dangerColor.withValues(alpha: 0.08)
                            : null,
                        gradient: _isDark
                            ? null
                            : LinearGradient(
                                colors: [
                                  dangerColor.withValues(alpha: 0.08),
                                  dangerColor.withValues(alpha: 0.02),
                                ],
                              ),
                      )
                    : null,
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: isCurrentMonth
                        ? AppDecorations.iconBadge(
                            _c,
                            context,
                            [dangerColor, primaryDark],
                          )
                        : BoxDecoration(
                            color: textSecondary.withValues(
                              alpha: _isDark ? 0.12 : 0.18,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cardBorder.withValues(alpha: 0.35),
                            ),
                          ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('MMM').format(summary.month),
                          style: TextStyle(
                            color: isCurrentMonth
                                ? Colors.white
                                : textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('yy').format(summary.month),
                          style: TextStyle(
                            color: isCurrentMonth
                                ? Colors.white.withValues(alpha: 0.9)
                                : textSecondary.withValues(alpha: 0.7),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    DateFormat('MMM yyyy').format(summary.month),
                    style: TextStyle(
                      fontWeight: isCurrentMonth
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontSize: 13,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${summary.transactionCount} payment${summary.transactionCount != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: isCurrentMonth ? dangerColor : textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  trailing: Text(
                    _currencyFormat.format(summary.totalSent),
                    style: TextStyle(
                      color: isCurrentMonth ? dangerColor : textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummaryCard() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();

    final sortedSummaries = List<MonthlyTransactionSummary>.from(
      _monthlySummaries,
    )..sort((b, a) => a.month.compareTo(b.month));

    final selectedSummary = sortedSummaries[_selectedMonthIndex];
    final previousIndex = _selectedMonthIndex + 1;
    final previousSummary = previousIndex < sortedSummaries.length
        ? sortedSummaries[previousIndex]
        : null;

    final percentageChange = previousSummary != null &&
            previousSummary.totalSent > 0
        ? ((selectedSummary.totalSent - previousSummary.totalSent) /
              previousSummary.totalSent *
              100)
        : 0.0;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: AppDecorations.dropdownChip(_c, context),
                  child: DropdownButton<int>(
                    value: _selectedMonthIndex,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: dangerColor,
                      size: 18,
                    ),
                    items: sortedSummaries.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(
                          DateFormat('MMM yy').format(entry.value.month),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dangerColor,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMonthIndex = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: selectedSummary.totalSent),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, animatedAmount, child) {
                return Text(
                  _currencyFormat.format(animatedAmount),
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              '${selectedSummary.transactionCount} payment${selectedSummary.transactionCount != 1 ? 's' : ''} this month',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (previousSummary != null && previousSummary.totalSent > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: AppDecorations.tintedChip(
                  context,
                  percentageChange <= 0 ? successColor : dangerColor,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: percentageChange <= 0
                            ? successColor.withValues(alpha: 0.2)
                            : dangerColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        percentageChange <= 0
                            ? Icons.trending_down
                            : Icons.trending_up,
                        color: percentageChange <= 0
                            ? successColor
                            : dangerColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${percentageChange >= 0 ? '+' : ''}${percentageChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: percentageChange <= 0
                            ? successColor
                            : dangerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'vs ${DateFormat('MMM').format(previousSummary.month)}',
                      style: TextStyle(color: textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCards() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final thisMonthTransactions = _allTransactions
        .where((t) => t.isSent)
        .where((t) => DateTime(t.date.year, t.date.month) == thisMonth);

    final thisMonthTotal = thisMonthTransactions.fold<double>(
      0,
      (sum, t) => sum + t.totalCost,
    );
    final thisMonthAvg = thisMonthTransactions.isEmpty
        ? 0.0
        : thisMonthTotal / thisMonthTransactions.length;

    const metricGradients = [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFFEC4899), Color(0xFFF472B6)],
      [Color(0xFF14B8A6), Color(0xFF5EEAD4)],
      [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Avg Payment',
                  _currencyFormat.format(_averageSpentAmount),
                  Icons.analytics_outlined,
                  metricGradients[0],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'This Month',
                  _currencyFormat.format(thisMonthAvg),
                  Icons.calendar_today_outlined,
                  metricGradients[1],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Highest',
                  _currencyFormat.format(_highestSpending),
                  Icons.arrow_upward_rounded,
                  metricGradients[2],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Total Fees',
                  _currencyFormat.format(_totalFees),
                  Icons.money_off_outlined,
                  metricGradients[3],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    List<Color> gradientColors,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.metricSurface(_c, context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AppDecorations.wrapBlur(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: AppDecorations.iconBadge(
                  _c,
                  context,
                  gradientColors,
                ),
                child: Icon(
                  icon,
                  color: AppDecorations.iconBadgeForeground(
                    _c,
                    context,
                    gradientColors,
                  ),
                  size: 16,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextMonthTargetCard() {
    final targetData = _nextMonthTarget;
    final target = targetData['target'] as double;
    final growthRate = targetData['growthRate'] as double;
    final lastMonth = targetData['lastMonth'] as double;
    final lastMonthDate = targetData['lastMonthDate'] as DateTime?;

    if (target <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.accentHero(
        _c,
        context,
        gradientColors: const [
          Color(0xFFB91C1C),
          Color(0xFFDC2626),
          Color(0xFFF87171),
        ],
        borderTint: dangerColor,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.flag_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next Month Budget',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Based on spending trend',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: target),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, animatedTarget, child) {
                  return Text(
                    _currencyFormat.format(animatedTarget),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Growth',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+${(growthRate * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lastMonthDate != null
                                  ? DateFormat('MMM yy').format(lastMonthDate)
                                  : 'Last',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _currencyFormat.format(lastMonth),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final periods = [
      (value: 'today', label: 'Today'),
      (value: 'week', label: 'Week'),
      (value: 'month', label: 'Month'),
      (value: 'year', label: 'Year'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.credit_card_rounded, color: primaryColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Expenses',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          ...periods.map((p) {
            final isSelected = _selectedPeriod == p.value;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () {
                  if (_selectedPeriod == p.value) return;
                  setState(() => _selectedPeriod = p.value);
                  _loadData();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor
                        : cardColor.withValues(alpha: _isDark ? 0.6 : 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : cardBorder.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    p.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final totalSpent = _spendingSummary?.totalSpent ?? 0;
    final txCount = _spendingSummary?.sentTransactionCount ?? 0;
    final vsPrev = _vsPreviousPercent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.hero(
        _c,
        context,
        gradientColors: [
          dangerColor,
          primaryDark,
          const Color(0xFF8B3A3A),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (!_isDark)
              Positioned(
                top: -40,
                right: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.trending_down_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Total Spent \u00b7 $_periodLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: totalSpent),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, animated, child) {
                      return Text(
                        _currencyFormat.format(animated),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          height: 1.0,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$txCount transactions',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (totalSpent > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                vsPrev >= 0
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                color: vsPrev >= 0
                                    ? const Color(0xFFFFB088)
                                    : const Color(0xFF5EEAD4),
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${vsPrev >= 0 ? '+' : ''}${vsPrev.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: vsPrev >= 0
                                      ? const Color(0xFFFFB088)
                                      : const Color(0xFF5EEAD4),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeVsExpenseCard() {
    final income = _incomeVsExpense?.totalIncome ?? 0;
    final expense = _incomeVsExpense?.totalExpenses ?? 0;
    final total = income + expense;
    final incomeRatio = total > 0 ? income / total : 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: _isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: successColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.compare_arrows_rounded,
                    color: successColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Income vs Expense',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: cardBorder.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: incomeRatio,
                      child: Container(
                        decoration: BoxDecoration(
                          color: successColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 1 - incomeRatio,
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: dangerColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildLegendItem(successColor, 'Income', _currencyFormat.format(income)),
                const Spacer(),
                _buildLegendItem(dangerColor, 'Expense', _currencyFormat.format(expense)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Savings: ',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _currencyFormat.format(income - expense),
                  style: TextStyle(
                    color: income >= expense ? successColor : dangerColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          amount,
          style: TextStyle(
            color: textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatsCard() {
    final habits = _spendingHabits;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: _isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.insights_rounded,
                    color: accentPurple,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Spending Habits',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (habits != null) ...[
              _buildStatRow(
                Icons.shopping_bag_rounded,
                'Most Common Category',
                habits.mostCommonCategory,
                accentPurple,
              ),
              const SizedBox(height: 10),
              _buildStatRow(
                Icons.person_rounded,
                'Most Common Recipient',
                habits.mostCommonRecipient,
                primaryColor,
              ),
              const SizedBox(height: 10),
              _buildStatRow(
                Icons.trending_up_rounded,
                'Daily Avg Spend',
                habits.formattedAverageDailySpend,
                accentPurple,
              ),
              const SizedBox(height: 10),
              _buildStatRow(
                Icons.calendar_month_rounded,
                'Weekly Avg Spend',
                habits.formattedAverageWeeklySpend,
                primaryColor,
              ),
              const SizedBox(height: 10),
              _buildStatRow(
                Icons.pie_chart_rounded,
                'Monthly Avg Spend',
                habits.formattedAverageMonthlySpend,
                accentPurple,
              ),
              if (habits.pattern.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildStatRow(
                  Icons.insights_rounded,
                  'Pattern',
                  habits.pattern,
                  primaryColor,
                ),
              ],
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'No spending habit data available',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
      IconData icon, String label, String value, Color iconColor) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildLowBalanceCard() {
    final lowBal = _lowBalanceStats;
    final periods = lowBal?.periods ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: _isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: dangerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: dangerColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Low Balance Alerts',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (lowBal != null && lowBal.timesBelow > 1)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: dangerColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${lowBal.timesBelow}',
                      style: TextStyle(
                        color: dangerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (lowBal == null || periods.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: successColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No low balance periods',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              ...periods.take(3).map(
                    (period) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: dangerColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.trending_down_rounded,
                                color: dangerColor,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  period.formattedDateRange,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${period.daysBelow} days below threshold',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: dangerColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              _currencyFormat.format(period.lowestBalance),
                              style: TextStyle(
                                color: dangerColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (periods.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: Text(
                      '+${periods.length - 3} more',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Threshold',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _currencyFormat.format(lowBal.threshold),
                    style: TextStyle(
                      color: dangerColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (lowBal.insight.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: textSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lowBal.insight,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: _isDark ? 0.6 : 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline_rounded,
                    color: primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Insights',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_insights.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No insights available yet',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              ..._insights.take(5).map(
                    (insight) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _insightIconColor(insight.type)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _insightIcon(insight.type),
                              color: _insightIconColor(insight.type),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  insight.description,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (insight.data.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      insight.data,
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  IconData _insightIcon(String type) {
    switch (type) {
      case 'spending_habit':
        return Icons.trending_up_rounded;
      case 'recommendation':
        return Icons.savings_rounded;
      case 'alert':
        return Icons.warning_rounded;
      case 'pattern':
        return Icons.repeat_rounded;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }

  Color _insightIconColor(String type) {
    switch (type) {
      case 'spending_habit':
        return dangerColor;
      case 'recommendation':
        return successColor;
      case 'alert':
        return Colors.orange;
      case 'pattern':
        return accentPurple;
      default:
        return primaryColor;
    }
  }
}
