# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Techbook
      class VariableFontInjector
        # @param font_configs [Array<Hash>] variable_fonts 設定配列
        def initialize(font_configs)
          @font_configs = Array(font_configs).compact
        end

        # 静的 @font-face 宣言の CSS を生成する
        # @return [String] CSS 文字列（設定なしの場合は空文字列）
        def css
          return "" if @font_configs.empty?

          declarations = @font_configs.flat_map { generate_declarations(it) }
          return "" if declarations.empty?

          "/* Vivlio Starter: techbook variable font static instances */\n" +
            declarations.join("\n")
        end

        private

        # 1つのフォント設定から全インスタンスの @font-face 宣言を生成する
        # エントリは著者定義の自由構造（キー欠落があり得る）ため、
        # nil 安全なシンボル [] で参照する（Data / シンボルキー Hash の双方で同義）
        def generate_declarations(config)
          family = config[:family]
          src = config[:src]
          instances = config[:instances]

          unless family && src && instances
            log_warning("[Techbook] variable_fonts エントリに必須フィールドが不足: #{config.inspect}")
            return []
          end

          Array(instances).map { build_font_face(family, src, it) }
        end

        def build_font_face(family, src, instance)
          weight = instance[:weight]
          settings = instance[:settings]
          derived_family = "#{family}-#{weight}"

          <<~CSS
            @font-face {
              font-family: "#{derived_family}";
              src: url("#{src}") format("woff2");
              font-weight: #{weight};
              font-style: normal;
              font-variation-settings: #{settings};
            }
          CSS
        end

        # Common.log_warn が利用可能ならそちらを使い、
        # テスト等で Common が未ロードの場合は warn にフォールバック
        def log_warning(message)
          if defined?(Common) && Common.respond_to?(:log_warn)
            Common.log_warn(message)
          else
            warn message
          end
        end
      end
    end
  end
end
