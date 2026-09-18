# Verse Search

## Architecture
Verse supports two search modes behind one `/api/search` endpoint.

### Elasticsearch (recommended production mode)
Configure:

```env
ELASTICSEARCH_URL=https://your-cluster
ELASTICSEARCH_API_KEY=...
ELASTICSEARCH_INDEX_PREFIX=verse
```

Indexes:
- `verse-jobs`
- `verse-talent`
- `verse-acts`
- `verse-samples`

The server uses Elasticsearch's REST document/index and bulk APIs. Search uses multi-field fuzzy matching, boosting names/titles/roles over long descriptions.

After enabling a new cluster, sign in as admin and use **Reindex search**, or call:

```http
POST /api/admin/search/reindex
```

Health:

```http
GET /api/search/status
GET /api/readiness
```

### Database fallback
When Elasticsearch is unconfigured or unavailable, `/api/search` falls back to indexed SQLite queries/LIKE matching. The user sees results rather than a search outage. At production scale, PostgreSQL should replace SQLite even as the fallback database.

## Index consistency
Core write paths asynchronously request index updates for:
- professional profile changes
- published/unpublished opportunities
- act creation
- work-sample create/update/delete

Admin reindex is the recovery mechanism for missed events or a new cluster.

## Production recommendations
- Put Elasticsearch behind private networking where possible.
- Use least-privilege API keys.
- Add explicit mappings/templates before large scale, especially keyword/facet and geo fields.
- Add aliases for zero-downtime index versioning.
- Build synonym sets from real zero-result queries, not assumptions.
- Add geo-distance search once locations are normalized to coordinates.
- Track query latency, zero results and click-through as product metrics.
