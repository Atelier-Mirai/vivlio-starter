# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/restore_plain_emoji.rb
# ================================================================
# 責務:
#   絵文字の画像を、元の絵文字の字へ戻す
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 絵文字の画像を、元の絵文字の字へ戻す
      module Transforms::Shared::RestorePlainEmoji
        module_function

        # techbook の絵文字画像 <img class="... vs-emoji ...">  の class を見分ける正規表現。
        # 絵文字画像化（twemoji SVG 差し替え）は Chromium が PDF で絵文字を Type 3 化する
        # 障害への対策で、PDF 専用。EPUB はリフロー型で Type 3 が存在せず、リーダーの
        # カラー絵文字で描画されるため、EPUB 経路では alt の元絵文字へ戻す（Fix-8）。
        # 囲み数字（vs-circled-number）は alt が数字でアクセント色付き画像のため除外する。
        EMOJI_CLASS_PATTERN = /\bvs-emoji\b/

        # ================================================================
        # EPUB 用 絵文字プレーン復元
        # ================================================================
        # techbook の絵文字画像化（EmojiReplacer）は PDF の Type 3 障害対策で、
        # EPUB には不要（EPUB に Type 3 は存在せずリーダーのカラー絵文字で描画される）。
        # EPUB 経路でのみ <img class="... vs-emoji ...">  を alt の元絵文字へ戻し、
        # twemoji 画像の同梱を不要にして軽量化する（localize_assets! が
        # stylesheets/twemoji 直下 svg を除外）。囲み数字（vs-circled-number）は alt が数字で
        # 字形・アクセント色を保てないため画像のまま残す。
        # ================================================================

        # 絵文字 <img> を alt の絵文字テキストへ復元する（vs-circled-number は除く）
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          # 囲み数字は数字 alt・アクセント色付き画像のため画像のまま維持する
          images = doc.css('img[class]').select do |img|
            img['class'].match?(EMOJI_CLASS_PATTERN) && img.key?('alt') &&
              img.attribute_nodes.none? { it.value.include?('vs-circled-number') }
          end
          return if images.empty?

          images.each { it.replace(doc.create_text_node(it['alt'])) }
          Common.log_info("[EPUB] #{ctx.page_name} の絵文字をプレーン文字へ復元しました")
        end
      end
    end
  end
end
