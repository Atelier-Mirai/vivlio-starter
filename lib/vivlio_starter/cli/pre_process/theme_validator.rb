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
#   - theme.color: 既定色名・HEX 以外を指定 → 警告（既定色 ThemeColor::DEFAULT_NAME で継続）
#   - theme.frontispiece / theme.ornament: 実在しない画像名 → 警告
#     （プレースホルダー画像で代用される旨を案内）
#   - theme.lead_size / theme.frontispiece.lead_size: 範囲外・読めない倍率 → 警告
#     （実際に組む値と、書き直し案を案内）
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

          # color とリードの倍率は image / simple どちらのスタイルでも使われるため常に検証する
          validate_color(theme_cfg[:color])
          validate_lead_size('theme.lead_size', theme_cfg[:lead_size], cfg:)

          # simple スタイルは扉絵・飾り画像を使わないため画像検証はスキップする
          return if theme_cfg[:style].to_s.strip.downcase == 'simple'

          validate_image(:frontispiece, image_source(theme_cfg[:frontispiece]), variant: :portrait)
          validate_image(:ornament, image_source(theme_cfg[:ornament]), variant: :landscape)
          validate_lead_size('theme.frontispiece.lead_size', frontispiece_lead_size(theme_cfg[:frontispiece]), cfg:)
        end

        # theme.lead_size / theme.frontispiece.lead_size を検証する（chapter-lead-size-spec.md §2.3）。
        # 読み方は FrontmatterGenerator.parse_lead_size と共有し、実際に組む値をそのまま案内する。
        # @param label [String] 警告に出すキーの名前（省略しない）
        def validate_lead_size(label, raw, cfg: Common::CONFIG)
          ratio, problem = FrontmatterGenerator.parse_lead_size(raw)
          return if problem.nil?

          key = label.split('.').last
          range = FrontmatterGenerator::LEAD_SIZE_RANGE
          fallback = if label == 'theme.lead_size'
                       "#{BookSettingsCss::DEFAULT_LEAD_SIZE} 倍で組みます"
                     else
                       'theme.lead_size に従います'
                     end

          case problem
          in :too_small
            Common.log_warn("#{label} は #{range.min} 以上にしてください（#{raw} は本文より小さくなります）。" \
                            "#{ratio} 倍で組みます",
                            detail: "book.yml: #{key}: #{raw} → #{ratio}\n" \
                                    'リードが章扉に収まらないときは、リードを縮めてください')
          in :too_large
            Common.log_warn("#{label} は #{range.max} 以下にしてください（#{raw} は章題と張り合う大きさです）。" \
                            "#{ratio} 倍で組みます",
                            detail: "book.yml: #{key}: #{raw} → #{ratio}")
          in :length | :invalid
            Common.log_warn("#{label} は本文に対する倍率（#{range.min}〜#{range.max}）で書いてください（#{raw}）。#{fallback}",
                            detail: "book.yml: #{key}: #{raw} → #{suggested_lead_size(raw, problem, cfg)}")
          end
        end

        # 読めなかった倍率の書き直し案。直接の大きさ（12pt）なら、今の判型の本文の大きさで割った
        # 倍率を示す。判型が読めないときや大きさでもない値には、範囲の中の例を示す。
        def suggested_lead_size(raw, problem, cfg)
          example = "#{BookSettingsCss::DEFAULT_LEAD_SIZE} など"
          return example unless problem == :length

          base_mm = Units.length_to_mm(BookSettingsCss.build_page_cfg(cfg)[:base_font_size])
          lead_mm = Units.length_to_mm(raw)
          return example unless base_mm&.positive? && lead_mm

          (lead_mm / base_mm).clamp(FrontmatterGenerator::LEAD_SIZE_RANGE).round(2).to_s
        rescue StandardError
          example
        end

        # 章扉のリードの倍率。frontispiece が画像名だけの短縮形なら書かれていない
        def frontispiece_lead_size(raw)
          raw.is_a?(String) || raw.is_a?(Symbol) ? nil : raw&.dig(:lead_size)
        end

        # theme.color の妥当性を検証する
        def validate_color(raw)
          value = raw.to_s.strip
          return if value.empty? # 未指定は既定色
          return if valid_color?(value)

          Common.log_warn(
            "theme.color '#{raw}' は無効な色名です。既定色（#{ThemeColor::DEFAULT_NAME}）でビルドを続行します。",
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

        # frontispiece / ornament は「スカラー＝画像名だけの短縮形」と
        # 「マッピング＝画像名＋寸法（heading_chars 等）」の両方を受けるため、画像名を取り出す。
        # スカラーのまま Data を渡すと画像名の代わりに `#<data …>` を検証して必ず警告になる。
        def image_source(raw)
          raw.is_a?(String) || raw.is_a?(Symbol) ? raw : raw&.dig(:image)
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
