# Jet — prototype

*The right call, in seconds, when disruption hits.* Decision support for airport disruption at Zayed International (TDRA UAE Hackathon 2026).

**Run it:** open `prototype/index.html` in a browser. It is a single file and needs no build.

All ten console screens from the pitch work:

| Screen | What it does |
|---|---|
| Live | 3D digital twin of AUH (drag to orbit), arrivals sequence, Safe Harbour, holding/landings charts, and the incident panel with timeline, options A/B/C, decide-by countdowns, sign, controller script and read-back check |
| Flights | Arrival/departure boards, search, filters |
| Ear | Radio call → structured facts (callsign, urgency, intent, fuel, heading, altitude, runway); browser speech input; read-back checker |
| Harbour | Max-flow (augmenting-path) proof that every inbound has a place to land; close/reopen airports as a what-if |
| Forecast | Calibrated ETA ranges, Kalman fuel estimates, capacity outlook |
| Weather | METAR/TAF, runway wind components, 24 h charts, NOTAMs, 5 airports |
| Agents | Jet Ear, Sentinel, Safe Harbour, Strategist, Brokers, Dispatcher, Recovery, Auditor, plus the message bus |
| Analytics | 12 simulated disrupted mornings computed in the browser (today's playbook vs Jet) and the measured re-plan time |
| Record | Hash-chained decision log: verify, simulate tampering, export JSON |
| System | Nine layers, feeds, fallback chain, safety-checker rules |

Five scenarios (top bar → *Run scenario*): medical emergency EY505, fog (28 → 14/h), runway 31R lost, DXB/DWC airspace closure, ground disruption. In each one, the planner drafts several plans and an independent rule-based safety checker vetoes the unsafe ones. A person signs before anything moves.

All times, traffic and weather are simulated. This is not for operational use.

`src/engine/` holds a typed TypeScript engine in progress (Dinic max-flow, sequencer and optimiser, planner, safety checker, conformal ETA ranges, Kalman fuel). It is meant for the next iteration, and the prototype does not use it yet.
