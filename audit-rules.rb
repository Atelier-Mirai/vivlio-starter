#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 置換ルール使用状況チェッカー
# - 目的: /_post_replace_list.yml の各ルールが、対象ディレクトリ内のファイルで何回ヒットしているかを集計します。
# - 使い方:
#     ruby audit-rules.rb [--dir DIR] [--glob GLOB] [--yaml PATH]
#   例:
#     ruby audit-rules.rb --dir dist --glob "**/*.{html,htm}"
#     ruby audit-rules.rb --dir contents --glob "**/*.{md}"
# - 出力: ルール番号, ヒット総数, ヒットしたファイル数, 説明, 正規表現パターン
#
# 注意:
# - _post_replace_list.yml の f は Ruby の正規表現文字列（/で囲まない）を想定しています。
# - YAML コメントは通常のロードでは失われるため、本スクリプトでは YAML 原文を同時に読み、
#   "- f:" の直前のコメント行(# ...)を簡易に「説明」として紐づけます（直前の1行のみ）。
#
require 'yaml'
require 'optparse'
require 'ostruct'
require 'pathname'

options = OpenStruct.new
options.dir = '.'
options.glob = '**/*.{html,htm,md}'
options.yaml = './_post_replace_list.yml'

OptionParser.new do |opt|
  opt.banner = 'Usage: ruby audit-rules.rb [options]'
  opt.on('--dir DIR', '走査対象ディレクトリ（既定: .）') { |v| options.dir = v }
  opt.on('--glob GLOB', 'ファイルグロブ（既定: **/*.{html,htm,md}）') { |v| options.glob = v }
  opt.on('--yaml PATH', 'ルールYAMLへのパス（既定: ./_post_replace_list.yml）') { |v| options.yaml = v }
  opt.on('-h', '--help', 'このヘルプを表示') { puts opt; exit 0 }
end.parse!(ARGV)

unless File.file?(options.yaml)
  warn "[ERR] ルールファイルが見つかりません: #{options.yaml}"
  exit 1
end

# YAML をロード（ルール配列）
rules = YAML.safe_load(File.read(options.yaml), permitted_classes: [], aliases: true)
unless rules.is_a?(Array)
  warn "[ERR] ルールYAMLが配列ではありません: #{options.yaml}"
  exit 1
end

# コメント取得のため元テキストも読む
raw_lines = File.read(options.yaml, encoding: 'UTF-8').lines
# 各 "- f:" ラインの直前にある連続したコメント行(# ...)を説明として拾う

descriptions = []
raw_lines.each_with_index do |line, i|
  if line =~ /^-\s*f:\s*(?:['"])?/
    # 直前に連なるコメントブロックを収集（空行はコメントブロック開始前のみスキップ可）
    j = i - 1
    block = []
    skipped_blanks_before_block = true
    while j >= 0
      prev = raw_lines[j]
      if prev.strip.start_with?('#')
        block << prev.sub(/^\s*#\s?/, '').rstrip
        skipped_blanks_before_block = false
        j -= 1
        next
      elsif prev.strip.empty?
        # コメントブロック開始前の空行は許容
        break unless skipped_blanks_before_block || block.any?
        j -= 1
        next
      else
        break
      end
    end
    desc = block.reverse.join(' / ')
    descriptions << desc
  end
end
# descriptions.length は rules.length と一致しない可能性もあるため、後で安全に参照

# 走査対象ファイル一覧
root = Pathname(options.dir)
file_paths = Dir.chdir(root.to_s) { Dir.glob(options.glob, File::FNM_EXTGLOB | File::FNM_CASEFOLD) }
file_paths.select! { |p| File.file?(File.join(root, p)) }

puts "[INFO] 走査ディレクトリ: #{root.realpath rescue root}"
puts "[INFO] ファイル数: #{file_paths.size} (glob: #{options.glob})"
puts "[INFO] ルール数: #{rules.size} (yaml: #{options.yaml})"
puts

# 集計器
RuleStat = Struct.new(:index, :pattern, :desc, :total_hits, :files_hit)
stats = []

rules.each_with_index do |rule, idx|
  pattern_str = rule['f']
  unless pattern_str.is_a?(String)
    warn "[WARN] f が文字列ではありません (index=#{idx}): #{pattern_str.inspect}"
    next
  end
  begin
    regex = Regexp.new(pattern_str, Regexp::MULTILINE)
  rescue RegexpError => e
    warn "[ERR] 正規表現エラー (index=#{idx}): #{e.message} | pattern=#{pattern_str.inspect}"
    next
  end

  total = 0
  files_hit = 0
  file_paths.each do |rel|
    path = (root + rel).to_s
    begin
      content = File.read(path, mode: 'r:UTF-8')
    rescue => e
      warn "[WARN] 読み込み失敗: #{path} (#{e.class}: #{e.message})"
      next
    end
    count = content.scan(regex).length
    if count > 0
      total += count
      files_hit += 1
    end
  end

  desc = descriptions[idx] rescue ''
  stats << RuleStat.new(idx, pattern_str, desc, total, files_hit)
end

# 出力（ヒット数降順）
stats.sort_by! { |s| [-s.total_hits, -s.files_hit, s.index] }

# 見出し
puts 'idx, total_hits, files_hit, desc, pattern'
stats.each do |s|
  d = s.desc&.gsub(/[,\n]/, ' ').to_s
  ptn = s.pattern.gsub(/\n/, '\\n')
  puts [s.index, s.total_hits, s.files_hit, d, ptn].join(', ')
end

# ヒットゼロの数を最後に
zero = stats.count { |s| s.total_hits.zero? }
puts
puts "[INFO] ヒット0のルール: #{zero}/#{stats.size}"
