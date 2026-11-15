import 'dart:convert';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/app_models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('debt_book_pro_v3.db');
    await _migrateFromSharedPreferences(_database!);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        phone TEXT,
        iconCode INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        personName TEXT NOT NULL,
        phone TEXT,
        amount REAL NOT NULL,
        isForMe INTEGER NOT NULL,
        note TEXT,
        date TEXT NOT NULL,
        dueDate TEXT,
        reminderDate TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        debtId TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY (debtId) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actionType TEXT NOT NULL,
        description TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  // ترحيل البيانات السابقة من SharedPreferences تلقائياً دون فقدان أي سجل
  Future<void> _migrateFromSharedPreferences(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyMigrated = prefs.getBool('db_migrated_v3') ?? false;
    if (alreadyMigrated) return;

    final String? oldDebtsJson = prefs.getString('saved_debts_list');
    if (oldDebtsJson != null && oldDebtsJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(oldDebtsJson);
        for (var item in decoded) {
          final debt = DebtItem.fromMap(item);
          await db.insert('debts', debt.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          await db.insert(
            'persons',
            {'name': debt.personName, 'phone': debt.phone, 'iconCode': 0xe491},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await logActivity('ترحيل', 'تم ترحيل ${decoded.length} معاملة سابقة إلى قاعدة البيانات الجديدة بنجاح');
      } catch (_) {}
    }
    await prefs.setBool('db_migrated_v3', true);
  }

  // ================= عمليات الأشخاص =================
  Future<List<PersonModel>> getAllPersons() async {
    final db = await database;
    final maps = await db.query('persons', orderBy: 'name ASC');
    return maps.map((m) => PersonModel.fromMap(m)).toList();
  }

  Future<void> upsertPerson(PersonModel person) async {
    final db = await database;
    final existing = await db.query('persons', where: 'name = ?', whereArgs: [person.name]);
    if (existing.isEmpty) {
      await db.insert('persons', person.toMap());
    } else if (person.phone.isNotEmpty) {
      await db.update('persons', {'phone': person.phone, 'iconCode': person.iconCode},
          where: 'name = ?', whereArgs: [person.name]);
    }
  }

  Future<void> updatePersonDetails(PersonModel oldPerson, PersonModel updatedPerson) async {
    final db = await database;
    await db.update('persons', updatedPerson.toMap(), where: 'id = ?', whereArgs: [oldPerson.id]);
    await db.update(
      'debts',
      {'personName': updatedPerson.name, 'phone': updatedPerson.phone},
      where: 'personName = ?',
      whereArgs: [oldPerson.name],
    );
    await logActivity('تعديل', 'تعديل بيانات الشخص: ${updatedPerson.name}');
  }

  Future<void> deletePersonAndDebts(String personName) async {
    final db = await database;
    final personDebts = await db.query('debts', where: 'personName = ?', whereArgs: [personName]);
    for (var d in personDebts) {
      await db.delete('payments', where: 'debtId = ?', whereArgs: [d['id']]);
    }
    await db.delete('debts', where: 'personName = ?', whereArgs: [personName]);
    await db.delete('persons', where: 'name = ?', whereArgs: [personName]);
    await logActivity('حذف', 'حذف الشخص وجميع حساباته: $personName');
  }

  // ================= عمليات الديون والدفعات =================
  Future<List<DebtItem>> getAllDebts() async {
    final db = await database;
    final debtMaps = await db.query('debts', orderBy: 'date DESC');
    final paymentMaps = await db.query('payments', orderBy: 'date DESC');

    final Map<String, List<PaymentItem>> paymentsByDebt = {};
    for (var pMap in paymentMaps) {
      final p = PaymentItem.fromMap(pMap);
      paymentsByDebt.putIfAbsent(p.debtId, () => []).add(p);
    }

    return debtMaps
        .map((d) => DebtItem.fromMap(d, payments: paymentsByDebt[d['id'].toString()] ?? []))
        .toList();
  }

  Future<void> insertOrUpdateDebt(DebtItem debt, {bool isNew = true}) async {
    final db = await database;
    await db.insert('debts', debt.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await upsertPerson(PersonModel(name: debt.personName, phone: debt.phone));
    await logActivity(
      isNew ? 'إضافة' : 'تعديل',
      '${isNew ? "إضافة" : "تعديل"} معاملة لـ ${debt.personName} بمبلغ ${debt.amount}',
    );
  }

  Future<void> deleteDebt(DebtItem debt) async {
    final db = await database;
    await db.delete('payments', where: 'debtId = ?', whereArgs: [debt.id]);
    await db.delete('debts', where: 'id = ?', whereArgs: [debt.id]);
    await logActivity('حذف', 'حذف معاملة لـ ${debt.personName} بمبلغ ${debt.amount}');
  }

  Future<void> restoreDeletedDebt(DebtItem debt) async {
    final db = await database;
    await db.insert('debts', debt.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    for (var p in debt.payments) {
      await db.insert('payments', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await upsertPerson(PersonModel(name: debt.personName, phone: debt.phone));
    await logActivity('إضافة', 'التراجع عن حذف معاملة: ${debt.personName}');
  }

  Future<void> upsertPayment(PaymentItem payment, String personName, {bool isNew = true}) async {
    final db = await database;
    await db.insert('payments', payment.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await logActivity(
      'سداد',
      '${isNew ? "تسجيل" : "تعديل"} دفعة مالية لـ $personName بمبلغ ${payment.amount}',
    );
  }

  Future<void> deletePayment(PaymentItem payment, String personName) async {
    final db = await database;
    await db.delete('payments', where: 'id = ?', whereArgs: [payment.id]);
    await logActivity('حذف', 'حذف دفعة مالية لـ $personName بمبلغ ${payment.amount}');
  }

  // ================= سجل العمليات =================
  Future<void> logActivity(String actionType, String description) async {
    final db = await database;
    await db.insert('activity_logs', {
      'actionType': actionType,
      'description': description,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<ActivityLog>> getActivityLogs() async {
    final db = await database;
    final maps = await db.query('activity_logs', orderBy: 'id DESC', limit: 200);
    return maps.map((m) => ActivityLog.fromMap(m)).toList();
  }

  // ================= النسخ الاحتياطي والاستعادة =================
  Future<String> exportFullBackupJson() async {
    final debts = await getAllDebts();
    final persons = await getAllPersons();
    final backupData = {
      'app': 'DebtBookProMax',
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'persons': persons.map((p) => p.toMap()).toList(),
      'debts': debts.map((d) => d.toBackupJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(backupData);
  }

  Future<bool> importFullBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('debts')) {
        return false;
      }
      final List debtsList = decoded['debts'];
      final List personsList = decoded['persons'] ?? [];

      // التحقق من صحة جميع السجلات قبل لمس قاعدة البيانات الحالية
      final List<DebtItem> validatedDebts = [];
      for (var d in debtsList) {
        final List pRaw = d['payments'] ?? [];
        final payments = pRaw.map((p) => PaymentItem.fromMap(p)).toList();
        validatedDebts.add(DebtItem.fromMap(d, payments: payments));
      }

      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('payments');
        await txn.delete('debts');
        await txn.delete('persons');

        for (var p in personsList) {
          await txn.insert('persons', PersonModel.fromMap(p).toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (var debt in validatedDebts) {
          await txn.insert('debts', debt.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.insert(
            'persons',
            {'name': debt.personName, 'phone': debt.phone, 'iconCode': 0xe491},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          for (var pay in debt.payments) {
            await txn.insert('payments', pay.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });
      await logActivity('استعادة', 'تمت استعادة نسخة احتياطية تحتوي على ${validatedDebts.length} معاملة');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearAllTables() async {
    final db = await database;
    await db.delete('payments');
    await db.delete('debts');
    await db.delete('persons');
    await db.delete('activity_logs');
  }
}
