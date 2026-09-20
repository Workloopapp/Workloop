import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/core/theme/app_theme.dart';
import 'package:workloop/shared/widgets/slate_ui.dart';

void _phone(WidgetTester tester, {Size size = const Size(320, 568)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewInsets);
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: home,
);

void main() {
  testWidgets('sheet is one edge-attached paper surface with a safe action', (
    tester,
  ) async {
    _phone(tester);
    int? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await showWorkloopBottomSheet<int>(
                  context: context,
                  builder: (context) => SlateSheetFrame(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const WorkloopSheetHeader(title: 'Record income'),
                        SlateButton(
                          label: 'Use amount',
                          onPressed: () => Navigator.pop(context, 7),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.left, 0);
    expect(sheet.right, 320);
    expect(sheet.bottom, 568);
    expect(
      tester.getRect(find.text('Use amount')).bottom,
      lessThanOrEqualTo(534),
    );
    expect(
      find.descendant(
        of: find.byType(SlateSheetFrame),
        matching: find.byType(SlateSurface),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Use amount'));
    await tester.pumpAndSettle();
    expect(result, 7);
  });

  testWidgets(
    'keyboard is accounted for once and save remains reachable at 2x text',
    (tester) async {
      _phone(tester);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await showWorkloopBottomSheet<String>(
                    context: context,
                    builder: (context) => Padding(
                      // Existing callers can keep this during incremental migration.
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: SlateSheetFrame(
                        scrollable: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const WorkloopSheetHeader(title: 'Add a note'),
                            TextField(controller: controller, maxLines: 4),
                            const SizedBox(height: 24),
                            SlateButton(
                              label: 'Save note',
                              onPressed: () =>
                                  Navigator.pop(context, controller.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Keep the customer’s preferred time.',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 230);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final fieldContext = tester.element(find.byType(TextField));
      expect(MediaQuery.viewInsetsOf(fieldContext).bottom, 0);
      await tester.ensureVisible(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Save note')).bottom, lessThan(338));
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(result, 'Keep the customer’s preferred time.');
    },
  );

  testWidgets('short pickers fit their content and keep the selected value', (
    tester,
  ) async {
    _phone(tester, size: const Size(390, 844));
    String? selected;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WorkloopPickerField<String>(
            title: 'Repeat booking',
            hint: 'Choose frequency',
            value: 'weekly',
            options: const [
              WorkloopPickerOption(value: 'none', label: 'Once'),
              WorkloopPickerOption(value: 'weekly', label: 'Weekly'),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(340));
    await tester.tap(find.text('Once'));
    await tester.pumpAndSettle();
    expect(selected, 'none');
  });

  testWidgets(
    'long picker can search and select with keyboard and large text',
    (tester) async {
      _phone(tester);
      int? selected;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WorkloopPickerField<int>(
              value: null,
              title: 'Choose a client',
              hint: 'Select client',
              options: List.generate(
                20,
                (i) => WorkloopPickerOption(
                  value: i,
                  label: i == 19 ? 'Maya Lewis' : 'Client $i',
                ),
              ),
              onChanged: (value) => selected = value,
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('Select client'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Maya');
      tester.view.viewInsets = const FakeViewPadding(bottom: 230);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Maya Lewis'),
        100,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maya Lewis'));
      await tester.pumpAndSettle();
      expect(selected, 19);
    },
  );

  testWidgets(
    'ordinary actions give one light haptic and disabled actions give none',
    (tester) async {
      final effects = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            effects.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var saves = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Column(
              children: [
                SlateButton(label: 'Save', onPressed: () => saves++),
                const SlateButton(label: 'Unavailable', onPressed: null),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(effects, ['HapticFeedbackType.lightImpact']);
      expect(saves, 1);
      effects.clear();
      await tester.tap(find.text('Unavailable'));
      await tester.pump();
      expect(effects, isEmpty);
    },
  );

  for (final future in [false, true]) {
    testWidgets(
      'date picker bounds ${future ? 'future' : 'past'} initial date safely',
      (tester) async {
        _phone(tester, size: const Size(568, 320));
        DateTime? selected;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Choose'),
                  onPressed: () async {
                    selected = await showWorkloopDatePicker(
                      context: context,
                      initialDate: DateTime(future ? 2028 : 2024),
                      firstDate: DateTime(2026, 9, 6),
                      lastDate: DateTime(2027, 9, 7),
                    );
                  },
                ),
              ),
            ),
            scale: 2,
          ),
        );
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Use date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use date'));
        await tester.pumpAndSettle();
        expect(selected, future ? DateTime(2027, 9, 7) : DateTime(2026, 9, 6));
      },
    );
  }
}
