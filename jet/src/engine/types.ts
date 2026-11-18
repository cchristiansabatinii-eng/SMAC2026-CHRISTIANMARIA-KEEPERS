export type Wake = 'M' | 'H' | 'J';
export type StandSize = 'C' | 'E' | 'F';

export interface AircraftType {
  code: string;
  name: string;
  wake: Wake;
  stand: StandSize;
  wide: boolean;
  /** Fuel burn while holding, kg per minute. */
  holdBurnKgMin: number;
}

export type Phase =
  | 'scheduled' // not yet airborne at origin
  | 'enroute'
  | 'holding'
  | 'approach'
  | 'landed'
  | 'taxi_in'
  | 'on_stand'
  | 'diverting'
  | 'diverted'
  | 'boarding'
  | 'taxi_out'
  | 'departed';

export type Emergency = 'medical' | 'mayday' | 'fuel' | null;

export interface Flight {
  id: string; // callsign, e.g. EY505
  airline: string;
  telephony: string;
  dir: 'arr' | 'dep';
  other: string; // origin (arr) or destination (dep) IATA
  otherCity: string;
  type: AircraftType;
  /** Scheduled time (s since local midnight). */
  sched: number;
  /** Unconstrained estimate at the runway (arr) or off-block (dep). */
  eta: number;
  /** Ground delay imposed at origin (s). */
  groundDelay: number;
  /** Time the flight leaves its origin gate (arr only). */
  offBlock: number;
  /** Endurance in minutes before final reserve, at the current sim time. Arr only. */
  fuelMin: number;
  /** One-sigma uncertainty of fuelMin, minutes (Kalman). */
  fuelSigma: number;
  phase: Phase;
  emergency: Emergency;
  emergencyNote?: string;
  souls?: number;
  slot?: number; // assigned landing / take-off time
  runway?: string;
  stand?: string;
  landedAt?: number;
  inBlock?: number;
  divertTo?: string;
  holdFix?: string;
  holdingSince?: number;
  holdMinutes: number;
  holdFuelKg: number;
  bearing: number; // inbound bearing from the airport, degrees
  /** Flights an approved plan pinned to an order in the sequence. */
  pinnedOrder?: number;
}

export interface Runway {
  id: string; // e.g. '31R'
  pair: string; // e.g. '13L'
  role: 'arr' | 'dep' | 'mixed';
  open: boolean;
  /** Arrival rate per hour when used for arrivals. */
  rate: number;
}

export interface Stand {
  id: string;
  pier: string;
  size: StandSize;
  x: number;
  y: number;
  closed: boolean;
  occupant?: string;
  heldFor?: string;
  ambulance?: boolean;
}

export interface Alternate {
  code: string;
  icao: string;
  name: string;
  distKm: number;
  /** Spare arrivals it can take in the next hour. */
  spare: number;
  open: boolean;
  hospitalMin: number; // drive from the stand to the nearest suitable hospital
}
