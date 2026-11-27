# frozen_string_literal: true
#
# **開発時にだけ使うスクリプト**（gem には同梱されるが、実行時には読まれない）。
# SudachiDict の語彙（core_lex.csv・notcore_lex.csv）から、英字の表記とカタカナの読みの組を
# 取り出し、用語集のふりがなの候補に使う furigana-sudachi.tsv を作る（改善案 #175）。
#
#   rake furigana:build SUDACHI_DIR=<core_lex.csv と notcore_lex.csv のあるフォルダ> SUDACHI_VERSION=20261015
#
# 語彙は AWS Open Data（https://registry.opendata.aws/sudachi/）の sudachidict-raw/<版>/ にある
#   https://sudachi.s3.ap-northeast-1.amazonaws.com/sudachidict-raw/20261015/core_lex.zip
#   https://sudachi.s3.ap-northeast-1.amazonaws.com/sudachidict-raw/20261015/notcore_lex.zip
# small_lex は使わない（UniDic の一部で、ライセンスが BSD。core・notcore は Apache-2.0）。
#
# 取り出す条件（Apache License 2.0 第 4 条 (b) の改変内容として THIRD-PARTY-LICENSES.md にも書く）:
#   - 表記の欄（5 列目）か正規化表記の欄（13 列目）が ASCII の印字可能文字だけで、英数字で始まり、
#     英字を 1 字以上含む（正規化表記を見るのは、カタカナの見出しが英字へ正規化される語のため。
#     リナックス → Linux・グーグルペイ → Google Pay）
#   - 読みの欄（12 列目）がカタカナ（と長音・中黒）だけ
#   - 同じ表記の読みは、重ねずに出てきた順に並べる（`ANK` → エーエヌケー|アンク）
#   - 表記の順に並べる
# 品詞・コスト・正規化表記などの欄は持ち出さない。
#
# 出力の形: 1 行 1 語、`表記<TAB>読み1|読み2`。先頭の `#` の行は出典の注記。

require 'csv'

dir = ENV.fetch('SUDACHI_DIR') { abort 'SUDACHI_DIR に core_lex.csv と notcore_lex.csv のあるフォルダを渡してください' }
version = ENV.fetch('SUDACHI_VERSION') { abort 'SUDACHI_VERSION に語彙の版（例: 20261015）を渡してください' }
sources = %w[core_lex.csv notcore_lex.csv].map { File.join(dir, it) }
sources.each { abort "見つかりません: #{it}" unless File.exist?(it) }

SURFACE = /\A[A-Za-z0-9][\x20-\x7e]*\z/
READING = /\A[ァ-ヶー・]+\z/

readings = Hash.new { |h, k| h[k] = [] }
sources.each do |path|
  File.foreach(path, encoding: 'utf-8') do |line|
    fields = line.chomp.split(',')
    reading = fields[11].to_s
    next unless reading.match?(READING)

    # 英字の表記（5 列目）と、カタカナの見出しが英字へ正規化される語（リナックス → Linux。13 列目）
    [fields[4], fields[12]].map(&:to_s).uniq.each do |surface|
      next unless surface.match?(SURFACE) && surface.match?(/[A-Za-z]/)

      readings[surface] << reading unless readings[surface].include?(reading)
    end
  end
end

out = File.join(__dir__, 'furigana-sudachi.tsv')
File.open(out, 'w', encoding: 'utf-8') do |file|
  file.puts "# SudachiDict #{version}（core_lex・notcore_lex）から取り出した、英字の表記とカタカナの読み。"
  file.puts '# Copyright (c) 2017-2023 Works Applications Co., Ltd. Licensed under the Apache License, Version 2.0'
  file.puts '# （LICENSE-APACHE-2.0.txt）。著作権表示は SudachiDict の README のまま。取り出しの条件は filter.rb の冒頭と THIRD-PARTY-LICENSES.md にある。'
  readings.sort_by { |surface, _| [surface.downcase, surface] }.each do |surface, list|
    file.puts "#{surface}\t#{list.join('|')}"
  end
end
puts "#{out}: #{readings.size} 語（読みが複数 #{readings.count { |_, v| v.size > 1 }} 語）"
