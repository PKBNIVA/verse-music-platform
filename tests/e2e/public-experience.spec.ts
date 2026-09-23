import {expect, test} from '@playwright/test';
import {assertNoHorizontalOverflow, openSettledPage, publicRoutes, watchRuntimeFailures} from './qa-helpers';

test.describe('public route experience', () => {
  for (const [name, path] of publicRoutes) {
    test(`${name} renders cleanly and responsively`, async ({page}, testInfo) => {
      const runtimeFailures = watchRuntimeFailures(page);
      await openSettledPage(page, path);

      await expect(page.locator('body')).toBeVisible();
      await expect(page.locator('body')).not.toBeEmpty();
      await expect(page.locator('main:visible, [role="main"]:visible, form:visible').first()).toBeVisible();
      await expect(page.locator('body')).not.toContainText(/application error|something went wrong|undefined is not/i);
      await assertNoHorizontalOverflow(page, testInfo);

      expect(runtimeFailures, runtimeFailures.join('\n')).toEqual([]);
    });
  }
});

test('a visitor can follow the primary discovery journey', async ({page}) => {
  const runtimeFailures = watchRuntimeFailures(page);
  await openSettledPage(page, '/');

  const primaryCta = page.locator('a[href="/start"]').first();
  await expect(primaryCta).toBeVisible();
  await primaryCta.click();
  await expect(page).toHaveURL(/\/start$/);
  await expect(page.getByRole('heading').first()).toBeVisible();

  await page.goBack({waitUntil: 'domcontentloaded'});
  const publicNavigation = page.locator('header a, footer a');
  await expect(publicNavigation.first()).toBeVisible();
  const count = await publicNavigation.count();
  expect(count).toBeGreaterThanOrEqual(6);
  for (let index = 0; index < count; index += 1) {
    const link = publicNavigation.nth(index);
    await expect(link).toHaveAttribute('href', /^\//);
    const accessibleName = (await link.getAttribute('aria-label')) || (await link.innerText());
    expect(accessibleName.trim(), `Unlabelled navigation link at index ${index}`).not.toBe('');
  }
  expect(runtimeFailures, runtimeFailures.join('\n')).toEqual([]);
});

test('keyboard navigation reaches interactive controls', async ({page}) => {
  await openSettledPage(page, '/');
  for (let index = 0; index < 6; index += 1) await page.keyboard.press('Tab');
  const focused = page.locator(':focus');
  await expect(focused).toBeVisible();
  await expect(focused).not.toHaveJSProperty('tagName', 'BODY');
});
