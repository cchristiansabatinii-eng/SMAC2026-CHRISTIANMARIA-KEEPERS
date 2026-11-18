import { TYPES } from './airport';
import { between, pick, rng } from './rng';
import type { Flight } from './types';

/**
 * Flight numbers and routes follow a real Zayed International board (27 Oct 2026, public sources);
 * times are re-timed around the simulation clock and aircraft types are assumed.
 */
const ARR_ROUTES: [string, string, string, string, string][] = [
  // callsign, origin IATA, origin city, type, bearing hint
  ['EY610', 'TLV', 'Tel Aviv', 'A321', '300'],
  ['EY22', 'YYZ', 'Toronto', 'B789', '320'],
  ['QR1003', 'DOH', 'Doha', 'A321', '280'],
  ['EY701', 'SEZ', 'Mahé', 'B789', '200'],
  ['EY505', 'LHR', 'London', 'B789', '315'],
  ['EY6', 'IAD', 'Washington', 'B789', '320'],
  ['EY842', 'SVO', 'Moscow', 'B789', '340'],
  ['EY728', 'ADD', 'Addis Ababa', 'A321', '230'],
  ['EY46', 'DUB', 'Dublin', 'B789', '315'],
  ['ME418', 'BEY', 'Beirut', 'A21N', '305'],
  ['EY32', 'CDG', 'Paris', 'A35K', '310'],
  ['EY758', 'CMN', 'Casablanca', 'B789', '290'],
  ['3L457', 'ALP', 'Aleppo', 'A320', '320'],
  ['EY854', 'LED', 'St Petersburg', 'A321', '340'],
  ['EY471', 'CGK', 'Jakarta', 'B77W', '110'],
  ['PK263', 'KHI', 'Karachi', 'A320', '80'],
  ['EY212', 'BOM', 'Mumbai', 'A321', '95'],
  ['AI941', 'COK', 'Kochi', 'A21N', '110'],
  ['EY20', 'MAN', 'Manchester', 'A388', '315'],
  ['SV582', 'RUH', 'Riyadh', 'A320', '270'],
  ['EY290', 'DEL', 'Delhi', 'A321', '70'],
  ['G9 555', 'SHJ', 'Sharjah', 'A320', '45'],
  ['EY318', 'MNL', 'Manila', 'B789', '100'],
  ['TK868', 'IST', 'Istanbul', 'A333', '320'],
  ['EY462', 'SYD', 'Sydney', 'B789', '120'],
  ['LH630', 'FRA', 'Frankfurt', 'A333', '315'],
  ['EY388', 'BKK', 'Bangkok', 'A35K', '100'],
  ['PA430', 'ISB', 'Islamabad', 'A320', '60'],
  ['EY12', 'JFK', 'New York', 'B77W', '320'],
  ['EY250', 'CMB', 'Colombo', 'A321', '120'],
  ['3L111', 'CAI', 'Cairo', 'A320', '290'],
  ['EY183', 'KTM', 'Kathmandu', 'A321', '65'],
  ['EY416', 'KUL', 'Kuala Lumpur', 'A35K', '110'],
  ['EY132', 'MXP', 'Milan', 'A321', '310'],
];

const DEP_ROUTES: [string, string, string, string][] = [
  ['EY11', 'JFK', 'New York', 'B77W'],
  ['EY19', 'LHR', 'London', 'B789'],
  ['EY451', 'SYD', 'Sydney', 'B789'],
  ['EY393', 'BKK', 'Bangkok', 'A35K'],
  ['EY617', 'ZRH', 'Zurich', 'A321'],
  ['3L184', 'IST', 'Istanbul', 'A320'],
  ['EY283', 'ATH', 'Athens', 'A321'],
  ['EY61', 'CDG', 'Paris', 'A388'],
  ['EY296', 'DEL', 'Delhi', 'A321'],
  ['EY402', 'KUL', 'Kuala Lumpur', 'B789'],
  ['G9 556', 'SHJ', 'Sharjah', 'A320'],
  ['EY681', 'ADD', 'Addis Ababa', 'A321'],
  ['EY24', 'FRA', 'Frankfurt', 'B789'],
  ['EY7', 'ORD', 'Chicago', 'B789'],
  ['EY315', 'MNL', 'Manila', 'B789'],
];

export const TELEPHONY: Record<string, string> = {
  EY: 'Etihad',
  QR: 'Qatari',
  ME: 'Cedar Jet',
  '3L': 'Alpha Delta',
  PK: 'Pakistan',
  AI: 'Air India',
  SV: 'Saudia',
  G9: 'Air Arabia',
  TK: 'Turkish',
  LH: 'Lufthansa',
  PA: 'Airblue',
  EK: 'Emirates',
  FZ: 'Sky Dubai',
};

export const AIRLINE_NAME: Record<string, string> = {
  EY: 'Etihad Airways',
  QR: 'Qatar Airways',
  ME: 'Middle East Airlines',
  '3L': 'Air Arabia Abu Dhabi',
  PK: 'PIA',
  AI: 'Air India Express',
  SV: 'Saudia',
  G9: 'Air Arabia',
  TK: 'Turkish Airlines',
  LH: 'Lufthansa',
  PA: 'Airblue',
};

function airlineOf(callsign: string): string {
  return callsign.match(/^([A-Z0-9]{2})/)![1];
}

export function blankFlight(partial: Partial<Flight> & Pick<Flight, 'id' | 'dir' | 'type'>): Flight {
  return {
    airline: airlineOf(partial.id),
    telephony: TELEPHONY[airlineOf(partial.id)] ?? partial.id,
    other: '',
    otherCity: '',
    sched: 0,
    eta: 0,
    groundDelay: 0,
    offBlock: 0,
    fuelMin: 0,
    fuelSigma: 2,
    phase: 'scheduled',
    emergency: null,
    holdMinutes: 0,
    holdFuelKg: 0,
    bearing: 300,
    ...partial,
  };
}

/**
 * Builds the day around `now`: arrivals about every 2 minutes (28 an hour declared rate),
 * some already landed and on stand, departures every ~3 minutes.
 */
export function buildDay(now: number, seed = 27): Flight[] {
  const r = rng(seed);
  const flights: Flight[] = [];
  ARR_ROUTES.forEach(([id, iata, city, type, b], i) => {
    const offset = (i - 8) * 128 + between(r, -25, 25); // first 8 already landed
    const eta = now + offset + 300;
    const flightTime = 3600 * between(r, 1, 8);
    const f = blankFlight({
      id: id.replace(' ', ''),
      dir: 'arr',
      type: TYPES[type],
      other: iata,
      otherCity: city,
      sched: Math.round((eta - between(r, -240, 420)) / 300) * 300,
      eta,
      offBlock: eta - flightTime,
      bearing: Number(b) + between(r, -8, 8),
      // minutes before final reserve: time to go + holding/alternate contingency
      fuelMin: Math.max(0, (eta - now) / 60) + between(r, 28, 62),
      fuelSigma: 1.5 + between(r, 0, 1.5),
      souls: Math.round(TYPES[type].wide ? between(r, 220, 330) : between(r, 120, 190)),
    });
    if (offset < -360) {
      f.phase = 'on_stand';
      f.landedAt = eta;
      f.inBlock = eta + 360;
    } else if (offset < 0) {
      f.phase = 'taxi_in';
      f.landedAt = eta;
    } else if (f.offBlock > now) {
      f.phase = 'scheduled';
    } else {
      f.phase = 'enroute';
    }
    flights.push(f);
  });
  DEP_ROUTES.forEach(([id, iata, city, type], i) => {
    const std = now + i * 200 + between(r, -40, 60) + 120;
    flights.push(
      blankFlight({
        id: id.replace(' ', ''),
        dir: 'dep',
        type: TYPES[type],
        other: iata,
        otherCity: city,
        sched: Math.round(std / 300) * 300,
        eta: std,
        phase: 'boarding',
        souls: Math.round(TYPES[type].wide ? between(r, 220, 330) : between(r, 120, 190)),
      }),
    );
  });
  // keep the medical flight a believable state: EY505 has ~39 minutes of fuel when it calls
  const ey505 = flights.find((f) => f.id === 'EY505')!;
  ey505.fuelMin = Math.max(ey505.fuelMin, 42);
  const pa = flights.find((f) => f.id === 'PA430')!;
  pa.fuelMin = Math.min(pa.fuelMin, (pa.eta - now) / 60 + 24);
  void pick;
  return flights;
}
