#!/usr/bin/env ruby
# frozen_string_literal: true

# OTF(CFF) → TTF(glyf) フォーマット変換。
#
# Chrome 149（Vivliostyle 11.x）は CFF アウトラインのサブセットを PDF へ Type 3 フォントで
# 埋め込む。TTF(glyf) 化すると CID TrueType で埋め込まれるため、keyfont(Keyboard-JP) 等の
# Type 3 化を回避するのに使う。
#
# 輪郭変換（3次→2次ベジェ）は Ruby に成熟ライブラリが無いため、標準フォントツール
# fontforge に委譲する（出力拡張子が .ttf のとき fontforge が自動で glyf へ変換する）。
# 字形・メトリクス・cmap は維持される。
#
# 使い方:  ruby otf2ttf.rb <input.otf> <output.ttf>
# 前提:    fontforge（macOS は `brew install fontforge`）。

# 1 つの OTF を TTF へ変換する。
# @param src [String] 入力 OTF パス
# @param dst [String] 出力 TTF パス
def convert(src, dst)
  raise ArgumentError, "入力フォントが見つかりません: #{src}" unless File.exist?(src)
  raise 'fontforge が見つかりません（`brew install fontforge`）' unless system('which', 'fontforge', out: File::NULL)

  # fontforge ネイティブスクリプト（-lang=ff）。パスは Ruby 側でクォートして埋め込む。
  ff_script = %(Open(#{src.inspect}); Generate(#{dst.inspect}))
  raise "fontforge による変換に失敗しました: #{src}" unless system('fontforge', '-lang=ff', '-c', ff_script)

  puts "変換しました: #{dst}"
end

if ARGV.length != 2
  warn "usage: ruby #{File.basename($PROGRAM_NAME)} <input.otf> <output.ttf>"
  exit 1
end

convert(ARGV[0], ARGV[1])
