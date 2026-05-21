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
        def generate_declarations(config)
          family = config_value(config, :family)
          src = config_value(config, :src)
          instances = config_value(config, :instances)

          unless family && src && instances
            log_warning("[Techbook] variable_fonts エントリに必須フィールドが不足: #{config.inspect}")
            return []
          end

          Array(instances).map { build_font_face(family, src, it) }
        end

        def build_font_face(family, src, instance)
          weight = config_value(instance, :weight)
          settings = config_value(instance, :settings)
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

        # Hash / Data 両対応のアクセサ
        # Common::CONFIG 経由の設定値は再帰的 Data ラッパーだが、
        # テスト等で Hash が渡される場合にも対応する
        def config_value(obj, key)
          case obj
          when Hash then obj[key.to_sym] || obj[key.to_s]
          else obj.respond_to?(key) ? obj.public_send(key) : nil
          end
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
