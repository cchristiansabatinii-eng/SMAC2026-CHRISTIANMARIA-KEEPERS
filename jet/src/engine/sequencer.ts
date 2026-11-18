import { wakeSpacing } from './airport';
import { FUEL_MARGIN_MIN } from './safeHarbour';
import type { Flight, Runway } from './types';

export interface SeqItem {
  f: Flight;
  /** Earliest time it can be at the threshold. */
  earliest: number;
  /** Latest landing time before the fuel margin is eaten. */
  deadline: number;
  airborne: boolean;
  /** Runway forced by the plan, if any. */
  runway?: string;
}

export interface SeqEntry {
  id: string;
  runway: string;
  slot: number;
  delay: number; // s beyond earliest
}

export interface RunwayUse {
  id: string;
  rate: number; // arrivals per hour
  open: boolean;
  /** Departure take-off times that arrivals on this runway must keep 120 s away from. */
  departures: number[];
}

export const DEP_GAP_S = 120;

export function landingDeadline(f: Flight, now: number): number {
  return now + (f.fuelMin - FUEL_MARGIN_MIN) * 60;
}

export function runwayUses(runways: Runway[], depTimes: number[], arrRunways: string[]): RunwayUse[] {
  return runways
    .filter((r) => arrRunways.includes(r.id))
    .map((r) => ({ id: r.id, rate: r.rate, open: r.open, departures: r.role === 'arr' ? [] : depTimes }));
}

/**
 * Assigns slots in the given order. Each aircraft goes to the arrival runway that lands it
 * soonest, respecting wake spacing, the declared rate and any departures on that runway.
 */
export function assignSlots(order: SeqItem[], runways: RunwayUse[], now: number): SeqEntry[] {
  const last: Record<string, { t: number; f: Flight } | undefined> = {};
  const out: SeqEntry[] = [];
  const usable = runways.filter((r) => r.open && r.rate > 0);
  for (const it of order) {
    let best: SeqEntry | null = null;
    for (const rw of usable) {
      if (it.runway && it.runway !== rw.id) continue;
      const prev = last[rw.id];
      let t = Math.max(it.earliest, now + 60);
      if (prev) t = Math.max(t, prev.t + Math.max(wakeSpacing(prev.f.type, it.f.type), 3600 / rw.rate));
      // slide past departures
      for (let guard = 0; guard < 50; guard++) {
        const clash = rw.departures.find((d) => Math.abs(d - t) < DEP_GAP_S);
        if (clash === undefined) break;
        t = clash + DEP_GAP_S;
      }
      if (!best || t < best.slot) best = { id: it.f.id, runway: rw.id, slot: t, delay: t - it.earliest };
    }
    if (!best) {
      // forced runway is closed or missing: keep it on that runway so the checker sees it
      const rw = it.runway ?? 'none';
      const prev = last[rw];
      const t = Math.max(it.earliest, now + 60, prev ? prev.t + 90 : 0);
      best = { id: it.f.id, runway: rw, slot: t, delay: t - it.earliest };
    }
    last[best.runway] = { t: best.slot, f: it.f };
    out.push(best);
  }
  return out;
}

export interface SeqCost {
  delay: number;
  airborneDelay: number;
  lateness: number; // seconds past fuel deadlines (should be 0)
  late: number; // count
}

export function seqCost(order: SeqItem[], entries: SeqEntry[]): SeqCost {
  let delay = 0;
  let airborneDelay = 0;
  let lateness = 0;
  let late = 0;
  entries.forEach((e, i) => {
    delay += e.delay;
    if (order[i].airborne) airborneDelay += e.delay;
    const over = e.slot - order[i].deadline;
    if (over > 0) {
      lateness += over;
      late++;
    }
  });
  return { delay, airborneDelay, lateness, late };
}

function score(c: SeqCost): number {
  return c.lateness * 1000 + c.airborneDelay * 1.6 + c.delay;
}

/**
 * Fuel-aware sequence optimiser.
 * Starts from first-come-first-served, then hill-climbs with swaps limited to a
 * constrained position shift (no aircraft moves more than `maxShift` places), which is what
 * controllers accept. Pinned items stay at the front in the given order.
 * This is the browser stand-in for the CP-SAT model in the full architecture.
 */
export function optimiseOrder(items: SeqItem[], runways: RunwayUse[], now: number, pinned: string[] = [], maxShift = 3): SeqItem[] {
  const pin = pinned.map((id) => items.find((i) => i.f.id === id)!).filter(Boolean);
  const rest = items.filter((i) => !pinned.includes(i.f.id)).sort((a, b) => a.earliest - b.earliest);
  const base = rest.map((i) => i.f.id);
  let order = [...pin, ...rest];
  let bestScore = score(seqCost(order, assignSlots(order, runways, now)));
  const posOf = (id: string) => base.indexOf(id);
  let improved = true;
  let passes = 0;
  while (improved && passes++ < 12) {
    improved = false;
    for (let i = pin.length; i < order.length - 1; i++) {
      for (let j = i + 1; j < Math.min(order.length, i + 1 + maxShift); j++) {
        const cand = order.slice();
        [cand[i], cand[j]] = [cand[j], cand[i]];
        if (Math.abs(i - pin.length - posOf(cand[i].f.id)) > maxShift) continue;
        if (Math.abs(j - pin.length - posOf(cand[j].f.id)) > maxShift) continue;
        const s = score(seqCost(cand, assignSlots(cand, runways, now)));
        if (s < bestScore - 1e-6) {
          bestScore = s;
          order = cand;
          improved = true;
        }
      }
    }
  }
  return order;
}
