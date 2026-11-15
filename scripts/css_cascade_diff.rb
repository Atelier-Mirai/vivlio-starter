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
require 'vivlio_starter/cli/css/cascade'

Flattener = VivlioStarter::CLI::Css::Flattener
LAYERS = VivlioStarter::CLI::Css::EntryWriter::LAYERS
Cascade = VivlioStarter::CLI::Css::Cascade
Selector = VivlioStarter::CLI::Css::Selector
UNLAYERED = Cascade::UNLAYERED
ENTRY_DIR = File.join('.cache', 'vs-cascade-diff')

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

# --- 比べる -------------------------------------------------------------

def rule_texts(pieces) = pieces.map { [Cascade.layer_rank(it.layer), it.text.gsub(/\s+/, ' ').strip] }

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

      was = Cascade.layered_precedence(before_by_key[left]) <=> Cascade.layered_precedence(before_by_key[right])
      now = Cascade.layered_precedence(a_after) <=> Cascade.layered_precedence(b_after)
      next if was == now || !Selector.may_overlap?(a_after.subject, b_after.subject)

      winner, loser = now.positive? ? [a_after, b_after] : [b_after, a_after]
      [longhand, before_by_key[winner.key], winner, before_by_key[loser.key], loser]
    end
  end
end

def describe(decl) = "#{decl.selector} { #{decl.property}: #{decl.value}#{' !important' if decl.important} }"

def layer_name(rank) = rank == UNLAYERED ? '層の外' : LAYERS[rank]

def short_source(decl) = "#{File.basename(File.dirname(decl.source))}/#{File.basename(decl.source)}"

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
      cache[[path, selector]] ||= doc.css(Selector.nokogiri_selectors(selector).join(', '))
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
    before_decls, before_opaque = Cascade.collect(before_pieces)
    after_decls, after_opaque = Cascade.collect(after_pieces)
    kind_flips = flips(before_decls, after_decls)
    opaque_changed = before_opaque != after_opaque

    puts "## #{kind}: 規則 #{before_rules.size} → #{after_rules.size}・なくなった #{missing.size}・" \
         "増えた #{added.size}・入れ替わり #{kind_flips.size}#{'・@page などの順が違う' if opaque_changed}"
    missing.each { puts "  - なくなった: #{it[0, 160]}" }
    added.each { puts "  + 増えた: #{it[0, 160]}" }
    layer_moves(before_rules, after_rules).each { |text, was, now| move_report[[text, was, now]] << kind }
    kind_flips.each { |flip| flip_report[flip.map { it.is_a?(Cascade::Decl) ? it.key : it }] << [kind, flip] }
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
    puts "    勝つようになった: #{describe(winner)}  (#{short_source(winner)}・" \
         "#{layer_name(winner_before.rank)}→#{layer_name(winner.rank)})"
    puts "    負けるようになった: #{describe(loser)}  (#{short_source(loser)}・" \
         "#{layer_name(loser_before.rank)}→#{layer_name(loser.rank)})"
  end
end

exit(found ? 1 : 0)
