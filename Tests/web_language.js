// Exercises the actual browser language resolver in both shipped web surfaces.
// Catches wrong preference order, ignored explicit selection, and non-English fallback.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '..');
const cases = [
  ['', ['en-US', 'zh-Hans'], 'en'],
  ['', ['zh-Hans-CN', 'en-US'], 'zh'],
  ['', ['de-DE', 'zh-CN'], 'zh'],
  ['', ['fr-FR'], 'en'],
  ['', [], 'en'],
  ['?lang=en', ['zh-CN'], 'en'],
  ['?lang=zh', ['en-US'], 'zh'],
  ['?lang=invalid', ['en-GB'], 'en'],
  ['', ['ZH-hant-TW'], 'zh'],
];
for (const surface of ['website', 'guide']) {
  const file = path.join(root, surface === 'website' ? 'website/language.js' : 'JustProxy/Proxy/ConnectionGuide.html');
  const source = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const script = surface === 'guide' ? source.match(/<script id="jp-language">([\s\S]*?)<\/script>/)?.[1] : source;
  assert.ok(script, `${surface} must support visitor language selection`);
  const context = { URLSearchParams, navigator: { languages: ['en-US'] }, location: { search: '' }, document: { documentElement: { dataset: {} }, addEventListener() {} } };
  vm.createContext(context);
  vm.runInContext(script, context);
  for (const [search, preferences, expected] of cases) {
    assert.equal(context.justProxyLanguage(search, preferences), expected, `${surface}: ${search} / ${preferences}`);
  }
  console.log(`${surface}: ${cases.length} language selection cases passed`);
}
