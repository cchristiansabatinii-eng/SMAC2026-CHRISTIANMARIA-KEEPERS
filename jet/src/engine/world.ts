import type { Alternate, Flight, Runway, Stand } from './types';

export type CrisisKind = 'medical' | 'capacity' | 'runway' | 'airspace' | 'ground';

export interface Incident {
  id: string;
  kind: CrisisKind;
  title: string;
  subtitle: string;
  severity: 'Critical' | 'Major' | 'Minor';
  openedAt: number;
  flightId?: string;
  closedRunway?: string;
  frozenTaxiways: string[];
  status: 'open' | 'options' | 'signed' | 'manual' | 'closed';
}

/** A read-only snapshot of everything the planner and checker need. */
export interface World {
  now: number;
  flights: Flight[];
  runways: Runway[];
  stands: Stand[];
  alternates: Alternate[];
  incident: Incident | null;
}
