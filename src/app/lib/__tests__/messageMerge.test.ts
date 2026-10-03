import { describe, expect, it } from 'vitest';
import { mergeMessages } from '../messageMerge';

const m = (id: string, createdAt: string, body = id) => ({ id, createdAt, body });

describe('mergeMessages', () => {
  it('keeps one copy of a message that arrives from a live update and a poll', () => {
    const live = mergeMessages([m('a', '1')], [m('b', '2')]);
    const polled = mergeMessages(live, [m('b', '2'), m('c', '3')]);
    expect(polled.map((x) => x.id)).toEqual(['a', 'b', 'c']);
  });

  it('lets the incoming copy win and drops duplicates inside one response', () => {
    const merged = mergeMessages([m('a', '1', 'old')], [m('a', '1', 'new'), m('a', '1', 'new')]);
    expect(merged).toEqual([m('a', '1', 'new')]);
  });

  it('orders by time, then id, whatever the arrival order', () => {
    expect(mergeMessages([m('z', '2')], [m('b', '1'), m('a', '2')]).map((x) => x.id)).toEqual(['b', 'a', 'z']);
  });
});
