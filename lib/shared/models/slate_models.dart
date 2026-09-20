DateTime? _dateTimeFrom(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

double _doubleFrom(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _intFrom(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Map<String, dynamic>? _nestedMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _nestedMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<String> _stringListFrom(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

String? _cleanDisplayText(dynamic value) {
  final text = value
      ?.toString()
      .replaceAll('[Slate demo]', '')
      .replaceFirst(RegExp(r'^Demo:\s*'), '')
      .trim();
  return text == null || text.isEmpty ? null : text;
}

class Workspace {
  final String id;
  final String name;
  final String? logoUrl;
  final String? industry;
  final DateTime? createdAt;

  const Workspace({
    required this.id,
    required this.name,
    this.industry,
    this.logoUrl,
    this.createdAt,
  });

  factory Workspace.fromMap(Map<String, dynamic> map) {
    return Workspace(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Your Business',
      industry: map['industry'] as String?,
      logoUrl: map['logo_url'] as String?,
      createdAt: _dateTimeFrom(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    if (industry != null) 'industry': industry,
    if (logoUrl != null) 'logo_url': logoUrl,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

class Client {
  final String id;
  final String workspaceId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String? importantNotes;
  final String status;
  final String preferredContactMethod;
  final String? source;
  final DateTime? birthday;
  final List<String> tags;
  final DateTime? lastActivityAt;
  final DateTime? createdAt;

  const Client({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.importantNotes,
    this.status = 'active',
    this.preferredContactMethod = 'phone',
    this.source,
    this.birthday,
    this.tags = const [],
    this.lastActivityAt,
    this.createdAt,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unnamed client',
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: _cleanDisplayText(map['notes']),
      importantNotes: _cleanDisplayText(map['important_notes']),
      status: map['status'] as String? ?? 'active',
      preferredContactMethod:
          map['preferred_contact_method'] as String? ?? 'phone',
      source: map['source'] as String?,
      birthday: _dateTimeFrom(map['birthday']),
      tags: _stringListFrom(map['tags']),
      lastActivityAt: _dateTimeFrom(map['last_activity_at']),
      createdAt: _dateTimeFrom(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'notes': notes,
    'important_notes': importantNotes,
    'status': status,
    'preferred_contact_method': preferredContactMethod,
    'source': source,
    if (birthday != null)
      'birthday': birthday!.toIso8601String().split('T').first,
    'tags': tags,
    if (lastActivityAt != null)
      'last_activity_at': lastActivityAt!.toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

class Service {
  final String id;
  final String workspaceId;
  final String name;
  final int durationMins;
  final double price;
  final String? description;
  final bool showOnProfile;
  final bool active;
  final List<ServiceAddOn> addOns;

  const Service({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.durationMins,
    required this.price,
    this.description,
    this.showOnProfile = true,
    this.active = true,
    this.addOns = const [],
  });

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      name: map['name'] as String? ?? 'Service',
      durationMins: _intFrom(map['duration_mins'], 60),
      price: _doubleFrom(map['price']),
      description: _cleanDisplayText(map['description']),
      showOnProfile: map['show_on_profile'] as bool? ?? true,
      active: map['active'] as bool? ?? true,
      addOns: _nestedMapList(
        map['service_add_ons'] ?? map['add_ons'],
      ).map(ServiceAddOn.fromMap).toList(growable: false),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'name': name,
    'duration_mins': durationMins,
    'price': price,
    'description': description,
    'show_on_profile': showOnProfile,
    'active': active,
  };
}

class ServiceAddOn {
  final String id;
  final String workspaceId;
  final String serviceId;
  final String name;
  final String? description;
  final int durationMins;
  final double price;
  final bool active;
  final int position;

  const ServiceAddOn({
    required this.id,
    required this.workspaceId,
    required this.serviceId,
    required this.name,
    this.description,
    this.durationMins = 0,
    this.price = 0,
    this.active = true,
    this.position = 0,
  });

  factory ServiceAddOn.fromMap(Map<String, dynamic> map) => ServiceAddOn(
    id: map['id'] as String,
    workspaceId: map['workspace_id'] as String? ?? '',
    serviceId: map['service_id'] as String? ?? '',
    name: map['name'] as String? ?? 'Optional extra',
    description: _cleanDisplayText(map['description']),
    durationMins: _intFrom(map['duration_mins']),
    price: _doubleFrom(map['price']),
    active: map['active'] as bool? ?? true,
    position: _intFrom(map['position']),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'service_id': serviceId,
    'name': name,
    'description': description,
    'duration_mins': durationMins,
    'price': price,
    'active': active,
    'position': position,
  };
}

class ServiceItemSnapshot {
  final String id;
  final String workspaceId;
  final String itemKind;
  final String? sourceServiceId;
  final String? sourceAddOnId;
  final String name;
  final int durationMins;
  final double price;
  final int position;

  const ServiceItemSnapshot({
    required this.id,
    required this.workspaceId,
    required this.itemKind,
    required this.name,
    required this.durationMins,
    required this.price,
    required this.position,
    this.sourceServiceId,
    this.sourceAddOnId,
  });

  bool get isAddOn => itemKind == 'add_on';

  factory ServiceItemSnapshot.fromMap(Map<String, dynamic> map) =>
      ServiceItemSnapshot(
        id: map['id'] as String,
        workspaceId: map['workspace_id'] as String? ?? '',
        itemKind: map['item_kind'] as String? ?? 'base',
        sourceServiceId: map['source_service_id'] as String?,
        sourceAddOnId: map['source_add_on_id'] as String?,
        name: map['name'] as String? ?? 'Service',
        durationMins: _intFrom(map['duration_mins']),
        price: _doubleFrom(map['price']),
        position: _intFrom(map['position']),
      );
}

class Appointment {
  final String id;
  final String workspaceId;
  final String? contactId;
  final String? serviceId;
  final String? title;
  final DateTime startTime;
  final DateTime? endTime;
  final String status;
  final double price;
  final String? notes;
  final String? location;
  final String? recurrenceRule;
  final String? recurrenceTimezone;
  final String? clientName;
  final String? serviceName;
  final List<ServiceItemSnapshot> serviceItems;

  const Appointment({
    required this.id,
    required this.workspaceId,
    this.contactId,
    this.serviceId,
    this.title,
    required this.startTime,
    this.endTime,
    this.status = 'scheduled',
    this.price = 0,
    this.notes,
    this.location,
    this.recurrenceRule,
    this.recurrenceTimezone,
    this.clientName,
    this.serviceName,
    this.serviceItems = const [],
  });

  factory Appointment.fromMap(Map<String, dynamic> map) {
    final contact = _nestedMap(map['contacts']);
    final service = _nestedMap(map['services']);
    final serviceItems =
        _nestedMapList(
            map['appointment_items'],
          ).map(ServiceItemSnapshot.fromMap).toList(growable: false)
          ..sort((left, right) => left.position.compareTo(right.position));
    ServiceItemSnapshot? baseItem;
    for (final item in serviceItems) {
      if (!item.isAddOn) {
        baseItem = item;
        break;
      }
    }
    final serviceNames = serviceItems
        .where((item) => !item.isAddOn)
        .map((item) => item.name)
        .toList();
    final savedTitle = _cleanDisplayText(map['title']);
    return Appointment(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      contactId: map['contact_id'] as String?,
      serviceId: map['service_id'] as String?,
      title: savedTitle,
      startTime:
          _dateTimeFrom(map['start_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endTime: _dateTimeFrom(map['end_time']),
      status: map['status'] as String? ?? 'scheduled',
      price: _doubleFrom(map['price']),
      notes: _cleanDisplayText(map['notes']),
      location: map['location'] as String?,
      recurrenceRule: map['recurrence_rule'] as String?,
      recurrenceTimezone: map['recurrence_timezone'] as String?,
      clientName: contact?['name'] as String?,
      serviceName: serviceNames.length > 1
          ? serviceNames.join(' + ')
          : baseItem?.name ?? savedTitle ?? _cleanDisplayText(service?['name']),
      serviceItems: serviceItems,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'contact_id': contactId,
    'service_id': serviceId,
    'title': title,
    'start_time': startTime.toIso8601String(),
    if (endTime != null) 'end_time': endTime!.toIso8601String(),
    'status': status,
    'price': price,
    'notes': notes,
    'location': location,
    'recurrence_rule': recurrenceRule,
    'recurrence_timezone': recurrenceTimezone,
  };
}

class PaymentReceipt {
  final String id;
  final double amount;
  final DateTime receivedAt;
  const PaymentReceipt({
    required this.id,
    required this.amount,
    required this.receivedAt,
  });
  factory PaymentReceipt.fromMap(Map<String, dynamic> row) => PaymentReceipt(
    id: row['id'] as String? ?? '',
    amount: _doubleFrom(row['amount']),
    receivedAt:
        _dateTimeFrom(row['received_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class Payment {
  final String id;
  final String workspaceId;
  final String? contactId;
  final String? appointmentId;
  final String number;
  final String status;
  final DateTime issueDate;
  final DateTime? incomeRecordedAt;
  final DateTime? dueDate;
  final double total;
  final double amountPaid;
  final double stripeAmountPaid;
  final String? notes;
  final String? clientName;
  final String? clientEmail;
  final String? sourceDocumentId;
  final List<PaymentReceipt> receipts;
  final double depositAmount;
  final DateTime? depositDueDate;

  const Payment({
    required this.id,
    required this.workspaceId,
    this.contactId,
    this.appointmentId,
    required this.number,
    required this.status,
    required this.issueDate,
    this.incomeRecordedAt,
    this.dueDate,
    required this.total,
    this.amountPaid = 0,
    this.stripeAmountPaid = 0,
    this.notes,
    this.clientName,
    this.clientEmail,
    this.sourceDocumentId,
    this.receipts = const [],
    this.depositAmount = 0,
    this.depositDueDate,
  });

  double get collectedAmount {
    if (total < 0) {
      if (status == 'paid' && amountPaid == 0) return total;
      return amountPaid.clamp(total, 0).toDouble();
    }
    if (status == 'paid' && amountPaid <= 0) return total;
    return amountPaid.clamp(0, total).toDouble();
  }

  double get outstandingAmount {
    if (status == 'cancelled' || status == 'declined') return 0;
    if (total <= 0) return 0;
    return (total - collectedAmount).clamp(0, total).toDouble();
  }

  DateTime get receivedDate => incomeRecordedAt?.toLocal() ?? issueDate;

  bool get hasDeposit => depositAmount > 0;
  double get depositOutstandingAmount =>
      (depositAmount - collectedAmount).clamp(0, outstandingAmount).toDouble();
  bool get depositReceived =>
      hasDeposit &&
      depositOutstandingAmount == 0 &&
      status != 'cancelled' &&
      status != 'declined';
  double get collectionAmount => depositOutstandingAmount > 0
      ? depositOutstandingAmount
      : outstandingAmount;

  /// Issued documents retain each receipt/refund date. Older money entries
  /// preserve their existing single recorded-date behavior.
  List<PaymentReceipt> get cashReceipts => sourceDocumentId != null
      ? receipts
      : [
          PaymentReceipt(
            id: id,
            amount: collectedAmount,
            receivedAt: receivedDate,
          ),
        ];

  double receivedAmountBetween(DateTime start, DateTime end) => cashReceipts
      .where(
        (receipt) =>
            !receipt.receivedAt.isBefore(start) &&
            receipt.receivedAt.isBefore(end),
      )
      .fold<double>(0, (total, receipt) => total + receipt.amount);

  factory Payment.fromMap(Map<String, dynamic> map) {
    final contact = _nestedMap(map['contacts']);
    return Payment(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      contactId: map['contact_id'] as String?,
      appointmentId: map['appointment_id'] as String?,
      number:
          map['invoice_number'] as String? ??
          map['payment_number'] as String? ??
          '',
      status: map['status'] as String? ?? 'pending',
      issueDate:
          _dateTimeFrom(map['issue_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      incomeRecordedAt: _dateTimeFrom(map['income_recorded_at']),
      dueDate: _dateTimeFrom(map['due_date']),
      total: _doubleFrom(map['total']),
      amountPaid: _doubleFrom(map['amount_paid']),
      stripeAmountPaid: _doubleFrom(map['stripe_amount_paid']),
      notes: _cleanDisplayText(map['notes']),
      clientName: contact?['name'] as String?,
      clientEmail: contact?['email'] as String?,
      sourceDocumentId: map['source_document_id'] as String?,
      depositAmount: _doubleFrom(map['deposit_amount']),
      depositDueDate: _dateTimeFrom(map['deposit_due_date']),
      receipts: _nestedMapList(
        map['payment_receipts'],
      ).map(PaymentReceipt.fromMap).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'contact_id': contactId,
    'appointment_id': appointmentId,
    'invoice_number': number,
    if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
    if (sourceDocumentId != null) 'deposit_amount': depositAmount,
    if (sourceDocumentId != null)
      'deposit_due_date': depositDueDate?.toIso8601String().split('T').first,
    if (sourceDocumentId != null)
      'payment_receipts': receipts
          .map(
            (receipt) => {
              'id': receipt.id,
              'amount': receipt.amount,
              'received_at': receipt.receivedAt.toIso8601String(),
            },
          )
          .toList(),
    'status': status,
    'issue_date': issueDate.toIso8601String().split('T').first,
    if (incomeRecordedAt != null)
      'income_recorded_at': incomeRecordedAt!.toIso8601String(),
    if (dueDate != null)
      'due_date': dueDate!.toIso8601String().split('T').first,
    'total': total,
    'amount_paid': amountPaid,
    'stripe_amount_paid': stripeAmountPaid,
    'notes': notes,
  };
}

class Expense {
  final String id;
  final String workspaceId;
  final double amount;
  final String category;
  final DateTime expenseDate;
  final String? notes;
  final DateTime? createdAt;

  const Expense({
    required this.id,
    required this.workspaceId,
    required this.amount,
    required this.category,
    required this.expenseDate,
    this.notes,
    this.createdAt,
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      amount: _doubleFrom(map['amount']),
      category: map['category'] as String? ?? 'Other',
      expenseDate:
          _dateTimeFrom(map['expense_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      notes: _cleanDisplayText(map['notes']),
      createdAt: _dateTimeFrom(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'amount': amount,
    'category': category,
    'expense_date': expenseDate.toIso8601String().split('T').first,
    'notes': notes,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

class SlateTask {
  final String id;
  final String workspaceId;
  final String title;
  final String status;
  final String priority;
  final String reminderTiming;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? contactId;
  final String? appointmentId;
  final String? clientName;

  const SlateTask({
    required this.id,
    required this.workspaceId,
    required this.title,
    this.status = 'open',
    this.priority = 'medium',
    this.reminderTiming = 'none',
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.contactId,
    this.appointmentId,
    this.clientName,
  });

  factory SlateTask.fromMap(Map<String, dynamic> map) {
    final contact = _nestedMap(map['contacts']);
    return SlateTask(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      title: _cleanDisplayText(map['title']) ?? '',
      status: map['status'] as String? ?? 'open',
      priority: map['priority'] as String? ?? 'medium',
      reminderTiming: map['reminder_timing'] as String? ?? 'none',
      dueDate: _dateTimeFrom(map['due_date']),
      createdAt: _dateTimeFrom(map['created_at']),
      updatedAt: _dateTimeFrom(map['updated_at']),
      contactId: map['contact_id'] as String?,
      appointmentId: map['appointment_id'] as String?,
      clientName: contact?['name'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'title': title,
    'status': status,
    'priority': priority,
    'reminder_timing': reminderTiming,
    if (dueDate != null)
      'due_date': dueDate!.toIso8601String().split('T').first,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    'contact_id': contactId,
    'appointment_id': appointmentId,
  };
}

class SlateNote {
  final String id;
  final String workspaceId;
  final String title;
  final String body;
  final String? contactId;
  final String? appointmentId;
  final String? clientName;
  final bool pinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SlateNote({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.body,
    this.contactId,
    this.appointmentId,
    this.clientName,
    this.pinned = false,
    this.createdAt,
    this.updatedAt,
  });

  factory SlateNote.fromMap(Map<String, dynamic> map) {
    final contact = _nestedMap(map['contacts']);
    return SlateNote(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      title: _cleanDisplayText(map['title']) ?? '',
      body: _cleanDisplayText(map['body']) ?? '',
      contactId: map['contact_id'] as String?,
      appointmentId: map['appointment_id'] as String?,
      clientName: contact?['name'] as String?,
      pinned: map['pinned'] as bool? ?? false,
      createdAt: _dateTimeFrom(map['created_at']),
      updatedAt: _dateTimeFrom(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'title': title,
    'body': body,
    'contact_id': contactId,
    'appointment_id': appointmentId,
    'pinned': pinned,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class TaskChecklistItem {
  final String id;
  final String workspaceId;
  final String taskId;
  final String title;
  final bool completed;
  final int position;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TaskChecklistItem({
    required this.id,
    required this.workspaceId,
    required this.taskId,
    required this.title,
    this.completed = false,
    this.position = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory TaskChecklistItem.fromMap(Map<String, dynamic> map) {
    return TaskChecklistItem(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      taskId: map['task_id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      completed: map['completed'] as bool? ?? false,
      position: _intFrom(map['position']),
      createdAt: _dateTimeFrom(map['created_at']),
      updatedAt: _dateTimeFrom(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'task_id': taskId,
    'title': title,
    'completed': completed,
    'position': position,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class BusinessProfile {
  final String id;
  final String workspaceId;
  final String handle;
  final String? bio;
  final String? coverPhotoUrl;
  final List<String> galleryImageUrls;
  final List<String> reviewQuotes;
  final bool reviewsEnabled;
  final bool galleryEnabled;

  final bool _legacyPayNowEnabled;

  /// Always false until Workloop has a connected online-payment processor.
  ///
  /// The database value is retained privately for round-trip compatibility,
  /// but cannot accidentally advertise an unavailable feature.
  bool get payNowEnabled => false;
  final String bookingMode;
  final String? noticeText;
  final DateTime? noticeStart;
  final DateTime? noticeEnd;

  const BusinessProfile({
    required this.id,
    required this.workspaceId,
    required this.handle,
    this.bio,
    this.coverPhotoUrl,
    this.galleryImageUrls = const [],
    this.reviewQuotes = const [],
    this.reviewsEnabled = false,
    this.galleryEnabled = false,
    bool payNowEnabled = false,
    this.bookingMode = 'manual',
    this.noticeText,
    this.noticeStart,
    this.noticeEnd,
  }) : _legacyPayNowEnabled = payNowEnabled;

  bool isNoticeActive({DateTime? now}) {
    if (noticeText?.trim().isNotEmpty != true) return false;
    final current = now ?? DateTime.now();
    if (noticeStart != null && current.isBefore(noticeStart!)) return false;
    if (noticeEnd != null && current.isAfter(noticeEnd!)) return false;
    return true;
  }

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      handle: map['handle'] as String? ?? '',
      bio: map['bio'] as String?,
      coverPhotoUrl: map['cover_photo_url'] as String?,
      galleryImageUrls: _stringListFrom(map['gallery_image_urls']),
      reviewQuotes: _stringListFrom(map['review_quotes']),
      reviewsEnabled: map['reviews_enabled'] as bool? ?? false,
      galleryEnabled: map['gallery_enabled'] as bool? ?? false,
      payNowEnabled: map['pay_now_enabled'] as bool? ?? false,
      bookingMode: map['booking_mode'] as String? ?? 'manual',
      noticeText: map['notice_text'] as String?,
      noticeStart: _dateTimeFrom(map['notice_start']),
      noticeEnd: _dateTimeFrom(map['notice_end']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'handle': handle,
    'bio': bio,
    'cover_photo_url': coverPhotoUrl,
    'gallery_image_urls': galleryImageUrls,
    'review_quotes': reviewQuotes,
    'reviews_enabled': reviewsEnabled,
    'gallery_enabled': galleryEnabled,
    'pay_now_enabled': _legacyPayNowEnabled,
    'booking_mode': bookingMode,
    'notice_text': noticeText,
    if (noticeStart != null) 'notice_start': noticeStart!.toIso8601String(),
    if (noticeEnd != null) 'notice_end': noticeEnd!.toIso8601String(),
  };
}

class BookingRequest {
  final String id;
  final String workspaceId;
  final String name;
  final String phone;
  final String email;
  final String? serviceId;
  final String? serviceName;
  final int? serviceDurationMins;
  final double? servicePrice;
  final DateTime? requestedFor;
  final String? requestedTimezone;
  final String? preferredTimeText;
  final String? message;
  final String status;
  final DateTime? createdAt;
  final List<ServiceItemSnapshot> serviceItems;

  const BookingRequest({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.phone,
    this.email = '',
    this.serviceId,
    this.serviceName,
    this.serviceDurationMins,
    this.servicePrice,
    this.requestedFor,
    this.requestedTimezone,
    this.preferredTimeText,
    this.message,
    this.status = 'pending',
    this.createdAt,
    this.serviceItems = const [],
  });

  /// Contacting someone does not confirm or decline their request.
  bool get needsDecision => status == 'pending' || status == 'contacted';

  factory BookingRequest.fromMap(Map<String, dynamic> map) {
    final service = _nestedMap(map['services']);
    final serviceItems =
        _nestedMapList(
            map['booking_request_items'],
          ).map(ServiceItemSnapshot.fromMap).toList(growable: false)
          ..sort((left, right) => left.position.compareTo(right.position));
    ServiceItemSnapshot? baseItem;
    for (final item in serviceItems) {
      if (!item.isAddOn) {
        baseItem = item;
        break;
      }
    }
    return BookingRequest(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      serviceId: map['service_id'] as String?,
      serviceName: serviceItems.where((item) => !item.isAddOn).length > 1
          ? serviceItems
                .where((item) => !item.isAddOn)
                .map((item) => item.name)
                .join(' + ')
          : baseItem?.name ?? service?['name'] as String?,
      serviceDurationMins: serviceItems.isNotEmpty
          ? serviceItems.fold<int>(
              0,
              (total, item) => total + item.durationMins,
            )
          : (_intFrom(service?['duration_mins'], 0) == 0
                ? null
                : _intFrom(service?['duration_mins'])),
      servicePrice: serviceItems.isNotEmpty
          ? serviceItems.fold<double>(0, (total, item) => total + item.price)
          : (service?['price'] == null ? null : _doubleFrom(service?['price'])),
      requestedFor: _dateTimeFrom(map['requested_for']),
      requestedTimezone: map['requested_timezone'] as String?,
      preferredTimeText: map['preferred_time_text'] as String?,
      message: _cleanDisplayText(map['message']),
      status: map['status'] as String? ?? 'pending',
      createdAt: _dateTimeFrom(map['created_at']),
      serviceItems: serviceItems,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'workspace_id': workspaceId,
    'name': name,
    'phone': phone,
    'email': email,
    'service_id': serviceId,
    if (requestedFor != null)
      'requested_for': requestedFor!.toUtc().toIso8601String(),
    'requested_timezone': requestedTimezone,
    'preferred_time_text': preferredTimeText,
    'message': message,
    'status': status,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

class SlateNotification {
  final String id;
  final String workspaceId;
  final String type;
  final String title;
  final String body;
  final String? deepLink;
  final bool read;
  final DateTime? createdAt;

  const SlateNotification({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.title,
    required this.body,
    this.deepLink,
    this.read = false,
    this.createdAt,
  });

  factory SlateNotification.fromMap(Map<String, dynamic> map) {
    return SlateNotification(
      id: map['id'] as String,
      workspaceId: map['workspace_id'] as String? ?? '',
      type: map['type'] as String? ?? 'system',
      title: _cleanDisplayText(map['title']) ?? '',
      body: _cleanDisplayText(map['body']) ?? '',
      deepLink: map['deep_link'] as String?,
      read: map['read'] as bool? ?? false,
      createdAt: _dateTimeFrom(map['created_at']),
    );
  }
}
