# frozen_string_literal: true

# ================================================================
# scripts/pages_snapshot.rb — ビルドなしで、EPUB と Kindle のページの HTML を作り直して写し取る
# ================================================================
# 使い方:
#   ruby scripts/pages_snapshot.rb <写しの本> <写し取る先> [--lib <vivlio-starter の lib>]
#
# 写しの本は `scripts/build_copy.rb --no-clean` で組んだもの（`.cache/vs/build/html` が残っている）。
# 出力先の変換（`transforms/`・`epub/`）だけを走らせ直すので、1 冊で 1 分ほどで済む。
# 前後の lib で 2 回写し取り、`scripts/pages_diff.rb` で比べる（v2-migration-plan.md §3.6）。
# --lib を省くと、このリポジトリの lib を使う。
# ================================================================

require 'fileutils'

ROOT = File.expand_path('..', __dir__)

args = ARGV.dup
lib = (index = args.index('--lib')) ? File.expand_path(args.slice!(index, 2).last) : File.join(ROOT, 'lib')
book, out = args.map { File.expand_path(it) }
abort 'usage: ruby scripts/pages_snapshot.rb <写しの本> <写し取る先> [--lib DIR]' unless book && out

# book.yml は読み込みの時に今のディレクトリから読まれるので、先に本へ移る
Dir.chdir(book)
$LOAD_PATH.unshift(lib)
require 'vivlio_starter/cli/startup'
require 'vivlio_starter/cli/loader'

cli = VivlioStarter::CLI
build = cli::Build
cli::Common.ensure_configured!
entries = cli::TokenResolver::Resolver.new.resolve

%i[epub kindle].each do |id|
  target = build::OutputTarget.for(id)
  FileUtils.rm_rf(target.workspace)
  build::Epub::Workspace.stage_consumer_htmls!(target.workspace)
  pages = build::EpubFlow.prepare_pages!(target, entries)
  dest = File.join(out, id.to_s)
  FileUtils.rm_rf(dest)
  FileUtils.mkdir_p(dest)
  pages.each { FileUtils.cp(it, dest) }
  FileUtils.cp_r(File.join(target.workspace, 'styles'), dest)
  FileUtils.cp(File.join(target.workspace, 'entries.epub.js'), dest)
  puts "#{id}: #{pages.size} ページ"
end
