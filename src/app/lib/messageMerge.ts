/** Orders messages oldest first; ties by id, so the order never depends on arrival. */
export const byTime = (a: { createdAt: string; id: string }, b: { createdAt: string; id: string }) =>
  a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id);

/**
 * Adds `incoming` to `current` once each: a message that arrives twice (a live update and a poll
 * racing, or the sender's own copy) keeps one entry, and the incoming copy wins, so a later read
 * receipt or edit replaces the old one.
 */
export function mergeMessages<T extends { id: string; createdAt: string }>(current: T[], incoming: T[]): T[] {
  const ids = new Set(incoming.map((m) => m.id));
  const unique = new Map<string, T>();
  incoming.forEach((m) => unique.set(m.id, m));
  return [...current.filter((m) => !ids.has(m.id)), ...unique.values()].sort(byTime);
}
