/* ----------------------------------------------------------
   brand.js
   - Detects brand by domain or ?brand=dk|se|ie
   - Exposes window.__BRAND { market, lang, logo, favicon, video, showVideo, name, title, showFAQ }
   - Swaps logo, favicon and chat FAB icon
   - Sets <html lang> and document title
   - (NEW) Supports asset base override via ?assets=/test or window.__ASSET_BASE_HINT__
   - (NEW) Adds showFAQ brand flag (SE hidden by default) with ?faq=1|0 override
---------------------------------------------------------- */
(function () {
  const host = (location.hostname || '').toLowerCase();
  const qs   = new URLSearchParams(location.search);

  // (NEW) Optional asset base override, e.g. ?assets=/test
  const assetsHint  = (window.__ASSET_BASE_HINT__ || '').trim();
  const assetsParam = (qs.get('assets') || '').trim();
  const ASSET_BASE  = assetsParam || assetsHint || '';
  const ASSET_BASE_NORM = ASSET_BASE
    ? ('/' + ASSET_BASE.replace(/^\/+|\/+$/g,'')).replace(/\/+/g,'/')
    : '';

  const withBase = (p) => {
    if (!ASSET_BASE_NORM) return p;
    if (typeof p !== 'string') return p;
    // only rewrite /assets/* paths
    if (p.startsWith('/assets/')) return ASSET_BASE_NORM + p;
    return p;
  };

  // Map domains → brand keys
  const BRAND_BY_HOST = {
    'dok.dinfamiliejurist.dk': 'dk',
    'dinfamiliejurist.dk'   : 'dk',
    'dok.dinfamiljejurist.se': 'se',
    'dinfamiljejurist.se'    : 'se',
    'docs.hereslaw.ie'       : 'ie',
    'hereslaw.ie'            : 'ie',
    'localhost'              : 'dk',
    '127.0.0.1'              : 'dk'
  };

  // Static config per brand
  const CONFIG = {
    dk: {
      market : 'DFJ_DK',
      lang   : 'da',
      logo   : '/assets/dk/logo.png',
      favicon: '/assets/dk/favicon.png',
      video  : 'https://www.youtube.com/embed/UsFmArdrO8s?rel=0',
      showVideo: true,
      name   : 'Din Familiejurist',
      title  : 'Din Familiejurist - Gennemgå og godkend dine dokumenter',
      showFAQ: true,              // DK shows FAQ
      countryIso: 'DK'            // (NEW) used for phone defaults/theme
    },
    se: {
      market : 'FA_SE',
      lang   : 'sv',
      logo   : '/assets/se/logo.png',
      favicon: '/assets/se/favicon.png',
      video  : 'https://www.youtube.com/embed/S54tmHZDGKo?rel=0',
      showVideo: true,
      name   : 'Din Familjejurist',
      title  : 'Din Familjejurist – Granska och godkänn dina dokument',
      showFAQ: false,             // (NEW) SE hides FAQ by default
      countryIso: 'SE'            // (NEW)
    },
    ie: {
      market : 'Ireland',
      lang   : 'en',
      logo   : '/assets/ie/logo.png',
      favicon: '/assets/ie/favicon.png',
      video  : '',
      showVideo: false,
      name   : "Heres Law",
      title  : "Heres Law – Review & Approve your documents",
      showFAQ: true,              // IE shows FAQ
      countryIso: 'IE'            // (NEW)
    }
  };

  // Determine brand key (query override > host map > dk)
  const qBrand = (qs.get('brand') || '').toLowerCase(); // dk|se|ie
  const key    = (qBrand && CONFIG[qBrand]) ? qBrand : (BRAND_BY_HOST[host] || 'dk');
  const cfg    = { ...CONFIG[key] };

  // Optional language override (?lang=da|sv|en)
  const qLang = (qs.get('lang') || '').toLowerCase();
  if (/^(da|sv|en)$/.test(qLang)) cfg.lang = qLang;

  // (NEW) Optional FAQ override (?faq=1|true to show, ?faq=0|false to hide)
  const qFaq = (qs.get('faq') || '').toLowerCase();
  if (qFaq === '1' || qFaq === 'true')  cfg.showFAQ = true;
  if (qFaq === '0' || qFaq === 'false') cfg.showFAQ = false;

  // Publish
  window.__BRAND = {
    market : cfg.market,
    lang   : cfg.lang,
    logo   : withBase(cfg.logo),
    favicon: withBase(cfg.favicon),
    video  : cfg.video && cfg.video.startsWith('/assets/') ? withBase(cfg.video) : (cfg.video || ''),
    showVideo: cfg.showVideo,
    name   : cfg.name,
    title  : cfg.title,
    showFAQ: cfg.showFAQ,           // (NEW)
    countryIso: cfg.countryIso      // (NEW) consumed by app.js for phone default
  };

  // Apply language + title
  try { document.documentElement.lang = window.__BRAND.lang || document.documentElement.lang || 'da'; } catch(e){}
  if (window.__BRAND.title) document.title = window.__BRAND.title;

  // (NEW) set data-brand for CSS theme overrides (se/ie accents)
  try { document.documentElement.setAttribute('data-brand', key); } catch(e){}

  // Swap logo
  const logoEl = document.getElementById('brandLogo');
  if (logoEl && window.__BRAND.logo) {
    logoEl.src = window.__BRAND.logo;
    logoEl.alt = window.__BRAND.name || logoEl.alt || '';
  }

  // Ensure <link rel="icon"> exists, then swap favicon
  function ensureFaviconEl() {
    let link = document.querySelector('link[rel="icon"]');
    if (!link) {
      link = document.createElement('link');
      link.rel = 'icon';
      document.head.appendChild(link);
    }
    return link;
  }
  if (window.__BRAND.favicon) {
    ensureFaviconEl().href = window.__BRAND.favicon;
  }

  // Update chat FAB icon (CSS points at favicon.png; override inline)
  const fab = document.getElementById('chatFab');
  if (fab && window.__BRAND.favicon) {
    fab.style.backgroundImage = `url('${window.__BRAND.favicon}')`;
  }

  // Optional: swap visible brand text if present
  const tag = document.querySelector('.tagline');
  if (tag && window.__BRAND.name) tag.textContent = window.__BRAND.name;
})();
