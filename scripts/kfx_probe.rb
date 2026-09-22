# frozen_string_literal: true

# ================================================================
# scripts/kfx_probe.rb — Kindle(KFX) が何を解するかを実測する
# ================================================================
# 使い方:
#   ruby scripts/kfx_probe.rb                 # 既定の一式を測る
#   ruby scripts/kfx_probe.rb var,calc,before # 機能を選んで測る
#   ruby scripts/kfx_probe.rb --list          # 測れる機能を並べる
#   ruby scripts/kfx_probe.rb --keep var      # KPF を消さずに残す（画面で見る用）
#
# Kindle Previewer の版が上がったら、これを回して
# `kindle-css-compatibility-notes.md` §2 の表を測り直す。
#
# 観測できるのは 3 つだけである（CLI は描画結果を書き出せない）。
#   1. Enhanced Typesetting の判定（Supported なら .kpf、でなければ .mobi）
#   2. 変換ログのコード（W14012 など）
#   3. 変換の中間生成物。KFXGen は解決した CSS を style と computedstyle として
#      要素へ書き戻すので、何が残り何が落ちたかが読める
#
# **中間生成物だけで判断しないこと。** 前処理は Chromium でページを組むため、
# calc() は正しく計算され linear-gradient() も残る。それでも描画側は両方捨てる
# （実測 2026-09-23）。最終判定は Previewer の画面で行う。--keep で KPF を残せる。
# ================================================================

require 'csv'
require 'fileutils'
require 'securerandom'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)

# 測る機能。key は指定に使う名前、値は [CSS, 本文 HTML, 判定の当て先]。
# 判定の当て先は [クラス名, 通っていれば現れる正規表現]。nil なら目視のみ。
FEATURES = {
  'var' => [
    '.t-var { color: var(--brand); }',
    '<p class="t-var">VAR-PROBE カスタムプロパティ</p>',
    ['t-var', /color:\s*rgb\(194,\s*24,\s*91\)/]
  ],
  'calc' => [
    '.t-calc { padding-left: calc(2mm + 2mm); }',
    '<p class="t-calc">CALC-PROBE 計算値</p>',
    ['t-calc', /padding-left:15\./]
  ],
  'clamp' => [
    '.t-clamp { font-size: clamp(0.9em, 1.2em, 1.5em); }',
    '<p class="t-clamp">CLAMP-PROBE 可変寸法</p>',
    ['t-clamp', /font-size:19/]
  ],
  'is' => [
    ':is(.t-is-a, .t-is-b) { border: 1px solid #0a7d3c; }',
    '<p class="t-is-a">IS-PROBE セレクタ関数</p>',
    ['t-is-a', /border/]
  ],
  'grid' => [
    '.t-grid { display: grid; grid-template-columns: 1fr 1fr; }',
    '<div class="t-grid"><span>GRID-PROBE 左</span><span>右</span></div>',
    ['t-grid', /display:\s*grid/]
  ],
  'flex' => [
    '.t-flex { display: flex; gap: 2mm; }',
    '<div class="t-flex"><span>FLEX-PROBE 左</span><span>右</span></div>',
    ['t-flex', /display:\s*flex/]
  ],
  'gradient' => [
    '.t-gradient { background: linear-gradient(90deg, #ffffff, #cccccc); }',
    '<p class="t-gradient">GRADIENT-PROBE 背景</p>',
    ['t-gradient', /linear-gradient/]
  ],
  'colormix' => [
    '.t-colormix { background-color: color-mix(in srgb, #c2185b 20%, white); }',
    '<p class="t-colormix">COLORMIX-PROBE 混色</p>',
    ['t-colormix', /background-color/]
  ],
  'before' => [
    '.t-before::before { content: "【BEFORE-PROBE】"; color: #b00; }',
    '<p class="t-before">擬似要素のラベル</p>',
    nil
  ],
  # 本書の囲みボックスに近い形。ラベルを独立した行にできるかを見る
  'adm' => [
    '.t-adm { border: 1px solid #0a7d3c; background-color: #eef6f0; padding: 4mm; }' \
    '.t-adm::before { content: "【NOTICE】"; display: block; color: #0a7d3c; ' \
    'font-weight: bold; margin-bottom: 2mm; }',
    '<div class="t-adm"><p>ADM-PROBE 囲みボックスの本文です。</p></div>',
    nil
  ],
  # ラベルに背景と余白を持たせた場合。帯として描けるかを見る
  'admband' => [
    '.t-band { border: 1px solid #b26a00; padding: 4mm; }' \
    '.t-band::before { content: "【TIP】"; display: block; background-color: #b26a00; ' \
    'color: #ffffff; padding: 1mm 2mm; margin-bottom: 2mm; }',
    '<div class="t-band"><p>BAND-PROBE ラベルに背景色を付けた場合です。</p></div>',
    nil
  ],
  'webp' => [
    '.t-webp img { width: 40%; }',
    '<p class="t-webp">WEBP-PROBE <img src="probe.webp" alt="webp"/></p>',
    nil
  ],
  # WebP との対照。画像の中身ではなく形式が効くことを確かめる
  'jpeg' => [
    '.t-jpeg img { width: 40%; }',
    '<p class="t-jpeg">JPEG-PROBE <img src="probe.jpg" alt="jpeg"/></p>',
    nil
  ],
  'svg' => [
    '',
    '<p>SVG-PROBE <img src="probe.svg" alt="svg"/></p>',
    nil
  ],
  'mathml' => [
    '',
    '<p>MATHML-PROBE <math xmlns="http://www.w3.org/1998/Math/MathML">' \
    '<msup><mi>a</mi><mn>2</mn></msup><mo>+</mo><msup><mi>b</mi><mn>2</mn></msup></math></p>',
    nil
  ]
}.freeze

# 画像を使う機能は、ET の判定を巻き添えにする（WebP・SVG）。既定からは外す。
DEFAULT_FEATURES = (FEATURES.keys - %w[webp jpeg svg mathml adm admband]).freeze

SOURCE_IMAGE = File.join(ROOT, 'images/00-preface/logo.webp')

# --- Phase: 検査用 EPUB を組む ---------------------------------------------

def build_epub(dir, features)
  FileUtils.mkdir_p(File.join(dir, 'META-INF'))
  FileUtils.mkdir_p(File.join(dir, 'EPUB'))
  File.write(File.join(dir, 'mimetype'), 'application/epub+zip')
  File.write(File.join(dir, 'META-INF/container.xml'), <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="EPUB/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
  XML

  css = features.filter_map { FEATURES.fetch(_1)[0] }.reject(&:empty?).join("\n")
  File.write(File.join(dir, 'EPUB/style.css'), ":root { --brand: #c2185b; }\n#{css}\n")

  File.write(File.join(dir, 'EPUB/ch1.xhtml'), <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" lang="ja" xml:lang="ja">
      <head><title>調査</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
      <body>
      <h1>KFX 対応状況の調査</h1>
      #{features.map { FEATURES.fetch(_1)[1] }.join("\n  ")}
      </body>
    </html>
  XML

  File.write(File.join(dir, 'EPUB/nav.xhtml'), <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ja" xml:lang="ja">
      <head><title>目次</title></head>
      <body><nav epub:type="toc"><h1>目次</h1><ol><li><a href="ch1.xhtml">調査</a></li></ol></nav></body>
    </html>
  XML

  File.write(File.join(dir, 'EPUB/content.opf'), opf(dir, features))
end

def opf(dir, features)
  items = ['<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
           '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>',
           '<item id="css" href="style.css" media-type="text/css"/>']
  items.concat(image_items(dir, features))

  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">urn:uuid:#{SecureRandom.uuid}</dc:identifier>
        <dc:title>KFX 対応状況の調査</dc:title>
        <dc:language>ja</dc:language>
        <dc:creator>kfx_probe</dc:creator>
        <meta property="dcterms:modified">#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}</meta>
      </metadata>
      <manifest>
        #{items.join("\n    ")}
      </manifest>
      <spine><itemref idref="c1"/></spine>
    </package>
  XML
end

def image_items(dir, features)
  items = []
  if features.include?('webp')
    FileUtils.cp(SOURCE_IMAGE, File.join(dir, 'EPUB/probe.webp'))
    items << '<item id="w" href="probe.webp" media-type="image/webp"/>'
  end
  if features.include?('jpeg')
    system('magick', SOURCE_IMAGE, '-background', 'white', '-flatten',
           File.join(dir, 'EPUB/probe.jpg'), exception: true)
    items << '<item id="j" href="probe.jpg" media-type="image/jpeg"/>'
  end
  if features.include?('svg')
    File.write(File.join(dir, 'EPUB/probe.svg'),
               %(<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80">) +
               %(<rect width="80" height="80" fill="#4488cc"/></svg>))
    items << '<item id="s" href="probe.svg" media-type="image/svg+xml"/>'
  end
  items
end

def zip_epub(dir, epub)
  FileUtils.rm_f(epub)
  # mimetype は無圧縮で先頭に置く（EPUB の決まり）
  system('zip', '-q', '-X', '-0', epub, 'mimetype', chdir: dir, exception: true)
  system('zip', '-q', '-X', '-r', epub, 'META-INF', 'EPUB', chdir: dir, exception: true)
end

# --- Phase: 変換し、中間生成物を採取する -----------------------------------

# Previewer は終了時に作業ディレクトリを消すので、走行中に写し取る。
def convert(epub, out, snap)
  pid = spawn('kindlepreviewer', epub, '--convert', '--output', out, '--locale', 'ja',
              out: File.join(out, 'run.log'), err: %i[child out])
  loop do
    break unless Process.wait(pid, Process::WNOHANG).nil?

    harvest(File.basename(epub, '.epub'), snap)
    # 小さな検査本では前処理が 1 秒足らずで終わり、中間生成物が消えてしまう。
    # 取りこぼすと判定そのものができないので、短い間隔で見に行く。
    sleep 0.2
  end
  harvest(File.basename(epub, '.epub'), snap)
end

def harvest(stem, snap)
  Dir.glob("/var/folders/*/*/T/kpr_cli_#{stem}*/**/*").each do |src|
    next unless File.file?(src) && %w[.xhtml .html .css .json .csv].include?(File.extname(src))

    dest = File.join(snap, src.sub(%r{\A.*/kpr_cli_[^/]+/}, ''))
    next if File.exist?(dest)

    FileUtils.mkdir_p(File.dirname(dest))
    begin
      FileUtils.cp(src, dest)
    rescue StandardError
      next
    end
  end
end

# --- Phase: 判定する ---------------------------------------------------------

def report(out, snap, features)
  summary = File.join(out, 'Summary_Log.csv')
  row = File.exist?(summary) ? CSV.parse(File.read(summary).delete_prefix("﻿")).drop(1).first : nil
  puts "Enhanced Typesetting: #{row&.dig(1)}   変換: #{row&.dig(2)}"
  puts "出力: #{Dir.glob(File.join(out, '{KPF,Mobi}', '*')).map { File.basename(_1) }.join(', ')}"

  notices(out).each { puts "  #{_1}" }

  # Enhanced Typesetting が落ちると Mobi 経路へ回り、置き場が変わる。どちらも見る。
  file = Dir.glob(File.join(snap, '**/preprocessed/*.xhtml')).first ||
         Dir.glob(File.join(snap, '**/mobi-*/EPUB/*.xhtml')).first
  return puts '中間生成物を採取できませんでした（変換が速すぎた可能性があります）' unless file

  html = File.read(file, encoding: 'utf-8')
  puts
  puts '中間生成物での判定（**描画の保証ではない**。最終判定は Previewer の画面で）'
  features.each do |name|
    target = FEATURES.fetch(name)[2]
    next puts format('  %-10s 目視で確認（--keep で KPF を残せます）', name) unless target

    klass, pattern = target
    tag = html[/<[a-z]+[^>]*class="#{Regexp.escape(klass)}"[^>]*>/]
    puts format('  %-10s %s', name, tag&.match?(pattern) ? '通った' : '落ちた')
  end

  # span のタグを取ってから属性を抜く。`style` は `amzn-selector` より前に出るため、
  # 1 つの正規表現で順序を決め打ちにはできない。`\s` を要求するのは `computedstyle` 除け。
  injected = html.scan(/<span[^>]*amzn-selector="before"[^>]*>/).filter_map { _1[/\sstyle="([^"]*)"/, 1] }
  return if injected.empty?

  puts
  puts '::before に対して注入された span'
  injected.each { puts "  #{_1.strip}" }
end

def notices(out)
  Dir.glob(File.join(out, 'Logs', '*.csv')).flat_map do |csv|
    File.readlines(csv, encoding: 'utf-8').filter_map { _1[/(?:W|E)\d{5}[^"]*/] }
  end
end

# --- 実行 -------------------------------------------------------------------

args = ARGV.dup
if args.delete('--list')
  puts "測れる機能: #{FEATURES.keys.join(' / ')}"
  puts "既定: #{DEFAULT_FEATURES.join(' / ')}"
  exit 0
end
keep = !args.delete('--keep').nil?
features = args.first ? args.first.split(',') : DEFAULT_FEATURES

unknown = features - FEATURES.keys
abort "知らない機能です: #{unknown.join(', ')}（--list で一覧）" unless unknown.empty?
abort 'kindlepreviewer が見つかりません（vs doctor で確認してください）' unless system('which kindlepreviewer',
                                                                                 out: File::NULL, err: File::NULL)

Dir.mktmpdir('vs-kfx-probe') do |work|
  src  = File.join(work, 'src')
  epub = File.join(work, 'probe.epub')
  out  = File.join(work, 'out')
  snap = File.join(work, 'snap')
  [out, snap].each { FileUtils.mkdir_p(_1) }

  build_epub(src, features)
  zip_epub(src, epub)
  puts "検査: #{features.join(' / ')}"
  convert(epub, out, snap)
  report(out, snap, features)

  next unless keep

  kpf = Dir.glob(File.join(out, '{KPF,Mobi}', '*')).first
  next unless kpf

  dest = File.join(Dir.home, 'Desktop', File.basename(kpf))
  FileUtils.cp(kpf, dest)
  puts "\n画面で確かめる用に残しました: #{dest}"
end
