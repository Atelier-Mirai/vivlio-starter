# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/css_updater.rb
# ================================================================
# 責務（P3 以降）:
#   ビルド設定 CSS の「値計算」と vivliostyle.config.js の同期を担う。
#
#   かつては theme.css / page-settings.css 等のソース CSS を毎ビルド正規表現で
#   in-place 書換していたが、それはソース CSS を可変化させテーマ CSS セットの
#   差し替えを阻んだ。P3（課題 C）でその書換を全廃し、設定値は
#   BookSettingsCss 生成器が `.cache/vs/book-settings.css` へ全文書き出す。
#   本モジュールは生成器が使う実証済みの値計算ロジック（用紙スケール・行長・
#   ノンブル配置・綴じオフセット・フォントスタック整形・色正規化・CSS 変数
#   マッピング）と、@page size / title を JS 設定へ書く config.js 同期のみを残す。
#
# 提供する値計算 API（BookSettingsCss から利用）:
#   - calculate_paper_scale / calculate_align_max_width /
#     calculate_frontispiece_binding_offset / apply_folio_placement!
#   - format_font_value / normalize_color_value / build_css_variable_mappings
#
# config.js 同期（P3-4: JS ファイルは書換のまま維持）:
#   - sync_vivliostyle_config_size! / sync_vivliostyle_config_title!
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # CSS 値計算・config.js 同期モジュール
      module CssUpdater
        ALLOWED_COLORS = %w[yellow orange red magenta purple indigo navy blue cyan teal green lime].freeze

        module_function

        # vivliostyle.config.js の size プロパティを book.yml のページ設定に同期する
        def sync_vivliostyle_config_size!(width, height, size_name = nil)
          config_path = Common::VIVLIOSTYLE_CONFIG_FILE
          return unless File.exist?(config_path)

          # サイズ文字列を決定（'A5', 'B5', 'A4' またはカスタム寸法）
          new_size = if size_name && !size_name.to_s.strip.empty?
                       size_name.to_s.strip.upcase
                     else
                       "#{width} #{height}"
                     end

          content = File.read(config_path, encoding: 'utf-8')

          if content.match?(/^\s*size:\s/)
            # 既存の size プロパティを更新
            updated = content.sub(/^(\s*size:\s*)'[^']*'/, "\\1'#{new_size}'")
            updated = updated.sub(/^(\s*size:\s*)"[^"]*"/, "\\1'#{new_size}'") if updated == content
          else
            # size プロパティが存在しない場合、language の後に挿入
            updated = content.sub(
              %r{^(\s*language:\s*'[^']*',\s*//[^\n]*\n)},
              "\\1  size: '#{new_size}', // ページサイズ（book.yml のプリセットから自動設定）\n"
            )
          end

          return if updated == content

          File.write(config_path, updated)
          Common.log_success("vivliostyle.config.js の size を '#{new_size}' に同期しました")
        rescue StandardError => e
          Common.log_warn("vivliostyle.config.js の size 同期に失敗: #{e.message}")
        end

        # vivliostyle.config.js の title を book.yml の main_title + subtitle に同期する
        #
        # PDF の文書タイトル（メタデータ）は vivliostyle.config.js の title から設定される。
        # book.yml に title キーがあればそれを優先し、なければ main_title と subtitle を結合する。
        def sync_vivliostyle_config_title!
          config_path = Common::VIVLIOSTYLE_CONFIG_FILE
          return unless File.exist?(config_path)

          book = Common::CONFIG.book
          title_raw = book.title
          main_title = book.main_title.to_s.strip
          subtitle = book.subtitle.to_s.strip

          new_title = if title_raw && !title_raw.to_s.strip.empty?
                        title_raw.to_s.strip
                      elsif !main_title.empty?
                        [main_title, subtitle].reject(&:empty?).join(' ')
                      else
                        return
                      end

          esc_title = new_title.gsub('\\', '\\\\').gsub("'", "\\'")
          content = File.read(config_path, encoding: 'utf-8')
          updated = content.sub(/^(\s*title:\s*)'[^']*'/, "\\1'#{esc_title}'")
          updated = updated.sub(/^(\s*title:\s*)"[^"]*"/, "\\1'#{esc_title}'") if updated == content

          return if updated == content

          File.write(config_path, updated)
          Common.log_success("vivliostyle.config.js の title を '#{new_title}' に同期しました")
        rescue StandardError => e
          Common.log_warn("vivliostyle.config.js の title 同期に失敗: #{e.message}")
        end

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
