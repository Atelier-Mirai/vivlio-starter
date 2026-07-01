# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/theme_validator.rb
# ================================================================
# 責務:
#   book.yml の theme 設定（color / frontispiece / ornament）を検証し、
#   問題があれば著者向けの親切な警告（🟡）を一度だけ表示する。
#
# 設計方針:
#   - ビルドは中断しない（警告のみ）。無効値は既定へフォールバックして継続する。
#   - Step 2（prepare_theme_images!）から一度だけ呼ぶ。frontmatter 生成は章ごとに
#     走るため、色・画像の警告を各所で出すと重複する。検証はここに集約する。
#
# 検証内容:
#   - theme.color: 既定色名・HEX 以外を指定 → 警告（既定 yellow で継続）
#   - theme.frontispiece / theme.ornament: 実在しない画像名 → 警告
#     （プレースホルダー画像で代用される旨を案内）
# ================================================================

require_relative '../common'
require_relative 'frontmatter_generator'
require_relative 'theme_image_resolver'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # theme 設定の検証と著者向け警告
      module ThemeValidator
        VALID_COLORS = FrontmatterGenerator::ALLOWED_COLORS

        module_function

        # theme 設定を検証し、問題があれば警告する。
        # @param cfg [Object] Common::CONFIG 相当（省略時は Common::CONFIG）
        def validate!(cfg = Common::CONFIG)
          theme_cfg = cfg && cfg[:theme]
          return unless theme_cfg

          # color は image / simple どちらのスタイルでも使われるため常に検証する
          validate_color(theme_cfg[:color])

          # simple スタイルは扉絵・飾り画像を使わないため画像検証はスキップする
          return if theme_cfg[:style].to_s.strip.downcase == 'simple'

          validate_image(:frontispiece, frontispiece_source(theme_cfg[:frontispiece]), variant: :portrait)
          validate_image(:ornament, theme_cfg[:ornament], variant: :landscape)
        end

        # theme.color の妥当性を検証する
        def validate_color(raw)
          value = raw.to_s.strip
          return if value.empty? # 未指定は既定色（yellow）
          return if valid_color?(value)

          Common.log_warn(
            "theme.color '#{raw}' は無効な色名です。既定色（yellow）でビルドを続行します。",
            detail: "指定できる色: #{VALID_COLORS.join(' / ')}、" \
                    "または '#ff0000' のような HEX（#rrggbb / #rrggbbaa）"
          )
        end

        # theme.frontispiece / theme.ornament の画像存在を検証する
        # @param kind [:frontispiece, :ornament] 警告メッセージ用の種別
        # @param source [String, nil] 画像名（未指定・URL は検証対象外）
        # @param variant [:portrait, :landscape] 判定するバリアント
        def validate_image(kind, source, variant:)
          return if source.nil? || source.to_s.strip.empty? # 未指定は既定画像
          return if ThemeImageResolver.theme_image_available?(source, variant: variant)

          fallback = ThemeImageResolver::FALLBACK_THEME_IMAGE_SLUG
          Common.log_warn(
            "theme.#{kind} の画像 '#{source}' が見つかりません。既定画像（#{fallback}）で代用します。",
            detail: "stylesheets/images/#{source}.webp を配置するか、" \
                    'バンドル画像名（sakura・himawari など）またはスペルを確認してください。'
          )
        end

        # frontispiece 設定は String か { image: ... } の Data のため、画像名を取り出す
        def frontispiece_source(raw)
          raw.is_a?(String) ? raw : raw&.dig(:image)
        end

        # color が既定色名・各種 HEX 記法のいずれかとして受理できるか
        # （FrontmatterGenerator.parse_theme_color の受理条件と一致させる）
        def valid_color?(value)
          t = value.downcase
          return true if VALID_COLORS.include?(t)

          t.match?(/\A#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\z/i) ||
            t.match?(/\A(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})\z/i) ||
            t.match?(/\A0x(?:[0-9a-f]{6}|[0-9a-f]{8})\z/i)
        end
      end
    end
  end
end
