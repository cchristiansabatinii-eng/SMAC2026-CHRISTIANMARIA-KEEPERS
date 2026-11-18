import { rng } from './rng';

/**
 * Range forecaster: every ETA is a calibrated interval, not a point.
 * The base model's error grows with time-to-go; split-conformal calibration on a held-out
 * set of past residuals scales the interval so that ~90% of actual times fall inside it.
 */
export interface EtaRange {
  lo: number;
  mid: number;
  hi: number;
}

const BASE_SIGMA_S = 35;
const PER_MIN_S = 4.5;

function scale(ttgMin: number): number {
  return BASE_SIGMA_S + PER_MIN_S * Math.max(0, ttgMin);
}

/** Residual generator standing in for history (fat-tailed: mostly small, some large). */
function syntheticResidual(r: () => number, ttgMin: number): number {
  const u = r();
  const z = Math.sqrt(-2 * Math.log(r() + 1e-9)) * Math.cos(2 * Math.PI * r());
  const tail = u < 0.08 ? 2.2 : 1;
  return z * scale(ttgMin) * tail;
}

export function calibrate(coverage = 0.9, n = 800, seed = 11): { q: number; coverage: number; n: number } {
  const r = rng(seed);
  const scores: number[] = [];
  for (let i = 0; i < n; i++) {
    const ttg = r() * 60;
    scores.push(Math.abs(syntheticResidual(r, ttg)) / scale(ttg));
  }
  scores.sort((a, b) => a - b);
  const k = Math.min(n - 1, Math.ceil((n + 1) * coverage) - 1);
  return { q: scores[k], coverage, n };
}

/** Measures empirical coverage of the calibrated interval on fresh residuals. */
export function testCoverage(q: number, n = 2000, seed = 99): number {
  const r = rng(seed);
  let inside = 0;
  for (let i = 0; i < n; i++) {
    const ttg = r() * 60;
    if (Math.abs(syntheticResidual(r, ttg)) <= q * scale(ttg)) inside++;
  }
  return inside / n;
}

const CAL = calibrate();
export const CONFORMAL_Q = CAL.q;

export function etaRange(eta: number, now: number): EtaRange {
  const ttg = (eta - now) / 60;
  const half = CONFORMAL_Q * scale(ttg);
  return { lo: eta - half, mid: eta, hi: eta + half };
}

/**
 * Fuel estimator: a 1-D Kalman filter on endurance (minutes to final reserve).
 * Predict: endurance falls 1 min per minute flown, uncertainty grows with the burn model's error.
 * Update: a fuel report on the radio ("fuel for 40 minutes") is a noisy measurement.
 */
export interface FuelState {
  mean: number;
  sigma: number;
}

export function fuelPredict(s: FuelState, dtSec: number, burnFactor = 1): FuelState {
  const dtMin = dtSec / 60;
  const q = 0.03 * dtMin; // process noise variance per minute
  return { mean: s.mean - dtMin * burnFactor, sigma: Math.sqrt(s.sigma * s.sigma + q) };
}

export function fuelUpdate(s: FuelState, measured: number, measSigma = 2): FuelState {
  const p = s.sigma * s.sigma;
  const rr = measSigma * measSigma;
  const k = p / (p + rr);
  return { mean: s.mean + k * (measured - s.mean), sigma: Math.sqrt((1 - k) * p) };
}
