# frozen_string_literal: true

# ================================================================
# scripts/epub_diff.rb — 二つの EPUB の中身を比べる
# ================================================================
# 使い方:
#   ruby scripts/epub_diff.rb <基準の EPUB> <新しい EPUB> [--full] [--epubcheck]
#
#   --full       テキストの差を全部出す（既定は 1 ファイルにつき 40 行まで）
#   --epubcheck  新しい EPUB に EPUBCheck を掛け、エラー・警告の数を出す（0 でなければ 1 で終わる）
#
# 終了コード: 0 = 違いが「無視する差」だけ / 1 = 違いがある / 2 = 比べられなかった
#
# 展開して、ファイルの一覧の差と、テキストのファイルの差を出す。画像と書体はハッシュで比べる
# （`v2-migration-plan.md` §3.4）。
#
# ビルドのたびに変わる値は、IGNORED の表に書いて比べる前に伏せる。表に無い差は全部数える。
# 段階ごとに許す差（S1 の role 属性など）はここに書かない。それは仕様書の完了の条件が決め、
# 報告された差を人が読んで判断する。
# ================================================================

require 'digest'
require 'fileutils'
require 'open3'
require 'optparse'
require 'tmpdir'

# テキストとして行の差を出すファイル。これ以外はハッシュで比べる。
TEXT_EXTENSIONS = %w[.xhtml .html .css .opf .ncx .xml .svg .js .txt].freeze

# ビルドのたびに変わる値。[当てるファイル（正規表現）, 伏せる箇所（正規表現）, 理由]。
# 同じコミットで二度組んで見つかった差だけを足す。
IGNORED = [
  [/\.opf\z/, %r{(<meta property="dcterms:modified">)[^<]*(</meta>)}, 'OPF の更新の日時'],
].freeze

options = { full: false, epubcheck: false }
parser = OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/epub_diff.rb <base.epub> <new.epub> [--full] [--epubcheck]'
  o.on('--full') { options[:full] = true }
  o.on('--epubcheck') { options[:epubcheck] = true }
end
base_epub, new_epub = parser.parse(ARGV)
abort parser.banner unless base_epub && new_epub

[base_epub, new_epub].each do |epub|
  next if File.file?(epub)

  warn "EPUB が見つかりません: #{epub}"
  exit 2
end

def extract(epub, dir)
  _out, err, status = Open3.capture3('unzip', '-q', '-o', epub, '-d', dir)
  return if status.success?

  warn "展開に失敗しました: #{epub}\n#{err}"
  exit 2
end

# 展開したディレクトリの中のファイルを、相対パスの並びで返す。
def entries(dir) = Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).select { File.file?(File.join(dir, it)) }.sort

# 生成した画像の名前（images/_epub_assets/<16 桁>.jpg など）は、元の画像の絶対パスと更新日時から
# 作られる（EpubBuilder）。写しのディレクトリが違えば、中身が同じでも名前が変わる。
# そこで、名前を中身のハッシュに置き換えてから比べる。中身が変われば名前も変わるので、
# 画像の違いは「なくなった・増えた」として数えられる。
GENERATED_ASSET = %r{/_epub_assets/[^/]+\z}

# 生成した画像の、元の名前の幹（拡張子を除いた部分）→ 中身のハッシュの幹、の表を返す。
# 幹で置き換えるのは、OPF の id（images_epub_assets<幹>svg）にも同じ幹が入るためである。
def asset_renames(dir, files)
  files.grep(GENERATED_ASSET).to_h do |relative|
    digest = Digest::SHA256.file(File.join(dir, relative)).hexdigest[0, 16]
    [File.basename(relative, '.*'), "content-#{digest}"]
  end
end

def rename_path(relative, renames)
  return relative unless relative.match?(GENERATED_ASSET)

  stem = File.basename(relative, '.*')
  File.join(File.dirname(relative), "#{renames.fetch(stem)}#{File.extname(relative)}")
end

# OPF の manifest は名前の順に並ぶので、名前を置き換えると順が崩れる。
# manifest の item の順は意味を持たない（読む順は spine が決める）ので、続いた item の行を並べ直す。
def sort_manifest_items(text)
  text.lines.chunk_while { |a, b| a.match?(/\A\s*<item\s/) && b.match?(/\A\s*<item\s/) }
      .flat_map { |chunk| chunk.first.match?(/\A\s*<item\s/) ? chunk.sort : chunk }.join
end

# 比べる前に、IGNORED の箇所を伏せ、生成した画像の名前を置き換えた中身を返す。
def masked(path, relative, renames)
  text = File.read(path, encoding: 'utf-8')
  IGNORED.each do |file_pattern, value_pattern, _reason|
    next unless relative.match?(file_pattern)

    text = text.gsub(value_pattern) { "#{::Regexp.last_match(1)}<IGNORED>#{::Regexp.last_match(2)}" }
  end
  text = text.gsub(Regexp.union(renames.keys), renames) unless renames.empty?
  relative.end_with?('.opf') ? sort_manifest_items(text) : text
end

exit_code = 0
Dir.mktmpdir('epub-diff') do |work|
  # --- Phase: 展開する ---
  base_dir = File.join(work, 'base')
  new_dir = File.join(work, 'new')
  extract(base_epub, base_dir)
  extract(new_epub, new_dir)
  base_renames = asset_renames(base_dir, entries(base_dir))
  new_renames = asset_renames(new_dir, entries(new_dir))
  # 比べる名前 → 展開した場所の実際の相対パス
  base_index = entries(base_dir).to_h { [rename_path(it, base_renames), it] }
  new_index = entries(new_dir).to_h { [rename_path(it, new_renames), it] }
  base_files = base_index.keys.sort
  new_files = new_index.keys.sort

  # --- Phase: ファイルの一覧を比べる ---
  removed = base_files - new_files
  added = new_files - base_files

  # --- Phase: 中身を比べる ---
  text_diffs = {}
  binary_diffs = []
  (base_files & new_files).each do |relative|
    base_path = File.join(base_dir, base_index.fetch(relative))
    new_path = File.join(new_dir, new_index.fetch(relative))
    if TEXT_EXTENSIONS.include?(File.extname(relative).downcase)
      base_text = masked(base_path, relative, base_renames)
      new_text = masked(new_path, relative, new_renames)
      next if base_text == new_text

      a = File.join(work, 'a.txt')
      b = File.join(work, 'b.txt')
      File.write(a, base_text)
      File.write(b, new_text)
      diff, = Open3.capture2('diff', '-u', '--label', "base/#{relative}", '--label', "new/#{relative}", a, b)
      text_diffs[relative] = diff
    elsif Digest::SHA256.file(base_path) != Digest::SHA256.file(new_path)
      binary_diffs << relative
    end
  end

  # --- Phase: 報告する ---
  puts "基準:   #{base_epub}（#{base_files.size} ファイル）"
  puts "新しい: #{new_epub}（#{new_files.size} ファイル）"
  puts "無視する差: #{IGNORED.map(&:last).join('・')}"
  total = removed.size + added.size + text_diffs.size + binary_diffs.size
  puts "違い: #{total} 件（なくなった #{removed.size}・増えた #{added.size}・" \
       "テキストが違う #{text_diffs.size}・画像などが違う #{binary_diffs.size}）"
  removed.each { puts "  - #{it}" }
  added.each { puts "  + #{it}" }
  binary_diffs.each { puts "  ≠ #{it}（ハッシュが違う）" }
  text_diffs.each do |relative, diff|
    lines = diff.lines
    puts "  ≠ #{relative}（#{lines.count { it.start_with?('+', '-') && !it.start_with?('+++', '---') }} 行）"
    shown = options[:full] ? lines : lines.first(40)
    shown.each { print "    #{it}" }
    puts "    …（残り #{lines.size - shown.size} 行。全部は --full）" if shown.size < lines.size
  end
  exit_code = 1 unless total.zero?
end

if options[:epubcheck]
  out, = Open3.capture2e('epubcheck', new_epub)
  # EPUBCheck は OS の言語で書く。英語と日本語の両方の要約の行を読む。
  summary = out.match(%r{(\d+) fatals? / (\d+) errors? / (\d+) warnings?}) ||
            out.match(%r{(\d+) 件の致命的エラー / (\d+) 件のエラー / (\d+) 件の警告})
  if summary
    fatals, errs, warns = summary.captures.map(&:to_i)
    puts "EPUBCheck: 致命 #{fatals}・エラー #{errs}・警告 #{warns}"
    exit_code = 1 unless (fatals + errs + warns).zero?
  else
    puts "EPUBCheck の結果を読めませんでした:\n#{out}"
    exit_code = 2
  end
end

exit exit_code
