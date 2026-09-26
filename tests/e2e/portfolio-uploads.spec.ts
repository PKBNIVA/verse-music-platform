import {randomUUID} from 'node:crypto';
import {expect, test, type APIRequestContext, type Page} from '@playwright/test';

// Real frontend + Rails. The API must run with Disk storage (no AWS_BUCKET) and a job
// adapter that executes jobs (development :async or GoodJob), because deleting a work
// sample removes its file through UploadCleanupJob. Direct (S3/R2) mode is simulated by
// intercepting the presign, bucket and completion requests in the browser.

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
// 40 MPEG-1 Layer III frames (128 kbps, 44.1 kHz) of silence behind an ID3v2 tag.
const MP3 = Buffer.concat([
  Buffer.from([0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0]),
  ...Array.from({length: 40}, () => Buffer.concat([Buffer.from([0xff, 0xfb, 0x90, 0x64]), Buffer.alloc(413)])),
]);
const PDF = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n');

const apiBase = () => process.env.QA_API_BASE_URL!;

async function signInFreshArtist(page: Page, request: APIRequestContext) {
  const response = await request.post(`${apiBase()}/auth/register`, {
    data: {name: 'Upload Artist', email: `qa-upload-${randomUUID()}@example.invalid`, password: 'IntegrationPass123!', role: 'jobseeker'},
  });
  expect(response.status()).toBe(201);
  const token = (await response.json()).accessToken as string;
  await page.addInitScript((value) => {
    localStorage.setItem('verse_access_token', value);
    localStorage.setItem('verse-tour-v2-jobseeker', 'done');
  }, token);
  return token;
}

async function uploadAndSave(page: Page, name: string, mimeType: string, buffer: Buffer, title: string) {
  await page.getByLabel('Upload a work-sample file').setInputFiles({name, mimeType, buffer});
  await expect(page.getByRole('button', {name: 'Remove file'})).toBeVisible();
  await expect(page.getByTestId('sample-preview')).toBeVisible();
  await page.getByLabel('Title', {exact: true}).fill(title);
  await page.getByRole('button', {name: 'Add sample'}).click();
  const card = page.getByTestId('work-sample').filter({has: page.getByRole('heading', {name: title})});
  await expect(card).toBeVisible();
  return card;
}

test.describe('portfolio uploads', () => {
  test.skip(process.env.QA_INTEGRATION !== 'true', 'Run against a disposable Rails API with QA_INTEGRATION=true.');

  test('uploads an image, an MP3 and a PDF, renders them, then deletes them and their files', async ({page, request}) => {
    const token = await signInFreshArtist(page, request);
    const auth = {Authorization: `Bearer ${token}`};
    await page.goto('/jobseeker/portfolio');
    await expect(page.getByRole('heading', {name: 'Work samples'})).toBeVisible();

    // Wrong type is refused in the browser with a clear message and no request.
    await page.getByLabel('Upload a work-sample file').setInputFiles({name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('hello')});
    await expect(page.getByRole('alert')).toContainText('Unsupported file type');

    // A dropped connection offers a retry that then succeeds.
    let failNext = true;
    await page.route('**/api/uploads/local', (route) => {
      if (failNext) {
        failNext = false;
        return route.abort('connectionreset');
      }
      return route.fallback();
    });
    await page.getByLabel('Upload a work-sample file').setInputFiles({name: 'cover.png', mimeType: 'image/png', buffer: PNG});
    await expect(page.getByRole('alert')).toContainText('Upload interrupted');
    await page.getByRole('button', {name: 'Retry upload'}).click();
    await expect(page.getByRole('button', {name: 'Remove file'})).toBeVisible();
    await page.getByLabel('Title', {exact: true}).fill('Cover art');
    await page.getByRole('button', {name: 'Add sample'}).click();
    const image = page.getByTestId('work-sample').filter({has: page.getByRole('heading', {name: 'Cover art'})});
    await expect(image.locator('img[alt="Cover art"]')).toBeVisible();
    await expect.poll(() => image.locator('img[alt="Cover art"]').evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(1);

    const audio = await uploadAndSave(page, 'demo take.mp3', 'audio/mpeg', MP3, 'Demo take');
    await expect(audio.locator('audio')).toBeAttached();
    await expect.poll(() => audio.locator('audio').evaluate((el: HTMLAudioElement) => el.readyState), {timeout: 10_000}).toBeGreaterThanOrEqual(1);
    await expect(audio.getByText('could not be played')).toHaveCount(0);

    const pdf = await uploadAndSave(page, 'rider.pdf', 'application/pdf', PDF, 'Tech rider');
    await expect(pdf.getByRole('link', {name: /PDF document/})).toBeVisible();

    const listed = await (await request.get(`${apiBase()}/portfolio`, {headers: auth})).json();
    const urls: string[] = listed.items.map((item: any) => item.url);
    expect(urls).toHaveLength(3);
    for (const url of urls) expect((await request.get(url)).status()).toBe(200);

    // Delete asks for confirmation; "Keep it" keeps the sample.
    await page.getByRole('button', {name: 'Delete Tech rider'}).click();
    await expect(page.getByRole('alertdialog')).toContainText('uploaded file is permanently deleted');
    await page.getByRole('button', {name: 'Keep it'}).click();
    await expect(pdf).toBeVisible();

    for (const title of ['Tech rider', 'Demo take', 'Cover art']) {
      await page.getByRole('button', {name: `Delete ${title}`}).click();
      await page.getByRole('button', {name: 'Delete work sample'}).click();
      await expect(page.getByTestId('work-sample').filter({has: page.getByRole('heading', {name: title})})).toHaveCount(0);
    }
    for (const url of urls) {
      await expect.poll(async () => (await request.get(url, {maxRedirects: 0})).status(), {timeout: 15_000}).toBe(404);
    }
  });

  test('direct bucket uploads post the policy form, are verified, and cannot be claimed without the server record', async ({page, request}) => {
    await signInFreshArtist(page, request);
    const bucket = 'https://bucket.verse-upload.test';
    const publicUrl = 'https://pub-verse-upload-test.r2.dev/uploads/u/k/cover.png';
    let posted = '';
    let completed = false;
    await page.route('**/api/uploads/presign', (route) => route.fulfill({json: {
      mode: 'direct', id: 'upl_fake', method: 'POST', uploadUrl: bucket, headers: {},
      fields: {key: 'uploads/u/k/cover.png', 'Content-Type': 'image/png', policy: 'cG9saWN5', 'x-amz-signature': 'sig'},
      publicUrl, completeUrl: '/api/uploads/upl_fake/complete',
    }}));
    await page.route(`${bucket}/`, async (route) => {
      posted = route.request().postDataBuffer()?.toString('latin1') || '';
      await route.fulfill({status: 201, headers: {'access-control-allow-origin': '*'}, body: ''});
    });
    await page.route('**/api/uploads/upl_fake/complete', (route) => {
      completed = true;
      return route.fulfill({json: {url: publicUrl, upload: {id: 'upl_fake', url: publicUrl, status: 'complete', contentType: 'image/png', byteSize: PNG.length}}});
    });
    await page.route(publicUrl, (route) => route.fulfill({status: 200, contentType: 'image/png', body: PNG}));

    await page.goto('/jobseeker/portfolio');
    await page.getByLabel('Upload a work-sample file').setInputFiles({name: 'cover.png', mimeType: 'image/png', buffer: PNG});
    await expect(page.getByRole('button', {name: 'Remove file'})).toBeVisible();
    expect(completed).toBe(true);
    expect(posted.indexOf('name="policy"')).toBeGreaterThan(-1);
    expect(posted.indexOf('name="policy"')).toBeLessThan(posted.indexOf('name="file"'));
    await expect(page.getByTestId('sample-preview').locator('img')).toBeVisible();

    // The real API has no completed upload with this URL for the user, so it refuses to save it.
    await page.getByRole('button', {name: 'Add sample'}).click();
    await expect(page.getByText(/must be one of your own completed uploads/)).toBeVisible();
  });

  test('embed links preview YouTube, Spotify and SoundCloud players before saving', async ({page, request}) => {
    await signInFreshArtist(page, request);
    await page.route(/youtube-nocookie\.com|open\.spotify\.com\/embed|w\.soundcloud\.com/, (route) => route.fulfill({contentType: 'text/html', body: '<p>player</p>'}));
    await page.goto('/jobseeker/portfolio');
    const link = page.getByLabel('Link', {exact: true});
    const cases = [
      ['https://youtu.be/dQw4w9WgXcQ?t=42', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=42'],
      ['https://www.youtube.com/shorts/dQw4w9WgXcQ', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'],
      ['https://open.spotify.com/intl-en/album/4aawyAB9vmqN3uQ7FjRGTy', 'https://open.spotify.com/embed/album/4aawyAB9vmqN3uQ7FjRGTy'],
      ['https://soundcloud.com/artist/track-name', 'https://w.soundcloud.com/player/?url=https%3A%2F%2Fsoundcloud.com%2Fartist%2Ftrack-name'],
    ];
    for (const [url, embed] of cases) {
      await link.fill(url);
      await expect(page.getByTestId('sample-preview').locator('iframe')).toHaveAttribute('src', new RegExp(`^${embed.replace(/[.?+]/g, '\\$&')}`));
    }
    await page.getByLabel('Title', {exact: true}).fill('Album');
    await link.fill(cases[2][0]);
    await page.getByRole('button', {name: 'Add sample'}).click();
    await expect(page.getByTestId('work-sample').locator('iframe[src^="https://open.spotify.com/embed/album/"]')).toBeVisible();
  });
});
