import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:workloop/features/finance/tax_estimate.dart';
import 'package:workloop/features/finance/expense_records_repository.dart';

void main() {
  TaxEstimate estimate(int pounds, {int paid = 0, int reserve = 0}) =>
      TaxEstimate.calculate(
        TaxEstimateInput(
          turnoverMinor: pounds * 100,
          nonVehicleExpensesMinor: 0,
          eligible: true,
          paidToHmrcMinor: paid * 100,
          reserveMinor: reserve * 100,
        ),
        mileageMinor: 0,
      );

  test(
    'pounds and miles parse without floating point rounding or silent truncation',
    () {
      expect(parseHundredths('10.01'), 1001);
      expect(parseHundredths('0.1'), 10);
      expect(parseHundredths('10.001'), null);
      expect(parseHundredths('NaN'), null);
      expect(parseHundredths('-1'), null);
      expect(parseHundredths('1e4'), null);
    },
  );
  test('2026/27 allowance and NI lower threshold', () {
    expect(estimate(12570).liabilityMinor, 0);
    expect(estimate(12571).incomeTaxMinor, 20);
    expect(estimate(12571).class4Minor, 6);
    expect(estimate(50270).incomeTaxMinor, 754000);
    expect(estimate(50270).class4Minor, 226200);
  });
  test('negative pence display retains its sign below one pound', () {
    expect(formatHundredths(-25), '-0.25');
    expect(formatHundredths(-125), '-1.25');
  });
  test('annual mileage forecast is separate from actual logged deduction', () {
    const input = TaxEstimateInput(
      turnoverMinor: 5000000,
      nonVehicleExpensesMinor: 0,
      vehicleMethod: VehicleExpenseMethod.mileage,
      annualCarVanMilesHundredths: 1100000,
      annualMotorcycleMilesHundredths: 10000,
      eligible: true,
    );
    final result = TaxEstimate.calculate(input, mileageMinor: 5500);
    expect(result.vehicleDeductionMinor, 577400);
    expect(result.profitMinor, 4422600);
    final restored = TaxEstimateInput.fromMap(input.toMap());
    expect(restored.annualCarVanMilesHundredths, 1100000);
    expect(restored.annualMotorcycleMilesHundredths, 10000);
    expect(restored.eligible, false);
  });
  test(
    'annual mileage bounds and paired inputs are checked before estimating',
    () {
      expect(
        () => mileageAllowanceMinor(
          carVanMilesHundredths: -1,
          motorcycleMilesHundredths: 0,
        ),
        throwsFormatException,
      );
      expect(
        () => mileageAllowanceMinor(
          carVanMilesHundredths: 0,
          motorcycleMilesHundredths: 100000001,
        ),
        throwsFormatException,
      );
      expect(
        () => TaxEstimate.calculate(
          const TaxEstimateInput(
            turnoverMinor: 5000000,
            nonVehicleExpensesMinor: 0,
            eligible: true,
            vehicleMethod: VehicleExpenseMethod.mileage,
            annualCarVanMilesHundredths: 100,
          ),
          mileageMinor: 0,
        ),
        throwsFormatException,
      );
    },
  );
  test('higher and additional bands and tapered personal allowance', () {
    expect(estimate(100000).incomeTaxMinor, 2743200);
    expect(estimate(110000).personalAllowanceMinor, 757000);
    expect(estimate(110000).incomeTaxMinor, 3343200);
    expect(estimate(125140).personalAllowanceMinor, 0);
    expect(estimate(125140).incomeTaxMinor, 4251600);
    expect(estimate(125141).incomeTaxMinor, 4251645);
    expect(estimate(200000).incomeTaxMinor, 7620300);
  });
  test(
    'reserve and paid tax reduce outstanding but not annual liability or advances',
    () {
      final result = estimate(50270, paid: 3000, reserve: 1000);
      expect(result.liabilityMinor, 980200);
      expect(result.outstandingMinor, 680200);
      expect(result.reserveShortfallMinor, 580200);
      expect(result.indicativeNextPaymentOnAccountMinor, 490100);
      expect(estimate(50270, paid: 15000).outstandingMinor, 0);
      expect(estimate(10000).indicativeNextPaymentOnAccountMinor, 0);
    },
  );
  test('chooses actual costs or mileage and never adds both', () {
    TaxEstimateInput input(VehicleExpenseMethod method) => TaxEstimateInput(
      turnoverMinor: 5000000,
      nonVehicleExpensesMinor: 1000000,
      actualVehicleExpensesMinor: 800000,
      vehicleMethod: method,
      eligible: true,
    );
    expect(
      TaxEstimate.calculate(
        input(VehicleExpenseMethod.actual),
        mileageMinor: 550000,
      ).profitMinor,
      3200000,
    );
    expect(
      TaxEstimate.calculate(
        input(VehicleExpenseMethod.mileage),
        mileageMinor: 550000,
      ).profitMinor,
      3450000,
    );
  });
  test('unsupported eligibility/residence and invalid input fail closed', () {
    expect(
      () => TaxEstimate.calculate(
        const TaxEstimateInput(
          turnoverMinor: 5000000,
          nonVehicleExpensesMinor: 0,
          eligible: false,
        ),
        mileageMinor: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => TaxEstimate.calculate(
        const TaxEstimateInput(
          turnoverMinor: 5000000,
          nonVehicleExpensesMinor: 0,
          eligible: true,
          jurisdiction: 'scotland',
        ),
        mileageMinor: 0,
      ),
      throwsFormatException,
    );
    expect(
      () => TaxEstimate.calculate(
        const TaxEstimateInput(
          turnoverMinor: -1,
          nonVehicleExpensesMinor: 0,
          eligible: true,
        ),
        mileageMinor: 0,
      ),
      throwsFormatException,
    );
    expect(
      TaxEstimateInput.fromMap(
        const TaxEstimateInput(
          turnoverMinor: 0,
          nonVehicleExpensesMinor: 0,
          eligible: true,
        ).toMap(),
      ).eligible,
      false,
    );
  });
  MileageEntry journey(
    int miles, {
    DateTime? date,
    String vehicle = 'AB12CDE',
    String type = 'car_van',
  }) => MileageEntry(
    id: 'id',
    date: date ?? DateTime(2026, 9, 8),
    milesHundredths: miles * 100,
    purpose: 'Client visit',
    vehicle: vehicle,
    vehicleType: type,
  );
  test(
    '2026/27 mileage uses new 55p rate then 25p and excludes other years',
    () {
      expect(mileageDeductionMinor([journey(11000)]), 575000);
      expect(mileageDeductionMinor([journey(1000), journey(10000)]), 575000);
      expect(
        mileageDeductionMinor([journey(10000, date: DateTime(2026, 4, 5))]),
        0,
      );
      expect(
        mileageDeductionMinor([journey(10000, date: DateTime(2027, 4, 6))]),
        0,
      );
      expect(mileageDeductionMinor([journey(1000, type: 'motorcycle')]), 24000);
    },
  );
  test(
    'the 10000-mile car/van band is shared across vehicles in one trade',
    () {
      expect(
        mileageDeductionMinor([
          journey(6000),
          journey(6000, vehicle: 'second van'),
        ]),
        600000,
      );
      expect(
        mileageDeductionMinor([
          journey(10000),
          journey(1000, type: 'motorcycle', vehicle: 'bike'),
        ]),
        574000,
      );
    },
  );

  test('mileage grouping normalises vehicle names and rejects mixed types', () {
    expect(
      mileageDeductionMinor([
        journey(10000),
        journey(1000, vehicle: ' ab12cde '),
      ]),
      575000,
    );
    expect(
      () => mileageDeductionMinor([
        journey(1000),
        journey(1000, type: 'motorcycle'),
      ]),
      throwsFormatException,
    );
  });
  test(
    'receipt validates actual MIME signature and byte limit without changing bytes',
    () {
      final pdf = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 55]);
      final file = ReceiptFile.checked('receipt.pdf', pdf);
      expect(file.mimeType, 'application/pdf');
      expect(identical(file.bytes, pdf), isTrue);
      expect(
        () => ReceiptFile.checked('fake.jpg', Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(
        () => ReceiptFile.checked('large.pdf', Uint8List(receiptMaxBytes + 1)),
        throwsFormatException,
      );
    },
  );
}
