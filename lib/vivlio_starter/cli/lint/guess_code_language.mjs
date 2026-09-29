// ================================================================
// File: lib/vivlio_starter/cli/lint/guess_code_language.mjs
// ================================================================
// 責務:
//   言語名のないコードブロックの言語を Guesslang（@vscode/vscode-languagedetection）で
//   推定する。仕様: code-language-detection-spec.md §4.2。
//   確信度の閾値と候補の決め方は Ruby 側（CodeLanguageGuesser・CodeLanguageDetector）が
//   持ち、ここは推定して候補の中の最上位を返すだけにする。
//
// 入出力:
//   stdin : JSON { package: "<パッケージのディレクトリ>",
//                  languages: { "<Guesslang の ID>": "<Prism の言語名>" },
//                  items: [{ id, body, candidates: ["<Prism の言語名>"] }] }
//   stdout: JSON 配列 [{ id, language, confidence, share }]
//           候補に入る言語が 1 つも返らなかった項目（20 文字未満など）は含めない。
//
// 日本語の置き換え:
//   日本語を含むコードをそのまま渡すと、Guesslang は ini と高い確信度で判定する
//   （学習に使われたコードが英語中心のため。実測は仕様 §1.4）。日本語の連なりを
//   `x` に置き換えてから渡す。消すと `"配列表示"` が `""` になり文字列の形が変わる。
// ================================================================

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';

const input = JSON.parse(readFileSync(0, 'utf8'));
const require = createRequire(import.meta.url);
const { ModelOperations } = require(input.package);
const model = new ModelOperations();

const results = [];
for (const item of input.items) {
  const scores = await model.runModel(item.body.replace(/[^\x00-\x7F]+/g, 'x'));
  const inCandidates = scores
    .map((score) => ({ language: input.languages[score.languageId], confidence: score.confidence }))
    .filter((score) => score.language && item.candidates.includes(score.language));
  if (inCandidates.length === 0) continue;

  // share は候補の中だけで割り直した確信度（候補の確信度の合計に占める割合）
  const total = inCandidates.reduce((sum, score) => sum + score.confidence, 0);
  const best = inCandidates[0];
  results.push({ id: item.id, ...best, share: total > 0 ? best.confidence / total : 0 });
}
model.dispose();
process.stdout.write(JSON.stringify(results));
