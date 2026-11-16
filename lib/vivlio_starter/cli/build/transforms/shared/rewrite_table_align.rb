# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/rewrite_table_align.rb
# ================================================================
# 責務:
#   表の align 属性を style へ移す
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 表の align 属性を style へ移す
      module Transforms::Shared::RewriteTableAlign
        module_function

        # ================================================================
        # EPUB 用 テーブル align 属性の変換
        # ================================================================
        # VFM はテーブル列の整列（|:--| 等）を <th align="left"> という
        # 廃止済みプレゼンテーション属性で出力する。XHTML5 では align 属性は
        # 不許可で epubcheck の RSC-005 ERROR になるため、EPUB 経路でのみ
        # style="text-align:..." へ変換する。PDF（Vivliostyle）は align を
        # 許容するため PDF 経路は従来どおり（共有 HTML の書き換えは Step E =
        # PDF 完成後のため安全）。
        # ================================================================

        # th/td の align 属性を style の text-align へ変換する
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            rewritten = html.gsub(/<t[hd]\b[^>]*\salign="(?:left|center|right|justify)"[^>]*>/) do
              convert_cell_align_to_style(it)
            end
            next if rewritten == html

            File.write(path, rewritten, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} のテーブル align 属性を style へ変換しました")
          end
          html_files
        end

        # 1 つの th/td 開始タグ内で align 属性を除去し、text-align を style に統合する。
        # align と style の属性順序に依存しないようタグ全体を受け取って組み立て直す
        # （部分捕捉だと捕捉範囲外に style が残り、style 属性が二重になるため）。
        #
        # @param tag [String] '<th align="left">' のような開始タグ全体
        # @return [String] 変換後のタグ
        def convert_cell_align_to_style(tag)
          value = tag[/\salign="(left|center|right|justify)"/, 1]
          stripped = tag.sub(/\salign="(?:left|center|right|justify)"/, '')

          if stripped.match?(/\sstyle="/)
            stripped.sub(/\sstyle="/, %( style="text-align:#{value};))
          else
            stripped.sub(/\A(<t[hd]\b)/, %(\\1 style="text-align:#{value}"))
          end
        end
      end
    end
  end
end
