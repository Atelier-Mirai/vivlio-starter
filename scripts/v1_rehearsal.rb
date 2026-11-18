# frozen_string_literal: true

# ================================================================
# scripts/v1_rehearsal.rb — 1.x の本を写しで 2.0 へ移し、PDF を画素で比べる（移行の予行）
# ================================================================
# 使い方:
#   ruby scripts/v1_rehearsal.rb --book DIR --out DIR [オプション] [-- vs build に渡す引数]
#
#   --book DIR      移す 1.x の本（本そのものには触れない）
#   --out DIR       作業の置き場（既にあれば消してから使う）
#   --v1 VERSION    1.x で組むときの gem の版（既定: インストール済みの 1.x の最新）
#   --targets LIST  output.targets を上書きする（既定: pdf）
#   --v1-upgrade    1.x の側も、組む前にその gem の vs upgrade で雛形を最新にする
#
# 例:
#   ruby scripts/v1_rehearsal.rb --book ../book_x --out /tmp/rehearsal/book_x
#   ruby scripts/v1_rehearsal.rb --book ../book_y --out /tmp/rehearsal/book_y -- upper
#
# v2-migration-plan.md §4.3 の S11a・S11c の「写しでの予行」。次の順に行う。
#   1. 本を 1.x の gem の bin/vs で組む（scripts/build_copy.rb。--out の v1/）
#   2. 本をもう一つ写し（--out の v2-src/）、作業ツリーの vs upgrade で 2.0 へ移す
#   3. 移した写しを作業ツリーの bin/vs で組む（--out の v2/）
#   4. 同じ名前の PDF どうしを scripts/pdf_pixel_diff.rb で比べ、違うページの画像を --out の diff/ に置く
#
# 1.x の側は、既定では本が持っている雛形の CSS のまま組む（著者の手元の今の紙面と比べる。S11c の見比べ）。
# --v1-upgrade を付けると、1.x の側にもその gem の vs upgrade を掛けてから組む。本の雛形が古い 1.x の版
# （1.0.0 など）のとき、1.x の中で直した雛形の CSS（1.0.1 の #132・#133・#135）の差を除き、2.0 で変わる
# ところだけを比べられる（§4.3 の完了の条件 1）。
#
# vs upgrade は写しで走らせても brew・npm・gem の更新がマシンに効くので、外部ツールの更新と
# 本体の自己更新は差し替える。確認には全部「はい」と答え、雛形と著者が同じファイルを変えた
# 競合だけは「いいえ」（著者のファイルを残す）と答える。移行の記録は --out の upgrade.log に残す。
# ================================================================

require 'fileutils'
require 'open3'
require 'optparse'
require 'rbconfig'

ROOT = File.expand_path('..', __dir__)

# 移す写しに持っていくもの。build_copy.rb の素材に、vs upgrade が見る Gemfile を足す
MATERIALS = %w[config contents stylesheets themes images covers codes data templates sources package.json Gemfile].freeze

options = { targets: 'pdf' }
parser = OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/v1_rehearsal.rb --book DIR --out DIR [--v1 VERSION] [--targets LIST] [-- vs build args]'
  o.on('--book DIR') { options[:book] = File.expand_path(it) }
  o.on('--out DIR') { options[:out] = File.expand_path(it) }
  o.on('--v1 VERSION') { options[:v1] = it }
  o.on('--targets LIST') { options[:targets] = it }
  o.on('--v1-upgrade') { options[:v1_upgrade] = true }
end
build_args = parser.parse(ARGV)
abort parser.banner unless options[:book] && options[:out]
abort "本が見つかりません: #{options[:book]}" unless File.file?(File.join(options[:book], 'config', 'book.yml'))

# 1.x の gem（bin/vs を持つディレクトリ）
specs = Gem::Specification.find_all_by_name('vivlio-starter').select { it.version < Gem::Version.new('2.0.0.a') }
spec = options[:v1] ? specs.find { it.version.to_s == options[:v1] } : specs.max_by(&:version)
abort "1.x の vivlio-starter がインストールされていません#{"（#{options[:v1]}）" if options[:v1]}" unless spec

out = options[:out]
FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)

def run!(label, *command, log: nil, **opts)
  puts "[v1_rehearsal] #{label}"
  output, status = Open3.capture2e(*command, **opts)
  File.write(log, output) if log
  puts output unless log
  abort "[v1_rehearsal] #{label} に失敗しました（終了コード #{status.exitstatus}）#{"。記録: #{log}" if log}" unless status.success?
end

build_copy = ->(book, vs, dest) { [RbConfig.ruby, File.join(ROOT, 'scripts', 'build_copy.rb'), '--book', book, '--vs', vs, '--out', dest, '--force', '--targets', options[:targets], '--', *build_args] }

# 本の素材を写す
copy_book = lambda do |dest|
  FileUtils.mkdir_p(dest)
  MATERIALS.each do |name|
    path = File.join(options[:book], name)
    FileUtils.cp_r(path, dest) if File.exist?(path)
  end
  dest
end

# 写しで vs upgrade を走らせるコード（1.x の gem と作業ツリーの両方で、-I で lib を替えて使う）
UPGRADE = <<~RUBY
  require 'vivlio_starter/cli/loader'
  include VivlioStarter::CLI
  DoctorCommands::ToolUpgrader.define_singleton_method(:run!) { |*, **| 0 }
  Common.define_singleton_method(:confirm?) { |message, **| puts("❓ \#{message} → はい"); true }
  UpgradeCommands.define_singleton_method(:prompt) { |message| puts("\#{message}→ いいえ"); 'n' }
  exit UpgradeCommands.run_from_command(Data.define(:options).new(options: { dry_run: false, yes: false, skip_self_update: true }))
RUBY

# --- Phase: 1.x で組む（--v1-upgrade なら、先に 1.x の vs upgrade で雛形を最新にする） ---------------
v1_book = options[:book]
if options[:v1_upgrade]
  v1_book = copy_book.(File.join(out, 'v1-src'))
  run!("1.x（#{spec.version}）の vs upgrade で雛形を最新にします", RbConfig.ruby, '-I', File.join(spec.gem_dir, 'lib'),
       '-e', UPGRADE, chdir: v1_book, log: File.join(out, 'upgrade-v1.log'))
end
run!("1.x（#{spec.version}）で組みます", *build_copy.(v1_book, spec.gem_dir, File.join(out, 'v1')),
     log: File.join(out, 'build-v1.log'))

# --- Phase: 写しを 2.0 へ移す ----------------------------------------------------------
source = copy_book.(File.join(out, 'v2-src'))
run!('作業ツリーの vs upgrade で 2.0 へ移します', RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', UPGRADE,
     chdir: source, log: File.join(out, 'upgrade.log'))

# --- Phase: 2.0 で組む ----------------------------------------------------------------
run!('作業ツリーの bin/vs で組みます', *build_copy.(source, ROOT, File.join(out, 'v2')), log: File.join(out, 'build-v2.log'))

# --- Phase: 比べる ---------------------------------------------------------------------
results = Dir.glob(File.join(out, 'v1', '*.pdf')).sort.map do |v1_pdf|
  name = File.basename(v1_pdf)
  v2_pdf = File.join(out, 'v2', name)
  next [name, '2.0 の側に同じ名前の PDF がありません'] unless File.file?(v2_pdf)

  report, = Open3.capture2e(RbConfig.ruby, File.join(ROOT, 'scripts', 'pdf_pixel_diff.rb'), v1_pdf, v2_pdf,
                            '--out', File.join(out, 'diff', File.basename(name, '.pdf')))
  [name, report.strip]
end

puts
puts "[v1_rehearsal] 結果（#{options[:book]}）"
results.each { |name, report| puts "  #{name}", report.lines.map { "    #{it}" }.join }
puts '  （1.x の側に PDF がありません）' if results.empty?
