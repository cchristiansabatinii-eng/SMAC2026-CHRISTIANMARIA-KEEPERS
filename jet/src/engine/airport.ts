import type { AircraftType, Alternate, Runway, Stand } from './types';

/**
 * Zayed International (OMAA / AUH), simplified to the parts Jet plans on.
 * Coordinates are kilometres from midfield: x east, y north.
 * Two parallel 4.1 km runways on 130/310 degrees, 2 km apart, Terminal A midfield.
 */
export const AIRPORT = { iata: 'AUH', icao: 'OMAA', name: 'Zayed International', elevationFt: 88 };

const deg = Math.PI / 180;
/** Unit vector pointing along runway 31 (heading 310). */
export const U = { x: Math.sin(310 * deg), y: Math.cos(310 * deg) };
/** Unit vector perpendicular, pointing to the right of runway 31 (heading 040). */
export const P = { x: Math.sin(40 * deg), y: Math.cos(40 * deg) };

export const RUNWAY_LENGTH_KM = 4.1;
export const RUNWAY_SEP_KM = 2.0;

export function runwayCenter(id: string): { x: number; y: number } {
  const right = id.endsWith('R') ? id.startsWith('31') : !id.startsWith('31');
  const s = right ? RUNWAY_SEP_KM / 2 : -RUNWAY_SEP_KM / 2;
  return { x: P.x * s, y: P.y * s };
}

/** Threshold where aircraft landing on the runway (in its direction) touch down. */
export function threshold(id: string): { x: number; y: number } {
  const c = runwayCenter(id);
  const dir = id.startsWith('31') ? -1 : 1;
  return { x: c.x + U.x * dir * (RUNWAY_LENGTH_KM / 2 - 0.3), y: c.y + U.y * dir * (RUNWAY_LENGTH_KM / 2 - 0.3) };
}

export function initialRunways(): Runway[] {
  return [
    { id: '31R', pair: '13L', role: 'arr', open: true, rate: 28 },
    { id: '31L', pair: '13R', role: 'dep', open: true, rate: 0 },
  ];
}

export const TYPES: Record<string, AircraftType> = {
  A320: { code: 'A320', name: 'Airbus A320', wake: 'M', stand: 'C', wide: false, holdBurnKgMin: 38 },
  A321: { code: 'A321', name: 'Airbus A321', wake: 'M', stand: 'C', wide: false, holdBurnKgMin: 42 },
  A21N: { code: 'A21N', name: 'Airbus A321neo', wake: 'M', stand: 'C', wide: false, holdBurnKgMin: 36 },
  B738: { code: 'B738', name: 'Boeing 737-800', wake: 'M', stand: 'C', wide: false, holdBurnKgMin: 40 },
  B789: { code: 'B789', name: 'Boeing 787-9', wake: 'H', stand: 'E', wide: true, holdBurnKgMin: 85 },
  B77W: { code: 'B77W', name: 'Boeing 777-300ER', wake: 'H', stand: 'E', wide: true, holdBurnKgMin: 120 },
  A35K: { code: 'A35K', name: 'Airbus A350-1000', wake: 'H', stand: 'E', wide: true, holdBurnKgMin: 100 },
  A333: { code: 'A333', name: 'Airbus A330-300', wake: 'H', stand: 'E', wide: true, holdBurnKgMin: 95 },
  A388: { code: 'A388', name: 'Airbus A380-800', wake: 'J', stand: 'F', wide: true, holdBurnKgMin: 190 },
};

/** Minimum time between two landings on one runway, by wake category (leader → follower), seconds. */
export function wakeSpacing(leader: AircraftType, follower: AircraftType): number {
  const table: Record<string, number> = {
    MM: 90, MH: 90, MJ: 90,
    HM: 135, HH: 105, HJ: 105,
    JM: 180, JH: 150, JJ: 120,
  };
  return table[leader.wake + follower.wake];
}

const SIZE_RANK: Record<string, number> = { C: 0, E: 1, F: 2 };
export function standFits(stand: Stand, type: AircraftType): boolean {
  return SIZE_RANK[stand.size] >= SIZE_RANK[type.stand];
}

/**
 * Terminal A: a central hub with four piers in an X, stands on both sides.
 * Pier D ends at the ambulance gate (D50-D53), which medical plans prefer.
 */
export function initialStands(): Stand[] {
  const piers: { id: string; angle: number; numbers: number[] }[] = [
    { id: 'A', angle: 45, numbers: range(1, 12) },
    { id: 'B', angle: 135, numbers: range(10, 21) },
    { id: 'C', angle: 225, numbers: range(20, 31) },
    { id: 'D', angle: 315, numbers: range(40, 53) },
  ];
  const stands: Stand[] = [];
  for (const pier of piers) {
    const a = pier.angle * deg;
    // pier axis expressed relative to the runway frame so the X sits square to the runways
    const ax = U.x * Math.cos(a) + P.x * Math.sin(a);
    const ay = U.y * Math.cos(a) + P.y * Math.sin(a);
    const nx = -ay;
    const ny = ax;
    pier.numbers.forEach((n, i) => {
      const along = 0.32 + Math.floor(i / 2) * 0.085;
      const side = i % 2 === 0 ? 1 : -1;
      const size = i < 2 ? 'F' : i < 8 ? 'E' : 'C';
      stands.push({
        id: `${pier.id}${n}`,
        pier: pier.id,
        size: size as Stand['size'],
        x: ax * along + nx * side * 0.07,
        y: ay * along + ny * side * 0.07,
        closed: false,
        ambulance: pier.id === 'D' && n >= 50,
      });
    });
  }
  return stands;
}

function range(a: number, b: number): number[] {
  const out: number[] = [];
  for (let i = a; i <= b; i++) out.push(i);
  return out;
}

export function initialAlternates(): Alternate[] {
  return [
    { code: 'AUH', icao: 'OMAA', name: 'Zayed International', distKm: 0, spare: 14, open: true, hospitalMin: 24 },
    { code: 'DWC', icao: 'OMDW', name: 'Al Maktoum', distKm: 95, spare: 6, open: true, hospitalMin: 30 },
    { code: 'DXB', icao: 'OMDB', name: 'Dubai International', distKm: 120, spare: 4, open: true, hospitalMin: 12 },
    { code: 'AAN', icao: 'OMAL', name: 'Al Ain', distKm: 150, spare: 3, open: true, hospitalMin: 18 },
    { code: 'SHJ', icao: 'OMSJ', name: 'Sharjah', distKm: 145, spare: 3, open: true, hospitalMin: 15 },
  ];
}

/** Minutes for an airborne aircraft near AUH to reach an alternate and land there. */
export function divertMinutes(alt: Alternate): number {
  if (alt.distKm === 0) return 0;
  return Math.round(alt.distKm / 7.5 + 9);
}

/** Holding fixes around AUH (bearing from the field, km). */
export const HOLD_FIXES = [
  { id: 'HOLD NORTH', bearing: 350, distKm: 26 },
  { id: 'HOLD EAST', bearing: 80, distKm: 28 },
  { id: 'HOLD SOUTH', bearing: 170, distKm: 26 },
  { id: 'HOLD WEST', bearing: 260, distKm: 28 },
];

export function holdFixFor(bearing: number): (typeof HOLD_FIXES)[number] {
  let best = HOLD_FIXES[0];
  let bestD = 999;
  for (const f of HOLD_FIXES) {
    const d = Math.abs(((bearing - f.bearing + 540) % 360) - 180);
    if (d < bestD) {
      bestD = d;
      best = f;
    }
  }
  return best;
}

/** Fire-crew routes from the fire station to each runway: taxiway segments that must stay clear. */
export const FIRE_ROUTES: Record<string, string[]> = {
  '31R': ['TWY K', 'TWY K3'],
  '31L': ['TWY B', 'TWY B5'],
};
