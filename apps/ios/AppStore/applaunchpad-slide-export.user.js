// ==UserScript==
// @name         AppLaunchpad — Export slide PNG
// @namespace    https://theapplaunchpad.com/
// @version      2.0.0
// @description  Adds a download button above every AppLaunchpad slide and exports it as a full-resolution PNG.
// @author       adrien
// @match        https://theapplaunchpad.com/dashboard/*
// @grant        GM_xmlhttpRequest
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_registerMenuCommand
// @connect      amazonaws.com
// @connect      cloudfront.net
// @connect      theapplaunchpad.com
// @connect      googleapis.com
// @connect      gstatic.com
// @connect      *
// @run-at       document-idle
// @noframes
// ==/UserScript==

/* global GM_xmlhttpRequest, GM_setValue, GM_getValue, GM_registerMenuCommand, GM */

(function () {
  'use strict';

  // ─────────────────────────────────────────────────────────────────────────
  // Config
  // ─────────────────────────────────────────────────────────────────────────

  const CONFIG = Object.freeze({
    UI_ATTR: 'data-alp-export-ui',
    STORE_SELECTOR: 'slideSelector',
    STORE_TARGET_WIDTH: 'targetWidth',
    FETCH_TIMEOUT_MS: 20000,
    // Shorter than for images: an unreachable font must not stall the export
    // for 20s -- the text will simply fall back to a system font.
    FONT_TIMEOUT_MS: 6000,
    RESYNC_DEBOUNCE_MS: 400,
    // Retries after load: the editor mounts its slides asynchronously.
    BOOT_RETRIES_MS: [0, 800, 2000, 4000, 8000],
    MIN_LOGICAL_SIDE: 120,
    // Accepted height/width ratios: phone/tablet portrait, or landscape.
    PORTRAIT_RATIO: [1.15, 2.7],
    LANDSCAPE_RATIO: [0.37, 0.87],
    // Two nested elements whose areas differ by less than this are duplicates.
    NESTED_AREA_TOLERANCE: 0.15,
    MAX_PIXEL_RATIO: 12,
    // Dry run before the real render: avoids partial exports when fonts or
    // images are not decoded yet. Set to false if it feels too slow.
    WARMUP_RENDER: true,
    WARMUP_PIXEL_RATIO: 0.15,
  });

  const SLIDE_SELECTORS = Object.freeze([
    // AppLaunchpad's actual class (verified against the live editor): the
    // reliable anchor. The rest only matters if they rename things.
    '.appLaunchpadCanvas',
    '[data-slide]',
    '[data-slide-id]',
    '[data-screenshot]',
    '[data-testid*="slide" i]',
    '[id^="slide"]',
    '[id^="screenshot"]',
    '[class*="slideCanvas" i]',
    '[class*="screenshotCanvas" i]',
    '[class*="slide" i]',
    '[class*="screenshot" i]',
    '[class*="canvas" i]',
  ]);

  const VOLATILE_CLASS_RE = /^(is-|has-|js-|active$|selected$|current$|open$|hover$|focus|dragging|hidden$)/i;
  // A factory rather than a constant: a /g regex carries a mutable `lastIndex`,
  // and sharing one between `matchAll` and `replace` is a silent-bug generator.
  const bgUrlPattern = () => /url\((['"]?)([^'")]+)\1\)/g;

  // ─────────────────────────────────────────────────────────────────────────
  // Utilitaires
  // ─────────────────────────────────────────────────────────────────────────

  const log = (...args) => console.log('%c[ALP export]', 'color:#6c5ce7;font-weight:bold', ...args);
  const warn = (...args) => console.warn('%c[ALP export]', 'color:#e17055;font-weight:bold', ...args);

  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  const debounce = (fn, delay) => {
    let timer = null;
    return (...args) => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => fn(...args), delay);
    };
  };

  const sleep = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));

  const cssEscape = (value) =>
    window.CSS && typeof CSS.escape === 'function'
      ? CSS.escape(value)
      : String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&');

  const readStore = (key, fallback) => {
    try {
      const value = GM_getValue(key, fallback);
      return value === undefined ? fallback : value;
    } catch (error) {
      warn('Could not read from storage', error);
      return fallback;
    }
  };

  const writeStore = (key, value) => {
    try {
      GM_setValue(key, value);
    } catch (error) {
      warn('Could not write to storage', error);
    }
  };

  const resolveHtmlToImage = () =>
    htmlToImageLib && typeof htmlToImageLib.toBlob === 'function' ? htmlToImageLib : null;

  // ─────────────────────────────────────────────────────────────────────────
  // Toasts
  // ─────────────────────────────────────────────────────────────────────────

  const TOAST_COLORS = Object.freeze({
    info: '#2d3436',
    success: '#00875a',
    error: '#c0392b',
    warn: '#b7791f',
  });

  let toastStack = null;

  const ensureToastStack = () => {
    if (toastStack && toastStack.isConnected) return toastStack;
    toastStack = document.createElement('div');
    toastStack.setAttribute(CONFIG.UI_ATTR, 'toasts');
    Object.assign(toastStack.style, {
      position: 'fixed',
      right: '16px',
      bottom: '16px',
      zIndex: '2147483001',
      display: 'flex',
      flexDirection: 'column',
      gap: '8px',
      alignItems: 'flex-end',
      pointerEvents: 'none',
      fontFamily: 'system-ui, -apple-system, sans-serif',
    });
    document.documentElement.appendChild(toastStack);
    return toastStack;
  };

  const toast = (message, kind = 'info', durationMs = 4000) => {
    const node = document.createElement('div');
    node.setAttribute(CONFIG.UI_ATTR, 'toast');
    node.textContent = message;
    Object.assign(node.style, {
      background: TOAST_COLORS[kind] || TOAST_COLORS.info,
      color: '#fff',
      padding: '10px 14px',
      borderRadius: '8px',
      fontSize: '13px',
      lineHeight: '1.4',
      maxWidth: '380px',
      boxShadow: '0 6px 20px rgba(0,0,0,.28)',
      pointerEvents: 'auto',
      whiteSpace: 'pre-wrap',
    });
    ensureToastStack().appendChild(node);
    window.setTimeout(() => node.remove(), durationMs);
    return node;
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Asset fetching (bypasses CORS through GM_xmlhttpRequest)
  // ─────────────────────────────────────────────────────────────────────────

  const gmRequest = (() => {
    if (typeof GM_xmlhttpRequest === 'function') return GM_xmlhttpRequest;
    if (typeof GM !== 'undefined' && typeof GM.xmlHttpRequest === 'function') return GM.xmlHttpRequest.bind(GM);
    return null;
  })();

  const fetchBlob = (url, timeoutMs) =>
    new Promise((resolve, reject) => {
      if (!gmRequest) {
        // Last resort: native fetch. Fails if the asset exposes no CORS headers.
        window
          .fetch(url, { mode: 'cors', credentials: 'omit' })
          .then((response) => (response.ok ? response.blob() : Promise.reject(new Error(`HTTP ${response.status}`))))
          .then(resolve, reject);
        return;
      }
      gmRequest({
        method: 'GET',
        url,
        responseType: 'blob',
        timeout: timeoutMs || CONFIG.FETCH_TIMEOUT_MS,
        onload: (response) => {
          if (response.status >= 200 && response.status < 300 && response.response) resolve(response.response);
          else reject(new Error(`HTTP ${response.status}`));
        },
        onerror: () => reject(new Error('network error')),
        ontimeout: () => reject(new Error('timeout')),
      });
    });

  const blobToDataUrl = (blob) =>
    new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error || new Error('could not read blob'));
      reader.readAsDataURL(blob);
    });

  const assetCache = new Map();

  const toDataUrl = (rawUrl, base, timeoutMs) => {
    const url = new URL(rawUrl, base || document.baseURI).href;
    if (!assetCache.has(url)) {
      assetCache.set(
        url,
        fetchBlob(url, timeoutMs)
          .then(blobToDataUrl)
          .catch((error) => {
            assetCache.delete(url); // never memoize a transient failure
            throw error;
          })
      );
    }
    return assetCache.get(url);
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Asset inlining: temporarily swaps remote URLs for data URIs
  // ─────────────────────────────────────────────────────────────────────────

  const isInlineable = (url) => Boolean(url) && !url.startsWith('data:') && !url.startsWith('blob:');

  const setOrRemoveAttribute = (node, name, value) => {
    if (value === null) node.removeAttribute(name);
    else node.setAttribute(name, value);
  };

  const inlineImageElements = async (nodes, restorers, failures) => {
    const images = nodes.filter((node) => node.tagName === 'IMG');
    await Promise.all(
      images.map(async (image) => {
        const source = image.currentSrc || image.src;
        if (!isInlineable(source)) return;
        try {
          const dataUrl = await toDataUrl(source);
          const previousSrc = image.getAttribute('src');
          const previousSrcset = image.getAttribute('srcset');
          image.setAttribute('src', dataUrl);
          image.removeAttribute('srcset');
          restorers.push(() => {
            setOrRemoveAttribute(image, 'src', previousSrc);
            setOrRemoveAttribute(image, 'srcset', previousSrcset);
          });
        } catch (error) {
          failures.push(`${source} (${error.message})`);
        }
      })
    );
  };

  /**
   * Inside a <picture>, the browser re-resolves <source srcset> and would
   * bypass the data URI we just set on the <img>. Neutralise them for the
   * duration of the capture.
   */
  const neutralizePictureSources = (nodes, restorers) => {
    for (const node of nodes) {
      if (node.tagName !== 'SOURCE' || !node.hasAttribute('srcset')) continue;
      const previous = node.getAttribute('srcset');
      node.removeAttribute('srcset');
      restorers.push(() => setOrRemoveAttribute(node, 'srcset', previous));
    }
  };

  const inlineSvgImages = async (nodes, restorers, failures) => {
    const svgImages = nodes.filter((node) => node.tagName.toLowerCase() === 'image');
    await Promise.all(
      svgImages.map(async (node) => {
        const attribute = node.hasAttribute('href') ? 'href' : 'xlink:href';
        const source = node.getAttribute(attribute);
        if (!isInlineable(source)) return;
        try {
          const dataUrl = await toDataUrl(source);
          node.setAttribute(attribute, dataUrl);
          restorers.push(() => setOrRemoveAttribute(node, attribute, source));
        } catch (error) {
          failures.push(`${source} (${error.message})`);
        }
      })
    );
  };

  const inlineBackgrounds = async (nodes, restorers, failures) => {
    const jobs = nodes.map(async (node) => {
      const computed = window.getComputedStyle(node).backgroundImage;
      if (!computed || computed === 'none' || !computed.includes('url(')) return;

      const urls = [...computed.matchAll(bgUrlPattern())].map((match) => match[2]).filter(isInlineable);
      if (urls.length === 0) return;

      const replacements = new Map();
      await Promise.all(
        urls.map(async (url) => {
          try {
            replacements.set(url, await toDataUrl(url));
          } catch (error) {
            failures.push(`${url} (${error.message})`);
          }
        })
      );
      if (replacements.size === 0) return;

      const rewritten = computed.replace(bgUrlPattern(), (whole, _quote, url) =>
        replacements.has(url) ? `url("${replacements.get(url)}")` : whole
      );
      const previousInline = node.style.backgroundImage;
      node.style.backgroundImage = rewritten;
      restorers.push(() => {
        node.style.backgroundImage = previousInline;
      });
    });
    await Promise.all(jobs);
  };

  /**
   * Replaces every remote asset in the subtree with a data URI.
   * Returns a restore function that MUST be called after the capture.
   */
  const inlineAssets = async (root) => {
    const nodes = [root, ...root.querySelectorAll('*')];
    const restorers = [];
    const failures = [];

    neutralizePictureSources(nodes, restorers);
    await inlineImageElements(nodes, restorers, failures);
    await inlineSvgImages(nodes, restorers, failures);
    await inlineBackgrounds(nodes, restorers, failures);

    const restore = () => {
      for (const undo of restorers.reverse()) {
        try {
          undo();
        } catch (error) {
          warn('Partial DOM restore', error);
        }
      }
    };

    return { restore, failures };
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Fonts
  //
  // AppLaunchpad declares 5600+ @font-face rules (its whole font picker).
  // html-to-image does not filter them by usage: left alone it tries to
  // download all 5600, fails, and the text falls back to a system font with
  // different metrics -- which is what breaks the line wrapping. So we hand it
  // ready-made CSS limited to the families actually present in the slide,
  // which short-circuits its own collection entirely.
  // ─────────────────────────────────────────────────────────────────────────

  const normalizeFamily = (name) => name.trim().replace(/^["']|["']$/g, '').toLowerCase();

  const collectUsedFontFamilies = (root) => {
    const families = new Set();
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      if (node.nodeValue.trim() && node.parentElement) {
        for (const name of window.getComputedStyle(node.parentElement).fontFamily.split(',')) {
          families.add(normalizeFamily(name));
        }
      }
      node = walker.nextNode();
    }
    return families;
  };

  /**
   * Returns null when no URL could be embedded: an @font-face rule still
   * pointing at the network is useless inside the render SVG, and could mask
   * a fallback font that would actually have worked.
   */
  const inlineCssUrls = async (cssText, baseHref, failures) => {
    const urls = [...cssText.matchAll(bgUrlPattern())].map((match) => match[2]).filter(isInlineable);
    if (urls.length === 0) return cssText;
    const replacements = new Map();
    await Promise.all(
      urls.map(async (url) => {
        try {
          replacements.set(url, await toDataUrl(url, baseHref, CONFIG.FONT_TIMEOUT_MS));
        } catch (error) {
          failures.push(`${url} (${error.message})`);
        }
      })
    );
    if (replacements.size === 0) return null;
    return cssText.replace(bgUrlPattern(), (whole, _quote, url) =>
      replacements.has(url) ? `url("${replacements.get(url)}")` : whole
    );
  };

  const fontCssCache = new Map();

  const buildFontEmbedCSS = async (root) => {
    const families = collectUsedFontFamilies(root);
    if (families.size === 0) return '';

    const key = [...families].sort().join('|');
    if (fontCssCache.has(key)) return fontCssCache.get(key);

    const promise = (async () => {
      const failures = [];
      const matched = [];
      let unreadableSheets = 0;

      for (const sheet of document.styleSheets) {
        let rules;
        try {
          rules = sheet.cssRules;
        } catch (error) {
          unreadableSheets += 1; // cross-origin sheet: unreadable from JS
          continue;
        }
        for (const rule of rules) {
          if (!(rule instanceof CSSFontFaceRule)) continue;
          const family = normalizeFamily(rule.style.getPropertyValue('font-family') || '');
          if (!families.has(family)) continue;
          matched.push({ cssText: rule.cssText, href: sheet.href });
        }
      }

      if (matched.length === 0) {
        warn(
          'No @font-face rule found for:', [...families],
          unreadableSheets > 0
            ? `(${unreadableSheets} unreadable sheet(s) -- text may render in a different font)`
            : '(system fonts? the render should stay faithful)'
        );
        return '';
      }

      const blocks = (await Promise.all(
        matched.map((entry) => inlineCssUrls(entry.cssText, entry.href, failures))
      )).filter(Boolean);

      if (failures.length > 0) {
        warn('Font files that could not be fetched:', failures);
        toast('Some fonts could not be embedded -- text may look different.', 'warn', 7000);
      }
      if (blocks.length === 0) {
        warn('No font embedded: the render will use a system font.');
        return '';
      }
      log(`Embedded ${blocks.length}/${matched.length} @font-face rule(s) for`, [...families]);
      return blocks.join('\n');
    })();

    fontCssCache.set(key, promise);
    promise.then((css) => {
      if (!css) fontCssCache.delete(key);
    });
    return promise;
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Slide detection
  // ─────────────────────────────────────────────────────────────────────────

  const isVisible = (element) => {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  const hasSlideShape = (element) => {
    const width = element.offsetWidth;
    const height = element.offsetHeight;
    if (width < CONFIG.MIN_LOGICAL_SIDE || height < CONFIG.MIN_LOGICAL_SIDE) return false;
    const ratio = height / width;
    const [portraitMin, portraitMax] = CONFIG.PORTRAIT_RATIO;
    const [landscapeMin, landscapeMax] = CONFIG.LANDSCAPE_RATIO;
    return (ratio >= portraitMin && ratio <= portraitMax) || (ratio >= landscapeMin && ratio <= landscapeMax);
  };

  const isPlausibleSlide = (element) => isVisible(element) && hasSlideShape(element);

  /**
   * The editor renders a wrapper at display size (e.g. 323 x 700) containing
   * the real canvas at native resolution (1290 x 2796), shrunk with
   * `transform: scale()`. Exporting the wrapper would yield a tiny PNG.
   * So we descend to the descendant that occupies the same on-screen footprint
   * but carries a larger logical size. With no such nesting, the element is
   * returned unchanged.
   */
  const resolveRenderTarget = (element) => {
    const rect = element.getBoundingClientRect();
    let best = element;
    for (const node of element.querySelectorAll('*')) {
      const nodeRect = node.getBoundingClientRect();
      const sameFootprint =
        Math.abs(nodeRect.width - rect.width) <= 2 && Math.abs(nodeRect.height - rect.height) <= 2;
      if (sameFootprint && node.offsetWidth > best.offsetWidth) best = node;
    }
    return best;
  };

  const logicalArea = (element) => element.offsetWidth * element.offsetHeight;

  /** Between two nested candidates of comparable size, keep the outer one. */
  const dropNestedDuplicates = (candidates) =>
    candidates.filter((candidate) =>
      candidates.every((other) => {
        if (other === candidate || !other.contains(candidate)) return true;
        const ratio = logicalArea(candidate) / logicalArea(other);
        return ratio < 1 - CONFIG.NESTED_AREA_TOLERANCE;
      })
    );

  const sizeSignature = (element) => `${Math.round(element.offsetWidth)}x${Math.round(element.offsetHeight)}`;

  const largestConsistentGroup = (candidates) => {
    const groups = new Map();
    for (const candidate of candidates) {
      const key = sizeSignature(candidate);
      groups.set(key, [...(groups.get(key) || []), candidate]);
    }
    const ranked = [...groups.values()].sort((a, b) => {
      if (b.length !== a.length) return b.length - a.length;
      return logicalArea(b[0]) - logicalArea(a[0]);
    });
    return ranked[0] || [];
  };

  const inDocumentOrder = (elements) =>
    [...elements].sort((a, b) =>
      a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
    );

  const findByStoredSelector = () => {
    const selector = readStore(CONFIG.STORE_SELECTOR, '');
    if (!selector) return null;
    try {
      const found = [...document.querySelectorAll(selector)].filter(isVisible);
      if (found.length === 0) return null;
      return inDocumentOrder([...new Set(found.map(resolveRenderTarget))]);
    } catch (error) {
      warn('Stored selector is invalid, falling back to auto-detection', selector, error);
      return null;
    }
  };

  const findByHeuristics = () => {
    const candidates = new Set();
    for (const selector of SLIDE_SELECTORS) {
      try {
        for (const element of document.querySelectorAll(selector)) {
          // Resolve BEFORE filtering on shape: the wrapper can be arbitrarily
          // small when the editor is zoomed out, but the target never is.
          if (isVisible(element)) candidates.add(resolveRenderTarget(element));
        }
      } catch (error) {
        warn('Heuristic selector rejected', selector, error);
      }
    }
    const targets = [...candidates].filter(hasSlideShape);
    if (targets.length === 0) return [];
    return inDocumentOrder(largestConsistentGroup(dropNestedDuplicates(targets)));
  };

  const findSlides = () => findByStoredSelector() || findByHeuristics();

  // ─────────────────────────────────────────────────────────────────────────
  // Building a stable selector (picker mode)
  // ─────────────────────────────────────────────────────────────────────────

  const classSelector = (element, classes) =>
    `${element.tagName.toLowerCase()}${classes.map((name) => `.${cssEscape(name)}`).join('')}`;

  const matchCount = (selector) => {
    try {
      return document.querySelectorAll(selector).length;
    } catch (error) {
      return 0;
    }
  };

  const matches = (element, selector) => {
    try {
      return element.matches(selector);
    } catch (error) {
      return false;
    }
  };

  const pathSelector = (element) => {
    const parts = [];
    let node = element;
    while (node && node !== document.body && node.parentElement && parts.length < 8) {
      const index = [...node.parentElement.children].indexOf(node) + 1;
      parts.unshift(`${node.tagName.toLowerCase()}:nth-child(${index})`);
      node = node.parentElement;
    }
    return `body > ${parts.join(' > ')}`;
  };

  /**
   * Shortest selector that still matches the element without blowing up the
   * result count. Start from every class, then drop them one by one.
   */
  const buildSelector = (element) => {
    if (element.id && matchCount(`#${cssEscape(element.id)}`) === 1) return `#${cssEscape(element.id)}`;

    const stableClasses = [...element.classList].filter((name) => !VOLATILE_CLASS_RE.test(name));
    if (stableClasses.length === 0) return pathSelector(element);

    const full = classSelector(element, stableClasses);
    const baseline = matchCount(full);
    if (baseline === 0) return pathSelector(element);

    let best = { selector: full, classes: stableClasses };
    for (let index = stableClasses.length - 1; index >= 0; index -= 1) {
      const trimmed = best.classes.filter((_, position) => position !== index);
      if (trimmed.length === 0) break;
      const candidate = classSelector(element, trimmed);
      const count = matchCount(candidate);
      if (matches(element, candidate) && count > 0 && count <= baseline * 3) {
        best = { selector: candidate, classes: trimmed };
      }
    }
    return matches(element, best.selector) ? best.selector : pathSelector(element);
  };

  // ─────────────────────────────────────────────────────────────────────────
  // ZIP archive ("stored" method, no dependency)
  //
  // A PNG is already compressed: deflating it would gain almost nothing.
  // Storing as-is avoids bundling a whole compression library for a format
  // whose structure fits in a few headers.
  // ─────────────────────────────────────────────────────────────────────────

  const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let index = 0; index < 256; index += 1) {
      let value = index;
      for (let bit = 0; bit < 8; bit += 1) {
        value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
      }
      table[index] = value >>> 0;
    }
    return table;
  })();

  const crc32 = (bytes) => {
    let crc = 0xffffffff;
    for (let index = 0; index < bytes.length; index += 1) {
      crc = CRC_TABLE[(crc ^ bytes[index]) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) >>> 0;
  };

  const dosStamp = (date) => ({
    time: ((date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1)) & 0xffff,
    date: (((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate()) & 0xffff,
  });

  /** entries: [{ name, bytes: Uint8Array }] → Blob application/zip */
  const buildZip = (entries) => {
    const encoder = new TextEncoder();
    const stamp = dosStamp(new Date());
    const payload = [];
    const directory = [];
    let offset = 0;

    for (const entry of entries) {
      const name = encoder.encode(entry.name);
      const crc = crc32(entry.bytes);
      const size = entry.bytes.length;

      const local = new Uint8Array(30 + name.length);
      const localView = new DataView(local.buffer);
      localView.setUint32(0, 0x04034b50, true); // local header signature
      localView.setUint16(4, 20, true); // version minimale
      localView.setUint16(6, 0, true); // drapeaux
      localView.setUint16(8, 0, true); // method 0 = stored
      localView.setUint16(10, stamp.time, true);
      localView.setUint16(12, stamp.date, true);
      localView.setUint32(14, crc, true);
      localView.setUint32(18, size, true); // compressed size
      localView.setUint32(22, size, true); // uncompressed size
      localView.setUint16(26, name.length, true);
      localView.setUint16(28, 0, true); // champ extra
      local.set(name, 30);
      payload.push(local, entry.bytes);

      const central = new Uint8Array(46 + name.length);
      const centralView = new DataView(central.buffer);
      centralView.setUint32(0, 0x02014b50, true); // central directory signature
      centralView.setUint16(4, 20, true);
      centralView.setUint16(6, 20, true);
      centralView.setUint16(8, 0, true);
      centralView.setUint16(10, 0, true);
      centralView.setUint16(12, stamp.time, true);
      centralView.setUint16(14, stamp.date, true);
      centralView.setUint32(16, crc, true);
      centralView.setUint32(20, size, true);
      centralView.setUint32(24, size, true);
      centralView.setUint16(28, name.length, true);
      centralView.setUint32(42, offset, true); // offset of the local header
      central.set(name, 46);
      directory.push(central);

      offset += local.length + size;
    }

    const directorySize = directory.reduce((total, part) => total + part.length, 0);
    const end = new Uint8Array(22);
    const endView = new DataView(end.buffer);
    endView.setUint32(0, 0x06054b50, true); // end-of-central-directory signature
    endView.setUint16(8, entries.length, true);
    endView.setUint16(10, entries.length, true);
    endView.setUint32(12, directorySize, true);
    endView.setUint32(16, offset, true);

    return new Blob([...payload, ...directory, end], { type: 'application/zip' });
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Export
  // ─────────────────────────────────────────────────────────────────────────

  const TRANSPARENT_PIXEL =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

  const slugify = (value) =>
    value
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '') // strip accents
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 40);

  /**
   * AppLaunchpad keeps the project name in the only visible text input in the
   * page header, so we name files after it. Falls back to the project id from
   * the URL, then to a constant, so a filename is always produced.
   */
  const projectSlug = () => {
    const header = [...document.querySelectorAll('input[type="text"]')].find((input) => {
      const rect = input.getBoundingClientRect();
      return rect.top < 80 && rect.width > 80 && String(input.value || '').trim() !== '';
    });
    const fromHeader = header ? slugify(header.value) : '';
    if (fromHeader) return fromHeader;
    const segment = window.location.pathname.split('/').filter(Boolean).pop() || '';
    return slugify(segment.slice(0, 8)) || 'applaunchpad';
  };

  // e.g. florin-1290x2796-01.png -- sorts correctly and states the device size,
  // which is what you actually need when uploading to App Store Connect.
  const buildFilename = (index, width, height) =>
    `${projectSlug()}-${width}x${height}-${String(index + 1).padStart(2, '0')}.png`;

  const buildZipName = (entries) => {
    const sizes = new Set(entries.map((entry) => entry.dimensions));
    return `${projectSlug()}-${sizes.size === 1 ? [...sizes][0] : 'screenshots'}.zip`;
  };

  const targetWidthOverride = () => {
    const stored = Number(readStore(CONFIG.STORE_TARGET_WIDTH, 0));
    return Number.isFinite(stored) && stored > 0 ? stored : 0;
  };

  const renderOptions = (slide, pixelRatio, fontEmbedCSS) => ({
    pixelRatio,
    // When provided, html-to-image skips scanning the page's 5600 @font-face.
    ...(fontEmbedCSS ? { fontEmbedCSS } : { skipFonts: true }),
    width: slide.offsetWidth,
    height: slide.offsetHeight,
    cacheBust: false,
    // An asset that could not be inlined becomes transparent instead of
    // failing the whole render; the failure is still surfaced in a toast.
    imagePlaceholder: TRANSPARENT_PIXEL,
    // The node is displayed shrunk via `transform: scale()` in the editor, so
    // we neutralise the transform on the clone to capture at full size.
    style: { transform: 'none', transformOrigin: 'top left', margin: '0' },
    filter: (node) => !(node instanceof Element && node.hasAttribute(CONFIG.UI_ATTR)),
  });

  const renderToBlob = async (slide, pixelRatio, fontEmbedCSS) => {
    const library = resolveHtmlToImage();
    if (!library) throw new Error('html-to-image renderer unavailable');

    if (CONFIG.WARMUP_RENDER) {
      try {
        await library.toCanvas(slide, renderOptions(slide, CONFIG.WARMUP_PIXEL_RATIO, fontEmbedCSS));
      } catch (error) {
        warn('Warm-up render failed (harmless)', error);
      }
    }

    let blob = null;
    try {
      blob = await library.toBlob(slide, renderOptions(slide, pixelRatio, fontEmbedCSS));
    } catch (error) {
      // Explicit fontless fallback: text will render in a system font.
      warn('Render with fonts failed, retrying without fonts', error);
      blob = await library.toBlob(slide, renderOptions(slide, pixelRatio, null));
    }
    if (!blob) throw new Error('the render produced an empty blob');
    return blob;
  };

  const downloadBlob = (blob, filename) => {
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute(CONFIG.UI_ATTR, 'download');
    link.href = url;
    link.download = filename;
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 10000);
  };

  const renderSlide = async (slide) => {
    const { restore, failures } = await inlineAssets(slide);
    try {
      const logicalWidth = slide.offsetWidth;
      const logicalHeight = slide.offsetHeight;
      if (logicalWidth === 0 || logicalHeight === 0) throw new Error('slide has zero size');

      const override = targetWidthOverride();
      const pixelRatio = clamp(override ? override / logicalWidth : 1, 0.05, CONFIG.MAX_PIXEL_RATIO);
      const fontEmbedCSS = await buildFontEmbedCSS(slide);
      const blob = await renderToBlob(slide, pixelRatio, fontEmbedCSS);
      return {
        blob,
        failures,
        width: Math.round(logicalWidth * pixelRatio),
        height: Math.round(logicalHeight * pixelRatio),
      };
    } finally {
      restore();
    }
  };

  const exportSlide = async (slide, index) => {
    const result = await renderSlide(slide);
    const filename = buildFilename(index, result.width, result.height);
    downloadBlob(result.blob, filename);
    return { ...result, filename };
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Boutons flottants
  // ─────────────────────────────────────────────────────────────────────────

  let layer = null;
  let buttons = []; // [{ node, slide, lastRect }]
  let busy = false; // one export at a time, batch and single button alike

  const ensureLayer = () => {
    if (layer && layer.isConnected) return layer;
    layer = document.createElement('div');
    layer.setAttribute(CONFIG.UI_ATTR, 'layer');
    Object.assign(layer.style, {
      position: 'fixed',
      inset: '0',
      pointerEvents: 'none',
      zIndex: '2147483000',
    });
    document.documentElement.appendChild(layer);
    return layer;
  };

  const styleButton = (node) => {
    Object.assign(node.style, {
      position: 'fixed',
      pointerEvents: 'auto',
      display: 'inline-flex',
      alignItems: 'center',
      gap: '6px',
      padding: '5px 10px',
      border: 'none',
      borderRadius: '6px',
      background: '#6c5ce7',
      color: '#fff',
      font: '600 12px/1.2 system-ui, -apple-system, sans-serif',
      cursor: 'pointer',
      boxShadow: '0 2px 8px rgba(0,0,0,.25)',
      whiteSpace: 'nowrap',
    });
  };

  const handleExportClick = async (entry, index) => {
    const { node, slide } = entry;
    if (node.disabled || busy) return;
    busy = true;
    const label = node.textContent;
    node.disabled = true;
    node.style.opacity = '0.6';
    node.textContent = '⏳ export…';
    try {
      const result = await exportSlide(slide, index);
      toast(`${result.filename}\n${result.width} × ${result.height} px`, 'success');
      if (result.failures.length > 0) {
        toast(`${result.failures.length} asset(s) could not be fetched -- see console.`, 'warn', 6000);
        warn('Assets left un-inlined:', result.failures);
      }
    } catch (error) {
      toast(`Export failed: ${error.message}`, 'error', 7000);
      warn('Export failed', error);
    } finally {
      busy = false;
      node.disabled = false;
      node.style.opacity = '1';
      node.textContent = label;
    }
  };

  const createButton = (slide, index) => {
    const node = document.createElement('button');
    node.setAttribute(CONFIG.UI_ATTR, 'button');
    node.type = 'button';
    node.textContent = `⬇ PNG ${index + 1}`;
    node.title = `Export slide ${index + 1} (${slide.offsetWidth} x ${slide.offsetHeight} px)`;
    styleButton(node);
    const entry = { node, slide, lastRect: '' };
    node.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      handleExportClick(entry, index);
    });
    return entry;
  };

  const viewportHeight = () => window.innerHeight || document.documentElement.clientHeight || 0;

  const positionButton = (entry) => {
    const rect = entry.slide.getBoundingClientRect();
    const height = viewportHeight();
    // The signature includes the viewport height: without it, a button hidden
    // while the window was degenerate (background tab, collapsed pane) would
    // never come back, since the slide's own rect never changed.
    const signature = `${rect.left}|${rect.top}|${rect.width}|${rect.height}|${height}`;
    if (signature === entry.lastRect) return;
    entry.lastRect = signature;

    const offscreen = rect.width === 0 || (height > 0 && (rect.bottom < 0 || rect.top > height));
    entry.node.style.visibility = offscreen ? 'hidden' : 'visible';
    if (offscreen) return;

    // Above the slide, or just inside it when there is no room.
    const top = rect.top - 32 < 4 ? rect.top + 6 : rect.top - 32;
    entry.node.style.left = `${Math.round(rect.left)}px`;
    entry.node.style.top = `${Math.round(top)}px`;
  };

  const trackPositions = () => {
    buttons.forEach(positionButton);
    positionBulkButton();
    window.requestAnimationFrame(trackPositions);
  };

  const sameElements = (a, b) => a.length === b.length && a.every((element, index) => element === b[index]);

  const syncSlides = () => {
    const slides = findSlides();
    if (sameElements(slides, buttons.map((entry) => entry.slide))) return;

    buttons.forEach((entry) => entry.node.remove());
    buttons = slides.map((slide, index) => createButton(slide, index));
    const container = ensureLayer();
    buttons.forEach((entry) => container.appendChild(entry.node));
    buttons.forEach(positionButton);
    ensureBulkButton();
    refreshBulkButton();

    if (slides.length > 0) {
      const first = slides[0];
      const scale = first.offsetWidth > 0 ? first.getBoundingClientRect().width / first.offsetWidth : 1;
      log(
        `Detected ${slides.length} slide(s) -- logical size ${first.offsetWidth} x ${first.offsetHeight} px ` +
          `(displayed at ${Math.round(scale * 100)}%). ` +
          'If that is not the resolution you want: menu -> "Force export width".',
        slides
      );
    }
    if (slides.length === 0) warn('No slide found -- use the Tampermonkey menu -> "Pick a slide".');
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Download all
  // ─────────────────────────────────────────────────────────────────────────

  let bulkButton = null;
  let bulkRunning = false;
  let bulkAbort = false;

  const bulkIdleLabel = () => `\u2b07 Download all as ZIP (${buttons.length})`;

  const refreshBulkButton = () => {
    if (!bulkButton) return;
    bulkButton.style.display = buttons.length > 0 ? 'inline-flex' : 'none';
    if (!bulkRunning) bulkButton.textContent = bulkIdleLabel();
    delete bulkButton.dataset.alpRect;
    positionBulkButton();
  };

  const reportBulk = (name, done, total, failures, aborted) => {
    const weight = ` (${Math.round(zipSize / 1024)} KB)`;
    if (aborted) {
      toast(`Stopped -- ${name} holds ${done}/${total} slide(s)${weight}.`, 'info', 6000);
      return;
    }
    if (failures.length > 0) {
      toast(`${name} -- ${done}/${total} slide(s)${weight}, ${failures.length} issue(s): see console.`,
        'warn', 9000);
      warn('Issues during the batch export:', failures);
      return;
    }
    toast(`${name} -- ${done} slide(s)${weight}.`, 'success', 6000);
  };

  let zipSize = 0;

  /**
   * Sequential rather than parallel: each render holds a whole slide in
   * memory. The PNGs are assembled into a single archive, which also avoids
   * the browser's "download multiple files" prompt. A second click during the
   * batch stops it: the archive then holds whatever was ready.
   */
  const handleBulkClick = async () => {
    if (bulkRunning) {
      bulkAbort = true;
      bulkButton.textContent = '\u23f8 stopping...';
      return;
    }
    if (busy) return;

    const slides = buttons.map((entry) => entry.slide);
    const total = slides.length;
    if (total === 0) return;

    bulkRunning = true;
    busy = true;
    bulkAbort = false;
    const failures = [];
    const entries = [];
    let name = `${projectSlug()}-screenshots.zip`;
    zipSize = 0;

    const setLabel = (text) => {
      bulkButton.textContent = text;
      delete bulkButton.dataset.alpRect; // the label just changed width
    };

    try {
      for (let index = 0; index < total; index += 1) {
        if (bulkAbort) break;
        const slide = slides[index];
        // The editor can re-render mid-batch and detach the slide.
        if (!slide.isConnected) {
          failures.push(`slide ${index + 1}: removed from the page during export`);
          continue;
        }
        setLabel(`\u23f9 ${index + 1}/${total} -- click to stop`);
        try {
          const result = await renderSlide(slide);
          entries.push({
            name: buildFilename(index, result.width, result.height),
            bytes: new Uint8Array(await result.blob.arrayBuffer()),
            dimensions: `${result.width}x${result.height}`,
          });
          if (result.failures.length > 0) {
            failures.push(`slide ${index + 1}: ${result.failures.length} missing asset(s)`);
          }
        } catch (error) {
          failures.push(`slide ${index + 1}: ${error.message}`);
          warn(`Rendering slide ${index + 1} failed`, error);
        }
      }

      if (entries.length > 0) {
        name = buildZipName(entries);
        setLabel('\ud83d\udce6 building archive...');
        // Let the browser paint the label before the synchronous CRC work,
        // which freezes the main thread for a few hundred ms.
        await sleep(16);
        const archive = buildZip(entries);
        zipSize = archive.size;
        downloadBlob(archive, name);
      } else {
        failures.push('no slide could be rendered');
      }
    } finally {
      const aborted = bulkAbort;
      bulkRunning = false;
      bulkAbort = false;
      busy = false;
      refreshBulkButton();
      reportBulk(name, entries.length, total, failures, aborted);
    }
  };

  /**
   * Anchored to the slide row rather than a screen corner: the editor owns
   * all four corners (side panel, its own Download button, Intercom bubble)
   * and a fixed bar would cover its controls.
   */
  const positionBulkButton = () => {
    if (!bulkButton || buttons.length === 0) return;
    const rects = buttons.map((entry) => entry.slide.getBoundingClientRect());
    const left = Math.min(...rects.map((rect) => rect.left));
    const right = Math.max(...rects.map((rect) => rect.right));
    const top = Math.min(...rects.map((rect) => rect.top));
    const width = bulkButton.offsetWidth;

    // Above the row, clear of the per-slide buttons (those sit at top-32).
    // With no room above, fall back to the row's top-right corner so we do not
    // land on the first slide's own button.
    const hasRoomAbove = top - 72 >= 4;
    const x = hasRoomAbove ? left : right - width;
    const y = hasRoomAbove ? top - 72 : top + 6;

    const signature = `${x}|${y}|${width}`;
    if (signature === bulkButton.dataset.alpRect) return;
    bulkButton.dataset.alpRect = signature;

    bulkButton.style.left = `${Math.round(clamp(x, 8, Math.max(8, window.innerWidth - width - 8)))}px`;
    bulkButton.style.top = `${Math.round(Math.max(4, y))}px`;
  };

  const ensureBulkButton = () => {
    if (bulkButton && bulkButton.isConnected) return bulkButton;
    bulkButton = document.createElement('button');
    bulkButton.setAttribute(CONFIG.UI_ATTR, 'bulk');
    bulkButton.type = 'button';
    bulkButton.textContent = bulkIdleLabel();
    // Positioned by positionBulkButton; see the note there.
    Object.assign(bulkButton.style, {
      position: 'fixed',
      left: '0px',
      top: '0px',
      pointerEvents: 'auto',
      display: 'none',
      alignItems: 'center',
      padding: '9px 14px',
      border: 'none',
      borderRadius: '8px',
      background: '#2d3436',
      color: '#fff',
      font: '600 13px/1.2 system-ui, -apple-system, sans-serif',
      cursor: 'pointer',
      boxShadow: '0 4px 14px rgba(0,0,0,.3)',
      whiteSpace: 'nowrap',
    });
    bulkButton.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      handleBulkClick();
    });
    ensureLayer().appendChild(bulkButton);
    return bulkButton;
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Picker manuel
  // ─────────────────────────────────────────────────────────────────────────

  const walkUp = (element, levels) => {
    let node = element;
    for (let step = 0; step < levels && node.parentElement && node.parentElement !== document.body; step += 1) {
      node = node.parentElement;
    }
    return node;
  };

  const startPicker = () => {
    const highlight = document.createElement('div');
    highlight.setAttribute(CONFIG.UI_ATTR, 'picker-highlight');
    Object.assign(highlight.style, {
      position: 'fixed',
      pointerEvents: 'none',
      zIndex: '2147483002',
      border: '2px solid #6c5ce7',
      background: 'rgba(108,92,231,.15)',
      borderRadius: '4px',
    });

    const hud = document.createElement('div');
    hud.setAttribute(CONFIG.UI_ATTR, 'picker-hud');
    Object.assign(hud.style, {
      position: 'fixed',
      top: '16px',
      left: '50%',
      transform: 'translateX(-50%)',
      zIndex: '2147483003',
      background: '#2d3436',
      color: '#fff',
      padding: '10px 14px',
      borderRadius: '8px',
      font: '13px/1.5 system-ui, -apple-system, sans-serif',
      boxShadow: '0 6px 20px rgba(0,0,0,.3)',
      pointerEvents: 'none',
      textAlign: 'center',
      maxWidth: '90vw',
    });

    document.documentElement.append(highlight, hud);

    const state = { hovered: null, depth: 0 };

    const current = () => (state.hovered ? walkUp(state.hovered, state.depth) : null);

    const paint = () => {
      const element = current();
      if (!element) return;
      const rect = element.getBoundingClientRect();
      Object.assign(highlight.style, {
        left: `${rect.left}px`,
        top: `${rect.top}px`,
        width: `${rect.width}px`,
        height: `${rect.height}px`,
      });
      const classes = [...element.classList].slice(0, 3).join('.');
      hud.textContent =
        `${element.tagName.toLowerCase()}${classes ? `.${classes}` : ''} — ` +
        `${element.offsetWidth} × ${element.offsetHeight} px (niveau ${state.depth})\n` +
        '\u2191/\u2193 = parent/child \u00b7 click = confirm \u00b7 Esc = cancel';
      hud.style.whiteSpace = 'pre-line';
    };

    const onMove = (event) => {
      const target = event.target;
      if (target instanceof Element && !target.hasAttribute(CONFIG.UI_ATTR)) {
        state.hovered = target;
        paint();
      }
    };

    const onKey = (event) => {
      if (event.key === 'Escape') {
        stop();
        toast('Selection cancelled.', 'info');
        return;
      }
      if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
        event.preventDefault();
        state.depth = Math.max(0, state.depth + (event.key === 'ArrowUp' ? 1 : -1));
        paint();
      }
    };

    const onClick = (event) => {
      event.preventDefault();
      event.stopImmediatePropagation();
      const element = current();
      stop();
      if (!element) return;

      const selector = buildSelector(element);
      // The stored selector points at the wrapper; resolution down to the
      // full-resolution canvas happens again on every detection pass.
      const count = matchCount(selector);
      writeStore(CONFIG.STORE_SELECTOR, selector);
      log('Selector saved:', selector, `(${count} match(es))`);
      toast(`Selector saved (${count} slide(s)):\n${selector}`, 'success', 7000);
      syncSlides();
    };

    function stop() {
      document.removeEventListener('mousemove', onMove, true);
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('keydown', onKey, true);
      highlight.remove();
      hud.remove();
    }

    document.addEventListener('mousemove', onMove, true);
    document.addEventListener('click', onClick, true);
    document.addEventListener('keydown', onKey, true);
    hud.textContent = 'Hover a slide, then click. \u2191/\u2193 to widen/narrow \u00b7 Esc to cancel.';
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Menu Tampermonkey
  // ─────────────────────────────────────────────────────────────────────────

  const registerMenu = () => {
    if (typeof GM_registerMenuCommand !== 'function') return;

    GM_registerMenuCommand('\ud83c\udfaf Pick a slide', startPicker);

    GM_registerMenuCommand('\ud83d\udd04 Reset saved selector', () => {
      writeStore(CONFIG.STORE_SELECTOR, '');
      toast('Selector cleared -- back to auto-detection.', 'info');
      syncSlides();
    });

    GM_registerMenuCommand('\ud83d\udcd0 Force export width', () => {
      const current = targetWidthOverride();
      const answer = window.prompt(
        'Export width in pixels (empty = the slide\'s native size).\ne.g. 1290 (iPhone 6.7"), 1242, 2048 (iPad).',
        current ? String(current) : ''
      );
      if (answer === null) return;
      const trimmed = answer.trim();
      if (trimmed === '') {
        writeStore(CONFIG.STORE_TARGET_WIDTH, 0);
        toast('Export width: automatic (native size).', 'info');
        return;
      }
      const value = Number(trimmed);
      if (!Number.isFinite(value) || value <= 0) {
        toast('Invalid value.', 'error');
        return;
      }
      writeStore(CONFIG.STORE_TARGET_WIDTH, value);
      toast(`Export width forced to ${value} px.`, 'success');
    });

    GM_registerMenuCommand('\ud83d\udd0d Re-run detection', () => {
      syncSlides();
      toast(`Detected ${buttons.length} slide(s).`, buttons.length > 0 ? 'success' : 'warn');
    });
  };

  // ─────────────────────────────────────────────────────────────────────────
  // html-to-image v1.11.11 -- bundled
  // MIT — Copyright (c) 2017-2023 W.Y. — https://github.com/bubkoo/html-to-image
  //
  // Bundled rather than loaded through @require: that load depended on a
  // reachable CDN, a healthy Tampermonkey cache, and resolving a global across
  // the sandbox -- three ways to make the script dead on arrival with no
  // recourse. By supplying `module`/`exports` ourselves, the UMD takes its
  // CommonJS branch and hands the exports straight back: no global involved.
  // ─────────────────────────────────────────────────────────────────────────

  const htmlToImageLib = (() => {
    const exports = {};
    const module = { exports };
    /* eslint-disable */
    !function(t,e){"object"==typeof exports&&"undefined"!=typeof module?e(exports):"function"==typeof define&&define.amd?define(["exports"],e):e((t="undefined"!=typeof globalThis?globalThis:t||self).htmlToImage={})}(this,(function(t){"use strict";function e(t,e,n,r){return new(n||(n=Promise))((function(i,o){function u(t){try{a(r.next(t))}catch(t){o(t)}}function c(t){try{a(r.throw(t))}catch(t){o(t)}}function a(t){var e;t.done?i(t.value):(e=t.value,e instanceof n?e:new n((function(t){t(e)}))).then(u,c)}a((r=r.apply(t,e||[])).next())}))}function n(t,e){var n,r,i,o,u={label:0,sent:function(){if(1&i[0])throw i[1];return i[1]},trys:[],ops:[]};return o={next:c(0),throw:c(1),return:c(2)},"function"==typeof Symbol&&(o[Symbol.iterator]=function(){return this}),o;function c(c){return function(a){return function(c){if(n)throw new TypeError("Generator is already executing.");for(;o&&(o=0,c[0]&&(u=0)),u;)try{if(n=1,r&&(i=2&c[0]?r.return:c[0]?r.throw||((i=r.return)&&i.call(r),0):r.next)&&!(i=i.call(r,c[1])).done)return i;switch(r=0,i&&(c=[2&c[0],i.value]),c[0]){case 0:case 1:i=c;break;case 4:return u.label++,{value:c[1],done:!1};case 5:u.label++,r=c[1],c=[0];continue;case 7:c=u.ops.pop(),u.trys.pop();continue;default:if(!(i=u.trys,(i=i.length>0&&i[i.length-1])||6!==c[0]&&2!==c[0])){u=0;continue}if(3===c[0]&&(!i||c[1]>i[0]&&c[1]<i[3])){u.label=c[1];break}if(6===c[0]&&u.label<i[1]){u.label=i[1],i=c;break}if(i&&u.label<i[2]){u.label=i[2],u.ops.push(c);break}i[2]&&u.ops.pop(),u.trys.pop();continue}c=e.call(t,u)}catch(t){c=[6,t],r=0}finally{n=i=0}if(5&c[0])throw c[1];return{value:c[0]?c[1]:void 0,done:!0}}([c,a])}}}var r,i=(r=0,function(){return r+=1,"u".concat("0000".concat((Math.random()*Math.pow(36,4)<<0).toString(36)).slice(-4)).concat(r)});function o(t){for(var e=[],n=0,r=t.length;n<r;n++)e.push(t[n]);return e}function u(t,e){var n=(t.ownerDocument.defaultView||window).getComputedStyle(t).getPropertyValue(e);return n?parseFloat(n.replace("px","")):0}function c(t,e){void 0===e&&(e={});var n,r,i,o=e.width||(r=u(n=t,"border-left-width"),i=u(n,"border-right-width"),n.clientWidth+r+i),c=e.height||function(t){var e=u(t,"border-top-width"),n=u(t,"border-bottom-width");return t.clientHeight+e+n}(t);return{width:o,height:c}}var a=16384;function s(t,e){return void 0===e&&(e={}),t.toBlob?new Promise((function(n){t.toBlob(n,e.type?e.type:"image/png",e.quality?e.quality:1)})):new Promise((function(n){for(var r=window.atob(t.toDataURL(e.type?e.type:void 0,e.quality?e.quality:void 0).split(",")[1]),i=r.length,o=new Uint8Array(i),u=0;u<i;u+=1)o[u]=r.charCodeAt(u);n(new Blob([o],{type:e.type?e.type:"image/png"}))}))}function l(t){return new Promise((function(e,n){var r=new Image;r.decode=function(){return e(r)},r.onload=function(){return e(r)},r.onerror=n,r.crossOrigin="anonymous",r.decoding="async",r.src=t}))}function f(t){return e(this,void 0,void 0,(function(){return n(this,(function(e){return[2,Promise.resolve().then((function(){return(new XMLSerializer).serializeToString(t)})).then(encodeURIComponent).then((function(t){return"data:image/svg+xml;charset=utf-8,".concat(t)}))]}))}))}function h(t,r,i){return e(this,void 0,void 0,(function(){var e,o,u;return n(this,(function(n){return e="http://www.w3.org/2000/svg",o=document.createElementNS(e,"svg"),u=document.createElementNS(e,"foreignObject"),o.setAttribute("width","".concat(r)),o.setAttribute("height","".concat(i)),o.setAttribute("viewBox","0 0 ".concat(r," ").concat(i)),u.setAttribute("width","100%"),u.setAttribute("height","100%"),u.setAttribute("x","0"),u.setAttribute("y","0"),u.setAttribute("externalResourcesRequired","true"),o.appendChild(u),u.appendChild(t),[2,f(o)]}))}))}var d=function(t,e){if(t instanceof e)return!0;var n=Object.getPrototypeOf(t);return null!==n&&(n.constructor.name===e.name||d(n,e))};function v(t,e,n){var r=".".concat(t,":").concat(e),i=n.cssText?function(t){var e=t.getPropertyValue("content");return"".concat(t.cssText," content: '").concat(e.replace(/'|"/g,""),"';")}(n):function(t){return o(t).map((function(e){var n=t.getPropertyValue(e),r=t.getPropertyPriority(e);return"".concat(e,": ").concat(n).concat(r?" !important":"",";")})).join(" ")}(n);return document.createTextNode("".concat(r,"{").concat(i,"}"))}function p(t,e,n){var r=window.getComputedStyle(t,n),o=r.getPropertyValue("content");if(""!==o&&"none"!==o){var u=i();try{e.className="".concat(e.className," ").concat(u)}catch(t){return}var c=document.createElement("style");c.appendChild(v(u,n,r)),e.appendChild(c)}}var g="application/font-woff",m="image/jpeg",w={woff:g,woff2:g,ttf:"application/font-truetype",eot:"application/vnd.ms-fontobject",png:"image/png",jpg:m,jpeg:m,gif:"image/gif",tiff:"image/tiff",svg:"image/svg+xml",webp:"image/webp"};function b(t){var e=function(t){var e=/\.([^./]*?)$/g.exec(t);return e?e[1]:""}(t).toLowerCase();return w[e]||""}function y(t){return-1!==t.search(/^(data:)/)}function x(t,e){return"data:".concat(e,";base64,").concat(t)}function S(t,r,i){return e(this,void 0,void 0,(function(){var e,o;return n(this,(function(n){switch(n.label){case 0:return[4,fetch(t,r)];case 1:if(404===(e=n.sent()).status)throw new Error('Resource "'.concat(e.url,'" not found'));return[4,e.blob()];case 2:return o=n.sent(),[2,new Promise((function(t,n){var r=new FileReader;r.onerror=n,r.onloadend=function(){try{t(i({res:e,result:r.result}))}catch(t){n(t)}},r.readAsDataURL(o)}))]}}))}))}var E={};function C(t,r,i){return e(this,void 0,void 0,(function(){var e,o,u,c,a;return n(this,(function(n){switch(n.label){case 0:if(e=function(t,e,n){var r=t.replace(/\?.*/,"");return n&&(r=t),/ttf|otf|eot|woff2?/i.test(r)&&(r=r.replace(/.*\//,"")),e?"[".concat(e,"]").concat(r):r}(t,r,i.includeQueryParams),null!=E[e])return[2,E[e]];i.cacheBust&&(t+=(/\?/.test(t)?"&":"?")+(new Date).getTime()),n.label=1;case 1:return n.trys.push([1,3,,4]),[4,S(t,i.fetchRequestInit,(function(t){var e=t.res,n=t.result;return r||(r=e.headers.get("Content-Type")||""),function(t){return t.split(/,/)[1]}(n)}))];case 2:return u=n.sent(),o=x(u,r),[3,4];case 3:return c=n.sent(),o=i.imagePlaceholder||"",a="Failed to fetch resource: ".concat(t),c&&(a="string"==typeof c?c:c.message),a&&console.warn(a),[3,4];case 4:return E[e]=o,[2,o]}}))}))}function P(t){return e(this,void 0,void 0,(function(){var e;return n(this,(function(n){return"data:,"===(e=t.toDataURL())?[2,t.cloneNode(!1)]:[2,l(e)]}))}))}function R(t,r){return e(this,void 0,void 0,(function(){var e,i,o,u;return n(this,(function(n){switch(n.label){case 0:return t.currentSrc?(e=document.createElement("canvas"),i=e.getContext("2d"),e.width=t.clientWidth,e.height=t.clientHeight,null==i||i.drawImage(t,0,0,e.width,e.height),[2,l(e.toDataURL())]):(o=t.poster,u=b(o),[4,C(o,u,r)]);case 1:return[2,l(n.sent())]}}))}))}function T(t){var r;return e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return e.trys.push([0,3,,4]),(null===(r=null==t?void 0:t.contentDocument)||void 0===r?void 0:r.body)?[4,L(t.contentDocument.body,{},!0)]:[3,2];case 1:return[2,e.sent()];case 2:return[3,4];case 3:return e.sent(),[3,4];case 4:return[2,t.cloneNode(!1)]}}))}))}function A(t,e){return d(e,Element)&&(function(t,e){var n=e.style;if(n){var r=window.getComputedStyle(t);r.cssText?(n.cssText=r.cssText,n.transformOrigin=r.transformOrigin):o(r).forEach((function(i){var o=r.getPropertyValue(i);if("font-size"===i&&o.endsWith("px")){var u=Math.floor(parseFloat(o.substring(0,o.length-2)))-.1;o="".concat(u,"px")}d(t,HTMLIFrameElement)&&"display"===i&&"inline"===o&&(o="block"),"d"===i&&e.getAttribute("d")&&(o="path(".concat(e.getAttribute("d"),")")),n.setProperty(i,o,r.getPropertyPriority(i))}))}}(t,e),function(t,e){p(t,e,":before"),p(t,e,":after")}(t,e),function(t,e){d(t,HTMLTextAreaElement)&&(e.innerHTML=t.value),d(t,HTMLInputElement)&&e.setAttribute("value",t.value)}(t,e),function(t,e){if(d(t,HTMLSelectElement)){var n=e,r=Array.from(n.children).find((function(e){return t.value===e.getAttribute("value")}));r&&r.setAttribute("selected","")}}(t,e)),e}function L(t,r,i){return e(this,void 0,void 0,(function(){return n(this,(function(u){return i||!r.filter||r.filter(t)?[2,Promise.resolve(t).then((function(t){return function(t,r){return e(this,void 0,void 0,(function(){return n(this,(function(e){return d(t,HTMLCanvasElement)?[2,P(t)]:d(t,HTMLVideoElement)?[2,R(t,r)]:d(t,HTMLIFrameElement)?[2,T(t)]:[2,t.cloneNode(!1)]}))}))}(t,r)})).then((function(i){return function(t,r,i){var u,c;return e(this,void 0,void 0,(function(){var e;return n(this,(function(n){switch(n.label){case 0:return e=[],0===(e=null!=(a=t).tagName&&"SLOT"===a.tagName.toUpperCase()&&t.assignedNodes?o(t.assignedNodes()):d(t,HTMLIFrameElement)&&(null===(u=t.contentDocument)||void 0===u?void 0:u.body)?o(t.contentDocument.body.childNodes):o((null!==(c=t.shadowRoot)&&void 0!==c?c:t).childNodes)).length||d(t,HTMLVideoElement)?[2,r]:[4,e.reduce((function(t,e){return t.then((function(){return L(e,i)})).then((function(t){t&&r.appendChild(t)}))}),Promise.resolve())];case 1:return n.sent(),[2,r]}var a}))}))}(t,i,r)})).then((function(e){return A(t,e)})).then((function(t){return function(t,r){return e(this,void 0,void 0,(function(){var e,i,o,u,c,a,s,l,f,h,d,v,p;return n(this,(function(n){switch(n.label){case 0:if(0===(e=t.querySelectorAll?t.querySelectorAll("use"):[]).length)return[2,t];i={},p=0,n.label=1;case 1:return p<e.length?(o=e[p],(u=o.getAttribute("xlink:href"))?(c=t.querySelector(u),a=document.querySelector(u),c||!a||i[u]?[3,3]:(s=i,l=u,[4,L(a,r,!0)])):[3,3]):[3,4];case 2:s[l]=n.sent(),n.label=3;case 3:return p++,[3,1];case 4:if((f=Object.values(i)).length){for(h="http://www.w3.org/1999/xhtml",(d=document.createElementNS(h,"svg")).setAttribute("xmlns",h),d.style.position="absolute",d.style.width="0",d.style.height="0",d.style.overflow="hidden",d.style.display="none",v=document.createElementNS(h,"defs"),d.appendChild(v),p=0;p<f.length;p++)v.appendChild(f[p]);t.appendChild(d)}return[2,t]}}))}))}(t,r)}))]:[2,null]}))}))}var N=/url\((['"]?)([^'"]+?)\1\)/g,k=/url\([^)]+\)\s*format\((["']?)([^"']+)\1\)/g,I=/src:\s*(?:url\([^)]+\)\s*format\([^)]+\)[,;]\s*)+/g;function D(t,r,i,o,u){return e(this,void 0,void 0,(function(){var e,c,a,s;return n(this,(function(n){switch(n.label){case 0:return n.trys.push([0,5,,6]),e=i?function(t,e){if(t.match(/^[a-z]+:\/\//i))return t;if(t.match(/^\/\//))return window.location.protocol+t;if(t.match(/^[a-z]+:/i))return t;var n=document.implementation.createHTMLDocument(),r=n.createElement("base"),i=n.createElement("a");return n.head.appendChild(r),n.body.appendChild(i),e&&(r.href=e),i.href=t,i.href}(r,i):r,c=b(r),a=void 0,u?[4,u(e)]:[3,2];case 1:return s=n.sent(),a=x(s,c),[3,4];case 2:return[4,C(e,c,o)];case 3:a=n.sent(),n.label=4;case 4:return[2,t.replace((l=r,f=l.replace(/([.*+?^${}()|\[\]\/\\])/g,"\\$1"),new RegExp("(url\\(['\"]?)(".concat(f,")(['\"]?\\))"),"g")),"$1".concat(a,"$3"))];case 5:return n.sent(),[3,6];case 6:return[2,t]}var l,f}))}))}function M(t){return-1!==t.search(N)}function H(t,r,i){return e(this,void 0,void 0,(function(){var e,o;return n(this,(function(n){return M(t)?(e=function(t,e){var n=e.preferredFontFormat;return n?t.replace(I,(function(t){for(;;){var e=k.exec(t)||[],r=e[0],i=e[2];if(!i)return"";if(i===n)return"src: ".concat(r,";")}})):t}(t,i),o=function(t){var e=[];return t.replace(N,(function(t,n,r){return e.push(r),t})),e.filter((function(t){return!y(t)}))}(e),[2,o.reduce((function(t,e){return t.then((function(t){return D(t,e,r,i)}))}),Promise.resolve(e))]):[2,t]}))}))}function V(t,r,i){var o;return e(this,void 0,void 0,(function(){var e,u;return n(this,(function(n){switch(n.label){case 0:return(e=null===(o=r.style)||void 0===o?void 0:o.getPropertyValue(t))?[4,H(e,null,i)]:[3,2];case 1:return u=n.sent(),r.style.setProperty(t,u,r.style.getPropertyPriority(t)),[2,!0];case 2:return[2,!1]}}))}))}function F(t,r){return e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return[4,V("background",t,r)];case 1:return e.sent()?[3,3]:[4,V("background-image",t,r)];case 2:e.sent(),e.label=3;case 3:return[4,V("mask",t,r)];case 4:return e.sent()?[3,6]:[4,V("mask-image",t,r)];case 5:e.sent(),e.label=6;case 6:return[2]}}))}))}function j(t,r){return e(this,void 0,void 0,(function(){var e,i,o;return n(this,(function(n){switch(n.label){case 0:return(e=d(t,HTMLImageElement))&&!y(t.src)||d(t,SVGImageElement)&&!y(t.href.baseVal)?[4,C(i=e?t.src:t.href.baseVal,b(i),r)]:[2];case 1:return o=n.sent(),[4,new Promise((function(n,r){t.onload=n,t.onerror=r;var i=t;i.decode&&(i.decode=n),"lazy"===i.loading&&(i.loading="eager"),e?(t.srcset="",t.src=o):t.href.baseVal=o}))];case 2:return n.sent(),[2]}}))}))}function q(t,r){return e(this,void 0,void 0,(function(){var e,i;return n(this,(function(n){switch(n.label){case 0:return e=o(t.childNodes),i=e.map((function(t){return U(t,r)})),[4,Promise.all(i).then((function(){return t}))];case 1:return n.sent(),[2]}}))}))}function U(t,r){return e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return d(t,Element)?[4,F(t,r)]:[3,4];case 1:return e.sent(),[4,j(t,r)];case 2:return e.sent(),[4,q(t,r)];case 3:e.sent(),e.label=4;case 4:return[2]}}))}))}var O={};function B(t){return e(this,void 0,void 0,(function(){var e,r;return n(this,(function(n){switch(n.label){case 0:return null!=(e=O[t])?[2,e]:[4,fetch(t)];case 1:return[4,n.sent().text()];case 2:return r=n.sent(),e={url:t,cssText:r},O[t]=e,[2,e]}}))}))}function z(t,r){return e(this,void 0,void 0,(function(){var i,o,u,c,a=this;return n(this,(function(s){return i=t.cssText,o=/url\(["']?([^"')]+)["']?\)/g,u=i.match(/url\([^)]+\)/g)||[],c=u.map((function(u){return e(a,void 0,void 0,(function(){var e;return n(this,(function(n){return(e=u.replace(o,"$1")).startsWith("https://")||(e=new URL(e,t.url).href),[2,S(e,r.fetchRequestInit,(function(t){var e=t.result;return i=i.replace(u,"url(".concat(e,")")),[u,e]}))]}))}))})),[2,Promise.all(c).then((function(){return i}))]}))}))}function W(t){if(null==t)return[];for(var e=[],n=t.replace(/(\/\*[\s\S]*?\*\/)/gi,""),r=new RegExp("((@.*?keyframes [\\s\\S]*?){([\\s\\S]*?}\\s*?)})","gi");;){if(null===(u=r.exec(n)))break;e.push(u[0])}n=n.replace(r,"");for(var i=/@import[\s\S]*?url\([^)]*\)[\s\S]*?;/gi,o=new RegExp("((\\s*?(?:\\/\\*[\\s\\S]*?\\*\\/)?\\s*?@media[\\s\\S]*?){([\\s\\S]*?)}\\s*?})|(([\\s\\S]*?){([\\s\\S]*?)})","gi");;){var u;if(null===(u=i.exec(n))){if(null===(u=o.exec(n)))break;i.lastIndex=o.lastIndex}else o.lastIndex=i.lastIndex;e.push(u[0])}return e}function $(t,r){return e(this,void 0,void 0,(function(){var e,i;return n(this,(function(n){return e=[],i=[],t.forEach((function(e){if("cssRules"in e)try{o(e.cssRules||[]).forEach((function(t,n){if(t.type===CSSRule.IMPORT_RULE){var o=n+1,u=B(t.href).then((function(t){return z(t,r)})).then((function(t){return W(t).forEach((function(t){try{e.insertRule(t,t.startsWith("@import")?o+=1:e.cssRules.length)}catch(e){console.error("Error inserting rule from remote css",{rule:t,error:e})}}))})).catch((function(t){console.error("Error loading remote css",t.toString())}));i.push(u)}}))}catch(o){var n=t.find((function(t){return null==t.href}))||document.styleSheets[0];null!=e.href&&i.push(B(e.href).then((function(t){return z(t,r)})).then((function(t){return W(t).forEach((function(t){n.insertRule(t,e.cssRules.length)}))})).catch((function(t){console.error("Error loading remote stylesheet",t)}))),console.error("Error inlining remote css file",o)}})),[2,Promise.all(i).then((function(){return t.forEach((function(t){if("cssRules"in t)try{o(t.cssRules||[]).forEach((function(t){e.push(t)}))}catch(e){console.error("Error while reading CSS rules from ".concat(t.href),e)}})),e}))]}))}))}function _(t){return t.filter((function(t){return t.type===CSSRule.FONT_FACE_RULE})).filter((function(t){return M(t.style.getPropertyValue("src"))}))}function G(t,r){return e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:if(null==t.ownerDocument)throw new Error("Provided element is not within a Document");return[4,$(o(t.ownerDocument.styleSheets),r)];case 1:return[2,_(e.sent())]}}))}))}function J(t,r){return e(this,void 0,void 0,(function(){var e;return n(this,(function(n){switch(n.label){case 0:return[4,G(t,r)];case 1:return e=n.sent(),[4,Promise.all(e.map((function(t){var e=t.parentStyleSheet?t.parentStyleSheet.href:null;return H(t.cssText,e,r)})))];case 2:return[2,n.sent().join("\n")]}}))}))}function Q(t,r){return e(this,void 0,void 0,(function(){var e,i,o,u,c;return n(this,(function(n){switch(n.label){case 0:return null==r.fontEmbedCSS?[3,1]:(i=r.fontEmbedCSS,[3,5]);case 1:return r.skipFonts?(o=null,[3,4]):[3,2];case 2:return[4,J(t,r)];case 3:o=n.sent(),n.label=4;case 4:i=o,n.label=5;case 5:return(e=i)&&(u=document.createElement("style"),c=document.createTextNode(e),u.appendChild(c),t.firstChild?t.insertBefore(u,t.firstChild):t.appendChild(u)),[2]}}))}))}function X(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){var e,i,o,u;return n(this,(function(n){switch(n.label){case 0:return e=c(t,r),i=e.width,o=e.height,[4,L(t,r,!0)];case 1:return[4,Q(u=n.sent(),r)];case 2:return n.sent(),[4,U(u,r)];case 3:return n.sent(),function(t,e){var n=t.style;e.backgroundColor&&(n.backgroundColor=e.backgroundColor),e.width&&(n.width="".concat(e.width,"px")),e.height&&(n.height="".concat(e.height,"px"));var r=e.style;null!=r&&Object.keys(r).forEach((function(t){n[t]=r[t]}))}(u,r),[4,h(u,i,o)];case 4:return[2,n.sent()]}}))}))}function K(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){var e,i,o,u,s,f,h,d,v;return n(this,(function(n){switch(n.label){case 0:return e=c(t,r),i=e.width,o=e.height,[4,X(t,r)];case 1:return[4,l(n.sent())];case 2:return u=n.sent(),s=document.createElement("canvas"),f=s.getContext("2d"),h=r.pixelRatio||function(){var t,e;try{e=process}catch(t){}var n=e&&e.env?e.env.devicePixelRatio:null;return n&&(t=parseInt(n,10),Number.isNaN(t)&&(t=1)),t||window.devicePixelRatio||1}(),d=r.canvasWidth||i,v=r.canvasHeight||o,s.width=d*h,s.height=v*h,r.skipAutoScale||function(t){(t.width>a||t.height>a)&&(t.width>a&&t.height>a?t.width>t.height?(t.height*=a/t.width,t.width=a):(t.width*=a/t.height,t.height=a):t.width>a?(t.height*=a/t.width,t.width=a):(t.width*=a/t.height,t.height=a))}(s),s.style.width="".concat(d),s.style.height="".concat(v),r.backgroundColor&&(f.fillStyle=r.backgroundColor,f.fillRect(0,0,s.width,s.height)),f.drawImage(u,0,0,s.width,s.height),[2,s]}}))}))}t.getFontEmbedCSS=function(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){return n(this,(function(e){return[2,J(t,r)]}))}))},t.toBlob=function(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return[4,K(t,r)];case 1:return[4,s(e.sent())];case 2:return[2,e.sent()]}}))}))},t.toCanvas=K,t.toJpeg=function(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return[4,K(t,r)];case 1:return[2,e.sent().toDataURL("image/jpeg",r.quality||1)]}}))}))},t.toPixelData=function(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){var e,i,o,u;return n(this,(function(n){switch(n.label){case 0:return e=c(t,r),i=e.width,o=e.height,[4,K(t,r)];case 1:return u=n.sent(),[2,u.getContext("2d").getImageData(0,0,i,o).data]}}))}))},t.toPng=function(t,r){return void 0===r&&(r={}),e(this,void 0,void 0,(function(){return n(this,(function(e){switch(e.label){case 0:return[4,K(t,r)];case 1:return[2,e.sent().toDataURL()]}}))}))},t.toSvg=X}));
    /* eslint-enable */
    return module.exports;
  })();

  // ─────────────────────────────────────────────────────────────────────────
  // Boot
  // ─────────────────────────────────────────────────────────────────────────

  const boot = () => {
    if (!document.body) {
      window.setTimeout(boot, 200);
      return;
    }
    if (!resolveHtmlToImage()) {
      warn('html-to-image renderer unavailable -- the script cannot work.');
      toast('Renderer unavailable: the script is corrupted, please reinstall it.', 'error', 8000);
    }

    registerMenu();
    ensureLayer();
    ensureBulkButton();

    const resync = debounce(syncSlides, CONFIG.RESYNC_DEBOUNCE_MS);
    new MutationObserver(resync).observe(document.body, { childList: true, subtree: true });
    CONFIG.BOOT_RETRIES_MS.forEach((delay) => window.setTimeout(syncSlides, delay));
    window.requestAnimationFrame(trackPositions);

    // Debug hook: inspect detection from the userscript's console context
    // (the sandbox, not the page).
    window.__alpExport = Object.freeze({
      CONFIG,
      findSlides,
      syncSlides,
      startPicker,
      buildSelector,
      inlineAssets,
      renderToBlob,
      exportSlide,
      exportAll: handleBulkClick,
      projectSlug,
      buildFilename,
      buildZip,
      crc32,
      buildFontEmbedCSS,
      collectUsedFontFamilies,
      slides: () => buttons.map((entry) => entry.slide),
    });

    log('Ready. Tampermonkey menu -> "Pick a slide" if nothing shows up.');
  };

  boot();
})();
