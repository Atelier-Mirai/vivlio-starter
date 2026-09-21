#!/usr/bin/env ruby
# frozen_string_literal: true

# ================================================================
# File: scripts/dict_conflicts.rb
# ================================================================
# 用途:
#   vs lint が使う辞書どうしが**逆を向いていないか**を調べる。
#
#   守る約束は 1 つ。**自前の辞書が「こう書け」と言う綴りは、他のどの規則からも
#   叱られてはならない。** これが破れると、著者は指摘を消せない——直すと別の
#   ルールが鳴り、戻すと元のルールが鳴る。原因は辞書の側にあるので、原稿を
#   いくら読んでも分からない。
#
# 調べ方:
#   自前 prh 辞書の expected（著者が書くことになる綴り）を集め、
#
#     1. spellcheck-tech-word が叱らないか  … 上流の実装にそのまま尋ねる
#     2. 自前の別の辞書が叱らないか          … Ruby で照合する
#     3. 同じ expected を別ファイルが宣言していないか
#
#   3 は逆を向く話ではないが、**規則が黙って死ぬ**ので一緒に見る。prh は expected の
#   同じ規則をファイルをまたいで統合し、**後から読む辞書のパターンを捨てる**。
#   実測: prh_idiom.yml に `いまだに => 今だに` を足した途端、prh_open_close.yml の
#   `いまだに => 未だに` が一切鳴らなくなった（同じファイルの中なら両方残る）。
#   エラーも警告も出ないので、辞書を読んでも気づけない。
#
#   1 で上流の実装を**実際に呼ぶ**のがこの検査の肝である。自前で規則を真似ると
#   上流の癖まで写し取れない。たとえば spellcheck-tech-word は「直し先が元の
#   綴りの先頭に一致する規則」を自ら黙らせるので、`エディター => エディタ` の
#   ような末尾長音を削る項目は**一度も発火しない**。この癖を知らずに正規表現で
#   数えると、実害の無い衝突を 54 件も拾ってしまう（実測）。
#
# 使い方:
#   ruby scripts/dict_conflicts.rb           既定（lint.trim_long_vowel: true）で調べる
#   ruby scripts/dict_conflicts.rb --no-trim 末尾長音を省かない本での衝突も含めて調べる
#
#   終了コード  0 … 矛盾なし
#               1 … 矛盾あり（内容を表示する）
#               2 … 上流辞書が見つからず検査できない
# ================================================================

require 'yaml'
require 'json'
require 'open3'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
require 'vivlio_starter/cli/lint'

RUNNER = VivlioStarter::CLI::LintCommands::LintRunner

# 上流辞書は spellcheck-tech-word の依存として入る。npm のグローバル配下を探す。
def spellcheck_module_path
  roots = [`npm root -g 2>/dev/null`.strip, '/opt/homebrew/lib/node_modules', '/usr/local/lib/node_modules']
  roots.reject(&:empty?).each do |root|
    path = File.join(root, 'textlint-rule-spellcheck-tech-word/node_modules/spellcheck-technical-word')
    return path if File.exist?(File.join(path, 'package.json'))
  end
  nil
end

# 自前 prh 辞書の 1 項目。expected が「著者が書くことになる綴り」。
Entry = Data.define(:file, :expected, :patterns)

# 辞書を読む順（.textlintrc.yml の rulePaths と同じ）。prh の統合は先勝ちなので、
# どちらが生き残るかはこの順で決まる。
def dictionary_paths
  config = YAML.safe_load_file(File.join(ROOT, 'config/.textlintrc.yml'))
  rule_paths = config.dig('rules', 'prh', 'rulePaths') || []
  rule_paths.map { File.expand_path(it, File.join(ROOT, 'config')) }
            .select { File.basename(it).start_with?('prh_') && File.exist?(it) }
end

# 同じ expected を別ファイルが宣言していないか。後から読むほうのパターンが消える。
def shadowed_entries(paths)
  owner = {}
  paths.flat_map do |path|
    name = File.basename(path)
    (YAML.safe_load_file(path, aliases: true)['rules'] || []).filter_map do |rule|
      expected = rule['expected'].to_s
      next if expected.empty?

      first = owner[expected]
      # 同じファイルの中なら両方とも残るので、別ファイルのときだけ数える
      if first.nil?
        owner[expected] = name
        next
      end
      next if first == name

      { expected:, winner: first, loser: name,
        patterns: Array(rule['patterns'] || rule['pattern']).map(&:to_s) }
    end
  end
end

def load_entries
  dictionary_paths.flat_map do |path|
    name = File.basename(path)
    (YAML.safe_load_file(path, aliases: true)['rules'] || []).filter_map do |rule|
      expected = rule['expected'].to_s
      # $1 のような後方参照を含む expected は、そのままでは実在の綴りにならない
      next if expected.empty? || expected.include?('$')

      Entry.new(name, expected, Array(rule['patterns'] || rule['pattern']).map(&:to_s))
    end
  end
end

# lint.trim_long_vowel が有効なとき、実行時に辞書から落とされる項目か。
# 判定は lib/vivlio_starter/cli/lint.rb の long_vowel_entry? と同じ
# ——見出し語に「ー」を足すと期待の綴りになるもの。既定で有効な設定なので、
# 既定のまま使う本にとっては存在しない項目として扱う。
def long_vowel_entry?(entry)
  entry.patterns.any? do |pattern|
    base = pattern.sub(%r{\A/}, '').sub(%r{/[imx]*\z}, '').sub(/\(\?!.*\)\z/, '')
    entry.expected == "#{base}ー"
  end
end

def compile(pattern)
  if (slashed = pattern.match(%r{\A/(.*)/([imx]*)\z}))
    body, flags = slashed.captures
    Regexp.new(body, flags.include?('i') ? Regexp::IGNORECASE : 0)
  else
    Regexp.new(Regexp.escape(pattern))
  end
rescue RegexpError
  nil
end

# ツール側で既に打ち消している綴り。実行時 textlintrc の filters.allowlist.allow
# へ注がれ、フィルタで消えた指摘には修正も当たらない。
def allowlist_matchers
  (RUNNER::BUILTIN_ALLOWLIST + RUNNER::TRIM_LONG_VOWEL_ALLOWLIST).filter_map { compile(it) }
end

# 上流の実装にそのまま尋ねる。語ごとに呼ぶ——spellCheckText は 1 つの規則につき
# 最初の一致しか返さないので、まとめて 1 つの文字列にすると取りこぼす。
def ask_spellcheck(module_path, words)
  script = <<~JS
    const { spellCheckText } = require(#{module_path.to_json});
    const words = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const out = {};
    for (const w of words) {
      const hits = spellCheckText(w);
      if (hits.length) out[w] = hits.map(h => h.actual + " => " + h.expected);
    }
    process.stdout.write(JSON.stringify(out));
  JS

  stdout, stderr, status = Open3.capture3('node', '-e', script, stdin_data: JSON.generate(words))
  raise "node の実行に失敗しました: #{stderr}" unless status.success?

  JSON.parse(stdout)
end

# --- Phase: 準備 ---

module_path = spellcheck_module_path
unless module_path
  warn '🟡 spellcheck-technical-word が見つからないため検査できません。'
  warn '   npm install -g textlint-rule-spellcheck-tech-word で導入してください。'
  exit 2
end

trim = !ARGV.include?('--no-trim')
all = load_entries
entries = trim ? all.reject { long_vowel_entry?(it) } : all
exempt = allowlist_matchers
candidates = entries.reject { |entry| exempt.any? { it.match?(entry.expected) } }

puts "自前辞書の項目: #{all.size} 件"
puts "  末尾長音として実行時に落ちる: #{all.size - entries.size} 件（lint.trim_long_vowel: true）" if trim
puts "  ツール側で打ち消し済み:       #{entries.size - candidates.size} 件（BUILTIN_ALLOWLIST）"
puts "  照合する:                     #{candidates.size} 件"

# --- Phase: 上流に尋ねる ---

flagged = ask_spellcheck(module_path, candidates.map(&:expected).uniq)
upstream_conflicts = candidates.select { flagged.key?(it.expected) }

# --- Phase: 自前どうしを照合する ---

matchers = entries.flat_map do |entry|
  entry.patterns.filter_map { |pattern| [entry, compile(pattern)] if compile(pattern) }
end

# **同じファイルの中も照合する。** 辞書が育つと、あとから足した一般則が先に
# 書いた個別項目と食い違う。実測で prh_open_close.yml が自分自身と逆を向いていた
# （「どういう時 => どういうとき」と「どういう => どのような」が同居）。
own_conflicts = candidates.flat_map do |entry|
  matchers.filter_map do |other, matcher|
    next if other.equal?(entry) || other.expected == entry.expected

    [entry, other] if matcher.match?(entry.expected)
  end
end

# --- Phase: 報告 ---

shadowed = shadowed_entries(dictionary_paths)

if upstream_conflicts.empty? && own_conflicts.empty? && shadowed.empty?
  puts '✅ 自前辞書の綴りは、どの規則からも叱られません。取り込まれずに消える規則もありません。'
  exit 0
end

unless shadowed.empty?
  puts
  puts "🔴 同じ expected を別ファイルが宣言していて、後のパターンが捨てられます: #{shadowed.size} 件"
  shadowed.each do |hit|
    puts "   「#{hit[:expected]}」を #{hit[:winner]} と #{hit[:loser]} の両方が宣言しています"
    puts "     消えるパターン: #{hit[:patterns].join('・')}（#{hit[:loser]} 側）"
  end
  puts '   → どちらかの辞書へ patterns をまとめてください。同じファイルの中なら両方とも残ります。'
end

unless upstream_conflicts.empty?
  puts
  puts "🔴 自前辞書が「こう書け」と言う綴りを、spellcheck-tech-word が叱ります: #{upstream_conflicts.size} 件"
  upstream_conflicts.each do |entry|
    puts "   #{entry.file} が → #{entry.expected}"
    flagged[entry.expected].each { puts "     spellcheck: #{it}" }
  end
end

unless own_conflicts.empty?
  puts
  puts "🔴 自前辞書どうしが逆を向いています: #{own_conflicts.size} 件"
  own_conflicts.each do |entry, other|
    puts "   #{entry.file} が → #{entry.expected}"
    puts "   #{other.file} が → #{other.expected}"
  end
end

puts
puts '直し方は 3 つ。辞書の項目そのものが誤っていれば辞書を直す。上流の取りこぼしなら'
puts 'BUILTIN_ALLOWLIST（lib/vivlio_starter/cli/lint.rb）で打ち消す。本の方針の問題なら'
puts 'config/textlint_allowlist.yml は著者に委ねる。'
exit 1
