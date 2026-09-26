import {randomUUID} from 'node:crypto';
import {expect, test} from '@playwright/test';

test.describe('real frontend and Rails journeys', () => {
  test.skip(process.env.QA_INTEGRATION !== 'true', 'Run against a disposable Rails test database with QA_INTEGRATION=true.');

  for (const role of ['jobseeker', 'employer'] as const) {
    test(`${role} registers, signs out, signs back in, and keeps profile data`, async ({page, request}) => {
      const email = `qa-${randomUUID()}@example.invalid`;
      const password = 'IntegrationPass123!';
      const name = role === 'jobseeker' ? 'Integration Artist' : 'Integration Studio';
      const profilePath = `/${role}/profile`;

      await page.goto(`/auth/${role}`);
      await page.getByRole('button', {name: /create .* account/i}).click();
      await page.getByLabel(role === 'employer' ? 'Your or company name' : 'Full name').fill(name);
      await page.getByLabel('Email').fill(email);
      await page.getByLabel('Password', {exact: true}).fill(password);
      await page.getByRole('button', {name: 'Create account', exact: true}).click();
      await expect(page).toHaveURL(new RegExp(`${profilePath}$`));

      const token = await page.evaluate(() => localStorage.getItem('verse_access_token'));
      expect(token).toBeTruthy();
      const apiBase = process.env.QA_API_BASE_URL!;
      const me = await request.get(`${apiBase}/me`, {headers: {Authorization: `Bearer ${token}`}});
      expect(me.status()).toBe(200);
      expect((await me.json()).user).toMatchObject({email, role});
      const forbidden = await request.get(`${apiBase}/admin/stats`, {headers: {Authorization: `Bearer ${token}`}});
      expect(forbidden.status()).toBe(403);

      const tour = page.getByRole('dialog', {name: 'Verse product tour'});
      await expect(tour).toBeVisible();
      await tour.getByRole('button', {name: 'Close tour'}).click();
      await expect(tour).toBeHidden();

      if (role === 'jobseeker') {
        await page.getByPlaceholder(/Playback singer/).fill('Integration vocalist');
        await page.getByRole('button', {name: 'Save career profile'}).click();
      } else {
        await page.locator('form input').first().fill('Integration Music Studio');
        await page.getByRole('button', {name: 'Save organization profile'}).click();
      }
      await expect.poll(async () => {
        const response = await request.get(`${apiBase}/me`, {headers: {Authorization: `Bearer ${token}`}});
        return (await response.json()).user.profileComplete;
      }).toBe(true);

      await page.getByRole('button', {name: 'Open account menu'}).click();
      await page.getByRole('menuitem', {name: 'Sign out'}).click();
      await expect(page).toHaveURL(/\/$/);
      await expect.poll(async () => {
        const revoked = await request.get(`${apiBase}/me`, {headers: {Authorization: `Bearer ${token}`}});
        return revoked.status();
      }).toBe(401);
      await expect.poll(() => page.evaluate(() => localStorage.getItem('verse_access_token'))).toBeNull();

      await page.goto(`/auth/${role}`);
      await page.getByLabel('Email').fill(email);
      await page.getByLabel('Password', {exact: true}).fill(password);
      await page.getByRole('button', {name: 'Sign in'}).click();
      await expect.poll(() => new URL(page.url()).pathname).toBe(`/${role}`);
      await page.goto(profilePath);
      if (role === 'jobseeker') {
        await expect(page.getByPlaceholder(/Playback singer/)).toHaveValue('Integration vocalist');
      } else {
        await expect(page.locator('form input').first()).toHaveValue('Integration Music Studio');
      }
    });
  }
});
