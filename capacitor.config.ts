import type {
  CapacitorConfig,
} from '@capacitor/cli';

const appId =
  process.env.APP_PACKAGE_ID ||
  'com.sitetoapp.test';

const appName =
  process.env.APP_NAME ||
  'SiteToApp Test';

const websiteUrl =
  process.env.APP_WEBSITE_URL ||
  'https://www.partenairefoyer.com';

const config: CapacitorConfig = {
  appId,

  appName,

  webDir:
    'www',

  server: {
    url:
      websiteUrl,

    cleartext:
      false,

    androidScheme:
      'https',

    allowNavigation: [
      '*',
    ],
  },

  android: {
    allowMixedContent:
      false,

    appendUserAgent:
      'PartenaireFoyerApp Android',
  },
};

export default config;
