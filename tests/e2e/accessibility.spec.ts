import AxeBuilder from '@axe-core/playwright';
import {expect, test} from '@playwright/test';
import {accessibilityRoutes, openSettledPage} from './qa-helpers';

test.describe('WCAG accessibility and colour contrast', () => {
  for (const [name, path] of accessibilityRoutes) {
    test(`${name} has no automatically detectable WCAG A/AA violations`, async ({page}, testInfo) => {
      await openSettledPage(page, path);
      const result = await new AxeBuilder({page})
        .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
        .analyze();

      if (result.violations.length) {
        await testInfo.attach('axe-violations.json', {
          body: JSON.stringify(result.violations, null, 2),
          contentType: 'application/json',
        });
      }
      expect(
        result.violations,
        result.violations.map(v => `${v.impact}: ${v.id} — ${v.help} (${v.nodes.length})`).join('\n'),
      ).toEqual([]);
    });
  }
});
