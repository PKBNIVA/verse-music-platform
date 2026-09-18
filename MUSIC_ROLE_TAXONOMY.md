# Verse Music Role Taxonomy

The runtime taxonomy lives in `server/music-taxonomy.mjs` and is exposed through `/api/taxonomy`.

It covers eight broad families:
1. Performance and vocal roles.
2. String instruments.
3. Keys, winds and brass.
4. Rhythm/percussion including Indian percussion.
5. Composition, writing, arranging and production.
6. Studio/audio engineering.
7. Live show, stage, touring, lighting/video and technical operations.
8. Business, rights, booking, management, education and media/creative roles.

Future migration should replace display strings with canonical role IDs, synonyms, parent/child categories and proficiency metadata so search does not fragment on spelling variants.
