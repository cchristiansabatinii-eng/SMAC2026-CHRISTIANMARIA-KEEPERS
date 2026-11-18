import { divertMinutes } from './airport';
import { MaxFlow } from './maxflow';
import type { Alternate, Flight } from './types';

/**
 * Safe Harbour: proves every airborne inbound has somewhere to land.
 *
 * Bipartite flow network  source → flight (cap 1) → airport (cap spare slots) → sink.
 * A flight connects to an airport only if it can get there with fuel to spare
 * (endurance minus the time to reach and land there ≥ margin). Max-flow = number of
 * flights that can be given a harbour simultaneously; if it equals the number of
 * flights, every plane is covered at the same time — not just individually.
 */
export interface HarbourResult {
  covered: number;
  total: number;
  assignment: Record<string, string>; // flight → airport
  reachable: Record<string, string[]>;
  load: Record<string, { used: number; cap: number }>;
  uncovered: string[];
}

export const FUEL_MARGIN_MIN = 5;

/** Minutes until a flight could land at AUH given the current sequence (slot if known, else ETA). */
function minutesToAuh(f: Flight, now: number): number {
  const t = Math.max(f.slot ?? f.eta, f.eta);
  return Math.max(0, (t - now) / 60);
}

export function canReach(f: Flight, alt: Alternate, now: number): boolean {
  if (!alt.open) return false;
  if (alt.distKm === 0) return f.fuelMin - minutesToAuh(f, now) >= FUEL_MARGIN_MIN;
  // diverting from where it is now: time to the AUH area (if still far away) + transit
  const toArea = Math.max(0, (f.eta - now) / 60 - 15);
  return f.fuelMin - toArea - divertMinutes(alt) >= FUEL_MARGIN_MIN;
}

export function safeHarbour(flights: Flight[], alternates: Alternate[], now: number, windowMin = 60): HarbourResult {
  const inbound = flights.filter(
    (f) =>
      f.dir === 'arr' &&
      (f.phase === 'enroute' || f.phase === 'holding' || f.phase === 'approach') &&
      f.eta - now <= windowMin * 60,
  );
  // priority: emergencies first, then least fuel — the flow is the same, but the
  // assignment Dinic finds is nicer to read when edges are added in that order
  inbound.sort((a, b) => Number(!!b.emergency) - Number(!!a.emergency) || a.fuelMin - b.fuelMin);
  const nF = inbound.length;
  const nA = alternates.length;
  const S = nF + nA;
  const T = S + 1;
  const g = new MaxFlow(nF + nA + 2);
  const edges: { f: number; a: number; e: number }[] = [];
  const reachable: Record<string, string[]> = {};
  inbound.forEach((f, i) => {
    g.addEdge(S, i, 1);
    reachable[f.id] = [];
    alternates.forEach((alt, j) => {
      if (canReach(f, alt, now)) {
        reachable[f.id].push(alt.code);
        // prefer AUH: it is added first so DFS tends to route there
        edges.push({ f: i, a: j, e: g.addEdge(i, nF + j, 1) });
      }
    });
  });
  const altEdges = alternates.map((alt, j) => g.addEdge(nF + j, T, alt.open ? Math.max(0, alt.spare) : 0));
  const covered = g.run(S, T);
  const assignment: Record<string, string> = {};
  for (const { f, a, e } of edges) if (g.flowOn(e) > 0) assignment[inbound[f].id] = alternates[a].code;
  const load: HarbourResult['load'] = {};
  alternates.forEach((alt, j) => (load[alt.code] = { used: g.flowOn(altEdges[j]), cap: alt.open ? alt.spare : 0 }));
  return {
    covered,
    total: nF,
    assignment,
    reachable,
    load,
    uncovered: inbound.filter((f) => !assignment[f.id]).map((f) => f.id),
  };
}
