import {expect, test, type Page, type Request} from '@playwright/test';

// Mocked-API regressions for the poster side of hiring (employer pages and the jobseeker hiring routes).
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Role = 'jobseeker' | 'employer';
type Handler = (request: Request, url: URL) => {status?: number; body: unknown} | undefined;

const description = 'Record layered guitar parts for a feature film score over three sessions with the composer.';
const draftJob = {
  id: 'job-draft', employer_id: 'qa-employer', title: 'Session guitarist', company: 'Verse Studio', location: '', kind: 'Contract', type: 'Contract',
  genre: 'Film', description: '', status: 'draft', opportunity_kind: 'session', function_area: 'Performance', workplace: 'onsite',
  compensation_min: null, compensation_max: null, currency: 'INR', paid: true, skills: ['Guitar'], languages: [], screeningQuestions: [],
  slots: 1, applications: 0, allowedNextStatuses: ['pending', 'closed'],
};
const application = {
  id: 'app-1', jobId: 'job-live', jobTitle: 'Tour drummer', candidateId: 'cand-1', candidateName: 'Asha Rao', candidateEmail: 'asha@example.invalid',
  status: 'Under Review', skills: ['Drums'], screeningAnswers: ['Q :: yes', 'Q :: yes'], allowedNextStatuses: ['Shortlisted', 'Interview Scheduled', 'Rejected'],
};
const candidates = [
  {id: 'cand-1', name: 'Asha Rao', headline: 'Drummer', skills: ['Drums'], shortlisted: false},
  {id: 'cand-2', name: 'Vik Shah', headline: 'Bassist', skills: ['Bass'], shortlisted: false},
];

async function signIn(page: Page, role: Role, handler: Handler = () => undefined) {
  const calls: Array<{method: string; path: string; body: any}> = [];
  const dialogs: string[] = [];
  const errors: string[] = [];
  page.on('dialog', dialog => { dialogs.push(dialog.message()); void dialog.dismiss(); });
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(r => {
    localStorage.setItem('verse_access_token', 'qa-token');
    localStorage.setItem(`verse-tour-v2-${r}`, 'done');
  }, role);
  await page.route('**/api/**', route => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api/, '');
    let body: any = null;
    try { body = request.postDataJSON(); } catch { body = request.postData(); }
    calls.push({method: request.method(), path, body});
    if (path === '/me') return route.fulfill({json: {user: {id: `qa-${role}`, name: 'QA User', email: 'qa@example.invalid', role, status: 'active', profileComplete: true}}});
    const custom = handler(request, url);
    if (custom) return route.fulfill({status: custom.status ?? 200, json: custom.body});
    if (path === '/notifications/unread') return route.fulfill({json: {unread: 0}});
    return route.fulfill({json: {}});
  });
  return {calls, dialogs, errors};
}

test('a saved draft can be reopened from the dashboard, edited and submitted for review', async ({page}) => {
  const {calls, errors} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname === '/api/employer/jobs') return {body: {jobs: [draftJob]}};
    if (url.pathname === '/api/jobs/job-draft') return {body: {job: {...draftJob, employer_id: 'qa-employer'}}};
    if (url.pathname === '/api/employer/jobs/job-draft' && request.method() === 'PATCH') return {body: {ok: true, job: {...draftJob, status: 'pending'}}};
    return undefined;
  });
  await page.goto('/employer');
  const card = page.getByTestId('pipeline-job').filter({hasText: 'Session guitarist'});
  await expect(card).toContainText('Draft');
  await card.getByRole('link', {name: 'Edit Session guitarist'}).click();

  await expect(page).toHaveURL(/\/employer\/post-job\?edit=job-draft$/);
  await expect(page.getByLabel('Title')).toHaveValue('Session guitarist');
  await expect(page.getByLabel('Skills')).toHaveValue('Guitar');
  await page.getByLabel('Location').fill('Mumbai');
  await page.getByLabel(/^Description/).fill(description);
  await page.getByRole('button', {name: 'Submit for review'}).click();

  await expect(page).toHaveURL(/\/employer$/);
  const patch = calls.find(c => c.method === 'PATCH' && c.path === '/employer/jobs/job-draft');
  expect(patch?.body).toMatchObject({status: 'pending', location: 'Mumbai', description, skills: ['Guitar']});
  expect(errors).toEqual([]);
});

test('saving a draft without a title explains why instead of calling the API', async ({page}) => {
  const {calls} = await signIn(page, 'employer');
  await page.goto('/employer/post-job');
  await page.getByRole('button', {name: 'Save draft'}).click();
  await expect(page.getByRole('alert')).toContainText('Add a title');
  await expect(page.getByLabel('Title')).toBeFocused();
  expect(calls.filter(c => c.method === 'POST' && c.path === '/jobs')).toHaveLength(0);
});

test('hitting the plan limit keeps the opportunity as a draft and links to plans', async ({page}) => {
  const {calls} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname !== '/api/jobs' || request.method() !== 'POST') return undefined;
    const body = request.postDataJSON();
    return body.status === 'draft' ? {status: 201, body: {id: 'job-new', status: 'draft', moderationFlags: []}} : {status: 402, body: {error: 'Your plan allows 1 active opportunity.', code: 'PLAN_LIMIT'}};
  });
  await page.goto('/employer/post-job');
  await page.getByLabel('Title').fill('Tour keyboardist');
  await page.getByLabel('Location').fill('Pune');
  await page.getByLabel(/^Description/).fill(description);
  await page.getByRole('button', {name: 'Submit for review'}).click();
  await expect(page.getByText(/saved as a draft/)).toBeVisible();
  await expect(page.getByRole('button', {name: 'View plans'})).toBeVisible();
  expect(calls.filter(c => c.method === 'POST' && c.path === '/jobs').map(c => c.body.status)).toEqual(['pending', 'draft']);
});

test('interview scheduling and recruiter notes use in-page dialogs, not browser prompts', async ({page}) => {
  const {calls, dialogs, errors} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname === '/api/employer/applications' && request.method() === 'GET') return {body: {applications: [application]}};
    if (url.pathname === '/api/employer/applications/app-1') return {body: {ok: true}};
    return undefined;
  });
  await page.goto('/employer/applications');
  await expect(page.getByRole('heading', {name: 'Asha Rao'})).toBeVisible();

  await page.getByRole('button', {name: 'Interview Scheduled'}).click();
  const interview = page.getByRole('dialog', {name: 'Schedule interview'});
  await expect(interview).toBeVisible();
  await expect(interview.getByRole('button', {name: 'Schedule interview'})).toBeDisabled();
  await interview.getByLabel('Interview date and time').fill('2030-01-15T14:30');
  await interview.getByRole('button', {name: 'Schedule interview'}).click();
  await expect(interview).toBeHidden();

  await page.getByRole('button', {name: 'Rate / note'}).click();
  const notes = page.getByRole('dialog', {name: 'Rate and note'});
  await notes.getByLabel('Recruiter note').fill('Great feel');
  await notes.getByLabel('Internal rating').selectOption('4');
  await notes.getByRole('button', {name: 'Save notes'}).click();
  await expect(notes).toBeHidden();

  const patches = calls.filter(c => c.method === 'PATCH').map(c => c.body);
  expect(patches[0]).toMatchObject({status: 'Interview Scheduled'});
  expect(new Date(patches[0].interviewDate).toISOString()).toBe(new Date('2030-01-15T14:30').toISOString());
  expect(patches[1]).toEqual({recruiterNote: 'Great feel', recruiterRating: 4});
  expect(dialogs).toEqual([]);
  expect(errors).toEqual([]);
});

test('talent can be filed into a new or existing folder from a dialog', async ({page}) => {
  const {calls, dialogs} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname === '/api/candidates') return {body: {candidates}};
    if (url.pathname === '/api/talent-folders' && request.method() === 'GET') return {body: {folders: [{id: 'f-1', name: 'Tour band', count: 3}]}};
    if (url.pathname === '/api/talent-folders' && request.method() === 'POST') return {status: 201, body: {id: 'f-2'}};
    if (url.pathname.startsWith('/api/talent-folders/')) return {status: 201, body: {ok: true}};
    return undefined;
  });
  await page.goto('/employer/candidates');
  await page.getByRole('button', {name: 'Add Asha Rao to a folder'}).click();
  let dialog = page.getByRole('dialog', {name: 'Add to talent folder'});
  await expect(dialog.getByLabel('Folder', {exact: true})).toHaveValue('f-1');
  await dialog.getByRole('button', {name: 'Add to folder'}).click();
  await expect(dialog).toBeHidden();

  await page.getByRole('button', {name: 'Add Vik Shah to a folder'}).click();
  dialog = page.getByRole('dialog', {name: 'Add to talent folder'});
  await dialog.getByLabel('Folder', {exact: true}).selectOption('new');
  await dialog.getByLabel('New folder name').fill('Session players');
  await dialog.getByRole('button', {name: 'Add to folder'}).click();
  await expect(dialog).toBeHidden();

  const posts = calls.filter(c => c.method === 'POST').map(c => [c.path, c.body]);
  expect(posts).toEqual([
    ['/talent-folders/f-1/candidates/cand-1', {}],
    ['/talent-folders', {name: 'Session players'}],
    ['/talent-folders/f-2/candidates/cand-2', {}],
  ]);
  expect(dialogs).toEqual([]);
});

test('organization verification asks for a valid link in a dialog', async ({page}) => {
  const {calls, dialogs} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname === '/api/verification-requests') return {status: 201, body: {id: 'v-1'}};
    return undefined;
  });
  await page.goto('/employer/profile');
  await page.getByRole('button', {name: 'Request verification'}).click();
  const dialog = page.getByRole('dialog', {name: 'Request organization verification'});
  await dialog.getByLabel('Evidence link').fill('not a link');
  await dialog.getByRole('button', {name: 'Submit request'}).click();
  // The browser's own URL validation blocks the submission and marks the field invalid.
  expect(await dialog.getByLabel('Evidence link').evaluate(input => (input as HTMLInputElement).validity.valid)).toBe(false);
  expect(calls.some(c => c.path === '/verification-requests')).toBe(false);
  await dialog.getByLabel('Evidence link').fill('https://label.example/about');
  await dialog.getByRole('button', {name: 'Submit request'}).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByRole('button', {name: 'Verification requested'})).toBeDisabled();
  expect(calls.find(c => c.path === '/verification-requests')?.body).toMatchObject({kind: 'organization', evidenceUrl: 'https://label.example/about'});
  expect(dialogs).toEqual([]);
});

test('compare without a selection guides back to talent search instead of erroring', async ({page}) => {
  const {calls} = await signIn(page, 'jobseeker');
  await page.goto('/jobseeker/compare');
  await expect(page.getByText(/(Pick|Select) two to four professionals/)).toBeVisible();
  await expect(page.getByRole('link', {name: 'Choose professionals'})).toHaveAttribute('href', '/jobseeker/hiring/talent');
  expect(calls.some(c => c.path.startsWith('/candidates/compare'))).toBe(false);
});

test('crew planner survives a failed load and leads to Band Builder after converting', async ({page}) => {
  let fail = true;
  const {errors} = await signIn(page, 'employer', (request, url) => {
    if (url.pathname === '/api/crew-plans' && request.method() === 'GET') {
      if (fail) { fail = false; return {status: 500, body: {error: 'Crew plans are unavailable.'}}; }
      return {body: {plans: [{id: 'plan-1', title: 'Gala', event_type: 'Wedding', city: 'Goa', roles: []}]}};
    }
    if (url.pathname === '/api/crew-plans/plan-1/convert') return {status: 201, body: {projectId: 'bp-1'}};
    return undefined;
  });
  await page.goto('/employer/build-my-crew');
  await expect(page.getByRole('alert')).toContainText('Crew plans are unavailable.');
  await page.getByRole('button', {name: 'Try again'}).click();
  await page.getByRole('button', {name: /Move to Band Builder/}).click();
  await page.getByRole('main').getByRole('button', {name: /Open Band Builder/}).click();
  await expect(page).toHaveURL(/\/employer\/band-builder$/);
  expect(errors).toEqual([]);
});

test('jobseekers who hire see and manage their own opportunities on the post page', async ({page}) => {
  await signIn(page, 'jobseeker', (_request, url) => url.pathname === '/api/employer/jobs' ? {body: {jobs: [{...draftJob, employer_id: 'qa-jobseeker'}]}} : undefined);
  await page.goto('/jobseeker/hiring/post');
  const card = page.getByTestId('pipeline-job').filter({hasText: 'Session guitarist'});
  await expect(card.getByRole('link', {name: 'Edit Session guitarist'})).toHaveAttribute('href', '/jobseeker/hiring/post?edit=job-draft');
  await expect(card.getByRole('button', {name: 'Submit for review'})).toBeVisible();
});
