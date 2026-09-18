# Verse — Band Booking & Music Workforce Blueprint

## Core principle
Verse has three different work systems that share identity, trust and messaging but must not share one generic data object:
1. **Hire** — recruit a person for a role, seat or ongoing responsibility.
2. **Book** — reserve an existing solo/duo/group/crew for a dated event and negotiate a quote.
3. **Build** — assemble a new band/live team from multiple missing seats.

## Buyer scenarios
- Wedding planner booking a singer, duo, DJ, wedding band, folk group or full live band.
- Corporate event team booking a band, emcee/artist combination or entertainment package.
- Venue programming recurring acts or residencies.
- Festival booking multiple acts and production crew.
- Artist manager sourcing touring musicians, MD, playback, FOH, monitors and technicians.
- Band leader replacing one member or building a new lineup from zero.
- Producer hiring session players, vocalist, arranger, orchestrator, engineer or mixer.
- Label hiring A&R, release/project staff, content/marketing, metadata/rights support.
- Composer assembling orchestra/choir/session ensemble.
- Studio hiring engineers, assistants, producers or session talent.
- Independent artist hiring one-off creative collaborators.
- Promoter hiring show runner, technical director, stage manager and crew.

## Performer packaging
A bookable identity can be: solo, duo, trio, fixed band, flexible band, ensemble, orchestra, choir, DJ, live-electronic act, tribute act, cover band, wedding band, corporate band, folk/devotional group or session collective.

Each act should eventually carry: lineup, substitute pool, city, travel radius, genres, languages, event suitability, repertoire, media, fee range, fee basis, availability, verified credits, tech rider, hospitality rider, production dependencies, travel party, manager/agent, cancellation terms and settlement/KYC identity.

## Hiring seat model
A band/project seat is not just `instrument = guitar`. It can include role, instrument/rig, count, skill level, commitment, rehearsal location, schedule, tour availability, compensation, audition material, repertoire, gear expectations, travel/visa needs and whether a substitute is acceptable.

Examples: lead vocalist, backing vocalist, acoustic/electric/bass guitar, keys/synth, drums/percussion, tabla/dholak/dhol/mridangam, sitar/sarod/santoor/veena, strings, winds/brass, playback engineer, FOH, monitor engineer, RF, backline tech, guitar/drum tech, stage manager, show caller, show runner, technical director, production manager, tour manager, lighting/video/LED/VJ, composer/arranger/orchestrator, producer, mix/master engineer, A&R, manager, booking agent, publisher/rights/royalty/metadata and creative/media roles.

## Booking state machine
`requested → viewed → quoted → negotiating → accepted → completed`
Alternative terminals: `declined`, `cancelled`, `disputed`.
Payment state is separate: `created → authorized/paid → refunded/failed`.

## Quote anatomy
Performance fee + travel + production/backline + other charges; currency; deposit%; validity; inclusions; exclusions; cancellation/reschedule terms. Quote versions are immutable; a new quote supersedes the previous one.

## Availability integrity
Current implementation blocks two accepted bookings for one act on one date. Production scale should upgrade this to timezone-aware start/end blocks, setup/soundcheck buffers, travel buffers, multi-day bookings, partial-lineup conflicts and member-level calendars.

## Money flow
SaaS subscription billing and booking money are separate ledgers. For bookings, create the gateway Order server-side, collect the deposit, verify the signature/webhook, then later collect balance. Marketplace settlement to performers should only be enabled after compliant payee KYC and an approved marketplace settlement product/workflow.
