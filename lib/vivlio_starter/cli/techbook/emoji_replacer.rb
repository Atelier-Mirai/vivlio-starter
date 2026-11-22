# frozen_string_literal: true

require 'pathname'
require_relative '../common'

module VivlioStarter
  module CLI
    module Techbook
      class EmojiReplacer
        # 絵文字の候補の並び。
        #
        # 隣り合う絵文字（`"🌊🌊🗻"`）はひとかたまりで当たるので、置き換えは書記素クラスタに
        # 分けてから 1 つずつ画像を探す（改善案 #156）。かたまりのまま `1f30a-1f30a-1f5fb` の
        # 画像を探していた頃は、見つからずに字のまま残り、PDF で Type 3 になっていた。
        # ZWJ（200D）・異体字セレクタ（FE0F）・キーキャップ（20E3）・タグ（E0020〜E007F、
        # 地域の旗）も並びに含める。含めないと `👨‍💻` や `1️⃣` が途中で切れる。
        EMOJI_REGEX = /[\p{Emoji}\u200D\uFE0F\u20E3\u{E0020}-\u{E007F}]+/

        # HTML の地の文だけをブロックの戻り値で置き換える。タグそのものと、style・script・svg の
        # 中身には触れない。Processor の囲み数字の画像化もこれを使う。
        # @param html [String]
        # @yieldparam text [String] タグの間の文字列
        # @return [String]
        def self.map_text_segments(html)
          in_ignored_element = nil

          html.split(/(<[^>]+>)/).map do |part|
            if part.start_with?('<')
              in_ignored_element = ignored_element_after(part, in_ignored_element)
              part
            elsif in_ignored_element
              part
            else
              yield part
            end
          end.join
        end

        # HTML タグ属性、style/script/svg の内容は置換対象外にする。
        # 特に既に生成済みの <img alt="✅"> を再処理して壊さないために必要。
        def self.ignored_element_after(tag, current)
          normalized = tag.downcase
          return nil if current && normalized.match?(%r{\A</\s*#{Regexp.escape(current)}\s*>})
          return current if current

          matched = normalized.match(%r{\A<\s*(script|style|svg)\b})
          matched ? matched[1] : nil
        end
        private_class_method :ignored_element_after

        # 置き換える書記素クラスタか。`\p{Emoji}` は ASCII の `0-9`・`#`・`*` も含むので、
        # ASCII だけのクラスタ（コードの `24` や `#`）は置き換えない。キーキャップ（`1️⃣`）は
        # FE0F・20E3 を伴うので ASCII だけにはならず、置き換える。
        def self.emoji_cluster?(cluster) = !cluster.ascii_only?

        # 絵文字の Unicode コードポイントを Twemoji ファイル名形式に変換する
        # 例: "✅" → "2705"、複合絵文字 "👨‍💻" → "1f468-200d-1f4bb"
        #
        # FE0F は ZWJ を含まないときだけ落とす（Twemoji の名前の付け方。`🏳️‍🌈` は
        # `1f3f3-fe0f-200d-1f308`、`🏔️` は `1f3d4`）。
        def self.emoji_codepoint(char)
          codepoints = char.codepoints
          codepoints = codepoints.reject { it == 0xFE0F } unless codepoints.include?(0x200D)
          codepoints.map { it.to_s(16).downcase }.join("-")
        end

        # @param emoji_dir [Pathname, String, nil] SVG ディレクトリ（nil 時は gem 同梱パスを使用）
        def initialize(emoji_dir = nil)
          @emoji_dir = Pathname(emoji_dir || default_emoji_dir)
        end

        # HTML 中の絵文字を SVG img タグに差し替える
        # @param html [String]
        # @return [String]
        def process(html) = self.class.map_text_segments(html) { replace_emoji_in_text(it) }

        def replace_emoji_in_text(text)
          text.gsub(EMOJI_REGEX) do |run|
            run.grapheme_clusters.map { self.class.emoji_cluster?(it) ? replace_emoji(it) : it }.join
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

        # 絵文字文字列を img タグに変換する
        # Techbook モードでは SVG → WebP 変換済みのため、WebP を優先参照する。
        # WebP が存在しない場合は SVG にフォールバックする。
        def replace_emoji(char)
          codepoint = self.class.emoji_codepoint(char)
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
