import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/imports/client_file_import.dart';

void main() {
  test(
    'Apple grouped/folded vCards keep full names and extra contact details',
    () {
      final table = parseClientFile(
        utf8.encode(r'''BEGIN:VCARD
VERSION:3.0
N:Mitchell;Ava;;;
FN:Ava Mitchell
item1.TEL;type=CELL:+44 7700 900001
item2.TEL;type=WORK:+44 7700 900002
EMAIL:ava@example.com
EMAIL:work@example.com
ADR;TYPE=WORK:;;1 Example\; Street;Leeds;;LS1 1AA;UK
NOTE:First line\nSecond
  line\, with punctuation.
PHOTO;ENCODING=b:IGNORED
END:VCARD
'''),
        fileName: 'contacts.vcf',
      );
      expect(table.rows.single[0], 'Ava Mitchell');
      expect(table.rows.single[1], '+44 7700 900001');
      expect(table.rows.single[3], '1 Example; Street, Leeds, LS1 1AA, UK');
      expect(
        table.rows.single[4],
        contains('First line\nSecond line, with punctuation.'),
      );
      expect(table.rows.single[4], contains('Other phone: +44 7700 900002'));
      expect(table.rows.single[4], contains('Other email: work@example.com'));
      expect(table.rows.single.join(), isNot(contains('IGNORED')));
    },
  );

  test(
    'vCard 4 URIs, structured names, quoted parameters and multiple cards',
    () {
      final table = parseClientFile(
        utf8.encode('''BEGIN:VCARD\r
VERSION:4.0\r
N:Ng;Sam;;Dr;\r
TEL;VALUE=uri:tel:+447700900001\r
EMAIL:mailto:sam@example.com\r
ADR;LABEL="Office: reception":;;1 Sample Road;York;;YO1;UK\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:3.0\r
ORG:Sample Studio\r
END:VCARD\r
'''),
        fileName: 'CONTACTS.VCF',
      );
      expect(table.rows, hasLength(2));
      expect(table.rows.first.take(3), [
        'Dr Sam Ng',
        '+447700900001',
        'sam@example.com',
      ]);
      expect(table.rows[1][0], 'Sample Studio');
    },
  );

  test(
    'malformed, truncated and old encoded cards fail before any rows import',
    () {
      for (final source in [
        'BEGIN:VCARD\nVERSION:3.0\nFN:Ava',
        'BEGIN:VCARD\nVERSION:2.1\nFN:Ava\nEND:VCARD',
        'BEGIN:VCARD\nVERSION:3.0\nBEGIN:VCARD\nEND:VCARD',
        'BEGIN:VCARD\nVERSION:3.0\nFN;ENCODING=QUOTED-PRINTABLE:Ava\nEND:VCARD',
        'Name,Phone\nAva,07123',
        'END:VCARD',
      ]) {
        expect(
          () => parseClientFile(utf8.encode(source), fileName: 'bad.vcf'),
          throwsFormatException,
        );
      }
    },
  );

  test('Google CSV recognises value columns instead of type labels', () {
    expect(guessClientImportField('E-mail 1 - Type'), ClientImportField.ignore);
    expect(guessClientImportField('E-mail 1 - Value'), ClientImportField.email);
    expect(guessClientImportField('Phone 1 - Label'), ClientImportField.ignore);
    expect(guessClientImportField('Phone 1 - Value'), ClientImportField.phone);
    expect(
      guessClientImportField('Organization Name'),
      ClientImportField.ignore,
    );
    expect(
      guessClientImportField('Address 1 - Formatted'),
      ClientImportField.address,
    );
  });

  test(
    'Outlook/Google split names are combined, full names take precedence',
    () {
      final mapping = {
        0: ClientImportField.givenName,
        1: ClientImportField.familyName,
        2: ClientImportField.name,
      };
      expect(
        clientImportValue(
          ['Ava', 'Mitchell', ''],
          mapping,
          ClientImportField.name,
        ),
        'Ava Mitchell',
      );
      expect(
        clientImportValue(
          ['Ava', 'Mitchell', 'Ava M.'],
          mapping,
          ClientImportField.name,
        ),
        'Ava M.',
      );
      expect(
        clientImportValue(
          ['', 'Mitchell', ''],
          mapping,
          ClientImportField.name,
        ),
        'Mitchell',
      );
      expect(
        clientImportValue(['', '', ''], mapping, ClientImportField.name),
        isNull,
      );
    },
  );

  test('CSV quoting, BOM and non-English names survive file preparation', () {
    final table = parseClientFile(
      utf8.encode(
        '\ufeffFirst Name,Last Name,Notes\nZoë,Ng,"Line one\nLine two"',
      ),
      fileName: 'contacts.csv',
    );
    expect(table.rows.single, ['Zoë', 'Ng', 'Line one\nLine two']);
  });

  test(
    'empty, oversized, overly wide and UTF16 files give actionable errors',
    () {
      expect(
        () => parseClientFile([], fileName: 'empty.csv'),
        throwsFormatException,
      );
      expect(
        () => parseClientFile(
          List.filled(5 * 1024 * 1024 + 1, 65),
          fileName: 'huge.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => parseClientFile([255, 254, 65, 0], fileName: 'utf16.csv'),
        throwsFormatException,
      );
      expect(
        () => parseClientFile(
          utf8.encode('Name\n${List.filled(1001, 'Ava').join('\n')}'),
          fileName: 'many.csv',
        ),
        throwsFormatException,
      );
      final wide = List.filled(101, 'column').join(',');
      expect(
        () =>
            parseClientFile(utf8.encode('$wide\n$wide'), fileName: 'wide.csv'),
        throwsFormatException,
      );
    },
  );
}
