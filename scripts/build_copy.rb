# frozen_string_literal: true

# ================================================================
# scripts/build_copy.rb — 本を写して組む（確かめのビルド）
# ================================================================
# 使い方:
#   ruby scripts/build_copy.rb --out DIR [オプション] [-- vs build に渡す引数]
#
#   --out DIR            写しを置くディレクトリ（既にあれば --force が要る）
#   --force              --out が既にあれば消してから写す
#   --book DIR           写す本（既定: このリポジトリ）
#   --vs DIR             bin/vs を走らせるリポジトリ（既定: このリポジトリ）
#   --targets LIST       output.targets を上書きする（例: pdf,epub）
#   --set KEY=VALUE      book.yml の値を上書きする（KEY は theme.style のような点の区切り。
#                        VALUE は YAML として読む。何度でも書ける）
#   --no-clean           vs build に --no-clean を渡す（Kindle 用の EPUB などを残す）
#   --collect DIR        組み上がった出力（PDF・EPUB・KPF・Kindle 用の EPUB・記録）を写す先
#   --kindle-record      Kindle 用の EPUB を Kindle Previewer でもう一度変換し、変換の記録と
#                        中間生成物（preprocessed/*.xhtml）を --collect の kindle-record/ に残す
#                        （--no-clean と --collect が要る）
#
# 例:
#   ruby scripts/build_copy.rb --out /tmp/b2 --targets pdf --set theme.style=simple
#   ruby scripts/build_copy.rb --out /tmp/b4 --book ../book_x --targets pdf,epub -- upper
#
# 確かめのビルドを、リポジトリの中ではなく本を複製したディレクトリで行う
# （`v2-migration-plan.md` §3.1）。リポジトリの中で組むと、ビルドの生成物と作業中の変更が
# 混ざり、比べる相手が汚れる。
#
# 写しで走らせても、ユーザーの画面には効く。vs build の最後はプレビューのウィンドウを
# 閉じて PDF を開くので、次の二つで止める。
#   1. book.yml の output.pdf_preview.close_existing_windows を false にする
#   2. 何もしない open と osascript を PATH の先頭に置く（vs build に開かない指定は無い）
# 開発機は 1 分でスリープするので、vs build は caffeinate -i の下で走らせる。
# ================================================================

require 'date'
require 'fileutils'
require 'open3'
require 'optparse'
require 'yaml'

ROOT = File.expand_path('..', __dir__)

# 本の素材。ここに無いもの（.cache/・出力・Gemfile など）は写さない。
# 生成物のキャッシュも写さないのは、毎回まっさらから組んで、前のビルドの残りに左右されない
# ようにするためである。
MATERIALS = %w[config contents stylesheets themes images covers codes data templates sources package.json].freeze

# 組み上がった出力として拾うもの（写しの直下）。
OUTPUT_GLOBS = %w[*.pdf *.epub *.kpf *_frontcover*.jpg].freeze

options = { book: ROOT, vs: ROOT, sets: [], clean: true, force: false, kindle_record: false }
parser = OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/build_copy.rb --out DIR [options] [-- vs build args]'
  o.on('--out DIR') { options[:out] = File.expand_path(it) }
  o.on('--force') { options[:force] = true }
  o.on('--book DIR') { options[:book] = File.expand_path(it) }
  o.on('--vs DIR') { options[:vs] = File.expand_path(it) }
  o.on('--targets LIST') { options[:sets] << ['output.targets', it.split(',').map(&:strip).join(', ')] }
  o.on('--set KEY=VALUE') do |pair|
    key, value = pair.split('=', 2)
    abort "--set は KEY=VALUE の形で書いてください: #{pair}" if value.nil?
    options[:sets] << [key, YAML.safe_load(value, permitted_classes: [Date])]
  end
  o.on('--no-clean') { options[:clean] = false }
  o.on('--collect DIR') { options[:collect] = File.expand_path(it) }
  o.on('--kindle-record') { options[:kindle_record] = true }
end
build_args = parser.parse(ARGV)

abort parser.banner unless options[:out]
abort "本が見つかりません: #{options[:book]}" unless File.exist?(File.join(options[:book], 'config', 'book.yml'))
abort "bin/vs が見つかりません: #{options[:vs]}" unless File.exist?(File.join(options[:vs], 'bin', 'vs'))
if options[:kindle_record] && (options[:clean] || options[:collect].nil?)
  abort '--kindle-record には --no-clean と --collect が要ります'
end

# --- Phase: 写す ---------------------------------------------------------------

out = options[:out]
if File.exist?(out)
  abort "既にあります（消してよければ --force）: #{out}" unless options[:force]
  FileUtils.rm_rf(out)
end
FileUtils.mkdir_p(out)

MATERIALS.each do |name|
  src = File.join(options[:book], name)
  FileUtils.cp_r(src, out) if File.exist?(src)
end

# このリポジトリ（本書）は、ルートの images/ を git で追跡しない（.git/info/exclude）。
# 追跡しているのは雛形の写し lib/project_scaffold/images/ だけで、中身は同じである。
# git archive で取り出した基準のコミットや、images/ を持たない作業ツリーから組むときは、
# 雛形の写しを使う。
scaffold_images = File.join(options[:book], 'lib', 'project_scaffold', 'images')
if !File.exist?(File.join(options[:book], 'images')) && File.directory?(scaffold_images)
  FileUtils.cp_r(scaffold_images, out)
  puts '[build_copy] images/ が無いため、lib/project_scaffold/images/ を写しました'
end

# node_modules は大きいので写さずリンクで済ませる。本に無ければ、bin/vs のリポジトリのものを使う
# （git archive で取り出した基準のコミットには node_modules が無い）。
node_modules = [options[:book], options[:vs], ROOT].map { File.join(it, 'node_modules') }.find { File.directory?(it) }
abort 'node_modules が見つかりません（npm install してください）' unless node_modules
File.symlink(node_modules, File.join(out, 'node_modules'))

# --- Phase: book.yml に上書きを当てる ----------------------------------------------

# 点の区切りの鍵を、入れ子のハッシュへ書き込む。途中の節が無ければ作る。
def assign(hash, dotted, value)
  *parents, leaf = dotted.split('.')
  node = parents.reduce(hash) { |h, key| h[key] ||= {} }
  node[leaf] = value
end

book_yml = File.join(out, 'config', 'book.yml')
config = YAML.safe_load_file(book_yml, permitted_classes: [Date, Time], aliases: true)
assign(config, 'output.pdf_preview.close_existing_windows', false)
options[:sets].each { |key, value| assign(config, key, value) }
File.write(book_yml, YAML.dump(config))

# --- Phase: 組む -----------------------------------------------------------------

stub_bin = File.join(out, '.stub-bin')
FileUtils.mkdir_p(stub_bin)
%w[open osascript].each do |name|
  path = File.join(stub_bin, name)
  File.write(path, "#!/bin/sh\nexit 0\n")
  File.chmod(0o755, path)
end

env = { 'PATH' => "#{stub_bin}:#{ENV.fetch('PATH')}" }
command = ['caffeinate', '-i', RbConfig.ruby, File.join(options[:vs], 'bin', 'vs'), 'build',
           *('--no-clean' unless options[:clean]), *build_args]
puts "[build_copy] #{options[:book]} を #{out} へ写し、#{options[:vs]} の bin/vs で組みます"
puts "[build_copy] 上書き: #{options[:sets].map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}" unless options[:sets].empty?

started = Time.now
status = File.open(File.join(out, 'build.log'), 'w') do |log|
  Open3.popen2e(env, *command, chdir: out) do |_stdin, output, wait|
    output.each_line do |line|
      $stdout.print line
      log.print line
    end
    wait.value
  end
end
elapsed = (Time.now - started).round(1)
puts "[build_copy] vs build の終了コード: #{status.exitstatus}（#{elapsed} 秒）"

# --- Phase: 出力を拾う --------------------------------------------------------------

# Kindle 用の EPUB（…-kindle.epub）は、--no-clean のとき出力と同じ直下に残る。
outputs = OUTPUT_GLOBS.flat_map { Dir.glob(File.join(out, it)) }.sort
kindle_epub = outputs.find { it.end_with?('-kindle.epub') }
puts '[build_copy] 出力:'
outputs.each { puts "  #{it}" }

if options[:collect]
  FileUtils.mkdir_p(options[:collect])
  outputs.each { FileUtils.cp(it, options[:collect]) }
  FileUtils.cp(File.join(out, 'build.log'), options[:collect])
  FileUtils.cp(book_yml, File.join(options[:collect], 'book.yml'))
end

# --- Phase: Kindle の変換の記録を残す --------------------------------------------------

# vs build は KPF への変換を一時のディレクトリで行い、記録を消す。比べるには、変換の記録
# （Summary_Log.csv・Logs/*.csv）と中間生成物（computedstyle の書かれた preprocessed/*.xhtml）が
# 要るので、残した Kindle 用の EPUB をもう一度変換する。入力も道具も同じなので、結果は
# vs build の中の変換と同じになる。読み方は `kindle-css-compatibility-notes.md` §2.1。
#
# Previewer は終了の時に作業のディレクトリを消すので、走っている間に写し取る（scripts/kfx_probe.rb と同じ）。
def harvest(stem, snap)
  Dir.glob("/var/folders/*/*/T/kpr_cli_#{stem}*/**/*").each do |src|
    next unless File.file?(src) && %w[.xhtml .html .css .json .csv].include?(File.extname(src))

    dest = File.join(snap, src.sub(%r{\A.*/kpr_cli_[^/]+/}, ''))
    next if File.exist?(dest)

    FileUtils.mkdir_p(File.dirname(dest))
    begin
      FileUtils.cp(src, dest)
    rescue StandardError
      next # 写す途中で Previewer が消したもの
    end
  end
end

if options[:kindle_record]
  abort '[build_copy] Kindle 用の EPUB が見つかりません（targets に kindle がありますか）' unless kindle_epub

  record = File.join(options[:collect], 'kindle-record')
  conversion = File.join(record, 'conversion')
  snap = File.join(record, 'intermediate')
  FileUtils.mkdir_p([conversion, snap])
  puts "[build_copy] Kindle 用の EPUB をもう一度変換し、記録を #{record} に残します"
  pid = spawn('caffeinate', '-i', 'kindlepreviewer', kindle_epub, '--convert', '--output', conversion,
              '--locale', 'ja', out: File.join(record, 'run.log'), err: %i[child out])
  stem = File.basename(kindle_epub, '.epub')
  loop do
    break unless Process.wait(pid, Process::WNOHANG).nil?

    harvest(stem, snap)
    sleep 0.5
  end
  harvest(stem, snap)
  count = Dir.glob(File.join(snap, '**', 'preprocessed', '*.xhtml')).size
  puts "[build_copy] 中間生成物 preprocessed/*.xhtml: #{count} 件"
end

exit status.exitstatus || 1
