import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/repositories/repository_pagination.dart';
import '../../shared/repositories/supabase_client_provider.dart';
import '../../shared/providers/workspace_provider.dart';
import '../../shared/utils/workflow_idempotency.dart';
import 'tax_estimate.dart';

const receiptBucket = 'expense-receipts';
const receiptMaxBytes = 10 * 1024 * 1024;

class ReceiptFile {
  final String name;
  final String mimeType;
  final Uint8List bytes;
  const ReceiptFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  factory ReceiptFile.checked(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > receiptMaxBytes) {
      throw const FormatException('Choose a receipt up to 10 MB.');
    }
    bool starts(List<int> magic) =>
        bytes.length >= magic.length &&
        List.generate(
          magic.length,
          (i) => bytes[i] == magic[i],
        ).every((value) => value);
    final mime = starts([0x25, 0x50, 0x44, 0x46, 0x2d])
        ? 'application/pdf'
        : starts([0xff, 0xd8, 0xff])
        ? 'image/jpeg'
        : starts([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ? 'image/png'
        : null;
    if (mime == null) {
      throw const FormatException('Choose a JPEG, PNG or PDF receipt.');
    }
    final safeName = name.split(RegExp(r'[/\\]')).last.trim();
    if (safeName.isEmpty || safeName.length > 200) {
      throw const FormatException(
        'Use a receipt filename under 200 characters.',
      );
    }
    return ReceiptFile(name: safeName, mimeType: mime, bytes: bytes);
  }
}

class ExpenseReceipt {
  final String id;
  final String path;
  final String name;
  final String mimeType;
  final int? sizeBytes;
  const ExpenseReceipt({
    required this.id,
    required this.path,
    required this.name,
    required this.mimeType,
    this.sizeBytes,
  });
  factory ExpenseReceipt.fromMap(Map<String, dynamic> row) => ExpenseReceipt(
    id: row['id'] as String,
    path: row['object_path'] as String,
    name: row['file_name'] as String,
    mimeType: row['mime_type'] as String,
    sizeBytes: (row['size_bytes'] as num?)?.toInt(),
  );
}

final expenseRecordsRepositoryProvider = Provider(
  (ref) => ExpenseRecordsRepository(ref.watch(supabaseClientProvider)),
);
final expenseReceiptsProvider = FutureProvider.autoDispose
    .family<List<ExpenseReceipt>, String>((ref, expenseId) async {
      final workspace = await ref.watch(workspaceIdProvider.future);
      return workspace == null
          ? []
          : ref
                .watch(expenseRecordsRepositoryProvider)
                .receipts(expenseId, workspaceId: workspace);
    });
final mileageEntriesProvider = FutureProvider<List<MileageEntry>>((ref) async {
  final workspace = await ref.watch(workspaceIdProvider.future);
  return workspace == null
      ? []
      : ref.watch(expenseRecordsRepositoryProvider).mileage(workspace);
});
final savedTaxEstimateProvider = FutureProvider.autoDispose
    .family<TaxEstimateInput?, String>((ref, workspaceId) async {
      final workspace = await ref.watch(workspaceIdProvider.future);
      return workspace != workspaceId
          ? null
          : ref.watch(expenseRecordsRepositoryProvider).taxInput(workspaceId);
    });

class ExpenseRecordsRepository {
  final SupabaseClient client;
  const ExpenseRecordsRepository(this.client);

  Future<List<ExpenseReceipt>> receipts(
    String expenseId, {
    required String workspaceId,
  }) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async => List<Map<String, dynamic>>.from(
        await client
            .from('expense_receipts')
            .select()
            .eq('expense_id', expenseId)
            .eq('workspace_id', workspaceId)
            .order('created_at')
            .order('id')
            .range(from, to),
      ),
    );
    return rows.map(ExpenseReceipt.fromMap).toList();
  }

  Future<void> attach(
    String workspaceId,
    String expenseId,
    ReceiptFile file,
  ) async {
    // Validate again at the repository boundary; preserve original bytes.
    final checked = ReceiptFile.checked(file.name, file.bytes);
    if (checked.mimeType != file.mimeType) {
      throw const FormatException(
        'The receipt file type does not match its contents.',
      );
    }
    final token = createPublicRequestToken().replaceAll('-', '');
    final extension = file.mimeType == 'application/pdf'
        ? 'pdf'
        : file.mimeType == 'image/png'
        ? 'png'
        : 'jpg';
    final path = '$workspaceId/$expenseId/$token.$extension';
    final row = await client
        .from('expense_receipts')
        .insert({
          'workspace_id': workspaceId,
          'expense_id': expenseId,
          'object_path': path,
          'file_name': file.name,
          'mime_type': file.mimeType,
          'size_bytes': file.bytes.length,
        })
        .select()
        .single();
    try {
      await client.storage
          .from(receiptBucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.mimeType,
              upsert: false,
              cacheControl: '0',
            ),
          );
    } catch (_) {
      // A timed-out upload might have succeeded. Remove bytes before metadata.
      try {
        await client.storage.from(receiptBucket).remove([path]);
        await client
            .from('expense_receipts')
            .delete()
            .eq('id', row['id'] as String);
      } catch (_) {
        /* Keep metadata so account cleanup/export can find the object. */
      }
      rethrow;
    }
  }

  Future<Uint8List> download(ExpenseReceipt receipt) =>
      client.storage.from(receiptBucket).download(receipt.path);

  Future<void> removeReceipt(ExpenseReceipt receipt) async {
    await client.storage.from(receiptBucket).remove([receipt.path]);
    await client
        .from('expense_receipts')
        .delete()
        .eq('id', receipt.id)
        .select('id')
        .single();
  }

  Future<List<MileageEntry>> mileage(String workspaceId) async {
    final rows = await fetchAllRepositoryPages<Map<String, dynamic>>(
      loadPage: (from, to) async => List<Map<String, dynamic>>.from(
        await client
            .from('mileage_entries')
            .select()
            .eq('workspace_id', workspaceId)
            .order('journey_date', ascending: false)
            .order('id')
            .range(from, to),
      ),
    );
    return rows.map(MileageEntry.fromMap).toList();
  }

  Future<void> saveJourney({
    required String workspaceId,
    String? id,
    String? creationId,
    required DateTime date,
    required int milesHundredths,
    required String purpose,
    required String vehicle,
    required String vehicleType,
  }) async {
    if (milesHundredths <= 0 ||
        milesHundredths > 1000000 ||
        purpose.trim().isEmpty ||
        vehicle.trim().isEmpty ||
        purpose.trim().length > 500 ||
        vehicle.trim().length > 80 ||
        !const ['car_van', 'motorcycle'].contains(vehicleType) ||
        DateTime(date.year, date.month, date.day).isAfter(DateTime.now())) {
      throw const FormatException(
        'Add the business purpose, vehicle and miles.',
      );
    }
    final data = {
      'workspace_id': workspaceId,
      'journey_date': date.toIso8601String().split('T').first,
      'miles_hundredths': milesHundredths,
      'purpose': purpose.trim(),
      'vehicle': vehicle.trim().toLowerCase(),
      'vehicle_type': vehicleType,
    };
    if (id == null) {
      await client.from('mileage_entries').upsert({
        ...data,
        'id': creationId ?? createPublicRequestToken(),
      });
    } else {
      await client
          .from('mileage_entries')
          .update(data)
          .eq('id', id)
          .eq('workspace_id', workspaceId)
          .select('id')
          .single();
    }
  }

  Future<void> deleteJourney(String id) async {
    await client
        .from('mileage_entries')
        .delete()
        .eq('id', id)
        .select('id')
        .single();
  }

  Future<TaxEstimateInput?> taxInput(String workspaceId) async {
    final row = await client
        .from('workspace_tax_estimates')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('tax_year', SoleTraderTaxRules.year)
        .maybeSingle();
    return row == null ? null : TaxEstimateInput.fromMap(row);
  }

  Future<void> saveTaxInput(String workspaceId, TaxEstimateInput input) async {
    await client.from('workspace_tax_estimates').upsert({
      ...input.toMap(),
      'workspace_id': workspaceId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'workspace_id,tax_year');
  }
}
