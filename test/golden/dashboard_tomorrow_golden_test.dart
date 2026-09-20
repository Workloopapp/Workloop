import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/dashboard/dashboard_screen.dart';
import 'package:workloop/features/weather/local_weather_provider.dart';
import 'package:workloop/shared/models/slate_models.dart';
import 'package:workloop/shared/providers/appointments_provider.dart';
import 'package:workloop/shared/providers/client_follow_up_provider.dart';
import 'package:workloop/shared/providers/clients_provider.dart';
import 'package:workloop/shared/providers/dashboard_provider.dart';
import 'package:workloop/shared/providers/finance_provider.dart';
import 'package:workloop/shared/providers/notes_provider.dart';
import 'package:workloop/shared/providers/notifications_provider.dart';
import 'package:workloop/shared/providers/setup_checklist_provider.dart';
import 'package:workloop/shared/providers/tasks_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/auth_repository.dart';
import 'package:workloop/shared/utils/client_follow_up.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _Auth extends Fake implements AuthRepository {
  @override
  String get currentUserId => 'owner';
  @override
  String get currentFirstName => 'Alex';
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Manrope': 'assets/fonts/Manrope-Variable.ttf',
      'Ahem': 'assets/fonts/Manrope-Variable.ttf',
      'WorkloopMono': 'assets/fonts/WorkloopMono-Regular.ttf',
      'packages/lucide_flutter/LucideIcons':
          'packages/lucide_flutter/assets/lucide.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final large in [false, true]) {
    testWidgets(
      'Tomorrow matches dashboard context ${large ? 'large' : 'normal'}',
      (tester) async {
        tester.view.physicalSize = large
            ? const Size(320, 640)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime(2026, 9, 8, 16);
        final tomorrow = Appointment(
          id: 'booking-tomorrow',
          workspaceId: 'workspace',
          clientName: 'Sam Morgan',
          serviceName: 'Window clean',
          startTime: DateTime.utc(2026, 9, 9, 8),
          endTime: DateTime.utc(2026, 9, 9, 9, 30),
        );
        final payments = [
          Payment(
            id: 'payment',
            workspaceId: 'workspace',
            number: 'PAY-101',
            status: 'paid',
            issueDate: now,
            incomeRecordedAt: now,
            total: 450,
            amountPaid: 450,
          ),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(_Auth()),
              weatherUserIdProvider.overrideWith((_) => Stream.value(null)),
              dashboardClockProvider.overrideWith((_) => Stream.value(now)),
              workspaceProvider.overrideWith((_) async => {'id': 'workspace'}),
              workspaceIdProvider.overrideWith((_) async => 'workspace'),
              setupChecklistDismissedProvider.overrideWith((_) async => true),
              clientsProvider.overrideWith((_) async => <Client>[]),
              appointmentsProvider.overrideWith(
                (_) async => [tomorrow.toMap()],
              ),
              invoicesProvider.overrideWith((_) async => payments),
              financeSummaryProvider.overrideWith(
                (_) async => FinanceSummary.from(
                  payments: payments,
                  expenses: [],
                  monthlyTarget: 1000,
                  now: now,
                ),
              ),
              dashboardAttentionProvider.overrideWith((_) async => []),
              allTasksProvider.overrideWith((_) async => <SlateTask>[]),
              allNotesProvider.overrideWith((_) async => <SlateNote>[]),
              unreadNotificationsProvider.overrideWith((_) async => 0),
              tomorrowBriefProvider.overrideWith(
                (_) async => TomorrowBrief(
                  [tomorrow],
                  'Europe/London',
                  90,
                  workspaceId: 'workspace',
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(large ? 2 : 1),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(
                  key: const ValueKey('tomorrow-dashboard'),
                  child: WorkloopAppCanvas(child: child!),
                ),
              ),
              home: DashboardScreen(
                onNavigate: (_) {},
                onOpenMoneyFollowUps: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('tomorrow-brief-row')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final capture = find.byKey(const ValueKey('tomorrow-dashboard'));
        const captureName = String.fromEnvironment('CAPTURE_TOMORROW_QA');
        if (captureName.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(capture);
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/workloop-tomorrow-$captureName-${large ? 'large' : 'normal'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        } else {
          await expectLater(
            capture,
            matchesGoldenFile(
              'files/dashboard-tomorrow-${large ? 'large' : 'normal'}.png',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
