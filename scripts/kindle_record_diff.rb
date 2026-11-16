# frozen_string_literal: true

# ================================================================
# File: scripts/kindle_record_diff.rb
# ================================================================
# 責務:
#   Kindle Previewer の変換の中間生成物（preprocessed/*.xhtml）を二つの記録で比べる
#   （v2-migration-plan.md §3.5 の 2・§8.5）。記録は build_copy.rb --kindle-record が
#   --collect の kindle-record/ に残したもの。
#
# 比べるもの:
#   - computedstyle 属性（変換の前処理が組んで測った値）。全部と、位置と箱の大きさを除いたものの両方を数える。
#     CSS の勝ち負けが同じでも、位置と大きさだけが変わることがある（css-layer-restructure-spec.md §10.1 の注）
#   - style 属性（変換が要素に書き出した指定）。宣言の集合で比べ、並び順だけの違いは差にしない。
#     違いは「なくなった宣言・増えた宣言」の組で数え、どの要素に出たかを添える
#
# 突き合わせ方:
#   ファイル名の頭の変換ごとのハッシュ（0_1_<16 進>_<16 進>-）を外し、要素は出現の順に並べる。
#   要素の数が違うファイルは比べない（要素を足すと並びがずれるため。その旨を出す）。
#
# 注意:
#   前処理は Chromium 相当の組版で測るので、KFX の描画が捨てる規則（:is() を含む規則・calc() など）を
#   映さない。差が 0 でも、規則の形を変えたときは Kindle Previewer の画面で確かめる
#   （kindle-css-compatibility-notes.md §2）。
#
# 使い方:
#   ruby scripts/kindle_record_diff.rb BEFORE AFTER [--verbose]
#     BEFORE・AFTER  kindle-record/ のディレクトリ
#     --verbose      位置と大きさのほかの computedstyle の違いを要素ごとに出す
#   終了コード: 0 = 差が無い / 1 = 差がある / 2 = 比べられない
# ================================================================

require 'optparse'

PREPROCESSED = File.join('intermediate', 'cTemp', 'conv_temp', 'preprocessed', '*.xhtml')
HASH_PREFIX = /\A0_1_[0-9a-f]+_[0-9a-f]+-/
GEOMETRY = %w[width height top left right bottom x y].freeze

# 要素 1 つ。computed は computedstyle を、declarations は style 属性の宣言の集合を持つ
Element = Data.define(:tag, :css_class, :computed, :declarations)

# @return [Hash{String => String}] ハッシュを外したファイル名 → パス
def record_files(record)
  files = Dir[File.join(record, PREPROCESSED)]
  abort("中間生成物がありません: #{File.join(record, PREPROCESSED)}") if files.empty?

  files.to_h { [File.basename(it).sub(HASH_PREFIX, ''), it] }
end

def elements(path)
  File.read(path, encoding: 'utf-8').scan(/<([a-zA-Z0-9]+)\s([^>]*)>/).filter_map do |tag, attrs|
    computed = attrs[/\scomputedstyle="([^"]*)"/, 1] or next
    # 属性は最初のものにも当たるように読む（タグの名前の後の空白は、上の scan が取っている）
    declarations = attrs[/(?:\A|\s)style="([^"]*)"/, 1].to_s.split(';').map { it.strip.sub(/\s*:\s*/, ':') }
    Element.new(tag:, css_class: attrs[/(?:\A|\s)class="([^"]*)"/, 1],
                computed: computed.split(';').to_h { it.split(':', 2) },
                declarations: declarations.reject(&:empty?).sort)
  end
end

options = { verbose: false }
OptionParser.new { |opts| opts.on('--verbose') { options[:verbose] = true } }.parse!
unless ARGV.size == 2
  warn '使い方: ruby scripts/kindle_record_diff.rb BEFORE AFTER [--verbose]'
  exit 2
end

before_files = record_files(ARGV[0])
after_files = record_files(ARGV[1])
only_one = (before_files.keys - after_files.keys) | (after_files.keys - before_files.keys)
puts "ファイル: 前 #{before_files.size}・後 #{after_files.size}#{"・片方だけ #{only_one.join(', ')}" unless only_one.empty?}"

totals = Hash.new(0)
style_changes = Hash.new { |hash, key| hash[key] = [0, []] }
found = !only_one.empty?

(before_files.keys & after_files.keys).sort.each do |name|
  # --- Phase: ファイルの要素を突き合わせる ---
  before = elements(before_files.fetch(name))
  after = elements(after_files.fetch(name))
  if before.size != after.size
    puts "#{name}: 要素の数が違うので比べられません（#{before.size} / #{after.size}）"
    found = true
    next
  end

  # --- Phase: 要素ごとに比べる ---
  counts = Hash.new(0)
  before.zip(after).each do |x, y|
    changed = (x.computed.keys | y.computed.keys).reject { x.computed[it] == y.computed[it] }
    counts[:computed] += 1 unless changed.empty?
    counts[:computed_style] += 1 unless (changed - GEOMETRY).empty?
    if options[:verbose] && !(changed - GEOMETRY).empty?
      detail = (changed - GEOMETRY).map { "#{it}: #{x.computed[it]} → #{y.computed[it]}" }.join('; ')
      puts "  #{name} <#{x.tag} class=#{x.css_class}> #{detail}"
    end
    next if x.declarations == y.declarations

    counts[:style] += 1
    entry = style_changes[[name, x.declarations - y.declarations, y.declarations - x.declarations]]
    entry[0] += 1
    label = [x.tag, x.css_class].compact.join('.')
    entry[1] << label unless entry[1].include?(label)
  end

  # --- Phase: ファイルの結果を出す ---
  counts[:elements] = before.size
  counts.each { |key, value| totals[key] += value }
  next if counts.values_at(:computed, :style).all?(&:zero?)

  found = true
  puts format('%-32s 要素 %5d・computedstyle の差 %4d（位置と大きさを除くと %4d）・style の差 %4d',
              name, before.size, counts[:computed], counts[:computed_style], counts[:style])
end

puts "合計: 要素 #{totals[:elements]}・computedstyle の差 #{totals[:computed]}" \
     "（位置と大きさを除くと #{totals[:computed_style]}）・style の差 #{totals[:style]}"
unless style_changes.empty?
  puts "\n## style 属性の違い（数・ファイル・なくなった宣言 → 増えた宣言・要素）"
  style_changes.sort_by { |_, (count, _)| -count }.each do |(name, removed, added), (count, labels)|
    change = "#{removed.join('; ')} → #{added.join('; ')}".strip
    puts format('%5d %-24s %s  [%s]', count, name, change, labels.first(4).join(' '))
  end
end

exit(found ? 1 : 0)
