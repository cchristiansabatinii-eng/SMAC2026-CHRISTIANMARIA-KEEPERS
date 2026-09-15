# 2026 SPE MENA Energy Efficiency Challenge, Case 02: Financial Case

This folder holds the team's working copy of the student workbook with the
**Financial Case** (Stage 05 of the student pack) completed: cash flow, returns,
sensitivity, break-even points and the effect of a carbon price.

File: `2026_Energy_Challenge_Case_Study_02_-_Student_Workbook_Financial_Case.xlsx`

## What was built

Every calculated cell is a formula that traces back to sheet `2. Inputs`.
Only yellow cells hold typed numbers. Change an input and everything, including
the charts, updates.

### Sheet `2. Inputs` (rows 43 to 61 added)

Two small blocks were appended below the data-pack inputs:

- **Financial case additions** (rows 44 to 53): capex phasing 40:60, tower
  evaporation rate (2,400 kJ/kg), tower-power pro-rata factor, heat tariff share
  of the neighbour's avoided gas cost, and the Option B parameters (cooling
  energy saved, USD per kW of IT, construction period, phasing).
- **Conversions** (rows 55 to 59): GJ per MWh, kJ per GJ, kg per tonne, kW per
  MW, kg per m3.

Sheets 7 and 8 reference these rows. Sheet 7 shows a warning in its
"Inputs link check" cell if the block is missing after a merge.

### Sheet `7. Cash Flow`

- **Key results** for Option A (heat pump and 1.8 km network to the cluster),
  Option B (cooling plant optimisation) and A + B: gross saving, electricity
  spent, O&M, net saving, simple payback, annuity factor, NPV, levelised cost of
  heat (USD/GJ), IRR, discounted payback, payback from the cash flow,
  profitability index, PV of capital, NPV cross-check by the annuity method,
  avoided cost of the heat displaced (USD/GJ), margin per GJ, net CO2 avoided,
  water saved, share of the campus electricity bill, saving per MWh of IT.
- A **recommendation sentence** that rewrites itself from the results.
- **Timing convention**: year 0 is the decision, capital in years 1 and 2,
  operations in years 3 to 22, end-of-year discounting at the WACC.
- **Annual cash flow table**, years 0 to 22, for A, B and A + B: capex,
  gross saving, electricity, O&M, net, discounted, cumulative, cumulative
  discounted.
- **Cash flow charts** (columns for net cash flow, cumulative discounted line
  on a secondary axis) for A and B.
- **Driver blocks** that derive the steady-state annual saving from the
  Inputs sheet one step per row with units, so the sheet stands alone until the
  Working sheet is complete.
- **Assumptions made on this sheet**, listed for copying into sheet 9.

### Sheet `8. Sensitivity`

- Ten variables, each with low, base (linked to Inputs) and high: electricity
  price, capital cost, heat demand served, heat pump COP, boiler efficiency,
  discount rate, carbon price, cooling energy saved (Option B), gas price, heat
  tariff share.
- NPV low, NPV high, swing and **break-even value** for both options, with a
  flag saying whether the break-even sits inside the tested range.
- A **scenario engine** that recomputes both NPVs for every case in its own
  column, plus proof columns that recompute NPV at each break-even value (they
  read zero) and a check that the engine agrees with sheet 7 to the dollar.
- Sorted **tornado tables and charts** for A and B.
- A **carbon price ladder** (0 to 100 USD/t) and a **two-way table** of
  Option A NPV against electricity price and gas price, both exact because NPV
  is linear in those prices.

## Base-case results (data-pack inputs)

| Measure | Option A: heat pump + network | Option B: cooling plant optimisation |
|---|---|---|
| Net annual saving | USD 0.96 m | USD 2.79 m |
| NPV at 8 % over 20 operating years | USD -4.27 m | USD +4.50 m |
| IRR | 3.1 % | 10.8 % |
| Simple payback | 14.5 years | 8.1 years |
| Levelised cost of heat | USD 13.4/GJ (11.8 net of credits) vs USD 10.2/GJ avoided gas | n/a |

Largest swings for Option A: capital cost, gas price, electricity price, heat
demand. Option A breaks even at roughly USD 61/MWh electricity, USD 10.4/GJ gas,
USD 10.2 m capital, 16.4 MW served, or a carbon price of about USD 49/t.

## How it was built

`build_financial_case.py` (kept alongside) takes the original blank workbook and
writes the formulas with openpyxl. The delivered file was then recalculated with
LibreOffice so cached values are present; 2,446 formulas, zero errors.
