import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/app_models.dart';
import 'services/database_service.dart';
import 'services/export_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await DatabaseService.instance.database;
  runApp(const DebtBookApp());
}

// ================= مدير الإعدادات العامة =================
class AppSettingsNotifier extends ChangeNotifier {
  bool isDarkMode = false;
  String currencySymbol = 'ل.ي';
  String dateFormatPattern = 'yyyy/MM/dd';
  bool useThousandSeparator = true;
  bool notificationsEnabled = true;
  bool autoBackupEnabled = false;
  String appPin = '';

  String formatNumber(double value) {
    if (useThousandSeparator) {
      return intl.NumberFormat('#,##0.##').format(value);
    }
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  String formatDate(DateTime date, {bool includeTime = false}) {
    final pattern = includeTime ? '$dateFormatPattern - hh:mm a' : dateFormatPattern;
    return intl.DateFormat(pattern).format(date);
  }

  void notify() => notifyListeners();
}

final AppSettingsNotifier appSettings = AppSettingsNotifier();

class DebtBookApp extends StatefulWidget {
  const DebtBookApp({super.key});

  @override
  State<DebtBookApp> createState() => _DebtBookAppState();
}

class _DebtBookAppState extends State<DebtBookApp> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    appSettings.addListener(() => setState(() {}));
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    appSettings.isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    appSettings.currencySymbol = prefs.getString('currency_symbol') ?? 'ل.ي';
    appSettings.dateFormatPattern = prefs.getString('date_format') ?? 'yyyy/MM/dd';
    appSettings.useThousandSeparator = prefs.getBool('thousand_sep') ?? true;
    appSettings.notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    appSettings.autoBackupEnabled = prefs.getBool('auto_backup') ?? false;
    appSettings.appPin = prefs.getString('app_pin') ?? '';
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دفتر الديون العالمي برو ماكس',
      themeMode: appSettings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF14B8A6),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF14B8A6),
          primary: const Color(0xFF14B8A6),
          secondary: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: appSettings.appPin.isNotEmpty ? const PinLockScreen() : const MainNavigation(),
    );
  }
}

// ================= شاشة القفل الأمني PIN =================
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  String _error = '';

  void _verify() {
    if (_pinController.text == appSettings.appPin) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigation()));
    } else {
      setState(() => _error = 'رمز الدخول غير صحيح، حاول مرة أخرى');
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F766E),
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 60, color: Color(0xFF0F766E)),
                const SizedBox(height: 16),
                const Text('دفتر الديون محمي برمز PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '••••',
                    errorText: _error.isEmpty ? null : _error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                    onPressed: _verify,
                    child: const Text('فتح الدفتر', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= 1. الملاحة السفلية الرئيسية =================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  List<DebtItem> _debts = [];
  List<PersonModel> _persons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    final debts = await DatabaseService.instance.getAllDebts();
    final persons = await DatabaseService.instance.getAllPersons();
    setState(() {
      _debts = debts;
      _persons = persons;
      _isLoading = false;
    });

    if (appSettings.autoBackupEnabled && debts.isNotEmpty) {
      await ExportService.exportJsonToFile(askLocation: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0F766E))));
    }

    final pages = [
      HomePage(debts: _debts, persons: _persons, onRefresh: _refreshAllData),
      PersonsDirectoryPage(debts: _debts, persons: _persons, onRefresh: _refreshAllData),
      AnalyticsPage(debts: _debts),
      SettingsPage(debts: _debts, onRefresh: _refreshAllData),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: 'الدفتر'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الأشخاص'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'التحليلات'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ================= 2. الصفحة الرئيسية: الدفتر المالي المتكامل =================
class HomePage extends StatefulWidget {
  final List<DebtItem> debts;
  final List<PersonModel> persons;
  final Future<void> Function() onRefresh;

  const HomePage({super.key, required this.debts, required this.persons, required this.onRefresh});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String _typeFilter = 'all'; // all, for_me, on_me
  String _statusFilter = 'all'; // all, unpaid, partial, paid, overdue
  String _sortBy = 'newest'; // newest, oldest, amount_desc, amount_asc

  double get totalRemainingForMe => widget.debts.where((i) => i.isForMe).fold(0.0, (s, i) => s + i.remainingAmount);
  double get totalRemainingOnMe => widget.debts.where((i) => !i.isForMe).fold(0.0, (s, i) => s + i.remainingAmount);
  int get overdueCount => widget.debts.where((i) => i.isOverdue).length;

  List<DebtItem> get processedDebts {
    final q = _searchQuery.trim().toLowerCase();
    var list = widget.debts.where((item) {
      final matchesSearch = q.isEmpty ||
          item.personName.toLowerCase().contains(q) ||
          item.phone.contains(q) ||
          item.note.toLowerCase().contains(q) ||
          item.amount.toString().contains(q) ||
          item.remainingAmount.toString().contains(q) ||
          appSettings.formatDate(item.date).contains(q);

      if (!matchesSearch) return false;
      if (_typeFilter == 'for_me' && !item.isForMe) return false;
      if (_typeFilter == 'on_me' && item.isForMe) return false;

      if (_statusFilter == 'paid' && !item.isFullyPaid) return false;
      if (_statusFilter == 'unpaid' && item.paidAmount > 0) return false;
      if (_statusFilter == 'partial' && !item.isPartiallyPaid) return false;
      if (_statusFilter == 'overdue' && !item.isOverdue) return false;

      return true;
    }).toList();

    list.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          return a.date.compareTo(b.date);
        case 'amount_desc':
          return b.remainingAmount.compareTo(a.remainingAmount);
        case 'amount_asc':
          return a.remainingAmount.compareTo(b.remainingAmount);
        default:
          return b.date.compareTo(a.date);
      }
    });
    return list;
  }

  void _openAddEdit({DebtItem? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddEditDebtPage(existingItem: existing, existingPersons: widget.persons)),
    );
    if (saved == true) {
      await widget.onRefresh();
    }
  }

  void _deleteWithUndo(DebtItem item) async {
    await DatabaseService.instance.deleteDebt(item);
    await widget.onRefresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حذف معاملة ${item.personName}'),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: Colors.amberAccent,
          onPressed: () async {
            await DatabaseService.instance.restoreDeletedDebt(item);
            await widget.onRefresh();
          },
        ),
      ),
    );
  }

  void _showReportsBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('التقارير المالية والتصدير الاحترافي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('تقرير PDF شامل (المعروض حالياً)'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.generateAndSharePdf(
                  debts: processedDebts,
                  currency: appSettings.currencySymbol,
                  title: 'التقرير المالي الشامل',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('تصدير البيانات إلى ملف Excel'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.exportToExcel(processedDebts, appSettings.currencySymbol, 'تقرير_الديون');
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward, color: Colors.teal),
              title: const Text('تقرير الديون المستحقة لي فقط (PDF)'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.generateAndSharePdf(
                  debts: widget.debts.where((d) => d.isForMe).toList(),
                  currency: appSettings.currencySymbol,
                  title: 'تقرير الديون المستحقة لي',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.orange),
              title: const Text('تقرير الديون التي عليّ فقط (PDF)'),
              onTap: () {
                Navigator.pop(ctx);
                ExportService.generateAndSharePdf(
                  debts: widget.debts.where((d) => !d.isForMe).toList(),
                  currency: appSettings.currencySymbol,
                  title: 'تقرير الديون التي عليّ',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range, color: Colors.blue),
              title: const Text('تقارير زمنية (يومي / أسبوعي / شهري / سنوي)'),
              onTap: () {
                Navigator.pop(ctx);
                _showPeriodReportDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPeriodReportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر الفترة الزمنية للتقرير'),
        children: [
          _periodOption(ctx, 'تقرير اليوم', 1),
          _periodOption(ctx, 'التقرير الأسبوعي (آخر 7 أيام)', 7),
          _periodOption(ctx, 'التقرير الشهري (آخر 30 يوماً)', 30),
          _periodOption(ctx, 'التقرير السنوي (آخر 365 يوماً)', 365),
        ],
      ),
    );
  }

  Widget _periodOption(BuildContext ctx, String label, int days) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(ctx);
        final cutoff = DateTime.now().subtract(Duration(days: days));
        final filtered = widget.debts.where((d) => d.date.isAfter(cutoff)).toList();
        ExportService.generateAndSharePdf(
          debts: filtered,
          currency: appSettings.currencySymbol,
          title: label,
        );
      },
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netBalance = totalRemainingForMe - totalRemainingOnMe;
    final isDark = appSettings.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر الديون العالمي برو ماكس', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: const Color(0xFF0F766E),
        actions: [
          if (overdueCount > 0)
            IconButton(
              icon: Badge(label: Text('$overdueCount'), child: const Icon(Icons.notifications_active, color: Colors.amberAccent)),
              tooltip: 'ديون متأخرة السداد',
              onPressed: () => setState(() => _statusFilter = 'overdue'),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
            tooltip: 'التقارير والتصدير',
            onPressed: _showReportsBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'سجل العمليات',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogsPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          // لوحة الملخص المالي
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF14B8A6)]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard('المتبقي لك', totalRemainingForMe, Colors.greenAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summaryCard('المتبقي عليك', totalRemainingOnMe, Colors.redAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الصافي المتبقي:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(
                        '${appSettings.formatNumber(netBalance)} ${appSettings.currencySymbol}',
                        style: TextStyle(
                          color: netBalance >= 0 ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // البحث والفرز والفلاتر
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'بحث بالاسم، الهاتف، المبلغ، التاريخ...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF0F766E)),
                          filled: true,
                          fillColor: isDark ? Colors.grey.shade800 : Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800 : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.sort_rounded, color: Color(0xFF0F766E)),
                      ),
                      tooltip: 'ترتيب المعاملات',
                      onSelected: (v) => setState(() => _sortBy = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'newest', child: Text('الأحدث إلى الأقدم')),
                        PopupMenuItem(value: 'oldest', child: Text('الأقدم إلى الأحدث')),
                        PopupMenuItem(value: 'amount_desc', child: Text('المبلغ: من الأكبر للأصغر')),
                        PopupMenuItem(value: 'amount_asc', child: Text('المبلغ: من الأصغر للأكبر')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('الكل', _typeFilter == 'all', () => setState(() => _typeFilter = 'all')),
                      _chip('دين لك', _typeFilter == 'for_me', () => setState(() => _typeFilter = 'for_me')),
                      _chip('دين عليك', _typeFilter == 'on_me', () => setState(() => _typeFilter = 'on_me')),
                      const SizedBox(width: 8),
                      _chip('كل الحالات', _statusFilter == 'all', () => setState(() => _statusFilter = 'all')),
                      _chip('غير مسدد', _statusFilter == 'unpaid', () => setState(() => _statusFilter = 'unpaid')),
                      _chip('مسدد جزئياً', _statusFilter == 'partial', () => setState(() => _statusFilter = 'partial')),
                      _chip('مسدد بالكامل', _statusFilter == 'paid', () => setState(() => _statusFilter = 'paid')),
                      _chip('متأخر', _statusFilter == 'overdue', () => setState(() => _statusFilter = 'overdue')),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // قائمة المعاملات
          Expanded(
            child: processedDebts.isEmpty
                ? const Center(child: Text('لا توجد معاملات مطابقة حالياً', style: TextStyle(color: Colors.grey, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: processedDebts.length,
                    itemBuilder: (context, index) {
                      final item = processedDebts[index];
                      return _buildDebtCard(item, isDark);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEdit(),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة معاملة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _summaryCard(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '${appSettings.formatNumber(amount)} ${appSettings.currencySymbol}',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        selectedColor: const Color(0xFF0F766E),
        labelStyle: TextStyle(color: selected ? Colors.white : null),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildDebtCard(DebtItem item, bool isDark) {
    final progress = item.amount > 0 ? (item.paidAmount / item.amount).clamp(0.0, 1.0) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: item.isOverdue ? const BorderSide(color: Colors.orange, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DebtPaymentsDetailPage(debt: item, onRefresh: widget.onRefresh)),
          );
          await widget.onRefresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: item.isForMe ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
                    child: Icon(
                      item.isForMe ? Icons.arrow_downward : Icons.arrow_upward,
                      color: item.isForMe ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(item.personName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            _statusBadge(item),
                          ],
                        ),
                        if (item.note.isNotEmpty)
                          Text(item.note, style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'pay') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DebtPaymentsDetailPage(debt: item, onRefresh: widget.onRefresh)),
                        ).then((_) => widget.onRefresh());
                      } else if (val == 'edit') {
                        _openAddEdit(existing: item);
                      } else if (val == 'delete') {
                        _deleteWithUndo(item);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'pay', child: Text('إدارة الدفعات والسداد')),
                      PopupMenuItem(value: 'edit', child: Text('تعديل المعاملة')),
                      PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الأصلي: ${appSettings.formatNumber(item.amount)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('المدفوع: ${appSettings.formatNumber(item.paidAmount)}', style: const TextStyle(fontSize: 12, color: Colors.teal)),
                  Text(
                    'المتبقي: ${appSettings.formatNumber(item.remainingAmount)} ${appSettings.currencySymbol}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: item.isForMe ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: Colors.grey.withOpacity(0.2),
                color: item.isFullyPaid ? Colors.green : const Color(0xFF14B8A6),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(appSettings.formatDate(item.date, includeTime: true), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (item.dueDate != null)
                    Text(
                      'الاستحقاق: ${appSettings.formatDate(item.dueDate!)}',
                      style: TextStyle(fontSize: 11, color: item.isOverdue ? Colors.orange.shade800 : Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(DebtItem item) {
    if (item.isFullyPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: const Text('مسدد', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    if (item.isPartiallyPaid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: const Text('جزئي', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    if (item.isOverdue) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
        child: const Text('متأخر', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    return const SizedBox.shrink();
  }
}

// ================= 3. صفحة إدارة الدفعات الجزئية والتسديد الكامل =================
class DebtPaymentsDetailPage extends StatefulWidget {
  final DebtItem debt;
  final Future<void> Function() onRefresh;

  const DebtPaymentsDetailPage({super.key, required this.debt, required this.onRefresh});

  @override
  State<DebtPaymentsDetailPage> createState() => _DebtPaymentsDetailPageState();
}

class _DebtPaymentsDetailPageState extends State<DebtPaymentsDetailPage> {
  late DebtItem currentDebt;

  @override
  void initState() {
    super.initState();
    currentDebt = widget.debt;
  }

  Future<void> _reloadDebt() async {
    final all = await DatabaseService.instance.getAllDebts();
    final updated = all.firstWhere((d) => d.id == currentDebt.id, orElse: () => currentDebt);
    setState(() => currentDebt = updated);
    await widget.onRefresh();
  }

  void _showPaymentDialog({PaymentItem? existingPayment}) {
    final amountCtrl = TextEditingController(
      text: existingPayment != null ? existingPayment.amount.toString() : currentDebt.remainingAmount.toString(),
    );
    final noteCtrl = TextEditingController(text: existingPayment?.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingPayment == null ? 'تسجيل دفعة مالية' : 'تعديل الدفعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'مبلغ الدفعة (${appSettings.currencySymbol})',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: 'ملاحظة الدفعة (اختياري)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
            onPressed: () async {
              final val = double.tryParse(amountCtrl.text) ?? 0;
              if (val <= 0) return;

              final payment = PaymentItem(
                id: existingPayment?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                debtId: currentDebt.id,
                amount: val,
                date: existingPayment?.date ?? DateTime.now(),
                note: noteCtrl.text.trim(),
              );
              await DatabaseService.instance.upsertPayment(payment, currentDebt.personName, isNew: existingPayment == null);
              if (mounted) Navigator.pop(ctx);
              await _reloadDebt();
            },
            child: const Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
  }

  Future<void> _settleFullRemaining() async {
    if (currentDebt.remainingAmount <= 0) return;
    final payment = PaymentItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      debtId: currentDebt.id,
      amount: currentDebt.remainingAmount,
      date: DateTime.now(),
      note: 'تسديد كامل المبلغ المتبقي',
    );
    await DatabaseService.instance.upsertPayment(payment, currentDebt.personName, isNew: true);
    await _reloadDebt();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم تسديد الدين بالكامل بنجاح')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('دفعات: ${currentDebt.personName}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('المبلغ الأصلي', currentDebt.amount, Colors.blueGrey),
                        _stat('المدفوع', currentDebt.paidAmount, Colors.green),
                        _stat('المتبقي', currentDebt.remainingAmount, Colors.red),
                      ],
                    ),
                    if (!currentDebt.isFullyPaid) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), foregroundColor: Colors.white),
                              onPressed: () => _showPaymentDialog(),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('تسجيل دفعة جزئية'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              onPressed: _settleFullRemaining,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('تسديد بالكامل'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('سجل الدفعات المسجلة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: currentDebt.payments.isEmpty
                  ? const Center(child: Text('لا توجد دفعات مسجلة لهذا الدين حتى الآن', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: currentDebt.payments.length,
                      itemBuilder: (ctx, i) {
                        final pay = currentDebt.payments[i];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.receipt, color: Colors.white)),
                            title: Text('${appSettings.formatNumber(pay.amount)} ${appSettings.currencySymbol}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${appSettings.formatDate(pay.date, includeTime: true)}\n${pay.note}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _showPaymentDialog(existingPayment: pay),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    await DatabaseService.instance.deletePayment(pay, currentDebt.personName);
                                    await _reloadDebt();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double val, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text('${appSettings.formatNumber(val)} ${appSettings.currencySymbol}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
      ],
    );
  }
}

// ================= 4. صفحة إضافة / تعديل معاملة مع الإكمال التلقائي والتذكيرات =================
class AddEditDebtPage extends StatefulWidget {
  final DebtItem? existingItem;
  final List<PersonModel> existingPersons;

  const AddEditDebtPage({super.key, this.existingItem, required this.existingPersons});

  @override
  State<AddEditDebtPage> createState() => _AddEditDebtPageState();
}

class _AddEditDebtPageState extends State<AddEditDebtPage> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  late bool _isForMe;
  DateTime? _dueDate;
  DateTime? _reminderDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingItem?.personName ?? '');
    _phoneController = TextEditingController(text: widget.existingItem?.phone ?? '');
    _amountController = TextEditingController(text: widget.existingItem?.amount.toString() ?? '');
    _noteController = TextEditingController(text: widget.existingItem?.note ?? '');
    _isForMe = widget.existingItem?.isForMe ?? true;
    _dueDate = widget.existingItem?.dueDate;
    _reminderDate = widget.existingItem?.reminderDate;
  }

  Future<void> _pickDate(bool isDue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    if (!isDue && mounted) {
      final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
      setState(() {
        _reminderDate = DateTime(picked.year, picked.month, picked.day, time?.hour ?? 9, time?.minute ?? 0);
      });
    } else {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;

    if (name.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال الاسم والمبلغ بشكل صحيح')));
      return;
    }

    final id = widget.existingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final item = DebtItem(
      id: id,
      personName: name,
      phone: _phoneController.text.trim(),
      amount: amount,
      isForMe: _isForMe,
      note: _noteController.text.trim(),
      date: widget.existingItem?.date ?? DateTime.now(),
      dueDate: _dueDate,
      reminderDate: _reminderDate,
      payments: widget.existingItem?.payments ?? [],
    );

    await DatabaseService.instance.insertOrUpdateDebt(item, isNew: widget.existingItem == null);

    if (appSettings.notificationsEnabled && _reminderDate != null) {
      await NotificationService.instance.scheduleDebtReminder(
        id: id.hashCode,
        title: 'تذكير بموعد سداد دين: $name',
        body: 'المبلغ المتبقي: ${appSettings.formatNumber(item.remainingAmount)} ${appSettings.currencySymbol}',
        scheduledDate: _reminderDate!,
      );
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingItem == null ? 'معاملة مالية جديدة' : 'تعديل المعاملة', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('دين لك (مستحق)')),
                    selected: _isForMe,
                    selectedColor: Colors.green.shade600,
                    labelStyle: TextStyle(color: _isForMe ? Colors.white : null, fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => _isForMe = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('دين عليك (التزام)')),
                    selected: !_isForMe,
                    selectedColor: Colors.red.shade600,
                    labelStyle: TextStyle(color: !_isForMe ? Colors.white : null, fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => _isForMe = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Autocomplete<PersonModel>(
              displayStringForOption: (p) => p.name,
              initialValue: TextEditingValue(text: _nameController.text),
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return widget.existingPersons;
                return widget.existingPersons
                    .where((p) => p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selected) {
                _nameController.text = selected.name;
                if (selected.phone.isNotEmpty) _phoneController.text = selected.phone;
              },
              fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                controller.addListener(() => _nameController.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'اسم الشخص أو المؤسسة (يمنع التكرار تلقائياً)',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف للاتصال والواتساب',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ (${appSettings.currencySymbol})',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'البيان / الملاحظات',
                prefixIcon: const Icon(Icons.note),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade400)),
              leading: const Icon(Icons.event, color: Color(0xFF0F766E)),
              title: Text(_dueDate == null ? 'تحديد موعد الاستحقاق (اختياري)' : 'موعد الاستحقاق: ${appSettings.formatDate(_dueDate!)}'),
              trailing: _dueDate != null ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _dueDate = null)) : null,
              onTap: () => _pickDate(true),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade400)),
              leading: const Icon(Icons.alarm, color: Colors.orange),
              title: Text(_reminderDate == null
                  ? 'تحديد تذكير وإشعار بالسداد (اختياري)'
                  : 'التذكير: ${appSettings.formatDate(_reminderDate!, includeTime: true)}'),
              trailing: _reminderDate != null ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _reminderDate = null)) : null,
              onTap: () => _pickDate(false),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _save,
                child: const Text('حفظ المعاملة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 5. صفحة إدارة الأشخاص والحسابات المستقلة =================
class PersonsDirectoryPage extends StatefulWidget {
  final List<DebtItem> debts;
  final List<PersonModel> persons;
  final Future<void> Function() onRefresh;

  const PersonsDirectoryPage({super.key, required this.debts, required this.persons, required this.onRefresh});

  @override
  State<PersonsDirectoryPage> createState() => _PersonsDirectoryPageState();
}

class _PersonsDirectoryPageState extends State<PersonsDirectoryPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final sortedPersons = widget.persons
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()) || p.phone.contains(_search))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name)); // ترتيب أبجدي

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأشخاص والحسابات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'بحث عن شخص أو مؤسسة...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: sortedPersons.isEmpty
                ? const Center(child: Text('لا يوجد أشخاص مسجلون حالياً'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: sortedPersons.length,
                    itemBuilder: (ctx, i) {
                      final person = sortedPersons[i];
                      final pDebts = widget.debts.where((d) => d.personName == person.name).toList();
                      final forMe = pDebts.where((d) => d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
                      final onMe = pDebts.where((d) => !d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
                      final net = forMe - onMe;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0F766E),
                            child: Icon(IconData(person.iconCode, fontFamily: 'MaterialIcons'), color: Colors.white),
                          ),
                          title: Text(person.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'له: ${appSettings.formatNumber(forMe)} | عليه: ${appSettings.formatNumber(onMe)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            '${appSettings.formatNumber(net)} ${appSettings.currencySymbol}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: net >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PersonFullProfilePage(person: person, onRefresh: widget.onRefresh),
                              ),
                            );
                            await widget.onRefresh();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ================= صفحة الملف الشخصي والتواصل المباشر وكشف الحساب =================
class PersonFullProfilePage extends StatefulWidget {
  final PersonModel person;
  final Future<void> Function() onRefresh;

  const PersonFullProfilePage({super.key, required this.person, required this.onRefresh});

  @override
  State<PersonFullProfilePage> createState() => _PersonFullProfilePageState();
}

class _PersonFullProfilePageState extends State<PersonFullProfilePage> {
  late PersonModel currentPerson;
  List<DebtItem> personDebts = [];

  @override
  void initState() {
    super.initState();
    currentPerson = widget.person;
    _loadPersonDebts();
  }

  Future<void> _loadPersonDebts() async {
    final all = await DatabaseService.instance.getAllDebts();
    setState(() {
      personDebts = all.where((d) => d.personName == currentPerson.name).toList();
    });
  }

  Future<void> _callPhone() async {
    if (currentPerson.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف مسجل لهذا الشخص')));
      return;
    }
    final uri = Uri.parse('tel:${currentPerson.phone}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(double netAmount) async {
    if (currentPerson.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إضافة رقم هاتف أولاً')));
      return;
    }
    final cleanPhone = currentPerson.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = 'مرحباً ${currentPerson.name}، تذكير ودّي بخصوص الرصيد المتبقي في الحساب وقدره: ${appSettings.formatNumber(netAmount.abs())} ${appSettings.currencySymbol}.';
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showCustomReminderDialog(double netAmount) {
    final msgCtrl = TextEditingController(
      text: 'السلام عليكم ${currentPerson.name}، نود تذكيركم بأن صافي الحساب المتبقي هو ${appSettings.formatNumber(netAmount.abs())} ${appSettings.currencySymbol}.',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رسالة تذكير قابلة للتعديل'),
        content: TextField(controller: msgCtrl, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('مشاركة الرسالة'),
            onPressed: () {
              Navigator.pop(ctx);
              Share.share(msgCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  void _editPersonDialog() {
    final nameCtrl = TextEditingController(text: currentPerson.name);
    final phoneCtrl = TextEditingController(text: currentPerson.phone);
    int selectedIcon = currentPerson.iconCode;
    final icons = [0xe491, 0xe0ba, 0xe559, 0xe8d3, 0xe3af];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل بيانات الشخص'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: icons.map((code) {
                  return IconButton(
                    icon: Icon(IconData(code, fontFamily: 'MaterialIcons'),
                        color: selectedIcon == code ? const Color(0xFF0F766E) : Colors.grey),
                    onPressed: () => setDialogState(() => selectedIcon = code),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final updated = PersonModel(
                  id: currentPerson.id,
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  iconCode: selectedIcon,
                );
                await DatabaseService.instance.updatePersonDetails(currentPerson, updated);
                setState(() => currentPerson = updated);
                await _loadPersonDebts();
                await widget.onRefresh();
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePerson() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الشخص نهائياً'),
        content: Text('هل أنت متأكد من حذف ${currentPerson.name} وجميع معاملاته ودفعاته؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseService.instance.deletePersonAndDebts(currentPerson.name);
              await widget.onRefresh();
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalForMe = personDebts.where((d) => d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
    final totalOnMe = personDebts.where((d) => !d.isForMe).fold(0.0, (s, d) => s + d.remainingAmount);
    final net = totalForMe - totalOnMe;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPerson.name, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _editPersonDialog),
          IconButton(icon: const Icon(Icons.delete), onPressed: _confirmDeletePerson),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _col('له (متبقي)', totalForMe, Colors.green),
                        _col('عليه (متبقي)', totalOnMe, Colors.red),
                        _col('الصافي', net, net >= 0 ? Colors.green : Colors.red),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _actionBtn(Icons.call, 'اتصال', Colors.blue, _callPhone),
                        _actionBtn(Icons.chat, 'واتساب', Colors.green, () => _openWhatsApp(net)),
                        _actionBtn(Icons.message, 'تذكير', Colors.orange, () => _showCustomReminderDialog(net)),
                        _actionBtn(Icons.picture_as_pdf, 'كشف حساب', Colors.red, () {
                          ExportService.generateAndSharePdf(
                            debts: personDebts,
                            currency: appSettings.currencySymbol,
                            title: 'كشف حساب: ${currentPerson.name}',
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: personDebts.length,
                itemBuilder: (ctx, i) {
                  final d = personDebts[i];
                  return Card(
                    child: ListTile(
                      title: Text(d.note.isEmpty ? (d.isForMe ? 'دين لك' : 'دين عليك') : d.note),
                      subtitle: Text('الأصلي: ${appSettings.formatNumber(d.amount)} | المدفوع: ${appSettings.formatNumber(d.paidAmount)}'),
                      trailing: Text(
                        '${appSettings.formatNumber(d.remainingAmount)} ${appSettings.currencySymbol}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: d.isForMe ? Colors.green : Colors.red),
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DebtPaymentsDetailPage(debt: d, onRefresh: _loadPersonDebts)),
                        );
                        await _loadPersonDebts();
                        await widget.onRefresh();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _col(String label, double val, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text('${appSettings.formatNumber(val)} ${appSettings.currencySymbol}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Column(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

// ================= 6. صفحة التحليلات والرسوم البيانية المتقدمة =================
class AnalyticsPage extends StatelessWidget {
  final List<DebtItem> debts;

  const AnalyticsPage({super.key, required this.debts});

  @override
  Widget build(BuildContext context) {
    final totalOriginal = debts.fold(0.0, (s, d) => s + d.amount);
    final totalPaid = debts.fold(0.0, (s, d) => s + d.paidAmount);
    final totalRemaining = debts.fold(0.0, (s, d) => s + d.remainingAmount);
    final openCount = debts.where((d) => !d.isFullyPaid).length;
    final closedCount = debts.where((d) => d.isFullyPaid).length;

    // أكثر الأشخاص مديونية (المتبقي لك عليهم)
    final Map<String, double> debtorsMap = {};
    for (var d in debts.where((d) => d.isForMe && d.remainingAmount > 0)) {
      debtorsMap[d.personName] = (debtorsMap[d.personName] ?? 0) + d.remainingAmount;
    }
    final topDebtors = debtorsMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // تطور الحسابات حسب الأشهر
    final Map<String, double> monthlyTotals = {};
    for (var d in debts) {
      final key = intl.DateFormat('yyyy-MM').format(d.date);
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + d.amount;
    }
    final sortedMonths = monthlyTotals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('التحليلات والرسوم البيانية', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _kpiCard('الديون المفتوحة', '$openCount', Colors.orange)),
                const SizedBox(width: 10),
                Expanded(child: _kpiCard('الديون المسددة', '$closedCount', Colors.green)),
                const SizedBox(width: 10),
                Expanded(
                  child: _kpiCard(
                    'نسبة التحصيل',
                    totalOriginal > 0 ? '${((totalPaid / totalOriginal) * 100).toStringAsFixed(0)}%' : '0%',
                    Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // الرسم البياني الدائري: المسدد مقابل المتبقي
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('توزيع الديون المسددة والمتبقية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: (totalPaid + totalRemaining) == 0
                          ? const Center(child: Text('لا توجد بيانات كافية للرسم'))
                          : PieChart(
                              PieChartData(
                                sections: [
                                  PieChartSectionData(
                                    value: totalPaid,
                                    title: 'المسدد\n${appSettings.formatNumber(totalPaid)}',
                                    color: Colors.green,
                                    radius: 65,
                                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  PieChartSectionData(
                                    value: totalRemaining,
                                    title: 'المتبقي\n${appSettings.formatNumber(totalRemaining)}',
                                    color: Colors.redAccent,
                                    radius: 65,
                                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // الرسم البياني العمودي: تطور الحسابات حسب الأشهر
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('تطور حجم المعاملات حسب الأشهر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: sortedMonths.isEmpty
                          ? const Center(child: Text('لا توجد بيانات شهرية'))
                          : BarChart(
                              BarChartData(
                                borderData: FlBorderData(show: false),
                                titlesData: FlTitlesData(
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (val, _) {
                                        final idx = val.toInt();
                                        if (idx < 0 || idx >= sortedMonths.length) return const SizedBox.shrink();
                                        return Text(sortedMonths[idx].key.substring(5), style: const TextStyle(fontSize: 11));
                                      },
                                    ),
                                  ),
                                ),
                                barGroups: List.generate(sortedMonths.length, (idx) {
                                  return BarChartGroupData(
                                    x: idx,
                                    barRods: [
                                      BarChartRodData(
                                        toY: sortedMonths[idx].value,
                                        color: const Color(0xFF0F766E),
                                        width: 18,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // أكثر الأشخاص مديونية
            const Text('أكثر الأشخاص مديونية لك:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (topDebtors.isEmpty)
              const Text('لا توجد ديون مستحقة حالياً', style: TextStyle(color: Colors.grey))
            else
              ...topDebtors.take(5).map((e) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.person, color: Color(0xFF0F766E)),
                      title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Text(
                        '${appSettings.formatNumber(e.value)} ${appSettings.currencySymbol}',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String val, Color color) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      );
}

// ================= 7. صفحة سجل العمليات (Audit Log) =================
class ActivityLogsPage extends StatelessWidget {
  const ActivityLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل العمليات والحركات', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: FutureBuilder<List<ActivityLog>>(
        future: DatabaseService.instance.getActivityLogs(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final logs = snapshot.data!;
          if (logs.isEmpty) return const Center(child: Text('سجل العمليات فارغ حالياً'));

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log = logs[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF0F766E).withOpacity(0.15),
                    child: Text(log.actionType.substring(0, 1), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(log.description),
                  subtitle: Text('${log.actionType} • ${appSettings.formatDate(log.timestamp, includeTime: true)}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ================= 8. صفحة الإعدادات الشاملة =================
class SettingsPage extends StatefulWidget {
  final List<DebtItem> debts;
  final Future<void> Function() onRefresh;

  const SettingsPage({super.key, required this.debts, required this.onRefresh});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final List<String> _currencies = ['ل.ي', 'ر.ي', 'ر.س', '\$', '€', 'د.إ', 'ج.م'];
  final List<String> _dateFormats = ['yyyy/MM/dd', 'dd/MM/yyyy', 'MM-dd-yyyy'];

  void _configurePin() {
    final pinCtrl = TextEditingController(text: appSettings.appPin);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعداد رمز قفل التطبيق (PIN)'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'اتركه فارغاً لإلغاء القفل',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              appSettings.appPin = pinCtrl.text.trim();
              await prefs.setString('app_pin', appSettings.appPin);
              appSettings.notify();
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(appSettings.appPin.isEmpty ? 'تم إلغاء قفل التطبيق' : 'تم تفعيل قفل التطبيق بنجاح')),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات والنسخ الاحتياطي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('المظهر والتنسيق', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('الوضع الليلي (Dark Mode)'),
                  value: appSettings.isDarkMode,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    appSettings.isDarkMode = v;
                    await prefs.setBool('is_dark_mode', v);
                    appSettings.notify();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('العملة المعروضة (دون تغيير القيم)'),
                  trailing: DropdownButton<String>(
                    value: _currencies.contains(appSettings.currencySymbol) ? appSettings.currencySymbol : _currencies.first,
                    items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      final prefs = await SharedPreferences.getInstance();
                      appSettings.currencySymbol = v;
                      await prefs.setString('currency_symbol', v);
                      appSettings.notify();
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('تنسيق التاريخ'),
                  trailing: DropdownButton<String>(
                    value: appSettings.dateFormatPattern,
                    items: _dateFormats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      final prefs = await SharedPreferences.getInstance();
                      appSettings.dateFormatPattern = v;
                      await prefs.setString('date_format', v);
                      appSettings.notify();
                    },
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.format_list_numbered),
                  title: const Text('فواصل الآلاف في الأرقام (1,000)'),
                  value: appSettings.useThousandSeparator,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    appSettings.useThousandSeparator = v;
                    await prefs.setBool('thousand_sep', v);
                    appSettings.notify();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('الأمان والتنبيهات', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('قفل التطبيق برمز PIN'),
                  subtitle: Text(appSettings.appPin.isEmpty ? 'غير مفعل' : 'مفعل'),
                  onTap: _configurePin,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active),
                  title: const Text('تفعيل التنبيهات والتذكيرات'),
                  value: appSettings.notificationsEnabled,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    appSettings.notificationsEnabled = v;
                    await prefs.setBool('notifications_enabled', v);
                    if (!v) await NotificationService.instance.cancelAll();
                    appSettings.notify();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('النسخ الاحتياطي والاستعادة (JSON)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt, color: Colors.teal),
                  title: const Text('تصدير نسخة احتياطية إلى ملف JSON'),
                  subtitle: const Text('اختيار مكان الحفظ في الجهاز'),
                  onTap: () async {
                    final path = await ExportService.exportJsonToFile(askLocation: true);
                    if (path != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ تم حفظ النسخة في: $path')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file, color: Colors.blue),
                  title: const Text('استيراد نسخة احتياطية JSON'),
                  subtitle: const Text('فحص السلامة واستعادة البيانات بأمان'),
                  onTap: () async {
                    final ok = await ExportService.importJsonFromFile();
                    if (ok) {
                      await widget.onRefresh();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تمت استعادة البيانات بنجاح')));
                      }
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('❌ فشل الاستيراد: الملف غير صالح، تم الحفاظ على بياناتك الحالية')),
                      );
                    }
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('نسخ احتياطي تلقائي عند التحديث'),
                  value: appSettings.autoBackupEnabled,
                  onChanged: (v) async {
                    final prefs = await SharedPreferences.getInstance();
                    appSettings.autoBackupEnabled = v;
                    await prefs.setBool('auto_backup', v);
                    appSettings.notify();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('تصفير ومسح جميع البيانات', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('تأكيد تصفير الدفتر'),
                        content: const Text('سيتم حذف جميع المعاملات والدفعات والأشخاص نهائياً.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            onPressed: () async {
                              await DatabaseService.instance.clearAllTables();
                              await widget.onRefresh();
                              if (mounted) Navigator.pop(ctx);
                            },
                            child: const Text('مسح الكل'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}