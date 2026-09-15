"""Build the Financial Case (sheets 7 and 8) of the 2026 Energy Challenge student workbook.

Everything calculated is a formula that traces back to the Inputs sheet. Only the
yellow cells hold typed numbers.
"""
import sys
import openpyxl
from openpyxl.styles import Font, PatternFill, Border, Side, Alignment
from openpyxl.utils import get_column_letter
from openpyxl.chart import BarChart, LineChart, Reference, Series
from openpyxl.chart.label import DataLabelList
from openpyxl.formatting.rule import CellIsRule

SRC = sys.argv[1]
OUT = sys.argv[2]

wb = openpyxl.load_workbook(SRC)

# ----------------------------------------------------------------- styles
NAVY = "FF0B365F"
TEAL = "FF007A87"
YELLOW = "FFFFF2CC"
GREEN = "FFE2EFDA"
GREY_TXT = "FF555555"
RED_TXT = "FFB00020"

F_LABEL = Font(name="Calibri", size=11)
F_BOLD = Font(name="Calibri", size=11, bold=True)
F_TITLE = Font(name="Calibri", size=14, bold=True, color=NAVY)
F_SECTION = Font(name="Calibri", size=11, bold=True, color=TEAL)
F_HDR = Font(name="Calibri", size=11, bold=True, color="FFFFFFFF")
F_NOTE = Font(name="Calibri", size=9, color=GREY_TXT)
F_WARN = Font(name="Calibri", size=9, bold=True, color=RED_TXT)

FILL_NAVY = PatternFill("solid", fgColor=NAVY)
FILL_TEAL = PatternFill("solid", fgColor=TEAL)
FILL_YELLOW = PatternFill("solid", fgColor=YELLOW)
FILL_GREEN = PatternFill("solid", fgColor=GREEN)
FILL_NONE = PatternFill(fill_type=None)

THIN = Side(style="thin", color="FFBFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
NO_BORDER = Border()

NF_USD = '#,##0;(#,##0);"-"'
NF_USD2 = '#,##0.00;(#,##0.00);"-"'
NF_NUM = '#,##0;(#,##0);"-"'
NF_NUM1 = '#,##0.0;(#,##0.0);"-"'
NF_NUM2 = '#,##0.00;(#,##0.00);"-"'
NF_PCT = '0.0%;(0.0%);"-"'
NF_PCT0 = '0%'
NF_YEAR = '0'
NF_YRS = '0.0'
NF_GEN = 'General'


def put(ws, ref, value, font=F_LABEL, fill=None, nf=None, border=None, align=None, wrap=False):
    c = ws[ref]
    c.value = value
    c.font = font
    c.fill = fill if fill is not None else FILL_NONE
    if nf:
        c.number_format = nf
    c.border = border if border is not None else NO_BORDER
    if align or wrap:
        c.alignment = Alignment(horizontal=align, vertical="center" if wrap else None, wrap_text=wrap)
    return c


def hdr(ws, ref, text, fill=FILL_NAVY, wrap=False):
    return put(ws, ref, text, font=F_HDR, fill=fill, border=BORDER, wrap=wrap)


def section(ws, row, text, first_col=2, last_col=5):
    for col in range(first_col, last_col + 1):
        put(ws, f"{get_column_letter(col)}{row}", text if col == first_col else None, font=F_HDR, fill=FILL_TEAL)


def inp(ws, ref, value, nf=NF_GEN):
    return put(ws, ref, value, fill=FILL_YELLOW, nf=nf, border=BORDER)


def res(ws, ref, formula, nf=NF_USD):
    return put(ws, ref, formula, fill=FILL_GREEN, nf=nf, border=BORDER)


def note(ws, ref, text):
    return put(ws, ref, text, font=F_NOTE)


def clear_range(ws, min_row, max_row, min_col=1, max_col=40):
    for row in ws.iter_rows(min_row=min_row, max_row=max_row, min_col=min_col, max_col=max_col):
        for c in row:
            c.value = None
            c.fill = FILL_NONE
            c.border = NO_BORDER
            c.font = F_LABEL
            c.number_format = NF_GEN


# ------------------------------------------------------------ Inputs sheet
wsI = wb["2. Inputs"]
IN = "'2. Inputs'"


def I(row):
    return f"{IN}!$C${row}"


# Existing data-pack inputs (row numbers on the Inputs sheet)
IT, PUE, CHILL, TOWER, UPS, LIGHT, COPCH, TCOND, HOURS = 6, 7, 8, 9, 10, 11, 12, 13, 14
QDEM, TDEM, BOIL, HDEM, LOSS, COP = 16, 17, 18, 19, 20, 21
ELEC, GEF, GAS, GASEF, CARB = 23, 24, 25, 26, 27
CAPEX, OM, LIFE, DR, CONST, AVAIL = 29, 30, 31, 32, 33, 34
WMAKEUP, WPRICE = 36, 37

# Added financial-case inputs
S1, S2, KJKG, PRORATA, TARIFF, BFRAC, BCAPKW, BCONST, BS1, BS2 = range(44, 54)
GJMWH, KJGJ, KGT, KWMW, KGM3 = 55, 56, 57, 58, 59

section(wsI, 43, "FINANCIAL CASE ADDITIONS (used by sheets 7 and 8)", 2, 5)
added = [
    (S1, "Capex spend share, construction year 1", 0.4, "fraction", "Data pack: spend 40:60 over 24 months"),
    (S2, "Capex spend share, construction year 2", 0.6, "fraction", "Must sum to 1 with the row above. Checked on sheet 7."),
    (KJKG, "Heat rejected per kg of tower water evaporated", 2400, "kJ/kg", "Data pack Section 07: about 2,400 kJ per kg"),
    (PRORATA, "Tower and pump power saved pro rata with heat diverted", 1, "fraction", "Assumption. 1 = fully pro rata (variable-speed fans and pumps), 0 = no saving. Tested on sheet 8 through the drivers."),
    (TARIFF, "Heat tariff as share of neighbour's avoided gas cost", 1, "fraction", "Assumption. 1 = whole gas saving counted, the pack's basis. Below 1 shares the value with the neighbour."),
    (BFRAC, "Option B: cooling energy saved by plant optimisation", 0.15, "fraction", "Data pack technology table: 8 to 18 per cent of cooling energy"),
    (BCAPKW, "Option B: capital cost per kW of IT load", 250, "USD/kW IT", "Data pack technology table: USD 150 to 400 per kW of IT"),
    (BCONST, "Option B: construction period", 1, "years", "Assumption: controls and set-point work on live plant, one year"),
    (BS1, "Option B: capex spend share, year 1", 1, "fraction", "Assumption: all spent in the single construction year"),
    (BS2, "Option B: capex spend share, year 2", 0, "fraction", ""),
]
for r, label, val, unit, src in added:
    put(wsI, f"B{r}", label)
    inp(wsI, f"C{r}", val)
    put(wsI, f"D{r}", unit)
    if src:
        note(wsI, f"E{r}", src)
section(wsI, 54, "CONVERSIONS (data pack Section 07)", 2, 5)
conv = [
    (GJMWH, "Gigajoules per megawatt-hour", 3.6, "GJ/MWh", "1 MWh = 3.6 GJ"),
    (KJGJ, "Kilojoules per gigajoule", 1000000, "kJ/GJ", "1 GJ = 1,000 MJ = 1,000,000 kJ"),
    (KGT, "Kilograms per tonne", 1000, "kg/t", "1 t = 1,000 kg"),
    (KWMW, "Kilowatts per megawatt", 1000, "kW/MW", "1 MW = 1,000 kW"),
    (KGM3, "Kilograms per cubic metre of make-up water", 1000, "kg/m3", "Assumption: water density at ambient, near enough"),
]
for r, label, val, unit, src in conv:
    put(wsI, f"B{r}", label)
    inp(wsI, f"C{r}", val)
    put(wsI, f"D{r}", unit)
    note(wsI, f"E{r}", src)
note(wsI, "B61", "Sheets 7 and 8 reference rows 44 to 59. Sheet 7 shows a warning if this block is missing after a merge.")
N_ADDED = 15  # numeric cells in C44:C59

# ---------------------------------------------------------------- Sheet 7
ws = wb["7. Cash Flow"]
CF = "'7. Cash Flow'"
clear_range(ws, 5, 200, 1, 40)

ws.column_dimensions["B"].width = 54
ws.column_dimensions["C"].width = 19
for col in range(4, 27):
    ws.column_dimensions[get_column_letter(col)].width = 13

YEARS = list(range(0, 23))  # year 0 to year 22 = 2 construction + 20 operating
Y0COL = 4                   # column D holds year 0
YL = {y: get_column_letter(Y0COL + y) for y in YEARS}
FIRST, LAST = YL[YEARS[0]], YL[YEARS[-1]]

# ---- Row map (assigned first so formulas can cross-reference)
R = {}
r = 5
R["hdr"] = r
key_rows = [
    ("gross", "Annual gross saving (USD/yr)"),
    ("elec", "Electricity you spend to deliver the heat (USD/yr)"),
    ("om", "Annual operating and maintenance cost (USD/yr)"),
    ("net", "Annual net saving (USD/yr)"),
    ("spb", "Simple payback (years)"),
    ("af", "Annuity factor"),
    ("npv", "Net present value (USD)"),
    ("lcoh", "Levelised cost of delivered heat (USD/GJ)"),
    ("irr", "Internal rate of return (%/yr)"),
    ("dpb", "Discounted payback (years from decision)"),
    ("cpb", "Payback from the cash flow (years from decision)"),
    ("pi", "Profitability index (PV of operating cash / PV of capital)"),
    ("capex", "Total capital (USD)"),
    ("pvcap", "Present value of capital at the decision date (USD)"),
    ("npvchk", "NPV cross-check by the annuity method (USD)"),
    ("avoided", "Avoided cost of the heat displaced, incl. carbon price (USD/GJ)"),
    ("lcohnet", "Levelised cost of heat net of water and tower credits (USD/GJ)"),
    ("margin", "Margin: avoided cost less levelised cost (USD/GJ)"),
    ("co2", "Net CO2 avoided (t CO2/yr)"),
    ("water", "Water saved (m3/yr)"),
    ("billshare", "Net saving as share of the campus electricity bill (%)"),
    ("perit", "Net saving per MWh of computing sold (USD/MWh IT)"),
]
for k, _ in key_rows:
    r += 1
    R[k] = r
r += 2
R["check"] = r
r += 1
R["reco"] = r
r += 2
R["timing"] = r          # timing convention header, 4 note lines below
r += 6
R["cf_hdr"] = r          # cash flow section header
R["cf_year"] = r + 1
cf_rows = [
    ("df", "Discount factor at the WACC", "–"),
    ("A_sec", "OPTION A: HEAT PUMP AND NETWORK TO THE CLUSTER", None),
    ("A_share", "Capex phasing share", "fraction"),
    ("A_flag", "Operating year flag (1 = plant running)", "0/1"),
    ("A_capex", "Capital expenditure", "USD"),
    ("A_gross", "Gross saving", "USD"),
    ("A_elec", "Heat pump electricity", "USD"),
    ("A_om", "Operating and maintenance", "USD"),
    ("A_net", "Net cash flow", "USD"),
    ("A_disc", "Discounted cash flow", "USD"),
    ("A_cum", "Cumulative net cash flow", "USD"),
    ("A_cumd", "Cumulative discounted cash flow", "USD"),
    ("B_sec", "OPTION B: COOLING PLANT OPTIMISATION", None),
    ("B_share", "Capex phasing share", "fraction"),
    ("B_flag", "Operating year flag (1 = measures in place)", "0/1"),
    ("B_capex", "Capital expenditure", "USD"),
    ("B_gross", "Gross saving", "USD"),
    ("B_om", "Operating and maintenance", "USD"),
    ("B_net", "Net cash flow", "USD"),
    ("B_disc", "Discounted cash flow", "USD"),
    ("B_cum", "Cumulative net cash flow", "USD"),
    ("B_cumd", "Cumulative discounted cash flow", "USD"),
    ("C_sec", "A + B TOGETHER", None),
    ("C_net", "Net cash flow", "USD"),
    ("C_disc", "Discounted cash flow", "USD"),
    ("C_cum", "Cumulative net cash flow", "USD"),
    ("C_cumd", "Cumulative discounted cash flow", "USD"),
]
rr = R["cf_year"]
for k, _, _ in cf_rows:
    rr += 1
    R[k] = rr
R["cf_end"] = rr
R["chart"] = rr + 2       # cash flow chart anchor, ~22 rows tall
R["drvA_hdr"] = rr + 26
# Driver rows for option A
drvA = [
    ("a_qdem", "Heat demand served at the cluster", "MW", f"={I(QDEM)}", "The only firm demand identified. Sheet 8 flexes it.", NF_NUM1),
    ("a_hours", "Hours of demand a year", "h/yr", f"={I(HDEM)}", "Cluster hours, not campus hours.", NF_NUM),
    ("a_avail", "System availability", "fraction", f"={I(AVAIL)}", "When the heat pump is down the boilers run, so only available hours displace gas.", NF_PCT),
    ("a_deliv", "Heat delivered to the cluster", "MWh/yr", "={a_qdem}*{a_hours}*{a_avail}", "Energy = power x time x availability. This is the heat that displaces gas.", NF_NUM),
    ("a_loss", "Network loss over the 1.8 km run", "fraction", f"={I(LOSS)}", "Heat lost in the buried pipe must be made at the campus but is not sold.", NF_PCT),
    ("a_sent", "Heat leaving the campus heat pump", "MWh/yr", "={a_deliv}/(1-{a_loss})", "Delivered = sent x (1 - loss), so sent = delivered / (1 - loss).", NF_NUM),
    ("a_size", "Heat pump output rating needed", "MW heat", "={a_qdem}/(1-{a_loss})", "Sizing check against the capital cost. Compare with USD 700 to 1,400 per kW heat.", NF_NUM1),
    ("a_cop", "Heat pump coefficient of performance", "–", f"={I(COP)}", "Heat out per unit of electricity in, 40 to 80 degrees C.", NF_NUM2),
    ("a_hpe", "Heat pump electricity", "MWh/yr", "={a_sent}/{a_cop}", "Electricity in = heat out / COP. This is the cost of the lift.", NF_NUM),
    ("a_drawn", "Heat drawn from the condenser loop", "MWh/yr", "={a_sent}-{a_hpe}", "Heat in = heat out - electricity. This is what the towers no longer reject.", NF_NUM),
    ("a_rej", "Heat rejected by the whole campus today", "MWh/yr", f"=({I(IT)}+{I(UPS)}+{I(LIGHT)}+{I(CHILL)})*{I(HOURS)}", "Cooling load (IT, UPS, lighting) plus chiller power, about 121.5 MW, times campus hours.", NF_NUM),
    ("a_divshare", "Share of rejected heat diverted to the heat pump", "fraction", "={a_drawn}/{a_rej}", "Used to pro-rate tower fan and pump power and make-up water.", NF_PCT),
    ("a_tow", "Tower and pump electricity saved", "MWh/yr", f"={I(TOWER)}*{I(HOURS)}*{{a_divshare}}*{I(PRORATA)}", "Pro rata with the heat diverted, scaled by the Inputs assumption.", NF_NUM),
    ("a_water", "Make-up water saved", "m3/yr", f"={{a_drawn}}*{I(GJMWH)}*{I(KJGJ)}/{I(KJKG)}/{I(KGM3)}", "Heat not evaporated in the towers, at 2,400 kJ per kg of water.", NF_NUM),
    ("a_boil", "Neighbour's boiler efficiency", "fraction", f"={I(BOIL)}", "Fuel = useful heat / efficiency, so every MWh delivered displaces more than a MWh of gas.", NF_PCT),
    ("a_gasgj", "Gas displaced at the neighbour", "GJ/yr", f"={{a_deliv}}*{I(GJMWH)}/{{a_boil}}", "Delivered heat in GJ divided by boiler efficiency.", NF_NUM),
    ("a_gasusd", "Neighbour's avoided gas cost", "USD/yr", f"={{a_gasgj}}*{I(GAS)}", "Gas displaced x gas price.", NF_USD),
    ("a_tariff", "Heat tariff as share of avoided gas cost", "fraction", f"={I(TARIFF)}", "How much of the gas saving Falaj captures. 1 = all of it, the pack's basis.", NF_PCT),
    ("a_heatval", "Value of heat delivered (gas displacement saving)", "USD/yr", "={a_gasusd}*{a_tariff}", "The main revenue line.", NF_USD),
    ("a_waterusd", "Water saving", "USD/yr", f"={{a_water}}*{I(WPRICE)}", "Make-up water saved x water price.", NF_USD),
    ("a_towusd", "Tower and pump electricity saving", "USD/yr", f"={{a_tow}}*{I(ELEC)}", "Tower electricity saved x electricity price.", NF_USD),
    ("a_co2n", "CO2 avoided at the neighbour (their Scope 1)", "t CO2/yr", f"={{a_gasgj}}*{I(GASEF)}/{I(KGT)}", "Gas displaced x gas emission factor, converted from kg to t.", NF_NUM),
    ("a_co2c", "CO2 added at the campus, net of tower saving (Scope 2)", "t CO2/yr", f"=({{a_hpe}}-{{a_tow}})*{I(GEF)}", "Heat pump electricity less tower electricity saved, x grid factor.", NF_NUM),
    ("a_co2", "Net CO2 avoided", "t CO2/yr", "={a_co2n}-{a_co2c}", "Neighbour's reduction less the campus's increase. Do not count the same tonne twice.", NF_NUM),
    ("a_carbusd", "Carbon value at the carbon price", "USD/yr", f"={{a_co2}}*{I(CARB)}", "Nil in the base case. Sheet 8 tests up to USD 100 per tonne.", NF_USD),
    ("a_elecusd", "Heat pump electricity cost", "USD/yr", f"={{a_hpe}}*{I(ELEC)}", "The electricity you spend to make the heat useful. Subtracted from the saving.", NF_USD),
    ("a_omusd", "Operating and maintenance cost", "USD/yr", f"={I(CAPEX)}*{I(OM)}", "3 per cent of capital a year.", NF_USD),
    ("a_gross", "Gross saving", "USD/yr", "={a_heatval}+{a_waterusd}+{a_towusd}+{a_carbusd}", "All benefits before the cost of running the plant.", NF_USD),
    ("a_net", "Net saving", "USD/yr", "={a_gross}-{a_elecusd}-{a_omusd}", "Gross saving less heat pump electricity and O&M. This feeds the cash flow.", NF_USD),
    ("a_delivgj", "Heat delivered", "GJ/yr", f"={{a_deliv}}*{I(GJMWH)}", "Denominator for the unit cost of heat.", NF_NUM),
    ("a_anncap", "Annualised capital", "USD/yr", f"={CF}!$C${R['pvcap']}*(1+{I(DR)})^{I(CONST)}/{CF}!$C${R['af']}", "PV of capital carried to the start of operations, spread over the life with the annuity factor.", NF_USD),
    ("a_lcoh", "Levelised cost of delivered heat", "USD/GJ", "=({a_anncap}+{a_elecusd}+{a_omusd})/{a_delivgj}", "(Annualised capital + electricity + O&M) / heat delivered.", NF_NUM2),
    ("a_lcohnet", "Levelised cost of heat net of water and tower credits", "USD/GJ", "=({a_anncap}+{a_elecusd}+{a_omusd}-{a_waterusd}-{a_towusd})/{a_delivgj}", "Same, crediting the by-product savings against the cost.", NF_NUM2),
    ("a_avoided", "Avoided cost of the heat displaced, incl. carbon price", "USD/GJ", f"=({I(GAS)}+{I(GASEF)}/{I(KGT)}*{I(CARB)})/{I(BOIL)}", "(Gas price + carbon cost per GJ of gas) / boiler efficiency. What the neighbour pays per GJ of useful heat.", NF_NUM2),
    ("a_margin", "Margin: avoided cost less levelised cost", "USD/GJ", "={a_avoided}-{a_lcohnet}", "Positive means the recovered heat is cheaper than gas.", NF_NUM2),
]
rr = R["drvA_hdr"] + 1
for k, *_ in drvA:
    rr += 1
    R[k] = rr
R["drvB_hdr"] = rr + 2
drvB = [
    ("b_cool", "Cooling plant electrical power today", "MW", f"={I(CHILL)}+{I(TOWER)}", "Chillers plus towers and pumps.", NF_NUM1),
    ("b_coolmwh", "Cooling energy today", "MWh/yr", f"={{b_cool}}*{I(HOURS)}", "Power x campus hours.", NF_NUM),
    ("b_frac", "Cooling energy saved by optimisation", "fraction", f"={I(BFRAC)}", "Data pack: 8 to 18 per cent. Sheet 8 flexes it.", NF_PCT),
    ("b_esaved", "Electricity saved", "MWh/yr", "={b_coolmwh}*{b_frac}", "Cooling energy x fraction saved.", NF_NUM),
    ("b_eval", "Electricity cost saved", "USD/yr", f"={{b_esaved}}*{I(ELEC)}", "Electricity saved x price. Rises with the electricity price, the opposite of Option A.", NF_USD),
    ("b_chshare", "Chiller share of cooling power", "fraction", f"={I(CHILL)}/{{b_cool}}", "Chiller drive power ends up in the condenser water; fan power does not.", NF_PCT),
    ("b_rejless", "Heat no longer rejected", "MWh/yr", "={b_esaved}*{b_chshare}", "Only the chiller-power share of the saving reduces tower duty.", NF_NUM),
    ("b_water", "Make-up water saved", "m3/yr", f"={{b_rejless}}*{I(GJMWH)}*{I(KJGJ)}/{I(KJKG)}/{I(KGM3)}", "At 2,400 kJ per kg evaporated.", NF_NUM),
    ("b_waterusd", "Water saving", "USD/yr", f"={{b_water}}*{I(WPRICE)}", "", NF_USD),
    ("b_co2", "CO2 avoided (campus Scope 2)", "t CO2/yr", f"={{b_esaved}}*{I(GEF)}", "Electricity saved x grid factor.", NF_NUM),
    ("b_carbusd", "Carbon value at the carbon price", "USD/yr", f"={{b_co2}}*{I(CARB)}", "", NF_USD),
    ("b_capex", "Capital cost", "USD", f"={I(BCAPKW)}*{I(IT)}*{I(KWMW)}", "USD per kW of IT x IT load in kW.", NF_USD),
    ("b_omusd", "Operating and maintenance cost", "USD/yr", f"={{b_capex}}*{I(OM)}", "Same 3 per cent basis as Option A.", NF_USD),
    ("b_gross", "Gross saving", "USD/yr", "={b_eval}+{b_waterusd}+{b_carbusd}", "", NF_USD),
    ("b_net", "Net saving", "USD/yr", "={b_gross}-{b_omusd}", "No electricity is spent, so net = gross less O&M.", NF_USD),
]
rr = R["drvB_hdr"] + 1
for k, *_ in drvB:
    rr += 1
    R[k] = rr
R["notes"] = rr + 2


def C(k):
    """Absolute reference to the value cell (column C) of a named driver row on sheet 7."""
    return f"$C${R[k]}"


def fmt(formula):
    return formula.format(**{k: C(k) for k in R})


# ---- Key results block
put(ws, f"B{R['hdr']}", "KEY RESULTS", font=F_SECTION)
hdr(ws, f"C{R['hdr']}", "Option A: heat pump + network", wrap=True)
hdr(ws, f"D{R['hdr']}", "Option B: cooling plant optimisation", wrap=True)
hdr(ws, f"E{R['hdr']}", "A + B together", wrap=True)
put(ws, f"F{R['hdr']}", "How each figure is built", font=F_NOTE)
ws.row_dimensions[R["hdr"]].height = 30
for k, label in key_rows:
    put(ws, f"B{R[k]}", label)

yr_row = R["cf_year"]


def cf_range(k):
    return f"${FIRST}${R[k]}:${LAST}${R[k]}"


def payback_formula(cum_key, cf_key, opt_tag):
    """Fractional year in which the cumulative row turns non-negative, from the cash flow rows."""
    cum = cf_range(cum_key)
    cf = cf_range(cf_key)
    n = f"COUNTIF({cum},\"<0\")"
    # year 0 sits at index 1. n negative years -> crossing happens in year n+1 (index n+2)
    return (f"=IF({n}>={I(CONST)}+{I(LIFE)},\"Not within life\","
            f"{n}+(-INDEX({cum},{n}+1))/INDEX({cf},{n}+2))")


def payback_formula_B(cum_key, cf_key):
    cum = cf_range(cum_key)
    cf = cf_range(cf_key)
    n = f"COUNTIF({cum},\"<0\")"
    return (f"=IF({n}>={I(BCONST)}+{I(LIFE)},\"Not within life\","
            f"{n}+(-INDEX({cum},{n}+1))/INDEX({cf},{n}+2))")


def payback_formula_C(cum_key, cf_key):
    cum = cf_range(cum_key)
    cf = cf_range(cf_key)
    n = f"COUNTIF({cum},\"<0\")"
    return (f"=IF({n}>=MAX({I(CONST)},{I(BCONST)})+{I(LIFE)},\"Not within life\","
            f"{n}+(-INDEX({cum},{n}+1))/INDEX({cf},{n}+2))")


# Option A column C
res(ws, f"C{R['gross']}", f"={C('a_gross')}")
res(ws, f"C{R['elec']}", f"={C('a_elecusd')}")
res(ws, f"C{R['om']}", f"={C('a_omusd')}")
res(ws, f"C{R['net']}", f"=C{R['gross']}-C{R['elec']}-C{R['om']}")
res(ws, f"C{R['spb']}", f"=IF(C{R['net']}>0,C{R['capex']}/C{R['net']},\"Never\")", NF_YRS)
res(ws, f"C{R['af']}", f"=(1-(1+{I(DR)})^(-{I(LIFE)}))/{I(DR)}", NF_NUM2)
res(ws, f"C{R['npv']}", f"=SUM({cf_range('A_disc')})")
res(ws, f"C{R['lcoh']}", f"={C('a_lcoh')}", NF_NUM2)
res(ws, f"C{R['irr']}", f"=IFERROR(IRR({cf_range('A_net')}),\"n/a\")", NF_PCT)
res(ws, f"C{R['dpb']}", payback_formula("A_cumd", "A_disc", "A"), NF_YRS)
res(ws, f"C{R['cpb']}", payback_formula("A_cum", "A_net", "A"), NF_YRS)
res(ws, f"C{R['pi']}", f"=IF(C{R['pvcap']}>0,(C{R['npv']}+C{R['pvcap']})/C{R['pvcap']},\"n/a\")", NF_NUM2)
res(ws, f"C{R['capex']}", f"={I(CAPEX)}")
res(ws, f"C{R['pvcap']}", f"=-SUMPRODUCT({cf_range('A_capex')},{cf_range('df')})")
res(ws, f"C{R['npvchk']}", f"=-C{R['pvcap']}+C{R['net']}*C{R['af']}/(1+{I(DR)})^{I(CONST)}")
res(ws, f"C{R['avoided']}", f"={C('a_avoided')}", NF_NUM2)
res(ws, f"C{R['lcohnet']}", f"={C('a_lcohnet')}", NF_NUM2)
res(ws, f"C{R['margin']}", f"={C('a_margin')}", NF_NUM2)
res(ws, f"C{R['co2']}", f"={C('a_co2')}", NF_NUM)
res(ws, f"C{R['water']}", f"={C('a_water')}", NF_NUM)
BILL = f"({I(IT)}*{I(PUE)}*{I(HOURS)}*{I(ELEC)})"
res(ws, f"C{R['billshare']}", f"=C{R['net']}/{BILL}", NF_PCT)
res(ws, f"C{R['perit']}", f"=C{R['net']}/({I(IT)}*{I(HOURS)})", NF_NUM2)

# Option B column D
res(ws, f"D{R['gross']}", f"={C('b_gross')}")
res(ws, f"D{R['elec']}", "=0")
res(ws, f"D{R['om']}", f"={C('b_omusd')}")
res(ws, f"D{R['net']}", f"=D{R['gross']}-D{R['elec']}-D{R['om']}")
res(ws, f"D{R['spb']}", f"=IF(D{R['net']}>0,D{R['capex']}/D{R['net']},\"Never\")", NF_YRS)
res(ws, f"D{R['af']}", f"=C{R['af']}", NF_NUM2)
res(ws, f"D{R['npv']}", f"=SUM({cf_range('B_disc')})")
put(ws, f"D{R['lcoh']}", "n/a, no heat sold", fill=FILL_GREEN, border=BORDER, font=F_NOTE)
res(ws, f"D{R['irr']}", f"=IFERROR(IRR({cf_range('B_net')}),\"n/a\")", NF_PCT)
res(ws, f"D{R['dpb']}", payback_formula_B("B_cumd", "B_disc"), NF_YRS)
res(ws, f"D{R['cpb']}", payback_formula_B("B_cum", "B_net"), NF_YRS)
res(ws, f"D{R['pi']}", f"=IF(D{R['pvcap']}>0,(D{R['npv']}+D{R['pvcap']})/D{R['pvcap']},\"n/a\")", NF_NUM2)
res(ws, f"D{R['capex']}", f"={C('b_capex')}")
res(ws, f"D{R['pvcap']}", f"=-SUMPRODUCT({cf_range('B_capex')},{cf_range('df')})")
res(ws, f"D{R['npvchk']}", f"=-D{R['pvcap']}+D{R['net']}*D{R['af']}/(1+{I(DR)})^{I(BCONST)}")
for k in ("avoided", "lcohnet", "margin"):
    put(ws, f"D{R[k]}", "n/a", fill=FILL_GREEN, border=BORDER, font=F_NOTE)
res(ws, f"D{R['co2']}", f"={C('b_co2')}", NF_NUM)
res(ws, f"D{R['water']}", f"={C('b_water')}", NF_NUM)
res(ws, f"D{R['billshare']}", f"=D{R['net']}/{BILL}", NF_PCT)
res(ws, f"D{R['perit']}", f"=D{R['net']}/({I(IT)}*{I(HOURS)})", NF_NUM2)

# A + B column E
for k in ("gross", "elec", "om", "net", "capex", "pvcap", "npv", "npvchk", "co2", "water"):
    nf = NF_NUM if k in ("co2", "water") else NF_USD
    res(ws, f"E{R[k]}", f"=C{R[k]}+D{R[k]}", nf)
res(ws, f"E{R['spb']}", f"=IF(E{R['net']}>0,E{R['capex']}/E{R['net']},\"Never\")", NF_YRS)
res(ws, f"E{R['af']}", f"=C{R['af']}", NF_NUM2)
put(ws, f"E{R['lcoh']}", "n/a", fill=FILL_GREEN, border=BORDER, font=F_NOTE)
res(ws, f"E{R['irr']}", f"=IFERROR(IRR({cf_range('C_net')}),\"n/a\")", NF_PCT)
res(ws, f"E{R['dpb']}", payback_formula_C("C_cumd", "C_disc"), NF_YRS)
res(ws, f"E{R['cpb']}", payback_formula_C("C_cum", "C_net"), NF_YRS)
res(ws, f"E{R['pi']}", f"=IF(E{R['pvcap']}>0,(E{R['npv']}+E{R['pvcap']})/E{R['pvcap']},\"n/a\")", NF_NUM2)
for k in ("avoided", "lcohnet", "margin"):
    put(ws, f"E{R[k]}", "n/a", fill=FILL_GREEN, border=BORDER, font=F_NOTE)
res(ws, f"E{R['billshare']}", f"=E{R['net']}/{BILL}", NF_PCT)
res(ws, f"E{R['perit']}", f"=E{R['net']}/({I(IT)}*{I(HOURS)})", NF_NUM2)

how = {
    "gross": "Sum of the benefit lines in the driver blocks below: heat value, water, tower power, carbon.",
    "elec": "Heat pump electricity (MWh) x electricity price. Option B spends none.",
    "om": "Capital x O&M percentage from the Inputs sheet.",
    "net": "Gross saving less electricity less O&M. The level annual figure that feeds the cash flow.",
    "spb": "Pack definition: capital divided by annual net benefit. Ignores the two-year build.",
    "af": "[1 - (1 + r)^-n] / r with r the discount rate and n the project life.",
    "npv": "Sum of the discounted cash flow row in the table below.",
    "lcoh": "(Annualised capital + electricity + O&M) / GJ of heat delivered. Compare with the avoided cost row.",
    "irr": "Excel IRR of the net cash flow row. The discount rate at which NPV is zero.",
    "dpb": "Year in which cumulative discounted cash turns positive, interpolated within the year.",
    "cpb": "Same on undiscounted cash. Differs from simple payback because capital is spent before operations begin.",
    "pi": "PV of operating cash divided by PV of capital. Above 1.0 means value is created.",
    "capex": "From the Inputs sheet (A) or USD per kW of IT x IT load (B).",
    "pvcap": "Capital phased over construction, discounted to the decision date.",
    "npvchk": "-PV(capital) + net saving x annuity factor, discounted back over the build. Must equal the NPV row.",
    "avoided": "(Gas price + carbon cost per GJ) / boiler efficiency. What the cluster pays per GJ of useful heat today.",
    "lcohnet": "Levelised cost with water and tower credits netted off.",
    "margin": "Positive means recovered heat undercuts gas. Negative means it does not, whatever the NPV says.",
    "co2": "Neighbour's gas emissions avoided less the campus's extra grid emissions (A); grid emissions avoided (B).",
    "water": "Tower make-up water no longer evaporated.",
    "billshare": "Net saving / (IT load x PUE x hours x electricity price). Puts the prize in proportion.",
    "perit": "Net saving / MWh of IT computing a year.",
}
for k, txt in how.items():
    note(ws, f"F{R[k]}", txt)

# Check and recommendation
put(ws, f"B{R['check']}", "Inputs link check")
put(ws, f"C{R['check']}",
    f"=IF(AND(COUNT({IN}!$C$44:$C$59)={N_ADDED},ABS({I(S1)}+{I(S2)}-1)<0.0001,ABS({I(BS1)}+{I(BS2)}-1)<0.0001),"
    f"\"OK: financial inputs found on the Inputs sheet, rows 44 to 59, and capex phasing sums to 1\","
    f"\"WARNING: Inputs rows 44 to 59 are missing or the capex phasing shares do not sum to 1\")",
    fill=FILL_GREEN, border=BORDER, font=F_BOLD)
put(ws, f"B{R['reco']}", "Recommendation in one sentence (rewrites itself from the results)", font=F_BOLD)
put(ws, f"C{R['reco']}",
    f"=\"At the current inputs Option A, the heat pump and network, returns an NPV of USD \"&TEXT(C{R['npv']},\"#,##0\")"
    f"&\" and an IRR of \"&IF(ISNUMBER(C{R['irr']}),TEXT(C{R['irr']},\"0.0%\"),\"n/a\")&\" against a \"&TEXT({I(DR)},\"0%\")"
    f"&\" hurdle, so on the money alone it \"&IF(C{R['npv']}>0,\"clears\",\"does not clear\")&\" the hurdle; Option B, cooling plant optimisation, returns USD \""
    f"&TEXT(D{R['npv']},\"#,##0\")&\" at an IRR of \"&IF(ISNUMBER(D{R['irr']}),TEXT(D{R['irr']},\"0.0%\"),\"n/a\")&\" and \"&IF(D{R['npv']}>0,\"clears\",\"does not clear\")&\" it.\"",
    fill=FILL_GREEN, border=BORDER)

# Timing convention
put(ws, f"B{R['timing']}", "TIMING CONVENTION", font=F_SECTION)
tl = [
    "Year 0 is the decision date and carries no cash. Capital is spent in years 1 and 2 in the Inputs phasing shares (40:60).",
    "Operations run from the year after construction ends (year 3) for the project life (20 years), so the table runs to year 22.",
    "Cash flows fall at the end of each year and are discounted at the WACC: discount factor = 1 / (1 + r)^year.",
    "All operating years carry the same steady-state saving. No escalation of prices is assumed; sheet 8 flexes the prices instead.",
    "Option B follows the same rules with its own construction period and phasing from the Inputs sheet.",
]
for i, t in enumerate(tl):
    note(ws, f"B{R['timing'] + 1 + i}", t)

# ---- Cash flow table
put(ws, f"B{R['cf_hdr']}", "ANNUAL CASH FLOW (USD)", font=F_SECTION)
put(ws, f"B{yr_row}", "Line", font=F_HDR, fill=FILL_NAVY, border=BORDER)
hdr(ws, f"C{yr_row}", "Unit / Year")
for y in YEARS:
    put(ws, f"{YL[y]}{yr_row}", y, font=F_HDR, fill=FILL_NAVY, nf=NF_YEAR, border=BORDER, align="center")

for k, label, unit in cf_rows:
    row = R[k]
    if unit is None:
        section(ws, row, label, 2, Y0COL + len(YEARS) - 1)
        continue
    put(ws, f"B{row}", label, font=F_BOLD if k.endswith("_net") or k == "df" else F_LABEL)
    put(ws, f"C{row}", unit, font=F_NOTE, align="center")

for y in YEARS:
    col = YL[y]
    yref = f"{col}${yr_row}"
    res(ws, f"{col}{R['df']}", f"=1/(1+{I(DR)})^{yref}", "0.0000")
    # Option A
    res(ws, f"{col}{R['A_share']}", f"=IF({yref}=1,{I(S1)},IF({yref}=2,{I(S2)},0))", NF_PCT)
    res(ws, f"{col}{R['A_flag']}", f"=IF(AND({yref}>={I(CONST)}+1,{yref}<={I(CONST)}+{I(LIFE)}),1,0)", NF_YEAR)
    res(ws, f"{col}{R['A_capex']}", f"=-{I(CAPEX)}*{col}{R['A_share']}")
    res(ws, f"{col}{R['A_gross']}", f"={C('a_gross')}*{col}{R['A_flag']}")
    res(ws, f"{col}{R['A_elec']}", f"=-{C('a_elecusd')}*{col}{R['A_flag']}")
    res(ws, f"{col}{R['A_om']}", f"=-{C('a_omusd')}*{col}{R['A_flag']}")
    res(ws, f"{col}{R['A_net']}", f"=SUM({col}{R['A_capex']}:{col}{R['A_om']})")
    res(ws, f"{col}{R['A_disc']}", f"={col}{R['A_net']}*{col}{R['df']}")
    prev = YL[y - 1] if y > 0 else None
    res(ws, f"{col}{R['A_cum']}", f"={col}{R['A_net']}" if prev is None else f"={prev}{R['A_cum']}+{col}{R['A_net']}")
    res(ws, f"{col}{R['A_cumd']}", f"={col}{R['A_disc']}" if prev is None else f"={prev}{R['A_cumd']}+{col}{R['A_disc']}")
    # Option B
    res(ws, f"{col}{R['B_share']}", f"=IF({yref}=1,{I(BS1)},IF({yref}=2,{I(BS2)},0))", NF_PCT)
    res(ws, f"{col}{R['B_flag']}", f"=IF(AND({yref}>={I(BCONST)}+1,{yref}<={I(BCONST)}+{I(LIFE)}),1,0)", NF_YEAR)
    res(ws, f"{col}{R['B_capex']}", f"=-{C('b_capex')}*{col}{R['B_share']}")
    res(ws, f"{col}{R['B_gross']}", f"={C('b_gross')}*{col}{R['B_flag']}")
    res(ws, f"{col}{R['B_om']}", f"=-{C('b_omusd')}*{col}{R['B_flag']}")
    res(ws, f"{col}{R['B_net']}", f"=SUM({col}{R['B_capex']}:{col}{R['B_om']})")
    res(ws, f"{col}{R['B_disc']}", f"={col}{R['B_net']}*{col}{R['df']}")
    res(ws, f"{col}{R['B_cum']}", f"={col}{R['B_net']}" if prev is None else f"={prev}{R['B_cum']}+{col}{R['B_net']}")
    res(ws, f"{col}{R['B_cumd']}", f"={col}{R['B_disc']}" if prev is None else f"={prev}{R['B_cumd']}+{col}{R['B_disc']}")
    # A + B
    res(ws, f"{col}{R['C_net']}", f"={col}{R['A_net']}+{col}{R['B_net']}")
    res(ws, f"{col}{R['C_disc']}", f"={col}{R['C_net']}*{col}{R['df']}")
    res(ws, f"{col}{R['C_cum']}", f"={col}{R['C_net']}" if prev is None else f"={prev}{R['C_cum']}+{col}{R['C_net']}")
    res(ws, f"{col}{R['C_cumd']}", f"={col}{R['C_disc']}" if prev is None else f"={prev}{R['C_cumd']}+{col}{R['C_disc']}")

# ---- Cash flow chart (columns = net cash flow, line = cumulative discounted, secondary axis)
put(ws, f"B{R['chart'] - 1}", "CHART: CASH FLOW OVER THE LIFE, OPTION A (columns net cash flow, line cumulative discounted cash on the right axis)", font=F_SECTION)
cats = Reference(ws, min_col=Y0COL, max_col=Y0COL + len(YEARS) - 1, min_row=yr_row)
bar = BarChart()
bar.type = "col"
bar.title = "Option A: net cash flow and cumulative discounted cash flow (USD)"
bar.y_axis.title = "Net cash flow (USD)"
bar.x_axis.title = "Year from decision"
s = Series(Reference(ws, min_col=Y0COL, max_col=Y0COL + len(YEARS) - 1, min_row=R["A_net"]), title="Net cash flow")
bar.series.append(s)
bar.set_categories(cats)
bar.y_axis.number_format = '#,##0'
bar.y_axis.majorGridlines = None
line = LineChart()
s2 = Series(Reference(ws, min_col=Y0COL, max_col=Y0COL + len(YEARS) - 1, min_row=R["A_cumd"]), title="Cumulative discounted cash flow")
line.series.append(s2)
line.y_axis.axId = 200
line.y_axis.title = "Cumulative discounted (USD)"
line.y_axis.number_format = '#,##0'
line.y_axis.crosses = "max"
bar += line
bar.height = 10
bar.width = 26
bar.legend.position = "b"
ws.add_chart(bar, f"B{R['chart']}")

# Option B chart alongside
bar2 = BarChart()
bar2.type = "col"
bar2.title = "Option B: net cash flow and cumulative discounted cash flow (USD)"
bar2.y_axis.title = "Net cash flow (USD)"
bar2.x_axis.title = "Year from decision"
bar2.series.append(Series(Reference(ws, min_col=Y0COL, max_col=Y0COL + len(YEARS) - 1, min_row=R["B_net"]), title="Net cash flow"))
bar2.set_categories(cats)
bar2.y_axis.number_format = '#,##0'
bar2.y_axis.majorGridlines = None
line2 = LineChart()
line2.series.append(Series(Reference(ws, min_col=Y0COL, max_col=Y0COL + len(YEARS) - 1, min_row=R["B_cumd"]), title="Cumulative discounted cash flow"))
line2.y_axis.axId = 200
line2.y_axis.title = "Cumulative discounted (USD)"
line2.y_axis.number_format = '#,##0'
line2.y_axis.crosses = "max"
bar2 += line2
bar2.height = 10
bar2.width = 26
bar2.legend.position = "b"
ws.add_chart(bar2, f"O{R['chart']}")

# ---- Driver blocks
def driver_block(hdr_row, title, rows):
    section(ws, hdr_row, title, 2, 5)
    hdr(ws, f"B{hdr_row + 1}", "Step")
    hdr(ws, f"C{hdr_row + 1}", "Value")
    hdr(ws, f"D{hdr_row + 1}", "Unit")
    hdr(ws, f"E{hdr_row + 1}", "Why this line is here")
    for k, label, unit, formula, why, nf in rows:
        row = R[k]
        put(ws, f"B{row}", label)
        res(ws, f"C{row}", fmt(formula), nf)
        put(ws, f"D{row}", unit, font=F_NOTE, align="center")
        note(ws, f"E{row}", why)


driver_block(R["drvA_hdr"], "ANNUAL DRIVERS, OPTION A: HEAT PUMP AND 1.8 km NETWORK TO THE CLUSTER (one steady-state operating year, from the Inputs sheet)", drvA)
driver_block(R["drvB_hdr"], "ANNUAL DRIVERS, OPTION B: COOLING PLANT OPTIMISATION (same basis, so the two can be compared)", drvB)

# ---- Notes and assumptions
put(ws, f"B{R['notes']}", "ASSUMPTIONS MADE ON THIS SHEET (copy into the assumption register, sheet 9)", font=F_SECTION)
notes = [
    "1. Timing: year 0 = decision, capital in years 1 and 2 at 40:60, operations years 3 to 22. End-of-year discounting at the WACC.",
    "2. Only available hours displace gas: heat delivered = demand x cluster hours x availability. When the heat pump is down the boilers run.",
    "3. The whole avoided gas cost is counted as the saving (heat tariff share = 1), which is the pack's basis. A tariff below the avoided cost shares value with the neighbour; sheet 8 tests it.",
    "4. Tower fan and pump power falls pro rata with the heat the heat pump takes off the condenser loop (Inputs row 47). Set it to 0 to remove the credit.",
    "5. Make-up water saved is the diverted heat at 2,400 kJ per kg evaporated (pack Section 07), priced at the make-up water rate.",
    "6. Carbon: the neighbour's gas emissions fall (their Scope 1); the campus's grid emissions rise (Scope 2). Only the net tonnes are valued, at the carbon price, nil in the base case.",
    "7. Capital for Option A is the pack's USD 14 m as supplied. The heat pump rating needed (row 'Heat pump output rating needed') lets you check it against USD 700 to 1,400 per kW heat plus USD 1 to 2 m per km of pipe.",
    "8. Option B: 15 per cent of cooling energy saved at USD 250 per kW of IT, both inside the pack's ranges, built in one year, 3 per cent O&M. Chiller-power savings also cut tower water; fan-power savings do not.",
    "9. No price escalation, no tax, no residual value, no degradation. A + B is a plain sum, which assumes the two measures do not interact.",
    "10. The driver blocks re-derive heat and electricity quantities from the Inputs sheet so this sheet stands alone. Re-point them to sheet 4 once the Working sheet is complete if you prefer a single chain.",
]
for i, t in enumerate(notes):
    note(ws, f"B{R['notes'] + 1 + i}", t)
note(ws, f"B{R['notes'] + len(notes) + 2}", "Required chart from this sheet: columns for the yearly cash flow with a cumulative line crossing zero. It sits below the cash flow table.")

# ---------------------------------------------------------------- Sheet 8
wsS = wb["8. Sensitivity"]
SN = "'8. Sensitivity'"
clear_range(wsS, 5, 300, 1, 60)
wsS.column_dimensions["B"].width = 46
for col in "CDE":
    wsS.column_dimensions[col].width = 13
for col in "FGHIJKLMNO":
    wsS.column_dimensions[col].width = 15
wsS.column_dimensions["J"].width = 26
wsS.column_dimensions["O"].width = 26

put(wsS, "B3", "Low, base and high for each variable, one at a time with everything else at base. Base values link to the Inputs sheet so the table follows any edit a judge makes there. The widest swing is the largest exposure. Watch electricity price: it moves Options A and B in opposite directions.", font=F_NOTE)

SH = 5
heads = ["Variable", "Low case", "Base case", "High case",
         "NPV low, Option A (USD)", "NPV high, Option A (USD)", "Swing, Option A (USD)", "Break-even value, Option A", "Break-even inside tested range?",
         "NPV low, Option B (USD)", "NPV high, Option B (USD)", "Swing, Option B (USD)", "Break-even value, Option B", "Break-even inside tested range?"]
for i, h in enumerate(heads):
    hdr(wsS, f"{get_column_letter(2 + i)}{SH}", h, wrap=True)
wsS.row_dimensions[SH].height = 45

# variable table: key, label, low, high, base formula, number format, linearity kind
variables = [
    ("elec", "Electricity price (USD/MWh)", 50, 130, f"={I(ELEC)}", NF_NUM1, "lin"),
    ("capexA", "Capital cost, Option A (USD)", 10000000, 34000000, f"={I(CAPEX)}", NF_USD, "lin"),
    ("qdem", "Heat demand served (MW)", 6, 20, f"={I(QDEM)}", NF_NUM1, "lin"),
    ("cop", "Heat pump COP", 2.8, 3.6, f"={I(COP)}", NF_NUM2, "inv"),
    ("boil", "Neighbour's boiler efficiency (fraction)", 0.85, 0.92, f"={I(BOIL)}", NF_PCT, "inv"),
    ("dr", "Discount rate (fraction)", 0.06, 0.12, f"={I(DR)}", NF_PCT, "irr"),
    ("carb", "Carbon price (USD/t CO2)", 0, 100, f"={I(CARB)}", NF_NUM1, "lin"),
    ("bfrac", "PUE improvement achieved (cooling energy saved, Option B)", 0.08, 0.20, f"={I(BFRAC)}", NF_PCT, "lin"),
    ("gas", "Natural gas price at the neighbour (USD/GJ)", 6, 12, f"={I(GAS)}", NF_NUM1, "lin"),
    ("tariff", "Heat tariff share of avoided gas cost", 0.6, 1.0, f"={I(TARIFF)}", NF_PCT, "lin"),
]
VROW = {}
for i, (k, label, lo, hi, base, nf, kind) in enumerate(variables):
    row = SH + 1 + i
    VROW[k] = row
    put(wsS, f"B{row}", label)
    inp(wsS, f"C{row}", lo, nf)
    res(wsS, f"D{row}", base, nf)
    inp(wsS, f"E{row}", hi, nf)
V_FIRST, V_LAST = SH + 1, SH + len(variables)

# ---- Scenario engine
ENG = V_LAST + 4
put(wsS, f"B{ENG - 1}", "SCENARIO ENGINE. Each column recomputes the two NPVs with one variable moved and everything else at base. The results table above reads from here.", font=F_SECTION)

scen_cols = []  # (col_letter, name, var_key or None, which: 'lo'|'hi'|'be_A'|'be_B'|None)
c = 3
scen_cols.append((get_column_letter(c), "Base", None, None)); c += 1
for k, label, *_ in variables:
    scen_cols.append((get_column_letter(c), f"{k} low", k, "lo")); c += 1
    scen_cols.append((get_column_letter(c), f"{k} high", k, "hi")); c += 1
for k, label, *_ in variables:
    scen_cols.append((get_column_letter(c), f"{k} at break-even A", k, "be_A")); c += 1
for k, label, *_ in variables:
    scen_cols.append((get_column_letter(c), f"{k} at break-even B", k, "be_B")); c += 1

E = {}
erows = [
    ("name", "Scenario", None),
    ("elec", "Electricity price", "USD/MWh"),
    ("capexA", "Capital cost, Option A", "USD"),
    ("qdem", "Heat demand served", "MW"),
    ("cop", "Heat pump COP", "–"),
    ("boil", "Boiler efficiency", "fraction"),
    ("dr", "Discount rate", "fraction"),
    ("carb", "Carbon price", "USD/t"),
    ("bfrac", "Cooling energy saved, Option B", "fraction"),
    ("gas", "Gas price", "USD/GJ"),
    ("tariff", "Heat tariff share", "fraction"),
    ("a_deliv", "A: heat delivered", "MWh/yr"),
    ("a_sent", "A: heat sent from the heat pump", "MWh/yr"),
    ("a_hpe", "A: heat pump electricity", "MWh/yr"),
    ("a_drawn", "A: heat drawn from the condenser loop", "MWh/yr"),
    ("a_tow", "A: tower and pump electricity saved", "MWh/yr"),
    ("a_water", "A: make-up water saved", "m3/yr"),
    ("a_gasgj", "A: gas displaced", "GJ/yr"),
    ("a_heatval", "A: value of heat delivered", "USD/yr"),
    ("a_waterusd", "A: water saving", "USD/yr"),
    ("a_towusd", "A: tower electricity saving", "USD/yr"),
    ("a_co2", "A: net CO2 avoided", "t/yr"),
    ("a_carbusd", "A: carbon value", "USD/yr"),
    ("a_elecusd", "A: heat pump electricity cost", "USD/yr"),
    ("a_omusd", "A: O&M", "USD/yr"),
    ("a_net", "A: net annual saving", "USD/yr"),
    ("af", "Annuity factor", "–"),
    ("a_pvcap", "A: PV of capital at decision", "USD"),
    ("a_npv", "A: NPV", "USD"),
    ("b_esaved", "B: electricity saved", "MWh/yr"),
    ("b_water", "B: make-up water saved", "m3/yr"),
    ("b_co2", "B: CO2 avoided", "t/yr"),
    ("b_capex", "B: capital cost", "USD"),
    ("b_net", "B: net annual saving", "USD/yr"),
    ("b_pvcap", "B: PV of capital at decision", "USD"),
    ("b_npv", "B: NPV", "USD"),
]
for i, (k, label, unit) in enumerate(erows):
    E[k] = ENG + i
    put(wsS, f"B{E[k]}", label, font=F_BOLD if k in ("a_npv", "b_npv", "name") else F_LABEL)
put(wsS, f"B{ENG - 1}", wsS[f"B{ENG - 1}"].value, font=F_SECTION)

driver_base = {
    "elec": f"={I(ELEC)}", "capexA": f"={I(CAPEX)}", "qdem": f"={I(QDEM)}", "cop": f"={I(COP)}",
    "boil": f"={I(BOIL)}", "dr": f"={I(DR)}", "carb": f"={I(CARB)}", "bfrac": f"={I(BFRAC)}",
    "gas": f"={I(GAS)}", "tariff": f"={I(TARIFF)}",
}
driver_nf = {"elec": NF_NUM1, "capexA": NF_USD, "qdem": NF_NUM1, "cop": NF_NUM2, "boil": NF_PCT, "dr": NF_PCT,
             "carb": NF_NUM1, "bfrac": NF_PCT, "gas": NF_NUM1, "tariff": NF_PCT}

for col, name, vk, which in scen_cols:
    def e(k):
        return f"{col}${E[k]}"
    put(wsS, f"{col}{E['name']}", name, font=F_HDR, fill=FILL_NAVY, border=BORDER, wrap=True)
    for dk in driver_base:
        if vk == dk and which == "lo":
            f = f"=$C${VROW[dk]}"
        elif vk == dk and which == "hi":
            f = f"=$E${VROW[dk]}"
        elif vk == dk and which == "be_A":
            f = f"=IF(ISNUMBER($I${VROW[dk]}),$I${VROW[dk]},$D${VROW[dk]})"
        elif vk == dk and which == "be_B":
            f = f"=IF(ISNUMBER($N${VROW[dk]}),$N${VROW[dk]},$D${VROW[dk]})"
        else:
            f = driver_base[dk]
        res(wsS, f"{col}{E[dk]}", f, driver_nf[dk])
    # Option A chain
    res(wsS, f"{col}{E['a_deliv']}", f"={e('qdem')}*{I(HDEM)}*{I(AVAIL)}", NF_NUM)
    res(wsS, f"{col}{E['a_sent']}", f"={e('a_deliv')}/(1-{I(LOSS)})", NF_NUM)
    res(wsS, f"{col}{E['a_hpe']}", f"={e('a_sent')}/{e('cop')}", NF_NUM)
    res(wsS, f"{col}{E['a_drawn']}", f"={e('a_sent')}-{e('a_hpe')}", NF_NUM)
    res(wsS, f"{col}{E['a_tow']}", f"={I(TOWER)}*{I(HOURS)}*{e('a_drawn')}/(({I(IT)}+{I(UPS)}+{I(LIGHT)}+{I(CHILL)})*{I(HOURS)})*{I(PRORATA)}", NF_NUM)
    res(wsS, f"{col}{E['a_water']}", f"={e('a_drawn')}*{I(GJMWH)}*{I(KJGJ)}/{I(KJKG)}/{I(KGM3)}", NF_NUM)
    res(wsS, f"{col}{E['a_gasgj']}", f"={e('a_deliv')}*{I(GJMWH)}/{e('boil')}", NF_NUM)
    res(wsS, f"{col}{E['a_heatval']}", f"={e('a_gasgj')}*{e('gas')}*{e('tariff')}", NF_USD)
    res(wsS, f"{col}{E['a_waterusd']}", f"={e('a_water')}*{I(WPRICE)}", NF_USD)
    res(wsS, f"{col}{E['a_towusd']}", f"={e('a_tow')}*{e('elec')}", NF_USD)
    res(wsS, f"{col}{E['a_co2']}", f"={e('a_gasgj')}*{I(GASEF)}/{I(KGT)}-({e('a_hpe')}-{e('a_tow')})*{I(GEF)}", NF_NUM)
    res(wsS, f"{col}{E['a_carbusd']}", f"={e('a_co2')}*{e('carb')}", NF_USD)
    res(wsS, f"{col}{E['a_elecusd']}", f"={e('a_hpe')}*{e('elec')}", NF_USD)
    res(wsS, f"{col}{E['a_omusd']}", f"={e('capexA')}*{I(OM)}", NF_USD)
    res(wsS, f"{col}{E['a_net']}", f"={e('a_heatval')}+{e('a_waterusd')}+{e('a_towusd')}+{e('a_carbusd')}-{e('a_elecusd')}-{e('a_omusd')}", NF_USD)
    res(wsS, f"{col}{E['af']}", f"=(1-(1+{e('dr')})^(-{I(LIFE)}))/{e('dr')}", NF_NUM2)
    res(wsS, f"{col}{E['a_pvcap']}", f"={e('capexA')}*({I(S1)}/(1+{e('dr')})+{I(S2)}/(1+{e('dr')})^2)", NF_USD)
    res(wsS, f"{col}{E['a_npv']}", f"=-{e('a_pvcap')}+{e('a_net')}*{e('af')}/(1+{e('dr')})^{I(CONST)}", NF_USD)
    # Option B chain
    res(wsS, f"{col}{E['b_esaved']}", f"=({I(CHILL)}+{I(TOWER)})*{I(HOURS)}*{e('bfrac')}", NF_NUM)
    res(wsS, f"{col}{E['b_water']}", f"={e('b_esaved')}*{I(CHILL)}/({I(CHILL)}+{I(TOWER)})*{I(GJMWH)}*{I(KJGJ)}/{I(KJKG)}/{I(KGM3)}", NF_NUM)
    res(wsS, f"{col}{E['b_co2']}", f"={e('b_esaved')}*{I(GEF)}", NF_NUM)
    res(wsS, f"{col}{E['b_capex']}", f"={I(BCAPKW)}*{I(IT)}*{I(KWMW)}", NF_USD)
    res(wsS, f"{col}{E['b_net']}", f"={e('b_esaved')}*{e('elec')}+{e('b_water')}*{I(WPRICE)}+{e('b_co2')}*{e('carb')}-{e('b_capex')}*{I(OM)}", NF_USD)
    res(wsS, f"{col}{E['b_pvcap']}", f"={e('b_capex')}*({I(BS1)}/(1+{e('dr')})+{I(BS2)}/(1+{e('dr')})^2)", NF_USD)
    res(wsS, f"{col}{E['b_npv']}", f"=-{e('b_pvcap')}+{e('b_net')}*{e('af')}/(1+{e('dr')})^{I(BCONST)}", NF_USD)
    wsS.column_dimensions[col].width = max(wsS.column_dimensions[col].width or 0, 14)

wsS.row_dimensions[E["name"]].height = 42
scen_lookup = {(vk, which): col for col, name, vk, which in scen_cols}
BASE_COL = scen_cols[0][0]
NPV_A_BASE = f"${BASE_COL}${E['a_npv']}"
NPV_B_BASE = f"${BASE_COL}${E['b_npv']}"

# Engine consistency check against sheet 7
CHK = E["b_npv"] + 2
put(wsS, f"B{CHK}", "Check: engine base NPV less sheet 7 NPV, Option A and Option B (must be 0)", font=F_BOLD)
res(wsS, f"C{CHK}", f"={NPV_A_BASE}-{CF}!$C${R['npv']}", NF_USD)
res(wsS, f"D{CHK}", f"={NPV_B_BASE}-{CF}!$D${R['npv']}", NF_USD)
put(wsS, f"E{CHK}", f"=IF(AND(ABS(C{CHK})<1,ABS(D{CHK})<1),\"OK\",\"MISMATCH\")", fill=FILL_GREEN, border=BORDER, font=F_BOLD)
note(wsS, f"B{CHK + 1}", "The engine uses the annuity method (level operating cash, capital phased over construction). Sheet 7 discounts year by year. They must agree to the dollar.")
note(wsS, f"B{CHK + 2}", "Break-even values are exact where NPV is linear in the variable (prices, capital, demand, carbon, tariff, cooling fraction), exact in 1/x for COP and boiler efficiency, and equal to the IRR for the discount rate. The 'at break-even' columns recompute NPV at that value as proof; they read about zero.")

# ---- Results table formulas
for k, label, lo, hi, base, nf, kind in variables:
    row = VROW[k]
    loA = f"${scen_lookup[(k, 'lo')]}${E['a_npv']}"
    hiA = f"${scen_lookup[(k, 'hi')]}${E['a_npv']}"
    loB = f"${scen_lookup[(k, 'lo')]}${E['b_npv']}"
    hiB = f"${scen_lookup[(k, 'hi')]}${E['b_npv']}"
    res(wsS, f"F{row}", f"={loA}")
    res(wsS, f"G{row}", f"={hiA}")
    res(wsS, f"H{row}", f"=ABS(G{row}-F{row})")
    res(wsS, f"K{row}", f"={loB}")
    res(wsS, f"L{row}", f"={hiB}")
    res(wsS, f"M{row}", f"=ABS(L{row}-K{row})")

    def be(lo_npv, hi_npv, irr_ref, col_out):
        if kind == "lin":
            f = f"=IF(ABS({hi_npv}-{lo_npv})<1,\"n/a, no effect\",C{row}-{lo_npv}*(E{row}-C{row})/({hi_npv}-{lo_npv}))"
        elif kind == "inv":
            inv = f"(1/C{row}-{lo_npv}*(1/E{row}-1/C{row})/({hi_npv}-{lo_npv}))"
            f = f"=IF(ABS({hi_npv}-{lo_npv})<1,\"n/a, no effect\",IF({inv}<=0,\"None, NPV never reaches zero\",1/{inv}))"
        else:  # discount rate: break-even is the IRR
            f = f"=IF(ISNUMBER({irr_ref}),{irr_ref},\"n/a, no IRR\")"
        res(wsS, f"{col_out}{row}", f, nf)
    be(loA, hiA, f"{CF}!$C${R['irr']}", "I")
    be(loB, hiB, f"{CF}!$D${R['irr']}", "N")
    for be_col, rng_col in (("I", "J"), ("N", "O")):
        put(wsS, f"{rng_col}{row}",
            f"=IF(ISNUMBER({be_col}{row}),IF(AND({be_col}{row}>=MIN(C{row}:E{row}),{be_col}{row}<=MAX(C{row}:E{row})),\"Yes\",\"No, extrapolated\"),\"\")",
            fill=FILL_GREEN, border=BORDER, font=F_NOTE)

RES_END = V_LAST
put(wsS, f"B{RES_END + 1}", "Base NPV, Option A (USD)", font=F_BOLD)
res(wsS, f"F{RES_END + 1}", f"={NPV_A_BASE}")
put(wsS, f"B{RES_END + 2}", "Base NPV, Option B (USD)", font=F_BOLD)
res(wsS, f"K{RES_END + 2}", f"={NPV_B_BASE}")
NPV_A_BASE_CELL = f"$F${RES_END + 1}"
NPV_B_BASE_CELL = f"$K${RES_END + 2}"

# ---- Tornado helper tables (sorted by swing) and charts
TOR = E["b_npv"] + 6
put(wsS, f"B{TOR - 1}", "TORNADO DATA, OPTION A. Sorted by swing with a unique rank so ties do not collide. Bars are NPV at low and high less base NPV.", font=F_SECTION)
th = ["Variable", "Rank", "Low case less base (USD)", "High case less base (USD)", "Swing (USD)"]
for i, h in enumerate(th):
    hdr(wsS, f"{get_column_letter(2 + i)}{TOR}", h, wrap=True)
wsS.row_dimensions[TOR].height = 30
# unique rank column beside the results table (column P) for A, Q for B
hdr(wsS, f"P{SH}", "Rank A", wrap=True)
hdr(wsS, f"Q{SH}", "Rank B", wrap=True)
wsS.column_dimensions["P"].width = 14
wsS.column_dimensions["Q"].width = 14
for k, *_ in variables:
    row = VROW[k]
    res(wsS, f"P{row}", f"=RANK(H{row},$H${V_FIRST}:$H${V_LAST})+COUNTIF($H${V_FIRST}:H{row},H{row})-1", NF_YEAR)
    res(wsS, f"Q{row}", f"=RANK(M{row},$M${V_FIRST}:$M${V_LAST})+COUNTIF($M${V_FIRST}:M{row},M{row})-1", NF_YEAR)

nvar = len(variables)
for i in range(nvar):
    row = TOR + 1 + i
    rank = i + 1
    m = f"MATCH({rank},$P${V_FIRST}:$P${V_LAST},0)"
    res(wsS, f"B{row}", f"=INDEX($B${V_FIRST}:$B${V_LAST},{m})", NF_GEN)
    res(wsS, f"C{row}", f"={rank}", NF_YEAR)
    res(wsS, f"D{row}", f"=INDEX($F${V_FIRST}:$F${V_LAST},{m})-{NPV_A_BASE_CELL}")
    res(wsS, f"E{row}", f"=INDEX($G${V_FIRST}:$G${V_LAST},{m})-{NPV_A_BASE_CELL}")
    res(wsS, f"F{row}", f"=INDEX($H${V_FIRST}:$H${V_LAST},{m})")
TOR_END = TOR + nvar

TORB = TOR_END + 3
put(wsS, f"B{TORB - 1}", "TORNADO DATA, OPTION B. Same construction.", font=F_SECTION)
for i, h in enumerate(th):
    hdr(wsS, f"{get_column_letter(2 + i)}{TORB}", h, wrap=True)
wsS.row_dimensions[TORB].height = 30
for i in range(nvar):
    row = TORB + 1 + i
    rank = i + 1
    m = f"MATCH({rank},$Q${V_FIRST}:$Q${V_LAST},0)"
    res(wsS, f"B{row}", f"=INDEX($B${V_FIRST}:$B${V_LAST},{m})", NF_GEN)
    res(wsS, f"C{row}", f"={rank}", NF_YEAR)
    res(wsS, f"D{row}", f"=INDEX($K${V_FIRST}:$K${V_LAST},{m})-{NPV_B_BASE_CELL}")
    res(wsS, f"E{row}", f"=INDEX($L${V_FIRST}:$L${V_LAST},{m})-{NPV_B_BASE_CELL}")
    res(wsS, f"F{row}", f"=INDEX($M${V_FIRST}:$M${V_LAST},{m})")
TORB_END = TORB + nvar


def tornado(anchor_row, data_row, title, anchor_col="H"):
    ch = BarChart()
    ch.type = "bar"
    ch.grouping = "clustered"
    ch.overlap = 100
    ch.gapWidth = 40
    ch.title = title
    ch.x_axis.title = None
    ch.y_axis.title = "Change in NPV from base (USD)"
    ch.y_axis.number_format = '#,##0'
    cats = Reference(wsS, min_col=2, min_row=data_row + 1, max_row=data_row + nvar)
    s_lo = Series(Reference(wsS, min_col=4, min_row=data_row + 1, max_row=data_row + nvar), title="Low case")
    s_hi = Series(Reference(wsS, min_col=5, min_row=data_row + 1, max_row=data_row + nvar), title="High case")
    ch.series.append(s_lo)
    ch.series.append(s_hi)
    ch.set_categories(cats)
    ch.x_axis.scaling.orientation = "maxMin"   # rank 1 at the top
    ch.x_axis.tickLblPos = "low"
    ch.height = 11
    ch.width = 24
    ch.legend.position = "b"
    wsS.add_chart(ch, f"{anchor_col}{anchor_row}")


tornado(TOR - 1, TOR, "Tornado, Option A: change in NPV from base (USD)")
tornado(TOR - 1, TORB, "Tornado, Option B: change in NPV from base (USD)", anchor_col="R")
note(wsS, f"H{TORB - 1}", "The Option B tornado sits to the right of the Option A tornado above.")

# ---- Carbon price ladder (exact: NPV is linear in the carbon price)
LAD = TORB_END + 3
put(wsS, f"B{LAD - 1}", "WHAT A CARBON PRICE DOES. NPV is linear in the carbon price, so each row is base NPV plus the slope from the engine times the price.", font=F_SECTION)
hdr(wsS, f"B{LAD}", "Carbon price (USD/t CO2)")
hdr(wsS, f"C{LAD}", "NPV A (USD)")
hdr(wsS, f"D{LAD}", "NPV B (USD)")
hdr(wsS, f"E{LAD}", "NPV A + B (USD)")
crow = VROW["carb"]
slopeA_c = f"(($G${crow}-$F${crow})/($E${crow}-$C${crow}))"
slopeB_c = f"(($L${crow}-$K${crow})/($E${crow}-$C${crow}))"
for i, cp in enumerate([0, 25, 45, 50, 75, 90, 100]):
    row = LAD + 1 + i
    inp(wsS, f"B{row}", cp, NF_NUM)
    res(wsS, f"C{row}", f"={NPV_A_BASE_CELL}+{slopeA_c}*(B{row}-$D${crow})")
    res(wsS, f"D{row}", f"={NPV_B_BASE_CELL}+{slopeB_c}*(B{row}-$D${crow})")
    res(wsS, f"E{row}", f"=C{row}+D{row}")
LAD_END = LAD + 7
note(wsS, f"B{LAD_END + 1}", "Bonus scenario A in the pack (USD 45 rising to 90) sits between the 45 and 90 rows. Electricity at USD 55 is read off the two-way table below.")

# ---- Two-way table: electricity price x gas price, Option A (exact by linearity)
TW = LAD_END + 4
put(wsS, f"B{TW - 1}", "TWO-WAY TABLE, OPTION A NPV (USD): ELECTRICITY PRICE DOWN THE SIDE, GAS PRICE ACROSS. NPV is linear in both prices with no cross term, so it is exact. Green cells are positive.", font=F_SECTION)
erow, grow = VROW["elec"], VROW["gas"]
slopeA_e = f"(($G${erow}-$F${erow})/($E${erow}-$C${erow}))"
slopeA_g = f"(($G${grow}-$F${grow})/($E${grow}-$C${grow}))"
hdr(wsS, f"B{TW}", "Electricity price (USD/MWh) \\ Gas price (USD/GJ)")
gas_vals = [6, 7, 8, 9, 10, 11, 12]
elec_vals = [50, 55, 60, 70, 80, 90, 100, 115, 130]
for j, g in enumerate(gas_vals):
    inp(wsS, f"{get_column_letter(3 + j)}{TW}", g, NF_NUM1)
for i, ev in enumerate(elec_vals):
    row = TW + 1 + i
    inp(wsS, f"B{row}", ev, NF_NUM1)
    for j in range(len(gas_vals)):
        col = get_column_letter(3 + j)
        res(wsS, f"{col}{row}", f"={NPV_A_BASE_CELL}+{slopeA_e}*($B{row}-$D${erow})+{slopeA_g}*({col}${TW}-$D${grow})")
TW_END = TW + len(elec_vals)
rng = f"C{TW + 1}:{get_column_letter(2 + len(gas_vals))}{TW_END}"
wsS.conditional_formatting.add(rng, CellIsRule(operator="greaterThan", formula=["0"], fill=PatternFill("solid", fgColor="FFC6EFCE"), font=Font(name="Calibri", size=11, color="FF006100")))
wsS.conditional_formatting.add(rng, CellIsRule(operator="lessThan", formula=["0"], fill=PatternFill("solid", fgColor="FFFFC7CE"), font=Font(name="Calibri", size=11, color="FF9C0006")))
note(wsS, f"B{TW_END + 1}", "Check one cell against the engine: the 80 / 9 cell must equal the base NPV of Option A.")
put(wsS, f"B{TW_END + 2}", "Check: table at base prices less base NPV (must be 0)", font=F_BOLD)
base_i = elec_vals.index(80)
base_j = gas_vals.index(9)
res(wsS, f"C{TW_END + 2}", f"={get_column_letter(3 + base_j)}{TW + 1 + base_i}-{NPV_A_BASE_CELL}")

note(wsS, f"B{TW_END + 4}", "Required chart from this sheet: a tornado, being a horizontal bar of each swing sorted with the largest at the top. Both tornados sit beside their data tables above.")

wb.save(OUT)
print("saved", OUT)
print("sheet7 rows:", {k: v for k, v in R.items()})
print("sheet8 vrows:", VROW, "engine start", ENG, "tornado", TOR, TORB, "ladder", LAD, "twoway", TW)
