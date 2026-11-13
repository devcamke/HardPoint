// Records the film behind the landing page's "Watch a sale": a sale in the demo shop from the first search to the
// receipt, paid by M-Pesa (simulated there), with captions and a pointer drawn over the screen.
//
//   node script/sale_video.mjs <output directory>
//
// Then copy the .webm to app/assets/images/marketing/sale.webm and poster.jpg to sale-poster.jpg.
// Needs the app running with the demo shop seeded (bin/setup, then bin/dev) and its jobs running, and Playwright with
// its Chromium (npm install --no-save playwright && npx playwright install chromium). It rings up a real sale in
// that shop each time. Settings, from the environment, as for script/help_screenshots.mjs:
//   HELP_SHOP_URL   default http://demo.localhost:3000
//   HELP_EMAIL      default owner@demo.test
//   HELP_PASSWORD   default hardpoint-demo
import { readdirSync, statSync, mkdirSync } from "node:fs"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const { chromium } = require("playwright")
const fs = { readdirSync, statSync }
const out = process.argv[2], shop = process.env.HELP_SHOP_URL || "http://demo.localhost:3000", size = { width: 1280, height: 720 }
mkdirSync(out, { recursive: true })
const overlay = () => {
  const ready = () => {
    if (document.getElementById('rec-cursor')) return;
    const c = document.createElement('div'); c.id = 'rec-cursor';
    c.style.cssText = 'position:fixed;z-index:2147483647;left:0;top:0;width:22px;height:22px;margin:-11px 0 0 -11px;border-radius:50%;background:rgba(228,111,47,.55);border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4);pointer-events:none;transition:transform .12s';
    const b = document.createElement('div'); b.id = 'rec-caption';
    b.style.cssText = 'position:fixed;z-index:2147483646;left:16px;bottom:64px;max-width:640px;padding:12px 18px;border-radius:12px;background:rgba(7,45,53,.94);color:#fff;font:600 19px/1.35 system-ui,sans-serif;box-shadow:0 8px 24px rgba(0,0,0,.25);pointer-events:none;display:none';
    document.documentElement.append(c, b);
    const saved = sessionStorage.getItem('rec-caption'); if (saved) { b.textContent = saved; b.style.display = 'block'; }
    const at = JSON.parse(sessionStorage.getItem('rec-at') || '[640,360]'); c.style.left = at[0] + 'px'; c.style.top = at[1] + 'px';
    addEventListener('mousemove', e => { c.style.left = e.clientX + 'px'; c.style.top = e.clientY + 'px'; sessionStorage.setItem('rec-at', JSON.stringify([e.clientX, e.clientY])); }, true);
    addEventListener('mousedown', () => { c.style.transform = 'scale(.7)'; }, true);
    addEventListener('mouseup', () => { c.style.transform = ''; }, true);
  };
  if (document.documentElement) ready(); addEventListener('DOMContentLoaded', ready);
};
(async () => {
  const browser = await chromium.launch();
  // Sign in off camera.
  const first = await browser.newContext({ viewport: size });
  let page = await first.newPage();
  await page.goto(shop + '/session/new');
  await page.fill('#email_address', process.env.HELP_EMAIL || 'owner@demo.test'); await page.fill('#password', process.env.HELP_PASSWORD || 'hardpoint-demo');
  await Promise.all([ page.waitForURL(u => !u.pathname.startsWith('/session')), page.click('input[type=submit]') ]);
  await page.goto(shop + '/pos');
  if (page.url().includes('/pos/till')) { await page.locator('a, button', { hasText: /shift open/ }).first().click(); await page.waitForURL(/\/pos$/); }
  await page.locator('[data-tour=categories]').waitFor();
  if (await page.locator('[data-tour=lines] li').count() > 0) {
    page.on('dialog', d => d.accept());
    await page.getByRole('button', { name: 'Clear sale' }).click(); await page.waitForTimeout(1200);
  }
  console.log('lines before recording', await page.locator('[data-tour=lines] li').count());
  const state = await first.storageState(); await first.close();

  const context = await browser.newContext({ viewport: size, storageState: state, recordVideo: { dir: out, size } });
  await context.addInitScript(overlay);
  page = await context.newPage();
  const say = async (text, ms = 1600) => {
    await page.evaluate(t => { sessionStorage.setItem('rec-caption', t); const b = document.getElementById('rec-caption'); if (b) { b.textContent = t; b.style.display = 'block'; } }, text);
    await page.waitForTimeout(ms);
  };
  const tidy = () => page.evaluate(() => [...document.querySelectorAll('body *')].find(e => e.textContent.includes('export all your shop') && e.getBoundingClientRect().height < 50 && e.getBoundingClientRect().width > 1000)?.remove());
  const go = async (locator, click = true) => {
    const box = await locator.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 30 });
    await page.waitForTimeout(350);
    if (click) { await page.mouse.down(); await page.waitForTimeout(90); await page.mouse.up(); }
  };
  await page.goto(shop + '/pos');
  await page.locator('[data-tour=categories]').waitFor();
  await tidy();
  await say('A sale at the counter, in HardPoint’s demo shop.', 2600);

  // Cement, found by typing.
  const search = page.locator('#code');
  await go(search);
  await say('Scan a barcode, or type to search.', 600);
  await search.pressSequentially('cement', { delay: 110 });
  await page.waitForTimeout(1300);
  await go(page.locator('#search_results button[type=submit]', { hasText: 'Portland cement 50kg' }).first());
  const qty = page.locator('dialog[open] input[name=quantity]');
  await qty.waitFor();
  await say('Ten bags of cement.', 500);
  await qty.fill(''); await qty.pressSequentially('10', { delay: 160 });
  await page.waitForTimeout(600);
  await go(page.locator('dialog[open]').getByRole('button', { name: 'Add to sale' }));
  await page.waitForTimeout(1500);

  // Nails, by weight, from the quick picks.
  await search.fill(''); await page.waitForTimeout(900);
  await tidy();
  await go(page.locator('#search_results button[type=submit]', { hasText: 'Wire nails 4 inch' }).first());
  await qty.waitFor();
  await say('Nails by the kilo: 2.5 kg.', 500);
  await qty.fill(''); await qty.pressSequentially('2.5', { delay: 160 });
  await page.waitForTimeout(600);
  await go(page.locator('dialog[open]').getByRole('button', { name: 'Add to sale' }));
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/poster.jpg`, type: 'jpeg', quality: 82 });

  // M-Pesa: a prompt to the customer's phone (the demo shop's M-Pesa is simulated).
  await go(page.getByText('M-Pesa', { exact: true }).last());
  await say('Paying by M-Pesa: send a prompt to the customer’s phone.', 1400);
  const phone = page.locator('#phone');
  await go(phone);
  await phone.pressSequentially('0722 000 111', { delay: 90 });
  await page.waitForTimeout(500);
  await go(page.getByRole('button', { name: 'Send prompt' }));
  await say('The customer enters their M-Pesa PIN on their own phone. (Simulated in the demo shop.)', 0);
  await page.waitForURL(/completed=/, { timeout: 30000 });
  await page.waitForTimeout(500);
  await tidy();
  await say('Paid. The sale completes by itself.', 2600);
  await go(page.getByText('Print receipt', { exact: true }).first(), false);
  await say('Print the receipt, or send it by WhatsApp, email or text.', 900);
  await go(page.getByText('WhatsApp receipt', { exact: true }).first(), false);
  await page.waitForTimeout(2200);
  await say('That’s a sale. Try HardPoint free for 30 days.', 3200);
  await context.close();
  const video = fs.readdirSync(out).find(f => f.endsWith('.webm'));
  console.log('video', video, fs.statSync(`${out}/${video}`).size);
  await browser.close();
})().catch(e => { console.error(String(e).slice(0, 700)); process.exit(1); });
