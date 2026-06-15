// ================================================================
// File: lib/vivlio_starter/cli/pre_process/mathjax_to_svg.mjs
// ================================================================
// 責務:
//   LaTeX 数式を MathJax で「静的な SVG 文字列」へ変換する（ビルド時 SVG 生成器）。
//   リーダー実行時の MathJax ではなく、前処理段階で SVG を焼き込むための裏方。
//   生成した SVG は Ruby 側が <img> として埋め込むため、PDF・EPUB・表セルの
//   いずれでも同一 SVG が表示される（lasem の記号グリフ化け対策として MathJax を採用）。
//
// 入出力:
//   stdin : JSON 配列 [{ id, latex, display }]
//   stdout: JSON オブジェクト { id: "<svg…>" }（描画失敗は null）
//
// 依存解決:
//   mathjax-full は通常グローバル導入（vs doctor --fix が npm -g で導入）。
//   ESM の bare import はグローバルを解決しないため、Ruby 側が渡す
//   環境変数 MATHJAX_ROOT（= npm root -g 等の node_modules パス）から絶対 import する。
//   ローカル node_modules にある場合は bare import が成功するためそちらを優先する。
// ================================================================

import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

// mathjax-full のサブモジュールを、ローカル→グローバルの順で動的 import する。
async function importMathJax(subpath) {
  const spec = 'mathjax-full/js/' + subpath;
  try {
    return await import(spec);
  } catch {
    const root = process.env.MATHJAX_ROOT;
    if (!root) throw new Error('mathjax-full を解決できません（MATHJAX_ROOT 未設定）');
    return await import(pathToFileURL(join(root, 'mathjax-full', 'js', subpath)).href);
  }
}

// SVG ルートから ex 単位の表示寸法（vertical-align/width/height）を取り除き、
// data-vs-* 属性へ退避する。viewBox だけ残すことで、Safari/WebKit 系の EPUB リーダーが
// 小さな intrinsic サイズで一度ラスタライズしてから拡大する（→ ぼやけ・ジャギー）のを防ぎ、
// コンテナの実表示サイズでラスタライズさせて鮮明に保つ。退避した寸法は Ruby 側が <img> の
// style（本文フォント相対）に写す。
function normalizeSvg(svg) {
  const openMatch = svg.match(/^<svg[^>]*>/);
  if (!openMatch) return svg;
  const open = openMatch[0];

  const valign = (open.match(/vertical-align:\s*([\-\d.]+ex)/) || [])[1] || '';
  const width = (open.match(/\bwidth="([\d.]+ex)"/) || [])[1] || '';
  const height = (open.match(/\bheight="([\d.]+ex)"/) || [])[1] || '';

  const newOpen = open
    .replace(/\s*style="[^"]*"/, '')
    .replace(/\s*width="[\d.]+ex"/, '')
    .replace(/\s*height="[\d.]+ex"/, '')
    .replace(/^<svg/, `<svg data-vs-valign="${valign}" data-vs-width="${width}" data-vs-height="${height}"`);

  return svg.replace(open, newOpen);
}

async function main() {
  const { mathjax } = await importMathJax('mathjax.js');
  const { TeX } = await importMathJax('input/tex.js');
  const { SVG } = await importMathJax('output/svg.js');
  const { liteAdaptor } = await importMathJax('adaptors/liteAdaptor.js');
  const { RegisterHTMLHandler } = await importMathJax('handlers/html.js');
  const { AllPackages } = await importMathJax('input/tex/AllPackages.js');

  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);

  // fontCache: 'none' で各 SVG にグリフのパスを内包させ、外部参照のない
  // 自己完結 SVG にする（EPUB 同梱・epubcheck で安全）。
  const tex = new TeX({ packages: AllPackages });
  const svg = new SVG({ fontCache: 'none' });
  const doc = mathjax.document('', { InputJax: tex, OutputJax: svg });

  let input = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) input += chunk;
  const items = JSON.parse(input || '[]');

  const out = {};
  for (const item of items) {
    try {
      const node = doc.convert(String(item.latex), { display: Boolean(item.display) });
      const html = adaptor.outerHTML(node);
      const match = html.match(/<svg[\s\S]*<\/svg>/);
      out[item.id] = match ? normalizeSvg(match[0]) : null;
    } catch {
      out[item.id] = null;
    }
  }

  process.stdout.write(JSON.stringify(out));
}

main().catch((e) => {
  process.stderr.write(String(e && e.message ? e.message : e));
  process.exit(1);
});
