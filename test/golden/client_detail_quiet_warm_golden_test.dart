import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/clients/client_detail_screen.dart';
import 'package:workloop/features/clients/widgets/client_overview_tab.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

// Fictional, render-only data. No account, repository or provider guards are
// changed, and no production requests or actions are performed. A fixed future
// appointment keeps the real DateTime.now-based next-booking selector stable
// without adding a test-only clock to the production widget.
const _clientId = 'quiet-warm-fictional-client';
const _workspaceId = 'quiet-warm-fictional-workspace';
const _client = <String, dynamic>{
  'id': _clientId,
  'workspace_id': _workspaceId,
  'name': 'Jamie Parker',
  'phone': '07700 900123',
  'email': 'jamie.parker@example.com',
  'status': 'active',
  'preferred_contact_method': 'sms',
  'notes': 'Prefers a morning visit.',
  'important_notes': 'Use the side gate.',
  'tags': <String>[],
};
const _appointments = <Map<String, dynamic>>[
  {
    'id': 'fictional-next-booking',
    'workspace_id': _workspaceId,
    'contact_id': _clientId,
    'start_time': '2099-09-04T10:30:00',
    'end_time': '2099-09-04T11:15:00',
    'status': 'scheduled',
    'price': 45,
    'title': 'Window clean',
    'contacts': {'name': 'Jamie Parker'},
    'services': {'name': 'Window clean', 'duration_mins': 45, 'price': 45},
  },
  {
    'id': 'fictional-previous-booking',
    'workspace_id': _workspaceId,
    'contact_id': _clientId,
    'start_time': '2026-08-28T10:30:00',
    'end_time': '2026-08-28T11:15:00',
    'status': 'completed',
    'price': 45,
    'title': 'Window clean',
    'contacts': {'name': 'Jamie Parker'},
    'services': {'name': 'Window clean', 'duration_mins': 45, 'price': 45},
  },
];

void main() {
  setUpAll(_loadFonts);

  for (final (appearance, empty) in [
    ('light', false),
    ('dark', false),
    ('light', true),
    ('dark', true),
  ]) {
    testWidgets('Quiet + Warm client detail $appearance${empty ? ' empty' : ''}', (
      tester,
    ) async {
      final theme = appearance == 'light' ? AppTheme.light : AppTheme.dark;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientAppointmentsProvider(
              _clientId,
            ).overrideWith((ref) async => empty ? const [] : _appointments),
            clientPaymentsProvider(_clientId).overrideWith(
              (ref) async => [
                Payment(
                  id: 'fictional-payment-due',
                  workspaceId: _workspaceId,
                  contactId: _clientId,
                  appointmentId: 'fictional-previous-booking',
                  number: 'PAY-104',
                  status: 'pending',
                  issueDate: DateTime(2026, 8, 28),
                  total: 45,
                  clientName: 'Jamie Parker',
                  notes: 'Window clean',
                ),
              ],
            ),
            clientTasksProvider(
              _clientId,
            ).overrideWith((ref) async => const <SlateTask>[]),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                devicePixelRatio: 1,
                padding: EdgeInsets.only(top: 47, bottom: 34),
                disableAnimations: true,
              ),
              child: RepaintBoundary(
                key: const ValueKey('client-detail-golden'),
                child: WorkloopAppCanvas(
                  // A pushed client-detail route currently has no bottom nav.
                  // Capture that actual composition rather than inventing one.
                  child: const ClientDetailScreen(client: _client),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Jamie Parker'), findsOneWidget);
      if (empty) {
        expect(find.text('Nothing booked yet'), findsOneWidget);
      } else {
        expect(find.text('Window clean'), findsWidgets);
      }
      await expectLater(
        find.byKey(const ValueKey('client-detail-golden')),
        matchesGoldenFile(
          'files/client-detail-quiet-warm-$appearance${empty ? '-empty' : ''}.png',
        ),
      );

      if (empty) {
        await tester.tap(find.text('Nothing booked yet'));
        await tester.pumpAndSettle();
        expect(find.text('No bookings yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        return;
      }

      // Also capture the real overview's payment and notes context, which is
      // below the first viewport. No content is removed to make the concept fit.
      final overviewScroll = find
          .descendant(
            of: find.byType(ClientOverviewTab),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Use the side gate.'),
        120,
        scrollable: overviewScroll,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Use the side gate.'), findsOneWidget);
      expect(find.text('£45 remaining'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('client-detail-golden')),
        matchesGoldenFile(
          'files/client-detail-context-quiet-warm-$appearance.png',
        ),
      );
    });
  }
}

Future<void> _loadFonts() async {
  final manrope = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final mono = FontLoader('WorkloopMono')
    ..addFont(rootBundle.load('assets/fonts/WorkloopMono-Regular.ttf'));
  final fallback = FontLoader('Ahem')
    ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
  final lucide = FontLoader('packages/lucide_flutter/LucideIcons')
    ..addFont(rootBundle.load('packages/lucide_flutter/assets/lucide.ttf'));
  await Future.wait([
    manrope.load(),
    mono.load(),
    fallback.load(),
    lucide.load(),
  ]);
}
