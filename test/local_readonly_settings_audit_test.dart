import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/features/onboarding/screens/ob_hours.dart';
import 'package:workloop/features/profile/profile_editor_screen.dart';
import 'package:workloop/features/settings/providers/settings_providers.dart';
import 'package:workloop/features/settings/widgets/settings_business_tab.dart';
import 'package:workloop/shared/providers/onboarding_provider.dart';
import 'package:workloop/shared/providers/workspace_provider.dart';
import 'package:workloop/shared/repositories/services_repository.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

class _RecordingServices implements ServicesRepository {
  final prices = <double>[];
  @override
  Future<void> create({required String workspaceId, required String name, required double price, required int durationMins, String? description, bool showOnProfile = true, bool active = true}) async { prices.add(price); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _HoursDraft extends OnboardingNotifier {
  int saves = 0;
  @override
  OnboardingState build() => const OnboardingState();
  @override
  void setWorkingHours(Map<String, dynamic> hours) { saves++; state=state.copyWith(workingHours: hours); }
}
void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  setUpAll(() async {
    for(final family in ['Manrope','Ahem']) { await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'))).load(); }
  });
  testWidgets('audit: malformed service price must not create a free service', (tester) async {
    final repo=_RecordingServices();
    tester.view.physicalSize=const Size(430,932); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      workspaceProvider.overrideWith((ref) async => {'id':'isolated-audit','name':'Fictional Test'}),
      workspaceIdProvider.overrideWith((ref) async => 'isolated-audit'),
      settingsBusinessProfileProvider.overrideWith((ref) async => null),
      settingsWorkspaceSettingsProvider.overrideWith((ref) async => null),
      settingsServicesProvider.overrideWith((ref) async => []),
      servicesRepositoryProvider.overrideWithValue(repo),
    ], child: MaterialApp(theme:AppTheme.light, home:const ProfileEditorScreen(section:SettingsBusinessSection.services))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WorkloopTopAction)); await tester.pumpAndSettle();
    Finder hint(String value)=>find.byWidgetPredicate((w)=>w is TextField && w.decoration?.hintText==value);
    await tester.enterText(hint('e.g. 1-on-1 PT Session'),'Fictional consultation');
    await tester.enterText(hint('65'),'£55.00');
    tester.testTextInput.hide(); await tester.pumpAndSettle();
    final save=find.text('Add Service'); await tester.ensureVisible(save); await tester.pumpAndSettle();
    expect(save.hitTestable(),findsOneWidget); await tester.tap(save); await tester.pumpAndSettle();
    expect(repo.prices,isEmpty,reason:'Invalid price text must require correction instead of saving a free service.');
  });
  testWidgets('audit: closing before opening must not advance onboarding', (tester) async {
    final semantics=tester.ensureSemantics();
    try {
      var advances=0;
      final container=ProviderContainer(overrides:[onboardingProvider.overrideWith(_HoursDraft.new)]);
      addTearDown(container.dispose);
      tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp(theme:AppTheme.light,home:Scaffold(body:ObHours(onNext:()=>advances++,onBack:(){})))));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Monday closing time')); await tester.pumpAndSettle();
      tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(DateTime(2000,1,1,8));
      await tester.pumpAndSettle(); await tester.tap(find.text('Use time')); await tester.pumpAndSettle();
      expect(tester.getSemantics(find.bySemanticsLabel('Monday closing time')).getSemanticsData().value,'08:00');
      await tester.tap(find.byKey(const ValueKey('onboarding-hours-continue'))); await tester.pumpAndSettle();
      expect(advances,0,reason:'09:00 opening / 08:00 closing must be corrected before continuing.');
      expect((container.read(onboardingProvider.notifier) as _HoursDraft).saves,0);
    } finally { semantics.dispose(); }
  });
}
