# frozen_string_literal: true

require 'pathname'
require_relative '../common'

module VivlioStarter
  module CLI
    module Techbook
      class EmojiReplacer
        # Unicode Emoji 検出用正規表現
        # Emoji_Presentation を持つ文字 + Variation Selector 付き文字を対象とする
        EMOJI_REGEX = /[\p{Emoji_Presentation}\p{Emoji}\uFE0F]+/

        # @param emoji_dir [Pathname, String, nil] SVG ディレクトリ（nil 時は gem 同梱パスを使用）
        def initialize(emoji_dir = nil)
          @emoji_dir = Pathname(emoji_dir || default_emoji_dir)
        end

        # HTML 中の絵文字を SVG img タグに差し替える
        # @param html [String]
        # @return [String]
        def process(html)
          in_ignored_element = nil

          html.split(/(<[^>]+>)/).map do |part|
            if part.start_with?('<')
              in_ignored_element = update_ignored_element_state(part, in_ignored_element)
              part
            elsif in_ignored_element
              part
            else
              replace_emoji_in_text(part)
            end
          end.join
        end

        def replace_emoji_in_text(text)
          text.gsub(EMOJI_REGEX) do |match|
            replace_emoji(match)
          end
        end

        private

        # HTML タグ属性、style/script/svg の内容は置換対象外にする。
        # 特に既に生成済みの <img alt="✅"> を再処理して壊さないために必要。
        def update_ignored_element_state(tag, current)
          normalized = tag.downcase
          return nil if current && normalized.match?(%r{\A</\s*#{Regexp.escape(current)}\s*>})
          return current if current

          matched = normalized.match(%r{\A<\s*(script|style|svg)\b})
          matched ? matched[1] : nil
        end

        # 利用者のプロジェクトルート（カレントディレクトリ）の stylesheets/twemoji/ を参照する。
        # vs new で展開された scaffold に Twemoji SVG が同梱されているため、
        # gem インストール先ではなくプロジェクト側のパスで解決する。
        # Vivliostyle は HTML ファイルからの相対パスで画像を解決するため、
        # 絶対パスではなく相対パスを返す。
        def default_emoji_dir
          File.join('stylesheets', 'twemoji')
        end

        # 絵文字文字列を img タグに変換する
        # Techbook モードでは SVG → WebP 変換済みのため、WebP を優先参照する。
        # WebP が存在しない場合は SVG にフォールバックする。
        def replace_emoji(char)
          codepoint = emoji_codepoint(char)
          webp_path = @emoji_dir.join("#{codepoint}.webp")
          svg_path = @emoji_dir.join("#{codepoint}.svg")

          if webp_path.exist?
            build_img_tag(char, webp_path)
          elsif svg_path.exist?
            build_img_tag(char, svg_path)
          else
            char
          end
        end

        # 絵文字の Unicode コードポイントを Twemoji ファイル名形式に変換する
        # 例: "✅" → "2705"、複合絵文字 "👨‍💻" → "1f468-200d-1f4bb"
        def emoji_codepoint(char)
          char.codepoints
              .reject { it == 0xFE0F }
              .map { it.to_s(16).downcase }
              .join("-")
        end

        # 絵文字 <img> を生成する。
        # 寸法は CSS（img.vs-emoji）と同値を style に統合する。
        # HTML の width/height 属性は整数 px のみ許容され "1em" は EPUB で
        # RSC-005 ERROR になるため、属性ではなくインライン style で寸法を与える。
        # src はワークスペース内 HTML からの相対（asset_prefix 前置・P4 §3.3）。
        # 絶対パス（テスト注入等）はそのまま解決できるため前置しない。
        def build_img_tag(char, svg_path)
          prefix = svg_path.absolute? ? '' : Common.asset_prefix
          %(<img src="#{prefix}#{svg_path}" alt="#{char}" ) +
            %(class="emoji vs-emoji" ) +
            %(style="width: 1em; height: 1em; vertical-align: -0.15em;">)
        end
      end
    end
  end
end
