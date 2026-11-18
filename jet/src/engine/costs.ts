/**
 * Cost model (from the pitch's stated inputs): EUROCONTROL diversion costs of €55k (narrow-body)
 * and €82k (wide-body); holding fuel at $181/bbl; delay at €100 a minute; €1 = AED 4.13.
 */
export const EUR_AED = 4.13;
export const USD_AED = 3.6725;
export const DIVERSION_AED = { narrow: 55_000 * EUR_AED, wide: 82_000 * EUR_AED };
const KG_PER_BBL = 159 * 0.8; // litres per barrel × jet fuel density
export const FUEL_AED_PER_KG = (181 / KG_PER_BBL) * USD_AED;
export const DELAY_AED_PER_MIN = 100 * EUR_AED;

export function aed(n: number): string {
  if (Math.abs(n) >= 1e6) return `AED ${(n / 1e6).toFixed(1)}M`;
  if (Math.abs(n) >= 1e3) return `AED ${Math.round(n / 1e3).toLocaleString('en-US')}k`;
  return `AED ${Math.round(n)}`;
}
