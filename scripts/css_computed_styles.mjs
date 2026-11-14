// ================================================================
// scripts/css_computed_styles.mjs — Chromium で全要素の計算値を書き出す
// ================================================================
// scripts/css_computed_diff.rb が呼ぶ（単独では使わない）。puppeteer を使うので JavaScript で書く。
//
// 使い方: node scripts/css_computed_styles.mjs JOBS.json
//   JOBS.json: { chrome, puppeteer, jobs: [{ html, base, css, inline, media, out }] }
//     html    組み上がった HTML（<link rel="stylesheet"> は外し、css を当てる）
//     base    相対パスを解く置き場（元の HTML のディレクトリ。付け替えた HTML でも元の場所を指す）
//     css     当てる CSS のパス。inline が true なら <style> に中身を入れ、false なら <link> で読む
//             （層ありの入口は @import を解くので <link>、平らな CSS は <style>）
//     media   "screen" か "print"
//     out     書き出す JSON。[{ d: 要素の説明, vals: { プロパティ: 値 } }] の要素の出現の順
//
// 疑似要素は content が none・normal でも項目を残す（vals は content だけ）。前後で content の
// 有無が変わっても、要素の並びがずれずに突き合わせられるようにするため。
// 計算値は document.fonts.ready を待ってから取る。待たないと、同じ CSS どうしでも、
// 書体の読み込みの途中で組まれた要素の高さが違う。
// ================================================================
import fs from 'node:fs';
import path from 'node:path';

const spec = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const { default: puppeteer } = await import(spec.puppeteer);
const browser = await puppeteer.launch({ executablePath: spec.chrome, args: ['--allow-file-access-from-files'] });
const scratch = fs.mkdtempSync(path.join(path.dirname(process.argv[2]), 'page-'));

for (const job of spec.jobs) {
  // 画像などの相対パスは、元の HTML の置き場（job.base）から解く
  const base = `<base href="file://${job.base}/">`;
  const css = job.inline
    ? `<style>${fs.readFileSync(job.css, 'utf8')}</style>`
    : `<link rel="stylesheet" href="file://${job.css}">`;
  const html = fs.readFileSync(job.html, 'utf8')
    .replace(/<link[^>]*rel="stylesheet"[^>]*>/g, '')
    .replace(/<head([^>]*)>/, `<head$1>${base}${css}`);
  const page_file = path.join(scratch, path.basename(job.html));
  fs.writeFileSync(page_file, html);

  const page = await browser.newPage();
  await page.setViewport({ width: 794, height: 1123 });
  await page.emulateMediaType(job.media);
  await page.goto(`file://${page_file}`, { waitUntil: 'load' });
  await page.evaluate(async () => { await document.fonts.ready; });
  const data = await page.evaluate(() => {
    const props = Array.from(getComputedStyle(document.body)).filter((p) => !p.startsWith('--'));
    const label = (el) => {
      const cls = typeof el.className === 'string' && el.className.trim() ? `.${el.className.trim().split(/\s+/).join('.')}` : '';
      return `${el.tagName.toLowerCase()}${cls}`;
    };
    const out = [];
    for (const el of [document.body, ...document.body.querySelectorAll('*')]) {
      const d = el.parentElement ? `${label(el.parentElement)} > ${label(el)}` : label(el);
      for (const pseudo of [null, '::before', '::after']) {
        const cs = getComputedStyle(el, pseudo);
        if (pseudo && (cs.content === 'none' || cs.content === 'normal')) {
          out.push({ d: d + pseudo, vals: { content: cs.content } });
          continue;
        }
        const vals = {};
        for (const p of props) vals[p] = cs.getPropertyValue(p);
        out.push({ d: d + (pseudo || ''), vals });
      }
    }
    return out;
  });
  fs.writeFileSync(job.out, JSON.stringify(data));
  await page.close();
}
await browser.close();
fs.rmSync(scratch, { recursive: true, force: true });
