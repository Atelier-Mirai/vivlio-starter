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
# 検証内容（選ばれたテーマの宣言から。theme-contract-spec.md §3.3）:
#   - type: color: 既定色名・HEX 以外 → 警告（default: の色、default_from: なら従う先の色で継続）
#   - type: number: 範囲外・読めない数 → 警告（実際に組む値と、書き直し案を案内）
#   - type: enum: values: に無い値 → 警告（default: で継続）
#   - 扉絵・節絵の機能が有効なら、theme.frontispiece / theme.ornament の実在しない画像名 → 警告
#     （プレースホルダー画像で代用される旨を案内）と、機能のオプション
#
#   警告は BookSettingWarning を通す（preflight / build の最終判定に数える）。
# ================================================================

require_relative '../common'
require_relative 'book_setting_warning'
require_relative 'frontmatter_generator'
require_relative 'theme_image_resolver'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # theme 設定の検証と著者向け警告
      module ThemeValidator
        VALID_COLORS = FrontmatterGenerator::ALLOWED_COLORS

        module_function

        # theme 設定を、選ばれたテーマの宣言（theme.yml の options: と組み込みの機能）から検証し、
        # 問題があれば警告する（theme-contract-spec.md §3.3）。
        # @param cfg [Object] Common::CONFIG 相当（省略時は Common::CONFIG）
        def validate!(cfg = Common::CONFIG)
          theme_cfg = cfg && cfg[:theme]
          theme = theme_cfg && Theme.declared(cfg)
          return unless theme

          # テーマのオプションは、機能の入り切りに依らず常に検証する
          options = theme.all_options
          theme.options.each { validate_option(it, theme_cfg, options, cfg:) }

          # 機能のオプションは、機能が有効なときだけ（standard の style: simple は扉絵・節絵を使わない）。
          # 画像の有無は機能のコードの検査（§3.4）
          active = theme.active_features(cfg)
          validate_image(:frontispiece, image_source(theme_cfg[:frontispiece]), variant: :portrait) if active.include?('frontispiece')
          validate_image(:ornament, image_source(theme_cfg[:ornament]), variant: :landscape) if active.include?('ornament')
          # 機能の数のうち範囲を宣言したもの（扉絵の章リードの倍率）もここで見る。字数・長さは、値を読む
          # 機能のコード（FrontmatterGenerator）が知らせる
          active.flat_map { Theme::Features[it]::OPTIONS }.select { it.min || it.max }
                .each { validate_option(it, theme_cfg, options, cfg:) }
        end

        # オプション 1 件を、宣言の type: で検証する（書いていなければ検証しない）
        def validate_option(option, theme_cfg, options, cfg: Common::CONFIG)
          raw = Theme::Values.written(theme_cfg, option)
          return if raw.nil?

          case option.type
          when 'color' then validate_color(raw, key: option.path.join('.').to_sym, option:)
          when 'number', 'ratio' then validate_number(option, raw, options:, cfg:)
          when 'enum' then validate_enum(option, raw)
          end
        end

        # theme.lead_size / theme.frontispiece.lead_size を検証する（chapter-lead-size-spec.md §2.3）。
        # @param label [String] 警告に出すキーの名前（theme.lead_size）
        def validate_lead_size(label, raw, cfg: Common::CONFIG)
          theme = Theme.declared(cfg)
          option = theme&.all_options&.find { it.label == label }
          return unless option && !raw.to_s.strip.empty?

          validate_number(option, raw, options: theme.all_options, cfg:)
        end

        # 数・倍率のオプション。範囲の外は端へ寄せた値を、読めない値は従う先か既定値を示す。
        # 倍率（ratio）は本文に対する倍率として案内する
        def validate_number(option, raw, options:, cfg: Common::CONFIG)
          value, problem = Theme::Values.parse(option, raw)
          return if problem.nil?

          label = option.label
          key = option.key
          ratio = option.type == 'ratio'
          shown = ->(number) { "#{number}#{ratio ? ' 倍' : option.unit}" }
          case problem
          in :too_small
            # 1 未満の倍率は本文より小さい字になる（倍率は本文に対する比）
            why = ratio && raw.to_f < 1 ? 'は本文より小さくなります' : "は #{option.min} より小さい値です"
            BookSettingWarning.report("#{label} は #{option.min} 以上にしてください（#{raw} #{why}）。" \
                                      "#{shown.(value)}で組みます",
                                      detail: "book.yml: #{key}: #{raw} → #{value}")
          in :too_large
            BookSettingWarning.report("#{label} は #{option.max} 以下にしてください（#{raw} は #{option.max} より大きい値です）。" \
                                      "#{shown.(value)}で組みます",
                                      detail: "book.yml: #{key}: #{raw} → #{value}")
          in :length | :invalid
            fallback = if option.default_from then "theme.#{option.default_from} に従います"
                       else "#{shown.(Theme::Values.parse(option, option.default).first)}で組みます"
                       end
            what = ratio ? '本文に対する倍率' : '数'
            BookSettingWarning.report("#{label} は#{what}（#{option.min}〜#{option.max}）で書いてください（#{raw}）。#{fallback}",
                                      detail: "book.yml: #{key}: #{raw} → #{suggested_number(option, raw, problem, options, cfg)}")
          end
        end

        # enum のオプション。values: に無い値は既定値で組む
        def validate_enum(option, raw)
          return if option.values.include?(raw.to_s.strip.downcase)

          BookSettingWarning.report("#{option.label} '#{raw}' は選べない値です。#{option.default} で組みます",
                                    detail: "選べる値: #{option.values.join('・')}")
        end

        # 読めなかった数の書き直し案。倍率（ratio）に直接の大きさ（12pt）を書いたなら、今の判型の
        # 本文の大きさで割った倍率を示す。判型が読めないときや大きさでもない値には、既定値を例に示す
        def suggested_number(option, raw, problem, options, cfg)
          source = option.default_from ? options.find { it.path == [option.default_from.to_sym] } : option
          example = "#{source&.default} など"
          return example unless problem == :length && option.type == 'ratio'

          base_mm = Units.length_to_mm(BookSettingsCss.build_page_cfg(cfg)[:base_font_size])
          lead_mm = Units.length_to_mm(raw)
          return example unless base_mm&.positive? && lead_mm

          (lead_mm / base_mm).clamp(option.min || -Float::INFINITY, option.max || Float::INFINITY).round(2).to_s
        rescue StandardError
          example
        end

        # 色のオプションの妥当性を検証する。default_from: のオプション（前書き・付録の色）は、
        # 読めなければ従う先の色になる（書かなかったときと同じ）
        # @param key [Symbol] 警告に出すキー
        # @param option [Theme::Option, nil] 宣言（無ければ theme.color と同じ扱い）
        def validate_color(raw, key: :color, option: nil)
          value = raw.to_s.strip
          return if value.empty? # 未指定は既定色（default_from: なら従う先の色）
          return if valid_color?(value)

          from = option ? option.default_from : (key == :color ? nil : 'color')
          default = option&.default || ThemeColor::DEFAULT_NAME
          fallback = from ? "theme.#{from} と同じ色" : "既定色（#{default}）"
          BookSettingWarning.report(
            "theme.#{key} '#{raw}' は無効な色名です。#{fallback}でビルドを続行します。",
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
          BookSettingWarning.report(
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

        # 色のオプションとして受理できるか（既定色名・各種 HEX 記法・12 色の var()。Theme::Values.color? と同じ）
        def valid_color?(value) = Theme::Values.color?(value.to_s.strip)
      end
    end
  end
end
