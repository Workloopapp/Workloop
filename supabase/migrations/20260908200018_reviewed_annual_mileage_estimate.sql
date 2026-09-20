-- Forecasts are reviewed annual inputs, separate from actual journey records.
-- Nullable keeps old saved estimates readable until the owner reviews them.
alter table public.workspace_tax_estimates
  add column annual_car_van_miles_hundredths bigint
    check (annual_car_van_miles_hundredths between 0 and 100000000),
  add column annual_motorcycle_miles_hundredths bigint
    check (annual_motorcycle_miles_hundredths between 0 and 100000000),
  add constraint annual_mileage_pair check (
    (annual_car_van_miles_hundredths is null) =
    (annual_motorcycle_miles_hundredths is null)
  );
comment on column public.workspace_tax_estimates.annual_car_van_miles_hundredths is
  'Owner-reviewed whole-year business mileage forecast, not a journey record. Includes actual logged miles.';
comment on column public.workspace_tax_estimates.annual_motorcycle_miles_hundredths is
  'Owner-reviewed whole-year motorcycle mileage forecast; zero when none, null until reviewed.';
