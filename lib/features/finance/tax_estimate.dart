import 'dart:math' as math;

/// GBP minor units throughout. Rules checked against HMRC on 8 September 2026.
/// This deliberately supports one trade and no other taxable income or reliefs.
class SoleTraderTaxRules {
  static const version = 'uk-ewni-2026-27-v1';
  static const year = '2026/27';
  static final start = DateTime(2026, 4, 6);
  static final end = DateTime(2027, 4, 6);
  // Both April boundaries fall in British Summer Time. Timestamped receipts
  // use UK civil midnight even when the owner opens the app while abroad.
  static final cashStart = DateTime.utc(2026, 4, 5, 23);
  static final cashEnd = DateTime.utc(2027, 4, 5, 23);
  static const sources = {
    'Income Tax': 'https://www.gov.uk/income-tax-rates',
    'National Insurance':
        'https://www.gov.uk/self-employed-national-insurance-rates',
    'Mileage':
        'https://www.gov.uk/simpler-income-tax-simplified-expenses/vehicles',
    'Payments on account':
        'https://www.gov.uk/understand-self-assessment-bill/payments-on-account',
  };
}

/// Parses pounds (or miles) exactly, without floating point arithmetic.
int? parseHundredths(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String formatHundredths(int value) =>
    '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';

enum VehicleExpenseMethod { actual, mileage }

class TaxEstimateInput {
  final int turnoverMinor;
  final int nonVehicleExpensesMinor;
  final int actualVehicleExpensesMinor;
  final int paidToHmrcMinor;
  final int reserveMinor;
  final VehicleExpenseMethod vehicleMethod;
  final String jurisdiction;
  final bool eligible;
  final int? annualCarVanMilesHundredths;
  final int? annualMotorcycleMilesHundredths;

  const TaxEstimateInput({
    required this.turnoverMinor,
    required this.nonVehicleExpensesMinor,
    this.actualVehicleExpensesMinor = 0,
    this.paidToHmrcMinor = 0,
    this.reserveMinor = 0,
    this.vehicleMethod = VehicleExpenseMethod.actual,
    this.jurisdiction = 'england',
    required this.eligible,
    this.annualCarVanMilesHundredths,
    this.annualMotorcycleMilesHundredths,
  });

  factory TaxEstimateInput.fromMap(Map<String, dynamic> row) =>
      TaxEstimateInput(
        turnoverMinor: (row['turnover_minor'] as num).toInt(),
        nonVehicleExpensesMinor: (row['non_vehicle_expenses_minor'] as num)
            .toInt(),
        actualVehicleExpensesMinor:
            (row['actual_vehicle_expenses_minor'] as num).toInt(),
        paidToHmrcMinor: (row['paid_to_hmrc_minor'] as num).toInt(),
        reserveMinor: (row['reserve_minor'] as num).toInt(),
        vehicleMethod: VehicleExpenseMethod.values.byName(
          row['vehicle_method'] as String,
        ),
        jurisdiction: row['jurisdiction'] as String,
        // Eligibility must be reviewed on every new calculation.
        eligible: false,
        annualCarVanMilesHundredths:
            (row['annual_car_van_miles_hundredths'] as num?)?.toInt(),
        annualMotorcycleMilesHundredths:
            (row['annual_motorcycle_miles_hundredths'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
    'tax_year': SoleTraderTaxRules.year,
    'rules_version': SoleTraderTaxRules.version,
    'turnover_minor': turnoverMinor,
    'non_vehicle_expenses_minor': nonVehicleExpensesMinor,
    'actual_vehicle_expenses_minor': actualVehicleExpensesMinor,
    'paid_to_hmrc_minor': paidToHmrcMinor,
    'reserve_minor': reserveMinor,
    'vehicle_method': vehicleMethod.name,
    'jurisdiction': jurisdiction,
    'annual_car_van_miles_hundredths': annualCarVanMilesHundredths,
    'annual_motorcycle_miles_hundredths': annualMotorcycleMilesHundredths,
  };
}

class TaxEstimate {
  final int profitMinor;
  final int personalAllowanceMinor;
  final int incomeTaxMinor;
  final int class4Minor;
  final int vehicleDeductionMinor;
  final int outstandingMinor;
  final int reserveShortfallMinor;

  const TaxEstimate({
    required this.profitMinor,
    required this.personalAllowanceMinor,
    required this.incomeTaxMinor,
    required this.class4Minor,
    required this.vehicleDeductionMinor,
    required this.outstandingMinor,
    required this.reserveShortfallMinor,
  });

  int get liabilityMinor => incomeTaxMinor + class4Minor;
  // Eligible users have no income tax deducted outside Self Assessment.
  int get indicativeNextPaymentOnAccountMinor =>
      liabilityMinor >= 100000 ? (liabilityMinor + 1) ~/ 2 : 0;

  static TaxEstimate calculate(
    TaxEstimateInput input, {
    required int mileageMinor,
  }) {
    if (!input.eligible ||
        !const [
          'england',
          'wales',
          'northern_ireland',
        ].contains(input.jurisdiction)) {
      throw const FormatException(
        'Confirm that this estimate supports your tax circumstances.',
      );
    }
    for (final amount in [
      input.turnoverMinor,
      input.nonVehicleExpensesMinor,
      input.actualVehicleExpensesMinor,
      input.paidToHmrcMinor,
      input.reserveMinor,
      mileageMinor,
    ]) {
      if (amount < 0 || amount > 99999999999) {
        throw const FormatException('Enter a valid positive amount.');
      }
    }
    if ((input.annualCarVanMilesHundredths == null) !=
        (input.annualMotorcycleMilesHundredths == null)) {
      throw const FormatException('Review both annual mileage totals.');
    }
    final vehicle = input.vehicleMethod == VehicleExpenseMethod.mileage
        ? input.annualCarVanMilesHundredths == null
              ? mileageMinor
              : mileageAllowanceMinor(
                  carVanMilesHundredths: input.annualCarVanMilesHundredths!,
                  motorcycleMilesHundredths:
                      input.annualMotorcycleMilesHundredths!,
                )
        : input.actualVehicleExpensesMinor;
    final profit = math.max(
      0,
      input.turnoverMinor - input.nonVehicleExpensesMinor - vehicle,
    );
    final allowance = math.max(
      0,
      1257000 - math.max(0, profit - 10000000) ~/ 2,
    );
    final taxable = math.max(0, profit - allowance);
    // Non-savings bands measured after the tapered personal allowance.
    final basic = math.min(taxable, 3770000);
    final higher = math.min(math.max(0, taxable - basic), 8744000);
    final additional = math.max(0, taxable - basic - higher);
    int percent(int amount, int rate) => (amount * rate + 50) ~/ 100;
    final incomeTax =
        percent(basic, 20) + percent(higher, 40) + percent(additional, 45);
    final class4 =
        percent(math.min(math.max(0, profit - 1257000), 3770000), 6) +
        percent(math.max(0, profit - 5027000), 2);
    final outstanding = math.max(0, incomeTax + class4 - input.paidToHmrcMinor);
    return TaxEstimate(
      profitMinor: profit,
      personalAllowanceMinor: allowance,
      incomeTaxMinor: incomeTax,
      class4Minor: class4,
      vehicleDeductionMinor: vehicle,
      outstandingMinor: outstanding,
      reserveShortfallMinor: math.max(0, outstanding - input.reserveMinor),
    );
  }
}

class MileageEntry {
  final String id;
  final DateTime date;
  final int milesHundredths;
  final String purpose;
  final String vehicle;
  final String vehicleType;
  const MileageEntry({
    required this.id,
    required this.date,
    required this.milesHundredths,
    required this.purpose,
    required this.vehicle,
    required this.vehicleType,
  });

  factory MileageEntry.fromMap(Map<String, dynamic> row) => MileageEntry(
    id: row['id'] as String,
    date: DateTime.parse(row['journey_date'] as String),
    milesHundredths: (row['miles_hundredths'] as num).toInt(),
    purpose: row['purpose'] as String,
    vehicle: row['vehicle'] as String,
    vehicleType: row['vehicle_type'] as String,
  );
}

({int carVan, int motorcycle}) mileageTotals(Iterable<MileageEntry> entries) {
  final milesByVehicle = <String, int>{};
  final types = <String, String>{};
  for (final entry in entries) {
    if (entry.date.isBefore(SoleTraderTaxRules.start) ||
        !entry.date.isBefore(SoleTraderTaxRules.end)) {
      continue;
    }
    if (entry.milesHundredths <= 0 ||
        !const ['car_van', 'motorcycle'].contains(entry.vehicleType)) {
      throw const FormatException('Review the mileage log.');
    }
    final key = entry.vehicle.trim().toLowerCase();
    if (types.containsKey(key) && types[key] != entry.vehicleType) {
      throw const FormatException(
        'Use the same vehicle type for each vehicle in the mileage log.',
      );
    }
    types[key] = entry.vehicleType;
    milesByVehicle.update(
      key,
      (value) => value + entry.milesHundredths,
      ifAbsent: () => entry.milesHundredths,
    );
  }
  // ITTOIA 2005 s94F(3): the 10,000-mile higher band is shared by all
  // qualifying cars/goods vehicles in the trade, not renewed per vehicle.
  var carMiles = 0;
  var motorcycleMiles = 0;
  for (final entry in milesByVehicle.entries) {
    if (types[entry.key] == 'motorcycle') {
      motorcycleMiles += entry.value;
    } else {
      carMiles += entry.value;
    }
  }
  return (carVan: carMiles, motorcycle: motorcycleMiles);
}

int mileageAllowanceMinor({
  required int carVanMilesHundredths,
  required int motorcycleMilesHundredths,
}) {
  if (carVanMilesHundredths < 0 ||
      motorcycleMilesHundredths < 0 ||
      carVanMilesHundredths > 100000000 ||
      motorcycleMilesHundredths > 100000000) {
    throw const FormatException('Enter annual miles between 0 and 1,000,000.');
  }
  final first = math.min(carVanMilesHundredths, 1000000);
  return (first * 55 +
          (carVanMilesHundredths - first) * 25 +
          motorcycleMilesHundredths * 24 +
          50) ~/
      100;
}

int mileageDeductionMinor(Iterable<MileageEntry> entries) {
  final totals = mileageTotals(entries);
  return mileageAllowanceMinor(
    carVanMilesHundredths: totals.carVan,
    motorcycleMilesHundredths: totals.motorcycle,
  );
}
