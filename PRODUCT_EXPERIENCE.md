# Verse Product Experience System — v0.4

## Experience principle
A user should not need to understand Verse before getting value. The primary navigation is therefore goal-led:

1. Find music work
2. Hire/build a team
3. Book live music
4. Solve an urgent replacement
5. Search everything

Advanced modules remain available, but the product should reveal them in context rather than making the user choose among dozens of feature names.

## Implemented in this pass
- First-login, role-aware product tour for professionals and hiring accounts.
- Persistent “Take product tour” launcher from the account menu.
- Public 5-minute guide explaining the shortest path for each major use case.
- `/start` intent hub with four plain-language entry points.
- `/search` global search across opportunities, professionals, acts and work samples.
- Elasticsearch REST integration with fuzzy multi-field search and transparent SQLite fallback.
- Search health endpoint and admin reindex action.
- Portfolio/work-sample model expanded to type, tags, genres, roles, instruments, credit name, year, featured status, visibility and ordering.
- Multiple work samples supported; users can mix external URLs with uploaded files.
- Local development media upload with type/size validation and unguessable filenames.
- Production object-storage upload adapter through a signing webhook.
- Distinct legal/trust pages with correct routing: About, Terms, Privacy, Safety, Cookies, Refunds, Community Guidelines, Accessibility and Contact.
- Human-readable `/sitemap` plus XML `/sitemap.xml` and `/robots.txt`.
- Search/auth/private pages marked noindex; public acquisition pages remain indexable.
- Duplicate navigation entries removed.

## Product-design details intentionally handled
- A musician may be a worker, hirer and booker at the same time.
- Booking an act is not the same workflow as recruiting a musician.
- Urgent replacement is intentionally separate from normal recruitment.
- One generic portfolio reel is weak proof; sample-level tagging allows evidence to match the exact search/hiring context.
- Users may use informal vocabulary, misspellings or incomplete terminology; Elasticsearch uses fuzzy matching while the fallback remains usable.
- Search infrastructure failure must not make the marketplace unusable; database fallback is automatic.
- Public contact data stays private even when a profile is searchable.
- Search results pages are useful to people but should not create infinite/low-value indexable URL combinations.
- Local uploads are useful for development but are not treated as production-grade object storage.
- Tour completion is a non-sensitive browser preference and is deliberately not part of authentication state.

## High-value next UX work after real-user testing
These should be driven by observed behavior, not built blindly:
- Search synonym/ontology tuning from zero-result queries.
- Personalized search ranking based on role, location, availability and prior intent.
- Portfolio media player/waveform and automatic thumbnail/transcode pipeline.
- Draft autosave on long job/booking forms.
- Recently viewed professionals/opportunities.
- Compare 2–4 candidates side by side.
- Contextual tooltips for industry terms (FOH, IEM, backline, first hold, buyout, work-for-hire).
- Guided “build my crew” brief generation.
- Saved filter chips and recent searches.
- Keyboard command palette for heavy recruiter users.
- Native mobile push and deep links when native apps are introduced.

## UX metrics to instrument in production
- Time to first successful search
- Search -> detail click-through
- Zero-result search rate
- Profile -> message/application conversion
- Job post completion/abandonment by field
- Booking enquiry completion rate
- Tour completion / skip rate
- Time to first qualified applicant
- Time to first urgent-replacement response
- Portfolio sample open rate by tag/role
- Search fallback rate / Elasticsearch error rate
