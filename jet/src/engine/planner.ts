import { divertMinutes, standFits } from './airport';
import { DELAY_AED_PER_MIN, DIVERSION_AED, FUEL_AED_PER_KG } from './costs';
import { canReach } from './safeHarbour';
import { assignSlots, landingDeadline, optimiseOrder, runwayUses, type SeqEntry, type SeqItem } from './sequencer';
import type { Alternate, Flight } from './types';
import type { World } from './world';

export const HORIZON_S = 100 * 60;
export const TAXI_IN_S = 6 * 60;
export const DEP_TAXI_S = 10 * 60;

export interface Strategy {
  key: string;
  title: (p: Plan) => string;
  describe: (p: Plan, ctx: PlanContext) => string;
  tags?: (p: Plan, ctx: PlanContext) => string[];
  /** Land this flight first, optionally on a given runway. */
  priority?: { id: string; runway?: string };
  /** Forced diversions (to: airport code, or best available). */
  divert?: { id: string; to?: string }[];
  /** Divert any flight the sequence can't land before its fuel margin. */
  autoDivert?: boolean;
  /** Hold departures on mixed/arrival runways for this many minutes. */
  holdDeparturesMin?: number;
  /** Keep not-yet-airborne flights on the ground at origin instead of holding in the air. */
  groundHold?: boolean;
  /** Use the fuel-aware optimiser (otherwise first come, first served). */
  optimise?: boolean;
  /** Runways used for arrivals, with rate overrides. */
  arrivalRunways?: { id: string; rate: number }[];
  /** Cap on arrivals per hour (e.g. to the stands that will really be free). */
  arrivalCap?: number;
  /** Stands to clear by towing to the cargo apron before arrivals need them. */
  towToCargo?: number;
  /** Assume an airport closure is lifted / a runway is open (lets the checker catch it). */
  assumeOpen?: string[];
}

export interface PlanMetrics {
  delayMin: number;
  holdingMin: number;
  holdingFuelKg: number;
  diversions: number;
  depDelayMin: number;
  costAED: number;
  treatmentMin?: number;
  flightsAffected: number;
  maxExtraMin: number;
}

export interface Plan {
  key: string;
  letter: string;
  title: string;
  summary: string;
  tags: string[];
  seq: SeqEntry[];
  diversions: { id: string; to: string }[];
  stands: Record<string, string | null>;
  groundHolds: Record<string, number>;
  depTimes: number[];
  depHoldMin: number;
  arrivalRunways: { id: string; rate: number }[];
  metrics: PlanMetrics;
  decideBy: number;
  score: number;
  /** Filled by the safety checker. */
  checks: { rule: string; ok: boolean; detail: string }[];
  passed: boolean;
  strategy: Strategy;
  computeMs: number;
}

export interface PlanContext {
  world: World;
  baseline: Plan | null;
}

export function inHorizon(w: World): Flight[] {
  return w.flights.filter(
    (f) =>
      f.dir === 'arr' &&
      ['scheduled', 'enroute', 'holding', 'approach'].includes(f.phase) &&
      f.eta + f.groundDelay - w.now < HORIZON_S,
  );
}

function departureTimes(w: World, holdMin: number): number[] {
  const deps = w.flights
    .filter((f) => f.dir === 'dep' && (f.phase === 'boarding' || f.phase === 'taxi_out'))
    .map((f) => Math.max(f.slot ?? f.eta + DEP_TAXI_S, w.now + 60))
    .sort((a, b) => a - b);
  if (!holdMin) return deps;
  const until = w.now + holdMin * 60;
  let next = until;
  return deps.map((t) => {
    if (t >= until) return Math.max(t, next);
    const nt = next;
    next += 110;
    return nt;
  });
}

function bestAlternate(f: Flight, w: World, used: Record<string, number>, prefer?: string, assumeOpen: string[] = []): Alternate | null {
  const alts = w.alternates
    .filter((a) => a.code !== 'AUH')
    .map((a) => (assumeOpen.includes(a.code) ? { ...a, open: true } : a));
  if (prefer) {
    const a = alts.find((x) => x.code === prefer);
    if (a) return a;
  }
  const ok = alts
    .filter((a) => a.open && (used[a.code] ?? 0) < a.spare && canReach(f, a, w.now))
    .sort((a, b) => a.distKm - b.distKm);
  return ok[0] ?? null;
}

export function evaluate(w: World, s: Strategy, ctx: PlanContext, letter = '?'): Plan {
  const t0 = performance.now();
  const now = w.now;
  const depHold = s.holdDeparturesMin ?? 0;
  const depTimes = departureTimes(w, depHold);
  const arrivalRunways =
    s.arrivalRunways ??
    w.runways.filter((r) => r.role !== 'dep' && (r.open || s.assumeOpen?.includes(r.id))).map((r) => ({ id: r.id, rate: r.rate }));
  const rwState = w.runways.map((r) => {
    const o = arrivalRunways.find((a) => a.id === r.id);
    const open = r.open || !!s.assumeOpen?.includes(r.id);
    return { ...r, rate: o ? o.rate : r.rate, open, role: r.role === 'dep' && o ? ('mixed' as const) : r.role };
  });
  let uses = runwayUses(rwState, depTimes, arrivalRunways.map((a) => a.id));
  if (s.arrivalCap) uses = uses.map((u) => ({ ...u, rate: Math.min(u.rate, s.arrivalCap! / uses.length) }));

  const diversions: { id: string; to: string }[] = [];
  const altUsed: Record<string, number> = {};
  for (const d of s.divert ?? []) {
    const f = w.flights.find((x) => x.id === d.id);
    if (!f) continue;
    const alt = bestAlternate(f, w, altUsed, d.to, s.assumeOpen);
    if (alt) {
      diversions.push({ id: f.id, to: alt.code });
      altUsed[alt.code] = (altUsed[alt.code] ?? 0) + 1;
    }
  }

  const build = (): { items: SeqItem[]; order: SeqItem[]; seq: SeqEntry[] } => {
    const items: SeqItem[] = inHorizon(w)
      .filter((f) => !diversions.some((d) => d.id === f.id))
      .map((f) => ({
        f,
        earliest: f.eta + f.groundDelay,
        deadline: f.phase === 'scheduled' ? Infinity : landingDeadline(f, now),
        airborne: f.phase !== 'scheduled',
        runway: s.priority?.id === f.id ? s.priority.runway : undefined,
      }));
    // already-pinned flights from an earlier signed plan keep their place
    const pinnedEarlier = items
      .filter((i) => i.f.pinnedOrder !== undefined)
      .sort((a, b) => a.f.pinnedOrder! - b.f.pinnedOrder!)
      .map((i) => i.f.id);
    const pins = s.priority && items.some((i) => i.f.id === s.priority!.id) ? [s.priority.id, ...pinnedEarlier.filter((x) => x !== s.priority!.id)] : pinnedEarlier;
    const order = s.optimise
      ? optimiseOrder(items, uses, now, pins)
      : [...pins.map((id) => items.find((i) => i.f.id === id)!), ...items.filter((i) => !pins.includes(i.f.id)).sort((a, b) => a.earliest - b.earliest)];
    return { items, order, seq: assignSlots(order, uses, now) };
  };

  let { order, seq } = build();
  if (s.autoDivert) {
    for (let guard = 0; guard < 8; guard++) {
      const lateIdx = seq.findIndex((e, i) => e.slot > order[i].deadline);
      if (lateIdx < 0) break;
      const f = order[lateIdx].f;
      if (f.emergency) break; // never divert the emergency silently — that is a human's call
      const alt = bestAlternate(f, w, altUsed, undefined, s.assumeOpen);
      if (!alt) break;
      diversions.push({ id: f.id, to: alt.code });
      altUsed[alt.code] = (altUsed[alt.code] ?? 0) + 1;
      ({ order, seq } = build());
    }
  }

  // ground holds: flights still at their origin wait there instead of circling here
  const groundHolds: Record<string, number> = {};
  if (s.groundHold) {
    seq.forEach((e, i) => {
      const it = order[i];
      if (!it.airborne && e.delay > 300) groundHolds[e.id] = e.delay - 180;
    });
  }

  const stands = allocateStands(w, seq, order, depHold, s.towToCargo ?? 0);

  // metrics
  let delay = 0;
  let holding = 0;
  let fuelKg = 0;
  seq.forEach((e, i) => {
    const f = order[i].f;
    delay += e.delay / 60;
    const airborneHold = Math.max(0, e.delay - (groundHolds[e.id] ?? 0)) / 60;
    const h = order[i].airborne || !groundHolds[e.id] ? airborneHold : Math.min(airborneHold, 3);
    holding += h;
    fuelKg += h * f.type.holdBurnKgMin;
  });
  let costAED = fuelKg * FUEL_AED_PER_KG + delay * DELAY_AED_PER_MIN;
  for (const d of diversions) {
    const f = w.flights.find((x) => x.id === d.id)!;
    costAED += f.type.wide ? DIVERSION_AED.wide : DIVERSION_AED.narrow;
  }
  const baseDeps = departureTimes(w, 0);
  const depDelayMin = depTimes.reduce((acc, t, i) => acc + Math.max(0, t - baseDeps[i]) / 60, 0);
  costAED += depDelayMin * DELAY_AED_PER_MIN;

  let treatmentMin: number | undefined;
  const em = w.incident?.flightId ? w.flights.find((f) => f.id === w.incident!.flightId) : undefined;
  if (em && em.emergency === 'medical') {
    const d = diversions.find((x) => x.id === em.id);
    if (d) {
      const alt = w.alternates.find((a) => a.code === d.to)!;
      treatmentMin = divertMinutes(alt) + Math.max(0, (em.eta - now) / 60 - 15) + 6 + 3 + alt.hospitalMin;
    } else {
      const e = seq.find((x) => x.id === em.id);
      const st = stands[em.id];
      const standObj = w.stands.find((x) => x.id === st);
      if (e) treatmentMin = (e.slot - now) / 60 + 6 + (standObj?.ambulance ? 2 : 6) + (standObj?.ambulance ? 22 : 26);
    }
  }

  // compare with the current plan of record
  let affected = 0;
  let maxExtra = 0;
  const base = ctx.baseline;
  if (base) {
    for (const e of seq) {
      const b = base.seq.find((x) => x.id === e.id);
      if (!b) continue;
      const extra = (e.slot - b.slot) / 60;
      if (extra >= 1) {
        affected++;
        maxExtra = Math.max(maxExtra, extra);
      }
    }
  }

  const metrics: PlanMetrics = {
    delayMin: delay,
    holdingMin: holding,
    holdingFuelKg: fuelKg,
    diversions: diversions.length,
    depDelayMin,
    costAED,
    treatmentMin,
    flightsAffected: affected,
    maxExtraMin: maxExtra,
  };

  // decide-by: the latest moment the plan still works as drafted
  let decideBy = now + 20 * 60;
  if (s.priority) {
    const e = seq.find((x) => x.id === s.priority!.id);
    if (e) decideBy = Math.min(decideBy, e.slot - 9 * 60);
  }
  for (const d of diversions) {
    const f = w.flights.find((x) => x.id === d.id)!;
    const alt = w.alternates.find((a) => a.code === d.to)!;
    const slack = f.fuelMin - divertMinutes(alt) - Math.max(0, (f.eta - now) / 60 - 15) - 5;
    decideBy = Math.min(decideBy, now + Math.max(0, slack) * 60 + 4 * 60);
  }
  decideBy = Math.max(decideBy, now + 150);

  const plan: Plan = {
    key: s.key,
    letter,
    title: '',
    summary: '',
    tags: [],
    seq,
    diversions,
    stands,
    groundHolds,
    depTimes,
    depHoldMin: depHold,
    arrivalRunways: uses.map((u) => ({ id: u.id, rate: u.rate })),
    metrics,
    decideBy,
    score: costAED + (treatmentMin ?? 0) * 25_000,
    checks: [],
    passed: false,
    strategy: s,
    computeMs: 0,
  };
  plan.title = s.title(plan);
  plan.summary = s.describe(plan, ctx);
  plan.tags = s.tags?.(plan, ctx) ?? [];
  plan.computeMs = performance.now() - t0;
  return plan;
}

/**
 * Stand allocation: each arrival gets the tightest-fitting stand that is free at its in-block time.
 * A medical emergency gets a stand at the ambulance gate.
 */
export function allocateStands(w: World, seq: SeqEntry[], _order: SeqItem[], depHoldMin: number, towToCargo: number): Record<string, string | null> {
  const busy: Record<string, number> = {};
  let towed = 0;
  for (const st of w.stands) {
    if (!st.occupant) continue;
    const f = w.flights.find((x) => x.id === st.occupant);
    if (!f) continue;
    let until: number;
    if (f.dir === 'dep') until = Math.max(f.eta, w.now) + depHoldMin * 60;
    else until = (f.inBlock ?? w.now) + (f.type.wide ? 95 : 65) * 60 + (st.closed ? 3600 * 6 : 0);
    if (towed < towToCargo && until > w.now + 20 * 60) {
      // tow the longest-staying aircraft to the cargo apron to free the contact stand
      until = w.now + 15 * 60;
      towed++;
    }
    busy[st.id] = until;
  }
  const out: Record<string, string | null> = {};
  const rank: Record<string, number> = { C: 0, E: 1, F: 2 };
  for (const e of seq) {
    const f = w.flights.find((x) => x.id === e.id)!;
    const inBlock = e.slot + TAXI_IN_S;
    const candidates = w.stands.filter(
      (st) => !st.closed && standFits(st, f.type) && (busy[st.id] ?? 0) <= inBlock && (!st.heldFor || st.heldFor === f.id),
    );
    candidates.sort((a, b) => {
      const amb = f.emergency === 'medical' ? Number(!!b.ambulance) - Number(!!a.ambulance) : Number(!!a.ambulance) - Number(!!b.ambulance);
      return amb || rank[a.size] - rank[b.size] || (busy[a.id] ?? 0) - (busy[b.id] ?? 0) || a.id.localeCompare(b.id);
    });
    const held = w.stands.find((st) => st.heldFor === f.id);
    const st = held && candidates.includes(held) ? held : candidates[0];
    if (st) {
      out[f.id] = st.id;
      busy[st.id] = inBlock + (f.type.wide ? 95 : 65) * 60;
    } else out[f.id] = null;
  }
  return out;
}
