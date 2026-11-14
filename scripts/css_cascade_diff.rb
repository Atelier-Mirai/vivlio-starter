# frozen_string_literal: true

# ================================================================
# File: scripts/css_cascade_diff.rb
# ================================================================
# 責務:
#   CSS のファイルを分けたり層を移したりした前と後で、ページの種類ごとに
#   「読む規則の集合」と「規則どうしの勝ち負け」が変わっていないかを調べる
#   （css-layer-restructure-spec.md §8 の S2-2〜S2-4 の確かめ）。
#
# なぜ要るか:
#   PDF の画素の比較は、本書で使っている記法と PDF に当たる規則しか確かめられない。
#   body.vs-kindle・body.vs-epub の規則や、本書に出てこない記法の規則は、画素では
#   差が出ない。そこで、入口を平らにした規則の列を前後で突き合わせ、次の三つを数える。
#     1. 規則の増減  … 前にあって後に無い規則・後にだけある規則（文字列で比べる）
#     2. 層の移動    … 同じ規則が別の層へ移ったもの（勝ち負けが変わりうるので一覧にする）
#     3. 勝ち負けの入れ替わり … 同じプロパティ（ロングハンドへ展開して比べる）で値の違う
#        二つの宣言のうち、同じ要素に当たりうる組で、勝つ側が前後で入れ替わったもの
#   3 の「同じ要素に当たりうる」は控えめに判定する（クラスの組は問わず、要素名と
#   疑似要素だけで当たらないと言えるものを外す）。挙がった組は手で読んで判断する。
#
# 使い方:
#   ruby scripts/css_cascade_diff.rb [--before REV] [--after DIR] [--kind KIND]...
#     --before  比べる前の版（git のリビジョン。既定は HEAD）
#     --after   比べる後のリポジトリ（既定は作業ツリー）
#     --kind    調べるページの種類（既定は全部）
#   終了コード: 0 = 差が無い / 1 = 差がある / 2 = 比べられない
#
# 前提:
#   横書き（horizontal-tb・ltr）として論理方向を物理方向へ読み替える。
#   .cache/vs/book-settings.css があれば、前後の両方の settings 層に同じものを入れる。
# ================================================================

require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'lib'))
Dir.chdir(ROOT)
require 'vivlio_starter/cli/css/flattener'
require 'vivlio_starter/cli/css/entry_writer'

Flattener = VivlioStarter::CLI::Css::Flattener
LAYERS = VivlioStarter::CLI::Css::EntryWriter::LAYERS
UNLAYERED = LAYERS.size
ENTRY_DIR = File.join('.cache', 'vs-cascade-diff')

# 宣言 1 つ。key は前後で同じ宣言を突き合わせる鍵、order は平らにした列の中の位置
Decl = Data.define(:key, :selector, :subject, :specificity, :longhands, :property, :value,
                   :important, :rank, :order, :source)
# 選択子の対象（最後の複合選択子）。tags は nil なら何の要素でもよい
Subject = Data.define(:tags, :excluded, :pseudo_element)

LEGACY_PSEUDO_ELEMENTS = %w[before after first-line first-letter].freeze
SIDES = { 'top' => 'top', 'right' => 'right', 'bottom' => 'bottom', 'left' => 'left',
          'block-start' => 'top', 'block-end' => 'bottom', 'inline-start' => 'left',
          'inline-end' => 'right' }.freeze
AXES = { 'block' => %w[top bottom], 'inline' => %w[left right] }.freeze
ALL_SIDES = %w[top right bottom left].freeze
BORDER_PARTS = %w[width style color].freeze
SHORTHANDS = {
  'font' => %w[font-style font-variant font-weight font-size line-height font-family font-stretch],
  'background' => %w[background-color background-image background-position background-size
                     background-repeat background-attachment background-origin background-clip],
  'list-style' => %w[list-style-type list-style-position list-style-image],
  'text-decoration' => %w[text-decoration-line text-decoration-color text-decoration-style
                          text-decoration-thickness],
  'gap' => %w[row-gap column-gap], 'grid-gap' => %w[row-gap column-gap],
  'flex' => %w[flex-grow flex-shrink flex-basis], 'flex-flow' => %w[flex-direction flex-wrap],
  'overflow' => %w[overflow-x overflow-y], 'columns' => %w[column-width column-count],
  'outline' => %w[outline-width outline-style outline-color]
}.freeze
# 同じものの別名（論理と物理・新旧の名前）
ALIASES = {
  'inline-size' => 'width', 'block-size' => 'height', 'max-inline-size' => 'max-width',
  'max-block-size' => 'max-height', 'min-inline-size' => 'min-width', 'min-block-size' => 'min-height',
  'page-break-before' => 'break-before', 'page-break-after' => 'break-after',
  'page-break-inside' => 'break-inside', 'word-wrap' => 'overflow-wrap',
  'text-wrap' => 'white-space', 'text-wrap-mode' => 'white-space', 'white-space-collapse' => 'white-space',
  '-webkit-appearance' => 'appearance'
}.freeze


# --- 入口を描く -------------------------------------------------------------

# リポジトリ（root）の EntryWriter で全種類の入口を描き、root/.cache/vs-cascade-diff/ に書く。
# 別のプロセスで描くのは、前と後で EntryWriter の中身（IMPORTS）が違うためである
def write_entries(root)
  script = 'w = VivlioStarter::CLI::Css::EntryWriter; ' \
           'puts JSON.generate(w::IMPORTS.keys.to_h { [it, w.render(it)] })'
  out, err, status = Open3.capture3('ruby', '-Ilib', '-rjson', '-rvivlio_starter/cli/css/entry_writer',
                                    '-e', script, chdir: root)
  abort("入口を描けません（#{root}）: #{err}") unless status.success?

  dir = File.join(root, ENTRY_DIR)
  FileUtils.mkdir_p(dir)
  %w[book-settings.css book-fonts.css].each do |name|
    generated = File.join(ROOT, '.cache', 'vs', name)
    FileUtils.cp(generated, dir) if File.file?(generated)
  end
  JSON.parse(out).to_h do |kind, css|
    path = File.join(dir, "entry-#{kind}.css")
    File.write(path, css)
    [kind, path]
  end
end

# git のリビジョンを一時のディレクトリへ取り出す
def checkout(rev, into)
  archive, status = Open3.capture2('git', '-C', ROOT, 'archive', rev, 'lib', 'stylesheets', 'config',
                                   binmode: true)
  abort("git archive に失敗しました: #{rev}") unless status.success?
  _, err, status = Open3.capture3('tar', '-x', '-C', into, stdin_data: archive, binmode: true)
  abort("取り出しに失敗しました: #{err}") unless status.success?
end

# --- 選択子を読む -------------------------------------------------------------

# 括弧と角括弧の外で sep の位置を切る
def split_top(text, sep)
  parts = []
  depth = 0
  current = +''
  text.each_char do |ch|
    depth += 1 if '(['.include?(ch)
    depth -= 1 if ')]'.include?(ch)
    if ch == sep && depth.zero?
      parts << current.strip
      current = +''
    else
      current << ch
    end
  end
  parts << current.strip
  parts.reject(&:empty?)
end

def skip_ident(text, index)
  index += 1 while index < text.length && text[index].match?(/[\w\-\\]/)
  index
end

def matching_paren(text, open)
  depth = 0
  (open...text.length).each do |i|
    depth += 1 if text[i] == '('
    depth -= 1 if text[i] == ')'
    return i if depth.zero?
  end
  text.length - 1
end

# 詳細度 [a, b, c]。:is()・:not()・:has() は引数の最大、:where() は 0
def specificity(selector)
  score = [0, 0, 0]
  i = 0
  while i < selector.length
    ch = selector[i]
    case ch
    when '#' then score[0] += 1
                  i = skip_ident(selector, i + 1)
    when '.' then score[1] += 1
                  i = skip_ident(selector, i + 1)
    when '[' then score[1] += 1
                  i = (selector.index(']', i) || selector.length) + 1
    when ':' then i = pseudo_specificity(selector, i, score)
    when /[a-zA-Z_]/ then score[2] += 1
                          i = skip_ident(selector, i)
    else i += 1
    end
  end
  score
end

# 疑似クラス・疑似要素 1 つ分の詳細度を score に足し、次の位置を返す
def pseudo_specificity(selector, index, score)
  if selector[index + 1] == ':'
    score[2] += 1
    stop = skip_ident(selector, index + 2)
    return selector[stop] == '(' ? matching_paren(selector, stop) + 1 : stop
  end

  stop = skip_ident(selector, index + 1)
  name = selector[(index + 1)...stop].downcase
  unless selector[stop] == '('
    LEGACY_PSEUDO_ELEMENTS.include?(name) ? score[2] += 1 : score[1] += 1
    return stop
  end

  close = matching_paren(selector, stop)
  args = selector[(stop + 1)...close]
  inner = case name
          when 'where' then [0, 0, 0]
          when 'is', 'not', 'has', 'matches' then split_top(args, ',').map { specificity(it) }.max
          when 'nth-child', 'nth-last-child'
            of = args[/\bof\b(.*)/m, 1]
            [0, 1, 0].zip(of ? split_top(of, ',').map { specificity(it) }.max : [0, 0, 0]).map(&:sum)
          else [0, 1, 0]
          end
  score.each_index { score[it] += inner[it] }
  close + 1
end

# 最後の複合選択子（結合子の後ろ）
def last_compound(selector)
  depth = 0
  start = 0
  selector.each_char.with_index do |ch, i|
    depth += 1 if '(['.include?(ch)
    depth -= 1 if ')]'.include?(ch)
    start = i + 1 if depth.zero? && (ch.match?(/\s/) || '>+~'.include?(ch))
  end
  selector[start..].strip
end

# 複合選択子の、括弧の外にある :name(…) の引数を集める
def pseudo_args(compound, name)
  compound.to_enum(:scan, /:#{name}\(/i).map do
    open = Regexp.last_match.end(0) - 1
    split_top(compound[(open + 1)...matching_paren(compound, open)], ',')
  end
end

def subject_of(selector)
  compound = last_compound(selector)
  head = compound[/\A([a-zA-Z][\w-]*)/, 1]&.downcase
  tags = head ? [head] : nil
  tags = ['html'] if compound.match?(/:root\b/i)
  pseudo_args(compound, 'is').each do |args|
    names = args.map(&:downcase)
    tags = tags ? tags & names : names if names.all? { it.match?(/\A[a-z][\w-]*\z/) }
  end
  excluded = pseudo_args(compound, 'not').flat_map do |args|
    args.flat_map { |arg| arg.match?(/\A:is\(/i) ? pseudo_args(arg, 'is').flatten : [arg] }
        .map(&:downcase).grep(/\A[a-z][\w-]*\z/)
  end
  legacy = compound[/:(#{LEGACY_PSEUDO_ELEMENTS.join('|')})\b/o, 1]
  pseudo = compound[/::([\w-]+)/, 1] || legacy
  Subject.new(tags:, excluded:, pseudo_element: pseudo)
end

# 二つの選択子が同じ要素に当たりうるか（控えめ: 当たらないと言えるときだけ false）
def overlap?(left, right)
  return false unless left.pseudo_element == right.pseudo_element

  tags = if left.tags && right.tags then left.tags & right.tags
         else left.tags || right.tags
         end
  return true if tags.nil?

  (tags - left.excluded - right.excluded).any?
end

# --- 宣言を集める -------------------------------------------------------------

def longhands(property)
  name = property.downcase
  name = ALIASES.fetch(name, name)
  case name
  when 'margin', 'padding', 'inset' then ALL_SIDES.map { side_name(name, it) }
  when /\A(margin|padding|inset)-(block|inline)\z/ then AXES.fetch(Regexp.last_match(2)).map { side_name(Regexp.last_match(1), it) }
  when /\A(margin|padding|inset)-(.+)\z/ then [side_name(Regexp.last_match(1), SIDES.fetch(Regexp.last_match(2), Regexp.last_match(2)))]
  when 'top', 'right', 'bottom', 'left' then [name]
  when 'border' then ALL_SIDES.product(BORDER_PARTS).map { "border-#{it.join('-')}" }
  when /\Aborder-(block|inline)\z/ then AXES.fetch(Regexp.last_match(1)).product(BORDER_PARTS).map { "border-#{it.join('-')}" }
  when /\Aborder-(width|style|color)\z/ then ALL_SIDES.map { "border-#{it}-#{Regexp.last_match(1)}" }
  when /\Aborder-(block|inline)-(width|style|color)\z/
    part = Regexp.last_match(2)
    AXES.fetch(Regexp.last_match(1)).map { "border-#{it}-#{part}" }
  when /\Aborder-([a-z-]+?)-(width|style|color)\z/ then ["border-#{SIDES.fetch(Regexp.last_match(1), Regexp.last_match(1))}-#{Regexp.last_match(2)}"]
  when /\Aborder-(top|right|bottom|left|block-start|block-end|inline-start|inline-end)\z/
    BORDER_PARTS.map { "border-#{SIDES.fetch(Regexp.last_match(1))}-#{it}" }
  when /radius/ then ['border-radius']
  else SHORTHANDS.fetch(name, [name])
  end
end

def side_name(base, side) = base == 'inset' ? side : "#{base}-#{side}"

def layer_rank(layer) = layer.empty? ? UNLAYERED : LAYERS.index(layer.first) || UNLAYERED

# 平らにした規則の列を、宣言の列と、選択子を持たない規則（@page・@font-face）の列にする
def collect(pieces)
  decls = []
  opaque = []
  seen = Hash.new(0)
  pieces.each_with_index do |piece, piece_index|
    walk(Crass.parse(piece.text), [], piece, piece_index, decls, opaque, seen)
  end
  [decls, opaque]
end

def walk(nodes, context, piece, piece_index, decls, opaque, seen)
  nodes.each do |node|
    case node
    in { node: :style_rule, selector: { value: selector_list }, children: }
      properties = children.select { it[:node] == :property }
      split_top(selector_list, ',').each do |raw|
        selector = raw.gsub(/\s+/, ' ')
        properties.each_with_index do |prop, decl_index|
          add_decl(decls, seen, context, selector, prop, piece, [piece_index, decl_index])
        end
      end
    in { node: :at_rule, name: /\A(media|supports)\z/i => name, prelude:, block: Array => block }
      inner = "@#{name.downcase} #{Crass::Parser.stringify(prelude).strip}"
      walk(Crass::Parser.parse_rules(block), [*context, inner], piece, piece_index, decls, opaque, seen)
    in { node: :at_rule }
      opaque << [layer_rank(piece.layer), Crass::Parser.stringify([node]).gsub(/\s+/, ' ').strip]
    else nil
    end
  end
end

def add_decl(decls, seen, context, selector, prop, piece, order)
  base = [context, selector, prop[:name].downcase, prop[:value].gsub(/\s+/, ' '), prop[:important]]
  key = [*base, seen[base] += 1]
  decls << Decl.new(key:, selector:, subject: subject_of(selector), specificity: specificity(selector),
                    longhands: longhands(prop[:name]), property: prop[:name].downcase, value: base[3],
                    important: prop[:important], rank: layer_rank(piece.layer), order:,
                    source: "#{File.basename(File.dirname(piece.source))}/#{File.basename(piece.source)}")
end

# カスケードの強さ。!important は層の順が逆になり、層の外が最も弱い
def precedence(decl)
  if decl.important
    [1, decl.rank == UNLAYERED ? -1 : UNLAYERED - decl.rank, *decl.specificity, *decl.order]
  else
    [0, decl.rank, *decl.specificity, *decl.order]
  end
end

# --- 比べる -------------------------------------------------------------

def rule_texts(pieces) = pieces.map { [layer_rank(it.layer), it.text.gsub(/\s+/, ' ').strip] }

# 前後で勝つ側が入れ替わった宣言の組
def flips(before, after)
  before_by_key = before.to_h { [it.key, it] }
  after_by_key = after.to_h { [it.key, it] }
  common = after_by_key.keys & before_by_key.keys
  groups = Hash.new { |hash, key| hash[key] = [] }
  common.each { |key| after_by_key[key].longhands.each { groups[it] << key } }

  groups.flat_map do |longhand, keys|
    keys.combination(2).filter_map do |left, right|
      a_after = after_by_key[left]
      b_after = after_by_key[right]
      next if a_after.property == b_after.property && a_after.value == b_after.value

      was = precedence(before_by_key[left]) <=> precedence(before_by_key[right])
      now = precedence(a_after) <=> precedence(b_after)
      next if was == now || !overlap?(a_after.subject, b_after.subject)

      winner, loser = now.positive? ? [a_after, b_after] : [b_after, a_after]
      [longhand, before_by_key[winner.key], winner, before_by_key[loser.key], loser]
    end
  end
end

def describe(decl) = "#{decl.selector} { #{decl.property}: #{decl.value}#{' !important' if decl.important} }"

def layer_name(rank) = rank == UNLAYERED ? '層の外' : LAYERS[rank]

def multiset_diff(left, right)
  counts = right.tally
  left.each_with_object([]) do |item, missing|
    counts[item].to_i.positive? ? counts[item] -= 1 : missing << item
  end
end

# 規則の文字列が同じで層だけ違うもの
def layer_moves(before_rules, after_rules)
  before_by_text = before_rules.group_by(&:last).transform_values { it.map(&:first).sort }
  after_rules.group_by(&:last).filter_map do |text, list|
    was = before_by_text[text]
    now = list.map(&:first).sort
    [text, was, now] if was && was != now
  end
end

# --- 組み上がった HTML で絞り込む -------------------------------------------------

# 静的な HTML では決まらない疑似クラスと、疑似要素（対象はその元の要素で数える）
STRIPPED_PSEUDO = /::[\w-]+(?:\([^()]*\))?|:(?:before|after|first-line|first-letter|hover|focus|active|visited|link)\b/

# Nokogiri が読める形にする。:is()・:where() は選択子の並びに、:not(:is(a, b)) は
# :not(a):not(b) に展開する。疑似要素などは外す
def nokogiri_selectors(selector)
  text = selector.gsub(STRIPPED_PSEUDO, '').gsub(/:root\b/, 'html').gsub(':checked', '[checked]')
  expand_is(expand_not_is(text))
end

def expand_not_is(text)
  while (match = text.match(/:not\(:is\(/))
    is_open = match.end(0) - 1
    is_close = matching_paren(text, is_open)
    not_close = matching_paren(text, match.begin(0) + 4)
    args = split_top(text[(is_open + 1)...is_close], ',')
    text = text[0...match.begin(0)] + args.map { ":not(#{it})" }.join + text[(not_close + 1)..]
  end
  text
end

def expand_is(selector)
  match = selector.match(/:(?:is|where|matches)\(/)
  return [selector.strip] unless match

  open = match.end(0) - 1
  close = matching_paren(selector, open)
  head = selector[0...match.begin(0)]
  tail = selector[(close + 1)..]
  split_top(selector[(open + 1)...close], ',').flat_map { expand_is("#{head}#{it}#{tail}") }
end

# HTML・XHTML・EPUB の中の文書を読む
def load_documents(paths, tmp)
  paths.flat_map do |path|
    files = if File.directory?(path) then Dir.glob(File.join(path, '**', '*.{html,xhtml}'))
            elsif path.end_with?('.epub')
              dir = Dir.mktmpdir('epub', tmp)
              system('unzip', '-q', '-o', path, '-d', dir, exception: true)
              Dir.glob(File.join(dir, '**', '*.xhtml'))
            else [path]
            end
    files.map { [it, Nokogiri::HTML5(File.read(it, encoding: 'utf-8'), max_errors: 0)] }
  end
end

# 両方の選択子に当たる要素の数（読めない選択子は nil を返し、当たるものとして扱う）
def shared_elements(documents, left, right, cache)
  documents.sum do |path, doc|
    matched = [left, right].map do |selector|
      cache[[path, selector]] ||= doc.css(nokogiri_selectors(selector).join(', '))
    end
    (matched[0] & matched[1]).size
  end
rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
  nil
end

# --- 実行 -------------------------------------------------------------

options = { before: 'HEAD', after: ROOT, kinds: [], html: [] }
OptionParser.new do |opts|
  opts.on('--before REV') { options[:before] = it }
  opts.on('--after DIR') { options[:after] = File.expand_path(it) }
  opts.on('--kind KIND') { options[:kinds] << it }
  opts.on('--html PATH', '入れ替わりの組を、この HTML（ディレクトリ・EPUB も可）で両方に当たる要素がある組に絞る') do
    options[:html] << File.expand_path(it)
  end
end.parse!
require 'nokogiri' unless options[:html].empty?

found = false
flip_report = Hash.new { |hash, key| hash[key] = [] }
move_report = Hash.new { |hash, key| hash[key] = [] }

Dir.mktmpdir('css-cascade-diff') do |tmp|
  checkout(options[:before], tmp)
  before_entries = write_entries(tmp)
  after_entries = write_entries(options[:after])
  kinds = options[:kinds].empty? ? after_entries.keys : options[:kinds]
  # url() はリポジトリの中の位置で比べる（前と後でリポジトリの置き場が違うため）
  relative_to = ->(root) { ->(path) { path.delete_prefix("#{root}/") } }

  kinds.each do |kind|
    before_pieces = Flattener.pieces(before_entries.fetch(kind), rebase: relative_to.call(tmp))
    after_pieces = Flattener.pieces(after_entries.fetch(kind), rebase: relative_to.call(options[:after]))
    before_rules = rule_texts(before_pieces)
    after_rules = rule_texts(after_pieces)
    missing = multiset_diff(before_rules.map(&:last), after_rules.map(&:last))
    added = multiset_diff(after_rules.map(&:last), before_rules.map(&:last))
    before_decls, before_opaque = collect(before_pieces)
    after_decls, after_opaque = collect(after_pieces)
    kind_flips = flips(before_decls, after_decls)
    opaque_changed = before_opaque != after_opaque

    puts "## #{kind}: 規則 #{before_rules.size} → #{after_rules.size}・なくなった #{missing.size}・" \
         "増えた #{added.size}・入れ替わり #{kind_flips.size}#{'・@page などの順が違う' if opaque_changed}"
    missing.each { puts "  - なくなった: #{it[0, 160]}" }
    added.each { puts "  + 増えた: #{it[0, 160]}" }
    layer_moves(before_rules, after_rules).each { |text, was, now| move_report[[text, was, now]] << kind }
    kind_flips.each { |flip| flip_report[flip.map { it.is_a?(Decl) ? it.key : it }] << [kind, flip] }
    found ||= missing.any? || added.any? || kind_flips.any? || opaque_changed
  end

  # 組み上がった HTML で、両方の選択子に当たる要素が無い組を外す
  unless options[:html].empty?
    documents = load_documents(options[:html], tmp)
    cache = {}
    unmatched = 0
    flip_report.select! do |_, entries|
      _, _, winner, _, loser = entries.first.last
      count = shared_elements(documents, winner.selector, loser.selector, cache)
      entries.each { it << count }
      (count.nil? || count.positive?).tap { unmatched += 1 unless it }
    end
    puts "\n（HTML #{documents.size} 文書で、両方に当たる要素が無い入れ替わり #{unmatched} 組を外した）"
  end
end

unless move_report.empty?
  puts "\n## 層の移動（#{move_report.size} 規則）"
  move_report.each do |(text, was, now), kinds|
    puts "  #{was.map { layer_name(it) }.uniq.join('/')} → #{now.map { layer_name(it) }.uniq.join('/')}: " \
         "#{text[0, 120]}  [#{kinds.join(' ')}]"
  end
end

unless flip_report.empty?
  puts "\n## 勝ち負けの入れ替わり（#{flip_report.size} 組）"
  flip_report.each_value do |entries|
    longhand, winner_before, winner, loser_before, loser = entries.first[1]
    shared = entries.first[2]
    note = if entries.first.size < 3 then ''
           elsif shared.nil? then '・HTML で調べられない選択子'
           else "・HTML で両方に当たる要素 #{shared}"
           end
    puts "  #{longhand}  [#{entries.map(&:first).join(' ')}]#{note}"
    puts "    勝つようになった: #{describe(winner)}  (#{winner.source}・" \
         "#{layer_name(winner_before.rank)}→#{layer_name(winner.rank)})"
    puts "    負けるようになった: #{describe(loser)}  (#{loser.source}・" \
         "#{layer_name(loser_before.rank)}→#{layer_name(loser.rank)})"
  end
end

exit(found ? 1 : 0)
