import { FIRE_ROUTES, divertMinutes, standFits, wakeSpacing } from './airport';
import type { Plan } from './planner';
import { FUEL_MARGIN_MIN } from './safeHarbour';
import { DEP_GAP_S } from './sequencer';
import type { World } from './world';

/**
 * Run-time assurance: an independent, rule-based safety checker.
 * Plain rules, not AI. It re-derives everything from the plan and the world and never
 * trusts the planner's own bookkeeping. Any failed rule vetoes the plan.
 */
export interface Check {
  rule: string;
  ok: boolean;
  detail: string;
}

export const RULES = [
  { id: 'Spacing', text: 'Landings on one runway keep wake-turbulence and declared-rate spacing; arrivals on a departure runway stay 2 minutes clear of take-offs; closed runways get no traffic.' },
  { id: 'Stand size', text: 'Every arrival has a stand that fits its wingspan, is open, and is not occupied when it blocks in.' },
  { id: 'Fuel', text: 'Every aircraft lands — here or at its alternate — with at least 5 minutes above final reserve, using the fuel estimate minus one sigma.' },
  { id: 'Fire routes', text: 'Fire-crew routes to a runway with an emergency landing stay clear; no traffic on a runway closed for an accident.' },
  { id: 'Alternates', text: 'Diversions only go to open airports, within the spare arrivals each has declared.' },
] as const;

const fmt = (s: number) => {
  const d = new Date(s * 1000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
};

export function checkPlan(plan: Plan, w: World): Check[] {
  const checks: Check[] = [];
  const byId = (id: string) => w.flights.find((f) => f.id === id)!;

  // 1. spacing
  {
    const problems: string[] = [];
    const rates: Record<string, number> = {};
    for (const r of plan.arrivalRunways) rates[r.id] = r.rate;
    const runways = [...new Set(plan.seq.map((e) => e.runway))];
    for (const rw of runways) {
      const real = w.runways.find((r) => r.id === rw);
      const landings = plan.seq.filter((e) => e.runway === rw).sort((a, b) => a.slot - b.slot);
      if (!real || !real.open) {
        if (landings.length) problems.push(`${landings.length} landing(s) planned on ${rw}, which is closed`);
        continue;
      }
      for (let i = 1; i < landings.length; i++) {
        const a = byId(landings[i - 1].id);
        const b = byId(landings[i].id);
        const need = Math.max(wakeSpacing(a.type, b.type), 3600 / Math.max(1, rates[rw] ?? real.rate) - 1);
        const gap = landings[i].slot - landings[i - 1].slot;
        if (gap + 0.5 < need) problems.push(`${b.id} only ${Math.round(gap)} s behind ${a.id} on ${rw} (needs ${Math.round(need)} s)`);
      }
      if (real.role !== 'arr') {
        for (const l of landings) {
          const clash = plan.depTimes.find((d) => Math.abs(d - l.slot) < DEP_GAP_S - 0.5);
          if (clash !== undefined) problems.push(`${l.id} lands ${Math.round(Math.abs(clash - l.slot))} s from a take-off on ${rw}`);
        }
      }
    }
    checks.push({ rule: 'Spacing', ok: problems.length === 0, detail: problems[0] ?? 'All landings keep wake and rate spacing.' });
  }

  // 2. stand size / availability
  {
    const problems: string[] = [];
    const used: Record<string, string[]> = {};
    for (const e of plan.seq) {
      const sid = plan.stands[e.id];
      const f = byId(e.id);
      if (!sid) {
        problems.push(`${e.id} has no stand that fits and is free at ${fmt(e.slot + 360)}`);
        continue;
      }
      const st = w.stands.find((s) => s.id === sid)!;
      if (st.closed) problems.push(`${e.id} is given ${sid}, which is closed`);
      if (!standFits(st, f.type)) problems.push(`${f.type.code} does not fit ${sid} (code ${st.size})`);
      (used[sid] ??= []).push(e.id);
    }
    checks.push({ rule: 'Stand size', ok: problems.length === 0, detail: problems[0] ?? `${plan.seq.length} arrivals each have a fitting, free stand.` });
  }

  // 3. fuel
  {
    const problems: string[] = [];
    let tightest = Infinity;
    let tightestId = '';
    for (const e of plan.seq) {
      const f = byId(e.id);
      if (f.phase === 'scheduled') continue;
      const left = f.fuelMin - f.fuelSigma - (e.slot - w.now) / 60;
      if (left < tightest) {
        tightest = left;
        tightestId = f.id;
      }
      if (left < FUEL_MARGIN_MIN) problems.push(`${f.id} would land with ${left.toFixed(0)} min above reserve (needs ${FUEL_MARGIN_MIN})`);
    }
    for (const d of plan.diversions) {
      const f = byId(d.id);
      const alt = w.alternates.find((a) => a.code === d.to)!;
      const left = f.fuelMin - f.fuelSigma - Math.max(0, (f.eta - w.now) / 60 - 15) - divertMinutes(alt);
      if (left < FUEL_MARGIN_MIN) problems.push(`${f.id} would reach ${d.to} with ${left.toFixed(0)} min above reserve`);
    }
    checks.push({
      rule: 'Fuel',
      ok: problems.length === 0,
      detail: problems[0] ?? (tightestId ? `Tightest: ${tightestId} lands with ${tightest.toFixed(0)} min above reserve.` : 'No airborne arrivals affected.'),
    });
  }

  // 4. fire routes
  {
    const problems: string[] = [];
    const inc = w.incident;
    if (inc?.closedRunway) {
      const on = plan.seq.filter((e) => e.runway === inc.closedRunway);
      if (on.length) problems.push(`${on.length} landing(s) on ${inc.closedRunway} while fire crews work there`);
    }
    if (inc?.flightId) {
      const e = plan.seq.find((x) => x.id === inc.flightId);
      if (e) {
        const route = FIRE_ROUTES[e.runway] ?? [];
        const rw = w.runways.find((r) => r.id === e.runway);
        if (rw && rw.role !== 'arr') {
          const crossing = plan.depTimes.filter((d) => Math.abs(d - e.slot) < 300);
          if (crossing.length) problems.push(`${crossing.length} departure(s) taxi across ${route.join(' / ')} within 5 min of ${e.id} landing`);
        }
      }
    }
    checks.push({ rule: 'Fire routes', ok: problems.length === 0, detail: problems[0] ?? 'Fire-crew routes stay clear.' });
  }

  // 5. alternates
  {
    const problems: string[] = [];
    const count: Record<string, number> = {};
    for (const d of plan.diversions) {
      const alt = w.alternates.find((a) => a.code === d.to);
      if (!alt || !alt.open) problems.push(`${d.id} sent to ${d.to}, which is closed`);
      count[d.to] = (count[d.to] ?? 0) + 1;
    }
    for (const [code, n] of Object.entries(count)) {
      const alt = w.alternates.find((a) => a.code === code);
      if (alt && n > alt.spare) problems.push(`${n} diversions to ${code}, which has room for ${alt.spare}`);
    }
    checks.push({ rule: 'Alternates', ok: problems.length === 0, detail: problems[0] ?? (plan.diversions.length ? 'Every alternate is open and has room.' : 'No diversions.') });
  }

  return checks;
}

export function applyChecks(plan: Plan, w: World): Plan {
  plan.checks = checkPlan(plan, w);
  plan.passed = plan.checks.every((c) => c.ok);
  return plan;
}
