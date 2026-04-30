# frozen_string_literal: true

require_relative 'emoji_replacer'
require_relative 'variable_font_injector'

module Vivlio
  module Starter
    module CLI
      module Techbook
        class Processor
          # @param config [Data] book.yml の設定オブジェクト（Common::CONFIG の再帰的 Data ラッパー）
          def initialize(config)
            @config = config
            @techbook = config.dig(:output, :pdf, :techbook) == true
          end

          def enabled? = @techbook

          # HTML 中の絵文字を Twemoji SVG に差し替え、Type 3 フォント化する文字を置換する
          # @param html [String] 変換対象の HTML
          # @return [String] 処理済み HTML（無効時はそのまま返す）
          def process(html)
            return html unless enabled?

            # --- Phase: 波ダッシュ → 全角チルダ置換 ---
            # U+301C（波ダッシュ）は多くのフォントに収録されておらず、
            # Chromium が Type 3 フォントとして埋め込む。
            # 字形が同一の U+FF5E（全角チルダ）に置換することで回避する。
            html = html.gsub("\u301C", "\uFF5E")

            # --- Phase: 絵文字 SVG 差し替え ---
            EmojiReplacer.new.process(html)
          end

          # Techbook 用 CSS（絵文字スタイル + 可変フォント静的インスタンス）を返す
          # @return [String] CSS 文字列（無効時は空文字列）
          def inject_css
            return "" unless enabled?

            css_parts = []
            css_parts << emoji_css
            font_css = VariableFontInjector.new(variable_font_configs).css
            css_parts << font_css unless font_css.empty?
            css_parts.join("\n")
          end

          private

          def emoji_css
            <<~CSS
              /* Vivlio Starter: techbook emoji style */
              img.vs-emoji {
                display: inline;
                width: 1em;
                height: 1em;
                vertical-align: -0.15em;
              }
            CSS
          end

          def variable_font_configs
            Array(@config.dig(:output, :pdf, :variable_fonts))
          end
        end
      end
    end
  end
end
