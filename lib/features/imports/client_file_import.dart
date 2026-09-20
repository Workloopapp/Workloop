import 'dart:convert';

import 'import_models.dart';

enum ClientImportField {
  ignore,
  name,
  givenName,
  familyName,
  phone,
  email,
  address,
  notes,
  tags,
}

ClientImportField guessClientImportField(String header) {
  final key = header.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (key.endsWith('type') || key.endsWith('label')) {
    return ClientImportField.ignore;
  }
  if (['firstname', 'givenname'].contains(key)) {
    return ClientImportField.givenName;
  }
  if (['lastname', 'familyname', 'surname'].contains(key)) {
    return ClientImportField.familyName;
  }
  if ([
    'name',
    'fullname',
    'displayname',
    'client',
    'clientname',
    'customername',
  ].contains(key)) {
    return ClientImportField.name;
  }
  if (key.contains('phone') || key == 'mobile') return ClientImportField.phone;
  if (key.contains('email')) return ClientImportField.email;
  if (key == 'address' || key == 'location' || key.endsWith('formatted')) {
    return ClientImportField.address;
  }
  if (key.contains('note')) return ClientImportField.notes;
  if (['tags', 'categories', 'category'].contains(key)) {
    return ClientImportField.tags;
  }
  return ClientImportField.ignore;
}

String? clientImportValue(
  List<String> row,
  Map<int, ClientImportField> mapping,
  ClientImportField field,
) {
  for (final entry in mapping.entries) {
    if (entry.value != field || entry.key >= row.length) continue;
    final value = row[entry.key].trim();
    if (value.isNotEmpty) return value;
  }
  if (field == ClientImportField.name) {
    final parts = [
      clientImportValue(row, mapping, ClientImportField.givenName),
      clientImportValue(row, mapping, ClientImportField.familyName),
    ].whereType<String>().join(' ');
    if (parts.isNotEmpty) return parts;
  }
  return null;
}

/// Read locally; only reviewed rows are subsequently sent to the repository.
CsvTable parseClientFile(List<int> bytes, {required String fileName}) {
  if (bytes.length > 5 * 1024 * 1024) {
    throw const FormatException(
      'Choose a file smaller than 5 MB. Export fewer contacts or leave out photos.',
    );
  }
  final isVcard = fileName.toLowerCase().endsWith('.vcf');
  String source;
  try {
    source = utf8.decode(bytes);
  } on FormatException {
    if (isVcard) {
      throw const FormatException(
        'Export your contacts again as a UTF-8 vCard 3.0 or 4.0 file.',
      );
    }
    if (bytes.length > 1 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      throw const FormatException(
        'Save this spreadsheet as CSV UTF-8, then choose it again.',
      );
    }
    source = latin1.decode(bytes);
  }
  final table = isVcard ? _parseVcards(source) : parseCsv(source);
  if (table.rows.isEmpty) {
    throw const FormatException('No contacts were found in this file.');
  }
  if (table.rows.length > 1000 || table.headers.length > 100) {
    throw const FormatException(
      'Import up to 1,000 contacts and 100 columns at a time. Export a smaller selection.',
    );
  }
  return table;
}

CsvTable _parseVcards(String source) {
  final lines = source
      .replaceFirst('\ufeff', '')
      .replaceAll(RegExp(r'\r\n?|\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');
  final rows = <List<String>>[];
  Map<String, List<String>>? card;
  String? version;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    if (line.toUpperCase() == 'BEGIN:VCARD') {
      if (card != null) {
        throw const FormatException(
          'The contact file has an unfinished card. Export it again.',
        );
      }
      card = {};
      version = null;
      continue;
    }
    if (line.toUpperCase() == 'END:VCARD') {
      if (card == null || !['3.0', '4.0'].contains(version)) {
        throw const FormatException(
          'Use vCard 3.0 or 4.0, or export your contacts as CSV.',
        );
      }
      String first(String key) => card![key]?.firstOrNull ?? '';
      final nameParts = _splitVcard(first('N'), ';');
      final name = first('FN').isNotEmpty
          ? _unescape(first('FN'))
          : [
              if (nameParts.length > 3) nameParts[3],
              if (nameParts.length > 1) nameParts[1],
              if (nameParts.length > 2) nameParts[2],
              if (nameParts.isNotEmpty) nameParts[0],
              if (nameParts.length > 4) nameParts[4],
            ].where((part) => part.isNotEmpty).join(' ');
      final phones = (card['TEL'] ?? [])
          .map(
            (v) => _unescape(
              v,
            ).replaceFirst(RegExp(r'^tel:', caseSensitive: false), ''),
          )
          .toList();
      final emails = (card['EMAIL'] ?? [])
          .map(
            (v) => _unescape(
              v,
            ).replaceFirst(RegExp(r'^mailto:', caseSensitive: false), ''),
          )
          .toList();
      final addresses = (card['ADR'] ?? [])
          .map((v) => _splitVcard(v, ';').where((p) => p.isNotEmpty).join(', '))
          .toList();
      final notes = [
        ...?card['NOTE']?.map(_unescape),
        if (first('ORG').isNotEmpty)
          'Organisation: ${_splitVcard(first('ORG'), ';').join(' · ')}',
        for (final phone in phones.skip(1)) 'Other phone: $phone',
        for (final email in emails.skip(1)) 'Other email: $email',
        for (final address in addresses.skip(1)) 'Other address: $address',
      ].join('\n');
      rows.add([
        name.isNotEmpty ? name : _unescape(first('ORG')),
        phones.firstOrNull ?? '',
        emails.firstOrNull ?? '',
        addresses.firstOrNull ?? '',
        notes,
      ]);
      if (rows.length > 1000) {
        throw const FormatException('Import up to 1,000 contacts at a time.');
      }
      card = null;
      continue;
    }
    if (card == null) {
      throw const FormatException('Choose a contact export ending in .vcf.');
    }
    // Parameter values may contain quoted colons (for example an ADR label).
    var quoted = false;
    var separator = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '"') quoted = !quoted;
      if (line[i] == ':' && !quoted) {
        separator = i;
        break;
      }
    }
    if (separator < 1) {
      throw const FormatException(
        'This contact file has an unreadable line. Export it again.',
      );
    }
    final header = line.substring(0, separator);
    final key = header.split(';').first.split('.').last.toUpperCase();
    final value = line.substring(separator + 1);
    if (key == 'VERSION') {
      version = value;
      continue;
    }
    if (!['FN', 'N', 'TEL', 'EMAIL', 'ADR', 'NOTE', 'ORG'].contains(key)) {
      continue;
    }
    if (header.toUpperCase().contains('ENCODING=') ||
        (header.toUpperCase().contains('CHARSET=') &&
            !header.toUpperCase().contains('CHARSET=UTF-8'))) {
      throw const FormatException(
        'Export this contact file as UTF-8 vCard 3.0/4.0 or CSV.',
      );
    }
    if (value.isNotEmpty) card.putIfAbsent(key, () => []).add(value);
  }
  if (card != null) {
    throw const FormatException(
      'The contact file is incomplete. Export it again.',
    );
  }
  return CsvTable(
    headers: const ['Full name', 'Phone', 'Email', 'Address', 'Notes'],
    rows: rows,
    delimiter: ',',
  );
}

List<String> _splitVcard(String value, String delimiter) {
  final parts = <String>[];
  final part = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] == '\\' && i + 1 < value.length) {
      part.write(value[i]);
      part.write(value[++i]);
    } else if (value[i] == delimiter) {
      parts.add(_unescape(part.toString()).trim());
      part.clear();
    } else {
      part.write(value[i]);
    }
  }
  parts.add(_unescape(part.toString()).trim());
  return parts;
}

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'\\([nN,;\\])'),
  (m) => m[1]!.toLowerCase() == 'n' ? '\n' : m[1]!,
);
