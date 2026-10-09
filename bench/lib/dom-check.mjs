// Ad hoc check (not part of bench/run) that a change to how room messages are rendered or sent leaves what the
// browser ends up with unchanged: run it against the baseline image and against the changed one, then compare the
// two outputs after masking ids and timestamps (bench/TUNING.md, "Checks").
//
//   npm i playwright-core                      # anywhere; uses the installed Google Chrome
//   BENCH_KEEP=1 bench/run --apps campfire=IMAGE --reps 1 --prepare-only      # leaves the app on :47130 with the seed
//   node dom-check.mjs http://localhost:47130 david@37signals.com secret123456 <busy room id> <bot key> out.json
//
// Usage: node dom-check.mjs BASE_URL EMAIL PASSWORD ROOM_ID BOT_KEY OUT.json
// Opens the room in headless Chrome as the seed user, posts messages through the bot API while the page is
// open, and records the DOM (outerHTML, normalised) of the live-inserted messages plus the same messages
// after a reload (full page render), and the user-visible interactions (options menu, boost).
import { chromium } from "playwright-core";
import fs from "node:fs";

const [base, email, password, room, botKey, out] = process.argv.slice(2);
const browser = await chromium.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
});
const ctx = await browser.newContext({ baseURL: base });
const page = await ctx.newPage();
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });

await page.goto("/session/new");
await page.fill('input[name="email_address"]', email);
await page.fill('input[name="password"]', password);
await Promise.all([page.waitForURL(/\/rooms\/|\/$/), page.click('button[type="submit"], input[type="submit"]')]);
await page.goto(`/rooms/${room}`);
await page.waitForSelector(".message");
await page.waitForFunction(() => document.querySelector("[data-phx-main].phx-connected, [data-phx-main]:not(.phx-loading)"));

async function post(text) {
  const r = await fetch(`${base}/rooms/${room}/${botKey}/messages`, { method: "POST", headers: { "content-type": "text/plain" }, body: text });
  if (r.status !== 201) throw new Error("post " + r.status);
  return (await r.json()).id;
}

const norm = (html) => html
  .replace(/data-phx-[a-z-]+="[^"]*"/g, "")
  .replace(/ phx-(?:connected|loading)/g, "")
  .replace(/\s+/g, " ").trim();

const texts = ["live one **bold** and a link https://example.com/x", "second :) \u{1F600}", "<b>not html</b> & \"quotes\""];
const ids = [];
for (const t of texts) {
  ids.push(await post(t));
  await page.waitForSelector(`[data-message-id="${ids.at(-1)}"]`);
}
const live = {};
for (const id of ids) live[id] = norm(await page.$eval(`[data-message-id="${id}"]`, (e) => e.outerHTML));

// interactions on the last live message: open the options menu, quick-boost, see the boost
const last = ids.at(-1);
await page.click(`[data-message-id="${last}"] .message__options-btn`);
const menuOpen = await page.$eval(`[data-message-id="${last}"] details`, (d) => d.open);
await page.click(`[data-message-id="${last}"] .quick-boosts button[phx-value-content="\u{1F44D}"]`);
await page.waitForSelector(`[data-message-id="${last}"] .boost-item`);
const boosted = norm(await page.$eval(`[data-message-id="${last}"]`, (e) => e.outerHTML));

await page.reload();
await page.waitForSelector(`[data-message-id="${last}"]`);
const reloaded = {};
for (const id of ids) reloaded[id] = norm(await page.$eval(`[data-message-id="${id}"]`, (e) => e.outerHTML));
const count = await page.$$eval(".message", (m) => m.length);

// paging: scrolling to the top loads the older page (load_older), and the new live message is still there
let paged = count;
for (let i = 0; i < 8 && paged <= count; i++) {
  await page.evaluate(() => {
    for (const el of document.querySelectorAll(".messages, .message-area, main, body, html")) el.scrollTop = 0;
    window.scrollTo(0, 0);
  });
  await page.waitForTimeout(500);
  paged = await page.$$eval(".message", (m) => m.length);
}
const stillThere = (await page.$$(`[data-message-id="${last}"]`)).length;

fs.writeFileSync(out, JSON.stringify({ errors, menuOpen, live, boosted, reloaded, count, paged, stillThere,
  liveEqualsReload: ids.map((id) => live[id] === reloaded[id]) }, null, 1));
console.log("errors:", errors.length, "menuOpen:", menuOpen, "live==reload:", ids.map((id) => live[id] === reloaded[id]).join(","), "messages:", count, "after scrolling up:", paged, "newest still there:", stillThere);
await browser.close();
