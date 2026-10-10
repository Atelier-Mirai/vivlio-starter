# frozen_string_literal: true

# vs pdf:read の紙面の推定（経路 B）を、直す前の版と今の作業ツリーで題材ごとに書き出して比べる
# （pdf-read-ocr-improvement-notes.md §6.8）。
#
#   ruby scripts/pdf_read_regress.rb                 # HEAD と比べる
#   ruby scripts/pdf_read_regress.rb d340fc0a        # 指定したコミットと比べる
#   ruby scripts/pdf_read_regress.rb --only IPSJ     # 名前に IPSJ を含む題材だけ
#   ruby scripts/pdf_read_regress.rb --out tmp/regress
#
# 題材は docs/pdf-samples/*.pdf（.gitignore で追跡外。手元に置く）と sources/97-sample.pdf。
# 書き出した Markdown（old_*.md・new_*.md）は --out のディレクトリに残るので、差のある本は差分を読んで確かめる。
# 数の差だけで良し悪しを決めない（差分の行数だけを見て、11 本の文字化けを見逃したことがある）。

require 'fileutils'
require 'open3'
require 'optparse'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
SAMPLES = [*Dir[File.join(ROOT, 'docs/pdf-samples/*.pdf')].sort, File.join(ROOT, 'sources/97-sample.pdf')].select { File.file?(it) }

# 1 本を経路 B で読んで書き出す。新旧の版は同じ定数を定義するので、別のプロセスで読む
RENDER = <<~RUBY
  require 'vivlio_starter/cli/pdf/structure_reader'
  reader = VivlioStarter::PDF::StructureReader.new(PDF::Reader.new(ARGV[0]))
  File.write(ARGV[1], reader.layout_markdown)
RUBY

# 化けた字が落ちる帯（Adobe-Japan1 の CID を Unicode とみなした字・康熙部首など）と、仮名・漢字
GARBLED = /[ɐ-˿Ͱ-ϿЀ-ӿ؀-ۿऀ-࿿⺀-⿿]/
JAPANESE = /[\p{Hiragana}\p{Katakana}\p{Han}]/

Counts = Data.define(:tables, :codes, :unknown, :images, :garbled, :japanese) do
  def self.of(path)
    text = File.read(path)
    new(tables: text.scan('列を推定して組んだ表').size, codes: text.scan(/^```/).size / 2, unknown: text.scan('▯').size,
        images: text.scan(/<!-- 画像|!\[/).size, garbled: text.scan(GARBLED).size, japanese: text.scan(JAPANESE).size)
  end

  def garbled_ratio = 100.0 * garbled / [garbled + japanese, 1].max
end

def parse_options
  options = { base: 'HEAD', only: nil, out: nil }
  OptionParser.new do |parser|
    parser.banner = 'usage: ruby scripts/pdf_read_regress.rb [BASE_REF] [--only NAME] [--out DIR]'
    parser.on('--only NAME', '名前に NAME を含む題材だけを比べる') { options[:only] = it }
    parser.on('--out DIR', '書き出した Markdown を置くディレクトリ（既定は一時ディレクトリ）') { options[:out] = it }
  end.parse!(ARGV)
  options[:base] = ARGV.first if ARGV.first
  options
end

# 2 つのプロセスで新旧を同時に書き出す。失敗した版は標準エラーの末尾を返す
def render_pair(pdf, worktree, out)
  name = File.basename(pdf, '.pdf')
  jobs = { old: File.join(worktree, 'lib'), new: File.join(ROOT, 'lib') }.map do |kind, lib|
    target = File.join(out, "#{kind}_#{name}.md")
    FileUtils.rm_f(target)
    Thread.new { [kind, *Open3.capture3('ruby', '-I', lib, '-e', RENDER, pdf, target)] }
  end
  jobs.map(&:value).to_h { |kind, _stdout, stderr, status| [kind, status.success? ? nil : stderr.lines.last(3).join] }
end

def diff_lines(old_path, new_path)
  stdout, = Open3.capture2('diff', old_path, new_path)
  stdout.lines.count { it.start_with?('<', '>') }
end

def format_row(name, old, new, diff)
  pair = ->(attr) { format('%5d → %5d', old.public_send(attr), new.public_send(attr)) }
  format('%-44s 表 %s  コード %s  ▯ %s  画像 %s  化け %5.1f%% → %5.1f%%  差 %d',
         name[0, 44], pair.(:tables), pair.(:codes), pair.(:unknown), pair.(:images), old.garbled_ratio, new.garbled_ratio, diff)
end

options = parse_options
samples = options[:only] ? SAMPLES.select { File.basename(it).include?(options[:only]) } : SAMPLES
abort(options[:only] ? "名前に #{options[:only]} を含む題材がありません" : 'docs/pdf-samples/ に題材の PDF がありません') if samples.empty?

out = options[:out] ? File.expand_path(options[:out], ROOT).tap { FileUtils.mkdir_p(it) } : Dir.mktmpdir('pdf-read-regress')
worktree = Dir.mktmpdir('pdf-read-base')
FileUtils.rm_rf(worktree) # git worktree add は空でないディレクトリを受け付けない
_, error, status = Open3.capture3('git', '-C', ROOT, 'worktree', 'add', '--detach', worktree, options[:base])
abort "直す前の版を出せません: #{error}" unless status.success?

begin
  # --- Phase: 題材ごとに新旧を書き出して数える ---
  puts "比べる版: #{options[:base]}（直す前）と作業ツリー（直した後）。題材 #{samples.size} 本"
  changed = samples.filter_map do |pdf|
    name = File.basename(pdf, '.pdf')
    failures = render_pair(pdf, worktree, out).compact
    next puts("#{name}: 書き出しに失敗しました\n#{failures.values.join}") unless failures.empty?

    old_path, new_path = %w[old new].map { File.join(out, "#{it}_#{name}.md") }
    diff = diff_lines(old_path, new_path)
    puts format_row(name, Counts.of(old_path), Counts.of(new_path), diff)
    name if diff.positive?
  end

  # --- Phase: 差のある本を挙げる ---
  puts
  puts changed.empty? ? '差のある本はありません' : "差のある本（中身を読んで確かめる）: #{changed.join('、')}"
  puts "書き出した Markdown: #{out}"
ensure
  Open3.capture3('git', '-C', ROOT, 'worktree', 'remove', '--force', worktree)
end
