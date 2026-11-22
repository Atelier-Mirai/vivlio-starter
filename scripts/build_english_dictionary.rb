# frozen_string_literal: true

# ================================================================
# Script: build_english_dictionary.rb
# ================================================================
# スペルチェックの同梱の英語の辞書（config/spellcheck_dictionaries/english-words-40.txt）を、
# SCOWL の配布物から作る（改善案.md #147）。
#
# 使い方:
#   ruby scripts/build_english_dictionary.rb <SCOWL を展開したディレクトリ>
#
# SCOWL は http://wordlist.aspell.net/ から入手する（scowl-YYYY.MM.DD.tar.gz を展開する）。
# 作り直したら `ruby scripts/copy_to_scaffold.rb` で雛形にも写す。
#
# 選ぶ一覧: final/ の english・american の words・upper・proper-names・contractions・
# abbreviations のうち、大きさが SIZE 以下のもの。大きさを 40 にした理由（誤検出と、
# 打ち間違いの見逃しの釣り合い）は改善案.md #147 にある。
#
# SCOWL の一覧は ISO-8859-1 なので、UTF-8 に直して書く（アクセント記号の付いた語のため）。
# SCOWL の許諾は「すべての写しに著作権表示を残す」ことを求めるので、配布物の Copyright を
# SCOWL-COPYRIGHT として辞書の隣に置く（.txt にしないのは、辞書として読み込まれないため）。
# ================================================================

require 'fileutils'

ROOT = File.expand_path('..', __dir__)
DICT_DIR = File.join(ROOT, 'config', 'spellcheck_dictionaries')
SIZE = 40
OUTPUT = File.join(DICT_DIR, "english-words-#{SIZE}.txt")

scowl = ARGV.fetch(0) { abort 'usage: ruby scripts/build_english_dictionary.rb <SCOWL を展開したディレクトリ>' }
final = File.join(scowl, 'final')
abort "SCOWL の final/ がありません: #{final}" unless Dir.exist?(final)

lists = Dir.glob(File.join(final, '{english,american}-*.*')).select { it[/\.(\d+)\z/, 1].to_i <= SIZE }.sort
words = lists.flat_map do |path|
  File.readlines(path, encoding: 'ISO-8859-1').map { it.strip.encode('UTF-8') }
end.reject(&:empty?).uniq.sort

File.write(OUTPUT, words.join("\n") + "\n")
FileUtils.cp(File.join(scowl, 'Copyright'), File.join(DICT_DIR, 'SCOWL-COPYRIGHT'))

puts "#{File.basename(OUTPUT)}: #{words.size} 語（#{lists.size} 個の一覧から・#{File.read(File.join(scowl, 'VERSION')).strip}）"
