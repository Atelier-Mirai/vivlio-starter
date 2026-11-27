// ================================================================
// File: lib/vivlio_starter/cli/lint/textlint_rules/spellcheck-tech-word.js
// ================================================================
// 責務:
//   技術用語の綴りの規則 `spellcheck-tech-word` を、vs の側で組み直したもの。
//   上流の textlint-rule-spellcheck-tech-word（5.0.0）と同じ辞書（technical-word-rules）を
//   使い、照合の仕方だけを直す。vs lint が `--rulesdir` で読み込み、上流の規則と差し替える
//   （LintRunner#own_rule_args。規則の名前はファイル名から付くので、指摘の見出しと
//   book.yml の lint.disabled_rules の名前は上流と同じ）。
//
// 上流から直した点（改善案 #170）:
//   1. 辞書の項目ごとに、段落の**すべての当たり**を照合する。上流は最初の 1 か所しか
//      照合せず、そこが正しい綴りなら照合をやめていた。「Ruby で書き、ruby で動かす」の
//      後ろの誤りを見逃し、`--fix` も 1 回に 1 か所しか直さなかった。
//   2. 大文字と小文字だけを直す当たり（`ruby` → `Ruby`・`javascript` → `JavaScript`）は、当たった語が
//      `.` か `/` で前後の英数字とつながっているとき当てない。`ruby.wasm`・`ruby/setup-ruby`
//      のようなファイル名・パッケージ名・リポジトリの名前の一部で、小文字が正しい綴り。
//      名前の全体が当たる項目（`node.JS` → `Node.js`）は前後が名前の外なので、今までどおり指摘する。
//      prh の辞書の大小だけを直す項目にも、vs lint が辞書の写しへ同じ条件を書き足す
//      （LintRunner#guard_name_parts）。二つの規則で判定を食い違わせない。
//   英字の語のすぐ後ろのかっこに書いた読み（「**Unicode**（ユニコード）」）は、ここでは扱わない。
//   同じ項目が prh の同梱辞書にもあるので、両方に効く内蔵の打ち消し（LintRunner::BUILTIN_ALLOWLIST）で外す。
//
// 上流と同じに保つ点: 項目の当て方（i の項目で、大小を区別して当たる綴りは正しいとみなす・
// 直す先が当たりの位置から始まっていれば当てない）、リンク・画像・引用・強調の中の文を見ないこと。
// ================================================================
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");

// 辞書は上流の規則の依存（textlint-rule-spellcheck-tech-word → spellcheck-technical-word →
// technical-word-rules）から読む。写しを持たないのは、上流が辞書を更新したら
// `vs doctor --upgrade` の更新だけで追随するため。上流の規則は textlint と同じ所に入るので
// （vs doctor が npm -g で入れる）、textlint の本体の場所と、本のフォルダの両方から探す。
function loadDictionary() {
  const bases = [path.join(process.cwd(), "package.json")];
  if (process.argv[1]) {
    try {
      bases.push(fs.realpathSync(process.argv[1]));
    } catch {
      // textlint の本体の場所が読めなければ、本のフォルダだけから探す
    }
  }
  for (const base of bases) {
    try {
      const rule = createRequire(base).resolve("textlint-rule-spellcheck-tech-word/package.json");
      const engine = createRequire(rule).resolve("spellcheck-technical-word/package.json");
      return createRequire(engine)("technical-word-rules");
    } catch {
      // 次の場所を探す
    }
  }
  throw new Error(
    "spellcheck-tech-word の辞書（textlint-rule-spellcheck-tech-word）が見つかりません。" +
      "vs doctor --upgrade で textlint 一式を入れ直してください。"
  );
}

// 上流の項目から抜く書き方（改善案 #180）。どれも正しい書き方を別の語へ書き換える。
//   既定 → デフォルト: 「既定」も正しい書き方で、本体と book_ai_web_starter が別々に打ち消していた。
//   薔薇 → バラ: どう書くかは著者の選択（同梱の辞書の「りんご → リンゴ」も同じ理由で外した）。
//   ML → メーリングリスト: 今は機械学習の略として使う。
// 項目ごとではなく書き方ごとに抜く。「既定|ディフォルト|デフォールト → デフォルト」の残りは正しい直し
const EXCLUDED_ALTERNATIVES = [
  { expected: "デフォルト", alternative: "既定" },
  { expected: "バラ", alternative: "薔薇" },
  { expected: "メーリングリスト", alternative: "\\bML\\b" },
];

function withoutExcluded(item) {
  const excluded = EXCLUDED_ALTERNATIVES.filter((e) => e.expected === item.expected).map((e) => e.alternative);
  if (excluded.length === 0) return item;

  const pattern = item.pattern
    .split("|")
    .filter((alternative) => !excluded.includes(alternative))
    .join("|");
  return pattern === "" ? null : { ...item, pattern };
}

const ITEMS = loadDictionary()
  .map(withoutExcluded)
  .filter((item) => item !== null)
  .map((item) => ({
    query: new RegExp(item.pattern, `${item.flag ?? ""}g`),
    replacer: new RegExp(item.pattern, item.flag ?? ""),
    strict: item.flag ? new RegExp(item.pattern) : null,
    expected: item.expected,
  }));

// 名前をつなぐ字（`ruby.wasm` の `.`・`ruby/setup-ruby` の `/`）と、その向こうの英数字
const JOINER = /[./]/;
const NAME_CHAR = /[A-Za-z0-9]/;

// 当たった語が、`.` か `/` で前後の英数字とつながった名前の一部か
function partOfName(source, start, end) {
  const joinedBefore = JOINER.test(source[start - 1] ?? "") && NAME_CHAR.test(source[start - 2] ?? "");
  const joinedAfter = JOINER.test(source[end] ?? "") && NAME_CHAR.test(source[end + 1] ?? "");
  return joinedBefore || joinedAfter;
}

// 当たった語が、英字の語の途中か（`WEBrick` の `WEBr`。改善案 #180）。
// 大文字と小文字だけを直す項目は語の全体を直すもので、語の一部に当てると名前を壊す
const ASCII_LETTER = /[A-Za-z]/;
function partOfWord(source, start, end) {
  return ASCII_LETTER.test(source[start - 1] ?? "") || ASCII_LETTER.test(source[end] ?? "");
}

// `git` の後ろに続くサブコマンド。`git init` はコマンドで、製品名の `Git` ではない（改善案 #180）
const GIT_SUBCOMMAND =
  /^[ \t]+(?:init|clone|status|add|commit|push|pull|fetch|merge|rebase|switch|checkout|branch|log|diff|restore|reset|stash|tag|remote|config|show|rm|mv|revert|cherry-pick|bisect|blame|grep|help|version|worktree|submodule)\b/;
function gitCommand(actual, source, end) {
  return actual === "git" && GIT_SUBCOMMAND.test(source.slice(end));
}

// 英語を訳語に直す項目を当てない所（改善案 #180）。
// カギかっこで引いた文言（画面の「Activity」）は、書いてあるとおりに引くもの。
// カタカナの語の直後のかっこ（「**パス**（path）」）は、訳語に添えた原語。
// 英語の語の直後のかっこのカタカナ（「Unicode（ユニコード）」）を外したこと（#170）と対になる
const QUOTE_OPEN = "「";
const QUOTE_CLOSE = "」";
const GLOSS_BEFORE = /[\p{Script=Katakana}ー](?:\*{1,2}|_{1,2})?[（(][ \t]*$/u;
const GLOSS_AFTER = /^[ \t]*[）)]/;
function quotedOrGloss(text, index, length, source, start, end) {
  const before = text.slice(0, index);
  const quoted = before.lastIndexOf(QUOTE_OPEN) > before.lastIndexOf(QUOTE_CLOSE) &&
    text.slice(index + length).includes(QUOTE_CLOSE);
  // `([^\w\s])\bpath\b` のように、当たりが前の字（`（`）から始まる項目がある。語の頭から前を見る
  const wordStart = start + (source.slice(start, end).match(/^[^A-Za-z]*/)[0].length);
  const gloss = GLOSS_BEFORE.test(source.slice(Math.max(0, wordStart - 40), wordStart)) &&
    GLOSS_AFTER.test(source.slice(end));
  return quoted || gloss;
}

// 剰余の演算子（`16 % 16`・`a % b`）。`%` を全角の百分率の記号にする項目を当てない（改善案 #180）
function moduloOperator(actual, source, start) {
  return actual.startsWith("%") &&
    /[A-Za-z0-9_)\]][ \t]*$/.test(source.slice(Math.max(0, start - 20), start)) &&
    /^[ \t]*[A-Za-z0-9_(]/.test(source.slice(start + 1));
}

function reporter(context) {
  const { Syntax, RuleError, fixer } = context;
  const skipped = [Syntax.Link, Syntax.Image, Syntax.BlockQuote, Syntax.Emphasis];

  const isInside = (node) => {
    for (let parent = node.parent; parent; parent = parent.parent) {
      if (skipped.includes(parent.type)) return true;
    }
    return false;
  };

  return {
    [Syntax.Str](node) {
      if (isInside(node)) return;

      const text = context.getSource(node);
      const source = context.getSource();
      const offset = node.range[0];

      for (const item of ITEMS) {
        item.query.lastIndex = 0;
        let match;
        while ((match = item.query.exec(text)) !== null) {
          const actual = match[0];
          if (actual === "") {
            item.query.lastIndex += 1;
            continue;
          }
          if (item.strict && item.strict.test(actual)) continue;

          const expected = actual.replace(item.replacer, item.expected);
          if (text.startsWith(expected, match.index)) continue;

          const start = offset + match.index;
          const end = start + actual.length;
          // 項目の i の印では決めない。`[Jj][Aa]…` のように字ごとに大小を並べた項目もあるため、
          // 当たった綴りと直す先が大文字と小文字の違いだけかを比べる
          const caseOnly = expected.toLowerCase() === actual.toLowerCase();
          if (caseOnly && (partOfName(source, start, end) || partOfWord(source, start, end))) continue;
          if (caseOnly && gitCommand(actual, source, end)) continue;
          if (!caseOnly && quotedOrGloss(text, match.index, actual.length, source, start, end)) continue;
          if (!caseOnly && moduloOperator(actual, source, start)) continue;

          // `--fix` で直すのは、大文字と小文字だけを直す項目に限る（改善案 #180）。訳語にする・
          // 記号を全角にするなど語を変える項目は、当たりが誤りのとき意味を変える（`16 % 16` →
          // `16 ％ 16`・「（path）」→「（パス）」）。指摘だけにして、直すかは著者が決める。
          // 直し方を付けなければ、vs lint の「自動修正可能」の件数にも入らない
          const options = { index: match.index };
          if (caseOnly) options.fix = fixer.replaceTextRange([match.index, match.index + actual.length], expected);
          context.report(node, new RuleError(`${actual} => ${expected}`, options));
        }
      }
    },
  };
}

module.exports = {
  linter: reporter,
  fixer: reporter,
};
