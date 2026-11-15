# frozen_string_literal: true

# ================================================================
# File: scripts/css_computed_diff.rb
# ================================================================
# 責務:
#   組み上がった HTML に、前の版と後の版の CSS を当てて Chromium で組み、全要素と
#   ::before・::after の計算値を比べる（v2-migration-plan.md §8.4・§8.5 の比べ方）。
#
# なぜ要るか:
#   scripts/css_cascade_diff.rb は規則を文字列で突き合わせるので、選択子を書き換えた規則や、
#   ページの種類が読むファイルを変えたときの結果は比べられない。PDF の画素は、本書で使って
#   いる記法の PDF しか確かめられない。同じ HTML に前後の CSS を当てて計算値を比べると、
#   EPUB・Kindle 用の HTML も含めて、CSS の変更が要素に与える差だけが残る。
#
# 使い方:
#   ruby scripts/css_computed_diff.rb [オプション] HTML またはディレクトリ...
#     HTML は写しの本の .cache/vs/build/{pdf,epub,kindle}/ の下のもの（build_copy.rb --no-clean）。
#     ディレクトリを渡すと、その中の *.html を全部比べる。
#     --before REV      比べる前の版（git のリビジョン。既定は HEAD）
#     --after DIR       比べる後のリポジトリ（既定は作業ツリー）
#     --media LIST      媒体（既定は screen,print）
#     --pdf-forms LIST  pdf/ の HTML に当てる CSS の形（既定は layered,flat。EPUB・Kindle は flat だけ）
#     --as KIND         body の種類のクラスを KIND に付け替えて比べる（例: 章の HTML を preface にし、
#                       本書の前書きに無い記法で、前書きの CSS の変更の影響を見る）
#     --ignore-layout   位置と箱の大きさ（width・top など）の差を数えない
#     --top N           違いの一覧に出す行の数（既定は 80）
#     --after-settings DIR  後の側にだけ使う book-settings*.css の置き場（book.yml から生成する CSS の
#                       分け方を変えたときに、後の版のコードで生成したものを渡す）
#   終了コード: 0 = 差が無い / 1 = 差がある / 2 = 比べられない
#
# 前提:
#   book-settings.css・book-fonts.css・theme-images/ は、HTML を組んだ写しの本の .cache/vs/ のものを
#   前後の両方に使う（book.yml から生成する規則は比べる対象ではないため）。
#   Kindle の HTML には、ビルドと同じく Css::LiteralResolver でリテラル化した CSS を当てる（その版に
#   LiteralResolver があるときだけ。S3-3 より前の版は var() のまま当てる）。
#   Chromium は ~/.cache/puppeteer/chrome/ の最も新しい版を使う（環境変数 VS_CHROME で指定できる）。
#   Chromium は text-spacing・margin-break・string-set など Vivliostyle だけのプロパティを計算しない。
#   これらは計算値に出ないので、CSS の文字列で別に確かめる（v2-migration-plan.md §8.5）。
# ================================================================

require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
STYLES_SCRIPT = File.join(ROOT, 'scripts', 'css_computed_styles.mjs')
PUPPETEER = File.join(ROOT, 'node_modules', 'puppeteer-core', 'lib', 'puppeteer', 'puppeteer-core.js')

# body のクラスと入口の名前が違うもの。どれにも当たらない HTML は章の入口で組む
BODY_KIND_ALIASES = { 'index-page' => 'index', 'glossary-page' => 'glossary' }.freeze
# --as で外すクラス（章・付録だけに付き、ほかのページの種類に付け替えると意味が変わるもの）
CHAPTER_ONLY_CLASSES = %w[chapter appendix chapter-first vs-header-image vs-header-simple].freeze
# 位置と箱の大きさ。組みの結果として変わるので、--ignore-layout で外す
LAYOUT_PROPERTIES = %w[width height inline-size block-size top left right bottom inset-block-start
                       inset-block-end inset-inline-start inset-inline-end perspective-origin
                       transform-origin grid-template-rows grid-template-columns].freeze

# 比べる組 1 つ。flavor は pdf・epub・kindle、form は layered（層ありの入口）か flat（平らな CSS）
Pair = Data.define(:html, :base, :flavor, :name, :kind, :form, :media)

# --- CSS を用意する -------------------------------------------------------------

# git のリビジョンを一時のディレクトリへ取り出す（css_cascade_diff.rb と同じ）
def checkout(rev, into)
  archive, status = Open3.capture2('git', '-C', ROOT, 'archive', rev, 'lib', 'stylesheets', 'config',
                                   binmode: true)
  abort("git archive に失敗しました: #{rev}") unless status.success?
  _, err, status = Open3.capture3('tar', '-x', '-C', into, stdin_data: archive, binmode: true)
  abort("取り出しに失敗しました: #{err}") unless status.success?
end

# リポジトリ（source）の EntryWriter と Flattener で、全種類の入口と平らな CSS を workspace に書く。
# 別のプロセスで描くのは、前と後でコード（IMPORTS・Flattener）が違うためである。
# workspace の .cache/vs/ と stylesheets/ の並びは本と同じにし、入口の相対パスがそのまま解けるようにする
# settings は book-settings*.css の置き場（既定は book_cache。--after-settings で後の側だけ差し替える）
# kindle_htmls は Kindle の HTML。source に Css::LiteralResolver があれば、Kindle の束をビルドと同じく
# リテラル化する（変数の表の範囲は Css::Bundle.kindle_scope で、その種類の HTML から作る）
def prepare_css(source, workspace, book_cache, kindle_htmls, settings = book_cache)
  cache = File.join(workspace, '.cache', 'vs')
  FileUtils.mkdir_p([cache, File.join(workspace, 'flat')])
  File.symlink(File.join(source, 'stylesheets'), File.join(workspace, 'stylesheets'))
  %w[book-settings.css book-fonts.css book-settings-kindle.css].each do
    FileUtils.cp(File.join(settings, it), cache) if File.file?(File.join(settings, it))
  end
  theme_images = File.join(book_cache, 'theme-images')
  File.symlink(theme_images, File.join(cache, 'theme-images')) if File.directory?(theme_images)

  script = <<~RUBY
    w = VivlioStarter::CLI::Css::EntryWriter
    f = VivlioStarter::CLI::Css::Flattener
    workspace = ARGV.fetch(0)
    kindle_htmls = JSON.parse(ARGV.fetch(1))
    literal = File.file?('lib/vivlio_starter/cli/css/literal_resolver.rb')
    require 'vivlio_starter/cli/css/bundle' if literal
    aliases = { 'index-page' => 'index', 'glossary-page' => 'glossary' }
    kind_of = lambda do |html|
      classes = File.read(html)[/<body\b[^>]*\bclass="([^"]*)"/, 1].to_s.split.map { aliases.fetch(it, it) }
      classes.find { w::IMPORTS.key?(it) } || 'chapter'
    end
    rebase = ->(abs) { "file://\#{abs}" }
    w::IMPORTS.each_key do |kind|
      entry = File.join(workspace, '.cache', 'vs', "entry-\#{kind}.css")
      File.write(entry, w.render(kind))
      # EPUB と Kindle は、出力先の target 層を足した入口から平らにする（Css::Bundle と同じ）
      { 'pdf' => nil, 'epub' => :epub, 'kindle' => :kindle }.each do |flavor, target|
        pieces = f.pieces(entry, rebase:, css: w.render(kind, target:))
        if literal && target == :kindle
          scope = VivlioStarter::CLI::Css::Bundle.kindle_scope(kindle_htmls.select { kind_of.call(it) == kind })
          pieces = VivlioStarter::CLI::Css::LiteralResolver.resolve(pieces.reject(&:nested), scope:).pieces
        end
        css = f.render(pieces)
        File.write(File.join(workspace, 'flat', "\#{flavor}-\#{kind}.css"), css)
      end
    end
  RUBY
  _, err, status = Open3.capture3('ruby', '-Ilib', '-rjson', '-rvivlio_starter/cli/css/entry_writer',
                                  '-rvivlio_starter/cli/css/flattener', '-e', script, workspace,
                                  JSON.generate(kindle_htmls), chdir: source)
  abort("CSS を用意できません（#{source}）: #{err}") unless status.success?
end

def css_path(workspace, pair)
  if pair.form == 'layered'
    File.join(workspace, '.cache', 'vs', "entry-#{pair.kind}.css")
  else
    File.join(workspace, 'flat', "#{pair.flavor}-#{pair.kind}.css")
  end
end

# --- 比べる組を作る -------------------------------------------------------------

def html_files(paths)
  paths.flat_map do |path|
    File.directory?(path) ? Dir[File.join(path, '*.html')].sort : [path]
  end.map { File.expand_path(it) }
end

# 写しの本の .cache/vs/（HTML の置き場から上へたどる）
def book_cache_of(html)
  dir = File.dirname(html)
  dir = File.dirname(dir) until File.basename(dir) == 'build' || dir == '/'
  abort("写しの本の .cache/vs/build/ の下の HTML ではありません: #{html}") if dir == '/'
  File.dirname(dir)
end

def body_kind(classes, kinds)
  classes.map { BODY_KIND_ALIASES.fetch(it, it) }.find { kinds.include?(it) } || 'chapter'
end

# --as で body の種類のクラスを付け替えた HTML を書き、そのパスを返す
def retarget_html(html, kind, into)
  source = File.read(html, encoding: 'utf-8')
  updated = source.sub(/<body class="([^"]*)"/) do
    classes = Regexp.last_match(1).split - CHAPTER_ONLY_CLASSES
    %(<body class="#{[kind, *classes].join(' ')}")
  end
  path = File.join(into, File.basename(File.dirname(html)), File.basename(html))
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, updated)
  path
end

def build_pairs(htmls, options, kinds, tmp)
  htmls.flat_map do |html|
    flavor = File.basename(File.dirname(html))
    page = options[:as] ? retarget_html(html, options[:as], File.join(tmp, 'as')) : html
    kind = body_kind(File.read(page, encoding: 'utf-8')[/<body class="([^"]*)"/, 1].to_s.split, kinds)
    forms = flavor == 'pdf' ? options[:pdf_forms] : %w[flat]
    forms.product(options[:media]).map do |form, media|
      Pair.new(html: page, base: File.dirname(html), flavor:, name: File.basename(html, '.html'),
               kind:, form:, media:)
    end
  end
end

# --- 計算値を取る -------------------------------------------------------------

def chrome_path
  return ENV['VS_CHROME'] if ENV['VS_CHROME']

  candidates = Dir[File.join(Dir.home, '.cache', 'puppeteer', 'chrome', '*', '**', 'Google Chrome for Testing')]
               .select { File.file?(it) && File.executable?(it) }
  newest = candidates.max_by { Gem::Version.new(it[%r{chrome/[^/-]+-([\d.]+)/}, 1] || '0') }
  newest or abort('Chromium が見つかりません（~/.cache/puppeteer/chrome/）。VS_CHROME で指定してください')
end

# 前後の全部の組を 1 回の Chromium の起動で組み、JSON を書き出す
def capture(pairs, workspaces, tmp)
  jobs = pairs.each_with_index.flat_map do |pair, index|
    workspaces.map do |side, workspace|
      { html: pair.html, base: pair.base, css: css_path(workspace, pair), inline: pair.form == 'flat',
        media: pair.media, out: File.join(tmp, 'styles', "#{index}-#{side}.json") }
    end
  end
  FileUtils.mkdir_p(File.join(tmp, 'styles'))
  spec = File.join(tmp, 'jobs.json')
  File.write(spec, JSON.generate({ chrome: chrome_path, puppeteer: PUPPETEER, jobs: }))
  _, err, status = Open3.capture3('node', STYLES_SCRIPT, spec)
  abort("Chromium で組めません: #{err}") unless status.success?
end

# --- 比べる -------------------------------------------------------------

# 前と後で CSS の置き場が違うので、url() の中の置き場の部分をそろえる
def normalize(value, workspace) = value.to_s.gsub("file://#{workspace}/", 'WORKSPACE/')

# @return [Array(Integer, Integer, Array)] 違う要素の数・要素の数・違い（要素・プロパティ・前・後）の列
def compare(before_file, after_file, workspaces, ignore_layout)
  before = JSON.parse(File.read(before_file))
  after = JSON.parse(File.read(after_file))
  return [nil, before.size, []] unless before.size == after.size

  differences = []
  changed = 0
  before.zip(after).each do |x, y|
    props = (x['vals'].keys | y['vals'].keys).reject do |prop|
      normalize(x['vals'][prop], workspaces[:before]) == normalize(y['vals'][prop], workspaces[:after])
    end
    props -= LAYOUT_PROPERTIES if ignore_layout
    next if props.empty?

    changed += 1
    props.each { differences << [x['d'].split(' > ').last, it, x['vals'][it].to_s, y['vals'][it].to_s] }
  end
  [changed, before.size, differences]
end

# --- 実行 -------------------------------------------------------------

options = { before: 'HEAD', after: ROOT, media: %w[screen print], pdf_forms: %w[layered flat],
            as: nil, ignore_layout: false, top: 80 }
OptionParser.new do |opts|
  opts.on('--before REV') { options[:before] = it }
  opts.on('--after DIR') { options[:after] = File.expand_path(it) }
  opts.on('--media LIST') { options[:media] = it.split(',') }
  opts.on('--pdf-forms LIST') { options[:pdf_forms] = it.split(',') }
  opts.on('--as KIND') { options[:as] = it }
  opts.on('--ignore-layout') { options[:ignore_layout] = true }
  opts.on('--top N', Integer) { options[:top] = it }
  opts.on('--after-settings DIR') { options[:after_settings] = File.expand_path(it) }
end.parse!
htmls = html_files(ARGV)
if htmls.empty?
  warn '比べる HTML を指定してください（写しの本の .cache/vs/build/ の下）'
  exit 2
end

book_caches = htmls.map { book_cache_of(it) }.uniq
abort("HTML は 1 冊の写しの本のものにしてください: #{book_caches.join(', ')}") if book_caches.size > 1

found = false
Dir.mktmpdir('css-computed-diff') do |tmp|
  # --- Phase: 前後の CSS を用意する ---
  source = File.join(tmp, 'before-source')
  FileUtils.mkdir_p(source)
  checkout(options[:before], source)
  workspaces = { before: File.join(tmp, 'before'), after: File.join(tmp, 'after') }
  kindle_htmls = htmls.select { File.basename(File.dirname(it)) == 'kindle' }
  prepare_css(source, workspaces[:before], book_caches.first, kindle_htmls)
  prepare_css(options[:after], workspaces[:after], book_caches.first, kindle_htmls,
              options[:after_settings] || book_caches.first)
  # flat/ のファイルは「出力先-種類.css」。種類の名前は pdf の分から取る
  kinds = Dir[File.join(workspaces[:after], 'flat', 'pdf-*.css')].map { File.basename(it, '.css').delete_prefix('pdf-') }

  # --- Phase: 組んで計算値を取る ---
  pairs = build_pairs(htmls, options, kinds, tmp)
  capture(pairs, workspaces, tmp)

  # --- Phase: 比べて数える ---
  counts = Hash.new { |hash, key| hash[key] = [0, []] }
  pairs.each_with_index do |pair, index|
    files = %w[before after].map { File.join(tmp, 'styles', "#{index}-#{it}.json") }
    changed, total, differences = compare(*files, workspaces, options[:ignore_layout])
    label = "#{pair.flavor}/#{pair.name}（#{pair.kind}・#{pair.form}・#{pair.media}）"
    if changed.nil?
      puts "#{label}: 要素の数が前後で違うので比べられません"
      found = true
      next
    end
    next if changed.zero?

    found = true
    puts format('%-64s 違う要素 %5d / %d', label, changed, total)
    differences.each do |element, prop, before, after|
      entry = counts[[pair.flavor, element, prop, before[0, 40], after[0, 40]]]
      entry[0] += 1
      entry[1] << pair.name unless entry[1].include?(pair.name)
    end
  end

  puts "#{pairs.size} 組（#{htmls.size} 文書）を比べました。#{'違いはありません。' unless found}"
  unless counts.empty?
    puts "\n## 違い（出力先・要素・プロパティ・前 → 後・数・文書）"
    counts.sort_by { |key, (count, _)| [-count, key] }.first(options[:top]).each do |(flavor, element, prop, before, after), (count, names)|
      puts format('%5d %-7s %-40s %-26s %s → %s  [%s]', count, flavor, element[0, 40], prop, before, after,
                  names.first(3).join(' '))
    end
    puts "（ほか #{counts.size - options[:top]} 行）" if counts.size > options[:top]
  end
end

exit(found ? 1 : 0)
