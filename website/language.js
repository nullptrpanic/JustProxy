function justProxyLanguage(search, languages) {
  const explicit = new URLSearchParams(search).get('lang');
  if (explicit === 'en' || explicit === 'zh') return explicit;
  for (const language of languages || []) {
    if (/^zh(?:-|$)/i.test(language)) return 'zh';
    if (/^en(?:-|$)/i.test(language)) return 'en';
  }
  return 'en';
}

const justProxySelectedLanguage = justProxyLanguage(location.search, navigator.languages || [navigator.language]);
document.documentElement.dataset.language = justProxySelectedLanguage;
document.documentElement.lang = justProxySelectedLanguage === 'zh' ? 'zh-Hans' : 'en';

document.addEventListener('DOMContentLoaded', () => {
  const visible = document.querySelector(`main[data-language="${justProxySelectedLanguage}"]`);
  if (visible) {
    document.title = visible.dataset.title;
    document.querySelector('meta[name="description"]').content = visible.dataset.description;
  }
  document.querySelectorAll('a[data-site-link]').forEach(link => {
    const url = new URL(link.href);
    url.searchParams.set('lang', justProxySelectedLanguage);
    link.href = url.href;
  });
  document.querySelectorAll('a[data-language-choice]').forEach(link => {
    if (link.dataset.languageChoice === justProxySelectedLanguage) link.setAttribute('aria-current', 'true');
  });
});
