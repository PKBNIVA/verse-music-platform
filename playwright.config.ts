import {defineConfig, devices} from '@playwright/test';

const liveBaseUrl = process.env.QA_BASE_URL?.replace(/\/$/, '');
const fullMatrix = process.env.QA_FULL_MATRIX === 'true';
const integrationRun = process.env.QA_INTEGRATION === 'true';

const browserProjects = [
  {
    name: 'chromium-desktop',
    testIgnore: /api-health\.spec\.ts/,
    use: {...devices['Desktop Chrome']},
  },
  {
    name: 'chromium-mobile',
    testIgnore: /api-health\.spec\.ts/,
    use: {...devices['Pixel 7']},
  },
  ...(fullMatrix
    ? [
        {
          name: 'firefox-desktop',
          testIgnore: /api-health\.spec\.ts/,
          use: {...devices['Desktop Firefox']},
        },
        {
          name: 'webkit-mobile',
          testIgnore: /api-health\.spec\.ts/,
          use: {...devices['iPhone 15']},
        },
      ]
    : []),
];

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : undefined,
  timeout: 30_000,
  expect: {timeout: 8_000},
  reporter: process.env.CI
    ? [['line'], ['html', {open: 'never'}], ['json', {outputFile: 'test-results/qa-results.json'}]]
    : [['list'], ['html', {open: 'never'}]],
  use: {
    baseURL: liveBaseUrl || 'http://127.0.0.1:4173',
    actionTimeout: 8_000,
    navigationTimeout: 20_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    reducedMotion: 'reduce',
  },
  projects: [
    {
      name: 'api',
      testMatch: /api-health\.spec\.ts/,
      use: {},
    },
    ...browserProjects,
  ],
  webServer: liveBaseUrl
    ? undefined
    : [
        {
          command: 'npm run build && npm exec vite preview -- --host 127.0.0.1 --port 4173',
          url: 'http://127.0.0.1:4173',
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
        },
        // error-monitoring.spec.ts only (skipped in integration runs): a local stand-in for
        // Sentry's ingest endpoint, and the app built with a fake DSN pointing at it.
        ...(integrationRun ? [] : [
          {
            command: 'node tests/e2e/support/sentry-sink.mjs 4175',
            url: 'http://127.0.0.1:4175',
            reuseExistingServer: !process.env.CI,
            timeout: 30_000,
          },
          {
            command: 'npm exec vite build -- --outDir dist-qa-sentry && npm exec vite preview -- --outDir dist-qa-sentry --host 127.0.0.1 --port 4174',
            url: 'http://127.0.0.1:4174',
            env: {VITE_SENTRY_DSN: 'http://qapublickey@127.0.0.1:4175/1', VITE_SENTRY_ENVIRONMENT: 'qa', VITE_RELEASE: 'qa-sentry-build'},
            reuseExistingServer: !process.env.CI,
            timeout: 120_000,
          },
        ]),
      ],
});
