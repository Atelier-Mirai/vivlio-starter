#!/usr/bin/env ruby
# frozen_string_literal: true

# vs pdf:read の出力を元の原稿と突き合わせ、どこまで戻せたかを数える物差し。
#
#   ruby scripts/pdf_read_score.rb contents/97-sample.md out1.md [out2.md ...]
#
# 文字の一致と構造の数の 2 つを並べて出す。
#   - 文字の一致: 原稿から記法を外し、codes/ の取り込みを展開し、数式を除いた文字列を基準に、
#     空白を無視して文字単位の最長共通部分列（diff の Myers 法）で再現率・適合率を出す。
#     脚注のように位置が動いた文字は、一致しなかった分として数えられる。
#   - 構造の数: 見出し・コードの囲み・表の行・::: ブロック・脚注・画像・リストを数える。
# 合格の目安は pdf-read-structure-spec.md と pdf-read-ocr-postprocess-spec.md に置く。
require 'open3'
require 'tmpdir'

Score = Data.define(:label, :chars, :recall, :precision, :ascii_hit, :ascii_total, :structure) do
  def f_value = recall + precision == 0 ? 0.0 : 2 * recall * precision / (recall + precision)
end

# --- 原稿を「紙面に載る文字列」へ寄せる ---

# ```include:file[:a-b]``` を codes/ の中身で置き換える。codes/ は原稿のプロジェクトのものを使う
def expand_includes(markdown, codes_dir)
  markdown.gsub(/^```include:([^:`]+)(?::(\d+)-(\d+))?```$/) do
    file, first, last = ::Regexp.last_match.captures
    path = File.join(codes_dir, file)
    next '' unless File.file?(path)

    lines = File.readlines(path)
    lines = lines[(first.to_i - 1)..(last.to_i - 1)] if first
    lines.join
  end
end

# 記法を外して文字だけを残す。数式は紙面で画像になり文字として取れないので、両側から除く
def manuscript_plain(markdown, codes_dir)
  text = expand_includes(markdown, codes_dir)
         .gsub(/<!--.*?-->/m, '').gsub('<br>', '')
         .gsub(/^\$\$\n.*?\n\$\$$/m, '').gsub(/\$[^$\n]+\$/, '')

  text.lines.filter_map do |line|
    next if line.match?(/\A(?::::|```)/)
    next if line.match?(/\A(?:rect|pointer|circle|arrow):/)
    next if line.match?(/\A\|\s*:?-+/)
    next if line.match?(/\A!\[[^\]]*\]\([^)]*\)(\{[^}]*\})?\s*\z/)

    line.sub(/\A#+\s*/, '').sub(/\A[-*]\s+/, '').sub(/\A>\s?/, '').sub(/\A\[\^\w+\]:\s*/, '')
        .gsub(/\[\^\w+\]/, '')
        .gsub(/\{([^|{}]+)\|([^{}]+)\}/, '\2\1')
        .gsub(/@\w+:[\w-]+/, '')
        .delete('*`').tr('|', ' ')
  end.join
end

# 比べる前の正規化。全角英数を半角へ寄せ、空白と節の記号（♣）を落とす
def normalize(text) = text.unicode_normalize(:nfkc).gsub(/\s+/, '').delete('♣')

# --- 突き合わせ ---

# 文字単位の最長共通部分列の長さ。1 文字 1 行のファイルにして diff に任せる（Ruby の DP では遅い）
def lcs_length(reference, output)
  Dir.mktmpdir do |dir|
    ref_path = File.join(dir, 'reference')
    out_path = File.join(dir, 'output')
    File.write(ref_path, "#{reference.chars.join("\n")}\n")
    File.write(out_path, "#{output.chars.join("\n")}\n")
    diff, = Open3.capture2('diff', '-d', ref_path, out_path)
    reference.length - diff.lines.count { it.start_with?('< ') }
  end
end

# 英字 3 文字以上の語がどれだけ戻ったか。コードの識別子の崩れ（metal → metat）を拾う
def ascii_words(text) = text.unicode_normalize(:nfkc).scan(/[A-Za-z_][A-Za-z0-9_]{2,}/).tally

def structure_counts(markdown)
  lines = markdown.lines
  {
    '見出し' => lines.count { it.match?(/\A#+ /) },
    # ```include:file``` は 1 行で 1 ブロック。ほかは開きと閉じの 2 行で 1 ブロック
    'コードの囲み' => lines.count { it.match?(/\A```include:/) } +
                      (lines.count { it.start_with?('```') && !it.match?(/\A```include:/) } / 2),
    '表の行' => lines.count { it.start_with?('|') },
    ':::ブロック' => lines.count { it.match?(/\A:::\s*\{/) },
    '脚注の参照' => markdown.scan(/\[\^\w+\](?!:)/).size,
    '脚注の本文' => lines.count { it.match?(/\A\[\^\w+\]:/) },
    '画像' => markdown.scan(/!\[[^\]]*\]\([^)]+\)/).size,
    'リストの項目' => lines.count { it.match?(/\A(?:\d+\.|[-*]) /) }
  }
end

def score(label, markdown, reference_plain)
  reference = normalize(reference_plain)
  output = normalize(markdown)
  lcs = output.empty? ? 0 : lcs_length(reference, output)
  ref_words = ascii_words(reference_plain)
  out_words = ascii_words(markdown)

  Score.new(
    label:,
    chars: output.length,
    recall: lcs.fdiv(reference.length),
    precision: output.empty? ? 0.0 : lcs.fdiv(output.length),
    ascii_hit: ref_words.sum { |word, count| [count, out_words.fetch(word, 0)].min },
    ascii_total: ref_words.values.sum,
    structure: structure_counts(markdown)
  )
end

# --- 表示 ---

def print_report(manuscript_path, reference_length, scores, original_structure)
  puts "基準: #{manuscript_path}（記法と数式を除いて #{reference_length} 字）"
  puts
  puts format('%-28s %8s %8s %8s %8s %12s', '出力', '字数', '再現率', '適合率', 'F値', '英字の語')
  scores.each do |s|
    puts format('%-28s %8d %7.1f%% %7.1f%% %7.1f%% %6d/%-5d',
                s.label, s.chars, s.recall * 100, s.precision * 100, s.f_value * 100, s.ascii_hit, s.ascii_total)
  end
  puts
  puts format('%-14s %8s', '構造', '原稿') + scores.map { format(' %12s', it.label[0, 12]) }.join
  original_structure.each do |name, count|
    puts format('%-14s %8d', name, count) + scores.map { format(' %12d', it.structure[name]) }.join
  end
end

if ARGV.size < 2
  warn 'usage: ruby scripts/pdf_read_score.rb MANUSCRIPT.md OUTPUT.md [OUTPUT.md ...]'
  exit 1
end

manuscript_path, *output_paths = ARGV
manuscript = File.read(manuscript_path)
# 原稿は contents/ の下にある前提で、その親を本のプロジェクトとみなして codes/ を探す
codes_dir = File.expand_path('../../codes', manuscript_path)
reference_plain = manuscript_plain(manuscript, codes_dir)

scores = output_paths.map do |path|
  # contents/ の下の出力なら、その上の作業ディレクトリ名（std-born など）をラベルにする
  label = File.basename(File.dirname(path)) == 'contents' ? File.basename(File.dirname(path, 2)) : File.basename(path, '.md')
  score(label, File.read(path), reference_plain)
end

print_report(manuscript_path, normalize(reference_plain).length, scores, structure_counts(manuscript))
