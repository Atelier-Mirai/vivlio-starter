# frozen_string_literal: true

require 'pathname'

module Vivlio
  module Starter
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
            html.gsub(EMOJI_REGEX) do |match|
              replace_emoji(match)
            end
          end

          private

          # 利用者のプロジェクトルート（カレントディレクトリ）の stylesheets/twemoji/ を参照する。
          # vs new で展開された scaffold に Twemoji SVG が同梱されているため、
          # gem インストール先ではなくプロジェクト側のパスで解決する。
          # Vivliostyle は HTML ファイルからの相対パスで画像を解決するため、
          # 絶対パスではなく相対パスを返す。
          def default_emoji_dir
            File.join('stylesheets', 'twemoji')
          end

          # 絵文字文字列を img タグに変換する（SVG が存在する場合のみ）
          def replace_emoji(char)
            codepoint = emoji_codepoint(char)
            svg_path = @emoji_dir.join("#{codepoint}.svg")
            svg_path.exist? ? build_img_tag(char, svg_path) : char
          end

          # 絵文字の Unicode コードポイントを Twemoji ファイル名形式に変換する
          # 例: "✅" → "2705"、複合絵文字 "👨‍💻" → "1f468-200d-1f4bb"
          def emoji_codepoint(char)
            char.codepoints
                .reject { it == 0xFE0F }
                .map { it.to_s(16).downcase }
                .join("-")
          end

          def build_img_tag(char, svg_path)
            %(<img src="#{svg_path}" alt="#{char}" ) +
              %(class="emoji vs-emoji" ) +
              %(width="1em" height="1em" ) +
              %(style="vertical-align: -0.15em;">)
          end
        end
      end
    end
  end
end
