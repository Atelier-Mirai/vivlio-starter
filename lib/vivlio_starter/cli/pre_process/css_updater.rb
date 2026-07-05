# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/css_updater.rb
# ================================================================
# 責務（P3-4 以降）:
#   ビルド設定 CSS の「値計算」専業モジュール。
#
#   かつては theme.css / page-settings.css 等のソース CSS を毎ビルド正規表現で
#   in-place 書換していたが、それはソース CSS を可変化させテーマ CSS セットの
#   差し替えを阻んだ。P3（課題 C）でその書換を全廃し、設定値は
#   BookSettingsCss 生成器が `.cache/vs/book-settings.css` へ全文書き出す。
#   さらに P3-4 で vivliostyle.config.js の size/title 正規表現同期も全廃し
#   （Build::VivliostyleConfigWriter による全文生成へ移行）、本モジュールは
#   生成器が使う実証済みの値計算ロジック（用紙スケール・行長・ノンブル配置・
#   綴じオフセット・フォントスタック整形・色正規化・CSS 変数マッピング）のみを残す。
#
# 提供する値計算 API（BookSettingsCss から利用）:
#   - calculate_paper_scale / calculate_align_max_width /
#     calculate_frontispiece_binding_offset / apply_folio_placement!
#   - format_font_value / normalize_color_value / build_css_variable_mappings
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # CSS 値計算・config.js 同期モジュール
      module CssUpdater
        ALLOWED_COLORS = %w[yellow orange red magenta purple indigo navy blue cyan teal green lime].freeze

        module_function

        # 色値を正規化（色名 or HEX）
        def normalize_color_value(raw_value, fallback: 'var(--accent-yellow)')
          raw_string = raw_value.to_s.strip
          return fallback if raw_string.empty?

          normalized = raw_string.downcase

          # HEX形式のチェック
          if normalized.match?(/^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/)
            raw_string.start_with?('#') ? raw_string : "##{normalized.sub(/^#/, '')}"
          elsif normalized.match?(/^(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/)
            "##{normalized}"
          elsif normalized.match?(/^0x(?:[0-9a-f]{6}|[0-9a-f]{8})$/)
            "##{normalized.sub(/^0x/, '')}"
          elsif normalized.start_with?('var(')
            raw_string
          elsif ALLOWED_COLORS.include?(normalized)
            "var(--accent-#{normalized})"
          else
            Common.log_warn("認識できない色: '#{raw_value}'。フォールバックを使用します。")
            fallback
          end
        end

        # .align-left / .align-center / .align-right ブロックの最大行長を算出する。
        # Vivliostyle は `min(26em, max-content)` のような比較関数を未対応のため、
        # CSS カスタムプロパティ `--align-max-width` として判型別に上書きする。
        # 詳細は docs/specs/vivliostyle_warnings_spec.md 参照。
        # 用紙幅 mm から判型を推定し、A5=26em / B5=36em / A4=40em を返す。
        def calculate_align_max_width(width)
          w_mm = Units.length_to_mm(width) || 0
          return '40em' unless w_mm.positive?
          return '26em' if w_mm <= 155 # A5 相当（148mm）
          return '36em' if w_mm <= 190 # B5 相当（JIS 182mm / ISO 176mm）

          '40em'                       # A4 以上
        end

        # 用紙スケールを算出（A4基準）
        def calculate_paper_scale(width, height)
          a4_w_mm = 210.0
          a4_h_mm = 297.0
          w_mm = Units.length_to_mm(width) || 0
          h_mm = Units.length_to_mm(height) || 0

          return 1.0 unless w_mm.positive? && h_mm.positive?

          scale_w = w_mm / a4_w_mm
          scale_h = h_mm / a4_h_mm
          paper_scale = [scale_w, scale_h].min

          # 0.5〜1.0 の安全域に丸める
          paper_scale.clamp(0.5, 1.0).round(4)
        end

        def calculate_frontispiece_binding_offset(margin_inner, margin_outer)
          inner_mm = Units.length_to_mm(margin_inner) || 0
          outer_mm = Units.length_to_mm(margin_outer) || 0
          diff = inner_mm - outer_mm
          return '0mm' unless diff.positive?

          offset = diff / 2.0
          format('%<value>.2fmm', value: offset.round(2))
        rescue StandardError
          '0mm'
        end

        # ノンブル配置を適用
        def apply_folio_placement!(page_cfg)
          placement = page_cfg[:folio_placement].to_s.strip.downcase
          placement = 'center' unless %w[center sides].include?(placement)

          case placement
          when 'center'
            page_cfg[:folio_center] = 'counter(page)'
            page_cfg[:folio_left]   = 'none'
            page_cfg[:folio_right]  = 'none'
            Common.log_info('ノンブル配置: 中央')
          when 'sides'
            page_cfg[:folio_center] = 'none'
            page_cfg[:folio_left]   = 'counter(page)'
            page_cfg[:folio_right]  = 'counter(page)'
            Common.log_info('ノンブル配置: 左右')
          end
        end

        # フォント変数ごとの generic フォールバック。
        # フォント非埋め込みの EPUB でも 明朝=serif / ゴシック=sans-serif /
        # コード=monospace の category がリーダー側で保たれるようにする。
        # PDF では実体フォントが常に在るため不発（無害）。
        FONT_GENERIC_FALLBACKS = {
          '--font-main-text' => 'serif',
          '--font-header'    => 'sans-serif',
          '--font-code'      => 'monospace',
          '--font-column'    => 'sans-serif',
          '--font-folio'     => 'sans-serif'
        }.freeze

        # Zen フォント非収録の記号（▶ ⁵ 等）は Chromium が OS フォントへフォールバックし、
        # Chrome 149 がそれを Type 3 フォントで埋め込む。これを防ぐため、記号被覆の広い
        # 同梱 HackGen35 Console NF（Regular/Bold 両字面）を generic の前に挟む。
        # --font-code は既にこのフォントのため対象外。
        FONT_TYPE3_FALLBACK = '"HackGen35 Console NF"'
        FONT_TYPE3_FALLBACK_TARGETS = %w[
          --font-main-text --font-header --font-column --font-folio
        ].freeze

        # :font 型の CSS 変数値を整形する。
        # 単一ファミリ名はクォートし、Type 3 回避フォールバック（HackGen35 Console NF）と
        # 変数に対応する generic フォールバックを付与する。
        # book.yml 側で既にカンマ区切り（独自フォールバック）が指定されている場合は尊重する。
        #
        # @param name [String] CSS 変数名（例: '--font-code'）
        # @param value [String] book.yml 由来のフォント値
        # @param kind [Symbol, nil] :font のときのみ整形する
        # @return [String]
        def format_font_value(name, value, kind)
          return value unless kind == :font
          return value if value.include?(',') # 既に独自フォールバック指定あり

          quoted = value =~ /\A".*"\z/ ? value : "\"#{value}\""
          stack = [quoted]
          stack << FONT_TYPE3_FALLBACK if FONT_TYPE3_FALLBACK_TARGETS.include?(name)
          stack << FONT_GENERIC_FALLBACKS[name] if FONT_GENERIC_FALLBACKS[name]
          stack.join(', ')
        end

        # CSS変数マッピングを構築
        def build_css_variable_mappings(page_cfg)
          [
            ['--page-width',            page_cfg[:width]],
            ['--page-height',           page_cfg[:height]],
            ['--paper-scale',           page_cfg[:paper_scale]],
            ['--align-max-width',       page_cfg[:align_max_width]],
            ['--base-font-size',        page_cfg[:base_font_size]],
            ['--base-line-height',      page_cfg[:base_line_height]],
            ['--letter-spacing',        page_cfg[:letter_spacing] || '0em'],
            ['--page-margin-top',       page_cfg[:margin_top]],
            ['--page-margin-bottom',    page_cfg[:margin_bottom]],
            ['--page-margin-inner',     page_cfg[:margin_inner]],
            ['--page-margin-outer',     page_cfg[:margin_outer]],
            ['--frontispiece-binding-offset', page_cfg[:frontispiece_binding_offset]],
            ['--column-font-size',      page_cfg[:column_font_size]],
            ['--folio-font-size',       page_cfg[:folio_font_size]],
            ['--font-main-text',        page_cfg[:main_text_font],  :font],
            ['--font-header',           page_cfg[:header_font],     :font],
            ['--font-code',             page_cfg[:code_font],       :font],
            ['--font-column',           page_cfg[:column_font],     :font],
            ['--font-folio',            page_cfg[:folio_font],      :font],
            ['--folio-center-content',  page_cfg[:folio_center]],
            ['--folio-left-content',    page_cfg[:folio_left]],
            ['--folio-right-content',   page_cfg[:folio_right]]
          ]
        end
      end
    end
  end
end
