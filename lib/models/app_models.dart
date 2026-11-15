class PersonModel {
  final int? id;
  final String name;
  final String phone;
  final int iconCode;

  PersonModel({
    this.id,
    required this.name,
    this.phone = '',
    this.iconCode = 0xe491, // Icons.person
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'iconCode': iconCode,
      };

  factory PersonModel.fromMap(Map<String, dynamic> map) => PersonModel(
        id: map['id'],
        name: map['name'],
        phone: map['phone'] ?? '',
        iconCode: map['iconCode'] ?? 0xe491,
      );
}

class PaymentItem {
  final String id;
  final String debtId;
  final double amount;
  final DateTime date;
  final String note;

  PaymentItem({
    required this.id,
    required this.debtId,
    required this.amount,
    required this.date,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'debtId': debtId,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory PaymentItem.fromMap(Map<String, dynamic> map) => PaymentItem(
        id: map['id'],
        debtId: map['debtId'],
        amount: (map['amount'] as num).toDouble(),
        date: DateTime.parse(map['date']),
        note: map['note'] ?? '',
      );
}

class DebtItem {
  final String id;
  final String personName;
  final String phone;
  final double amount; // المبلغ الأصلي
  final bool isForMe; // true = دين لي، false = دين عليّ
  final String note;
  final DateTime date;
  final DateTime? dueDate;
  final DateTime? reminderDate;
  final List<PaymentItem> payments;

  DebtItem({
    required this.id,
    required this.personName,
    this.phone = '',
    required this.amount,
    required this.isForMe,
    this.note = '',
    required this.date,
    this.dueDate,
    this.reminderDate,
    this.payments = const [],
  });

  double get paidAmount => payments.fold(0.0, (sum, p) => sum + p.amount);
  double get remainingAmount => (amount - paidAmount) < 0 ? 0 : (amount - paidAmount);
  bool get isFullyPaid => remainingAmount <= 0.001;
  bool get isPartiallyPaid => paidAmount > 0 && !isFullyPaid;
  bool get isOverdue => !isFullyPaid && dueDate != null && dueDate!.isBefore(DateTime.now());

  Map<String, dynamic> toMap() => {
        'id': id,
        'personName': personName,
        'phone': phone,
        'amount': amount,
        'isForMe': isForMe ? 1 : 0,
        'note': note,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'reminderDate': reminderDate?.toIso8601String(),
      };

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'personName': personName,
        'phone': phone,
        'amount': amount,
        'isForMe': isForMe,
        'note': note,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'reminderDate': reminderDate?.toIso8601String(),
        'payments': payments.map((p) => p.toMap()).toList(),
      };

  factory DebtItem.fromMap(Map<String, dynamic> map, {List<PaymentItem> payments = const []}) => DebtItem(
        id: map['id'].toString(),
        personName: map['personName'],
        phone: map['phone'] ?? '',
        amount: (map['amount'] as num).toDouble(),
        isForMe: map['isForMe'] == 1 || map['isForMe'] == true,
        note: map['note'] ?? '',
        date: DateTime.parse(map['date']),
        dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
        reminderDate: map['reminderDate'] != null ? DateTime.parse(map['reminderDate']) : null,
        payments: payments,
      );
}

class ActivityLog {
  final int? id;
  final String actionType; // إضافة، تعديل، حذف، سداد
  final String description;
  final DateTime timestamp;

  ActivityLog({
    this.id,
    required this.actionType,
    required this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'actionType': actionType,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ActivityLog.fromMap(Map<String, dynamic> map) => ActivityLog(
        id: map['id'],
        actionType: map['actionType'],
        description: map['description'],
        timestamp: DateTime.parse(map['timestamp']),
      );
}
