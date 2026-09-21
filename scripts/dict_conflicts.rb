#!/usr/bin/env ruby
# frozen_string_literal: true

# ================================================================
# File: scripts/dict_conflicts.rb
# ================================================================
# 用途:
#   vs lint が使う辞書どうしが**逆を向いていないか**を調べる。
#   一方が「A => B」と言い、他方が「B => A」と言う組み合わせは、
#   直しても直しても叱られる。著者には原因が見えないので、辞書を足したとき・
#   上流を更新したときに回す。
#
# 見る辞書:
#   - 自前         config/textlint_dictionaries/prh_*.yml
#   - 上流         technical-word-rules（spellcheck-tech-word が読む辞書）
#
# なぜ「循環」だけを数えるのか:
#   「A => B」と「B => C」が並ぶのは、指摘が二段になるだけで落ち着く先がある。
#   困るのは落ち着く先が無い場合だけなので、そこへ絞らないと件数に埋もれる
#   （実測では 58 件の衝突のうち、本当の循環は 4 件だった）。
#
# 使い方:
#   ruby scripts/dict_conflicts.rb           # trim_long_vowel: true を前提にする
#   ruby scripts/dict_conflicts.rb --no-trim # 末尾長音の項目も含めて数える
#
#   終了コードは、循環が残っていれば 1。
# ================================================================

require 'yaml'
require 'json'

ROOT = File.expand_path('..', __dir__)
OUR_DICTIONARIES = File.join(ROOT, 'config/textlint_dictionaries/prh_*.yml')

$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
require 'vivlio_starter/cli/lint'

# ツール側で既に打ち消している綴り。決着済みの循環を「残件」に数えないために読む。
BUILTIN_ALLOWLIST = VivlioStarter::CLI::LintCommands::LintRunner::BUILTIN_ALLOWLIST.filter_map do |entry|
  Regexp.new(entry.sub(%r{\A/}, '').sub(%r{/[imx]*\z}, ''))
rescue RegexpError
  nil
end

# 上流辞書は spellcheck-tech-word の依存として入る。npm のグローバル配下を探す。
def upstream_dictionary_path
  roots = [`npm root -g 2>/dev/null`.strip, '/opt/homebrew/lib/node_modules', '/usr/local/lib/node_modules']
  roots.reject(&:empty?).each do |root|
    path = File.join(root, 'textlint-rule-spellcheck-tech-word/node_modules/technical-word-rules/all.json')
    return path if File.exist?(path)
  end
  nil
end

# 1 つの置換規則。raw は辞書に書かれたままの綴り（報告に使う）。
Rule = Data.define(:source, :matcher, :expected, :raw)

# prh は `/…/` で囲むと正規表現、囲まなければただの文字列。
def compile(pattern, expected, source)
  pattern = pattern.to_s
  return nil if pattern.empty? || expected.to_s.empty?

  if (slashed = pattern.match(%r{\A/(.*)/([imx]*)\z}))
    body, flags = slashed.captures
    Rule.new(source, Regexp.new(body, flags.include?('i') ? Regexp::IGNORECASE : 0), expected.to_s, pattern)
  else
    Rule.new(source, Regexp.new(Regexp.escape(pattern)), expected.to_s, pattern)
  end
rescue RegexpError
  nil
end

def load_our_rules
  Dir.glob(OUR_DICTIONARIES).sort.flat_map do |path|
    name = File.basename(path)
    (YAML.safe_load_file(path, aliases: true)['rules'] || []).flat_map do |rule|
      Array(rule['patterns'] || rule['pattern']).filter_map { compile(it, rule['expected'], name) }
    end
  end
end

def load_upstream_rules(path)
  JSON.parse(File.read(path)).filter_map do |rule|
    next if rule['pattern'].to_s.empty? || rule['expected'].to_s.empty?

    flags = rule['flag'].to_s.include?('i') ? Regexp::IGNORECASE : 0
    begin
      Rule.new('technical-word-rules', Regexp.new(rule['pattern'], flags), rule['expected'].to_s, rule['pattern'])
    rescue RegexpError
      nil
    end
  end
end

# book.yml の lint.trim_long_vowel: true が実行時に落とす項目か。
# 判定は lib/vivlio_starter/cli/lint.rb の long_vowel_entry? と同じ
# ——見出し語に「ー」を足すと期待の綴りになるもの。
def long_vowel_entry?(rule)
  base = rule.raw.sub(%r{\A/}, '').sub(%r{/[imx]*\z}, '').sub(/\(\?!.*\)\z/, '')
  rule.expected == "#{base}ー"
end

# other が rule の直し先を指摘し、その直し先が rule の見出し語へ戻るなら循環。
def cycle?(rule, other)
  matched = other.matcher.match(rule.expected)
  return false unless matched

  back = rule.expected.sub(other.matcher) { other.expected.gsub(/\$(\d)/) { matched[$1.to_i].to_s } }
  return false if back == rule.expected

  rule.matcher.match?(back)
end

# --- Phase: 読み込み ---

upstream_path = upstream_dictionary_path
unless upstream_path
  warn '🔴 上流辞書 technical-word-rules が見つかりません。'
  warn '   npm install -g textlint-rule-spellcheck-tech-word で導入してください。'
  exit 2
end

trim = !ARGV.include?('--no-trim')
ours = load_our_rules
upstream = load_upstream_rules(upstream_path)

puts "自前 #{ours.size} 規則 / 上流 #{upstream.size} 規則"
puts "上流辞書: #{upstream_path}"
puts

# --- Phase: 循環を探す ---

cycles = ours.flat_map { |rule| upstream.filter_map { [rule, it] if cycle?(rule, it) } }
cycles += ours.combination(2).select { |a, b| a.source != b.source && cycle?(a, b) }

absorbed, rest = cycles.partition { |rule, _| trim && long_vowel_entry?(rule) }
settled, remaining = rest.partition { |rule, _| BUILTIN_ALLOWLIST.any? { it.match?(rule.expected) } }

# --- Phase: 報告 ---

puts "末尾長音（trim_long_vowel: true が落とす分）: #{absorbed.size} 件" if trim
puts "BUILTIN_ALLOWLIST で決着済み: #{settled.size} 件（#{settled.map { it[0].expected }.join('・')}）" if settled.any?
puts

if remaining.empty?
  puts '✅ 未決着の循環はありません。'
  exit 0
end

puts "🟡 逆を向いていて、まだ決着していない組み合わせ: #{remaining.size} 件"
puts
remaining.each do |rule, other|
  puts "   自前  #{rule.raw}  →  #{rule.expected}   [#{rule.source}]"
  puts "   相手  #{other.raw}  →  #{other.expected}   [#{other.source}]"
  puts
end

puts '上流が「文字を削るだけ」の規則は、直し先が元の綴りの先頭に一致するため'
puts '実際には発火しません（spellcheck-technical-word の実装）。本当に指摘されるかは'
puts '短い原稿を作って vs lint に通して確かめてください。'
exit 1
