# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/css_updater.rb
# ================================================================
# 責務:
#   テーマ設定に基づいて CSS ファイルのカスタムプロパティを更新する。
#
# 更新対象ファイル:
#   - stylesheets/theme.css: テーマカラー・扉絵・飾り画像
#   - stylesheets/appendix.css: 付録用スタイル
#   - stylesheets/preface.css: 前書き用スタイル
#   - stylesheets/chapter.css: 章共通スタイル
#   - stylesheets/page-settings.css: ページサイズ・余白
#
# 更新する CSS カスタムプロパティ:
#   - --theme-accent: アクセントカラー
#   - --frontispiece-image: 扉絵画像 URL
#   - --ornament-image: 飾り画像 URL
#   - --page-width, --page-height: ページサイズ
# ================================================================

require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # CSS ファイル更新モジュール
        module CssUpdater
          ALLOWED_COLORS = %w[yellow orange red magenta purple indigo navy blue cyan teal green lime].freeze

          module_function

          # 安全なCSS更新処理
          # ファイルの読み込み→変換→書き込みを行い、失敗時にファイルを空にしないようガード
          def safe_css_update(path, &block)
            return unless File.exist?(path)

            original_content = File.read(path, encoding: 'utf-8')
            updated_content = block.call(original_content)

            # 変更がない、または空になってしまう場合は書き込まない
            if updated_content.nil? || updated_content.strip.empty?
              Common.log_warn("CSS更新がスキップされました（空の内容）: #{path}")
              return false
            end

            return false if updated_content == original_content

            File.write(path, updated_content, encoding: 'utf-8')
            true
          rescue StandardError => e
            Common.log_error("CSS更新に失敗: #{path} - #{e.message}")
            false
          end

          # theme.css を更新
          def update_theme_css(theme_name:, theme_accent_value:, theme_style:, frontispiece_path:,
                               door_padding_value:, ornament_path:, heading_width_value: nil,
                               lead_width_value: nil)
            theme_css_path = File.join(Common::STYLESHEETS_DIR, 'theme.css')

            unless File.exist?(theme_css_path)
              Common.log_error("theme.css が見つかりません: #{theme_css_path}")
              return
            end

            css = File.read(theme_css_path, encoding: 'utf-8')
            if css.strip.empty?
              Common.log_error("theme.css が空です: #{theme_css_path}")
              return
            end

            updated = css.dup

            # --theme-accent を更新
            updated = updated.sub(/(--theme-accent:\s*)[^;]+(\s*;)/) do
              "#{::Regexp.last_match(1)}#{theme_accent_value}#{::Regexp.last_match(2)}"
            end

            # 強調色・強意の下線色もテーマアクセントに追従
            updated = updated.sub(/(--color-strong:\s*)[^;]+(\s*;)/, '\\1var(--theme-accent)\\2')
            updated = updated.sub(/(--color-em-underline:\s*)[^;]+(\s*;)/, '\\1var(--theme-accent)\\2')

            if theme_style == 'simple'
              # 画像を使わないシンプルスタイル
              updated = updated.sub(/(--section-bg-image:\s*)[^;]+(\s*;)/, '\\1none\\2')
              updated = updated.sub(/(--frontispiece-image:\s*)[^;]+(\s*;)/, '\\1none\\2')
            else
              # 画像ありスタイル
              # ornament の指定があればそれを優先
              if ornament_path
                ornament_value = ornament_path.start_with?('url(') ? ornament_path : "url(\"#{ornament_path}\")"
                updated = updated.sub(/(--section-bg-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                  "#{::Regexp.last_match(1)}#{ornament_value}#{::Regexp.last_match(2)}"
                end
              else
                # ornament 未指定時は既定の frame-yellow.webp を使用
                updated = updated.sub(/(--section-bg-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                  "#{::Regexp.last_match(1)}url(\"images/frame-yellow.webp\")#{::Regexp.last_match(2)}"
                end
              end

              # frontispiece_path を CSS の url(...) 形式で設定
              door_value = frontispiece_path.start_with?('url(') ? frontispiece_path : "url(\"#{frontispiece_path}\")"
              updated = updated.sub(/(--frontispiece-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                "#{::Regexp.last_match(1)}#{door_value}#{::Regexp.last_match(2)}"
              end

              updated = updated.sub(/(--frontispiece-padding:\s*)[^;]+(\s*;)/) do
                "#{::Regexp.last_match(1)}#{door_padding_value}#{::Regexp.last_match(2)}"
              end
            end

            if heading_width_value
              updated = updated.sub(/(--frontispiece-heading-width:\s*)[^;]+(\s*;)/) do
                "#{::Regexp.last_match(1)}#{heading_width_value}#{::Regexp.last_match(2)}"
              end
            end

            if lead_width_value
              updated = updated.sub(/(--frontispiece-lead-width:\s*)[^;]+(\s*;)/) do
                "#{::Regexp.last_match(1)}#{lead_width_value}#{::Regexp.last_match(2)}"
              end
            end

            if updated == css
              Common.log_info('theme.css: 更新不要（変更なし）')
              return
            end

            File.write(theme_css_path, updated, encoding: 'utf-8')
            Common.log_success("theme.css を更新: theme=#{theme_name}, style=#{theme_style}")
          rescue StandardError => e
            Common.log_error("theme.css の更新に失敗: #{e.message}")
          end

          # appendix.css の付録専用色を更新
          def update_appendix_css(appendix_color:, theme_accent_value:)
            appendix_css_path = File.join(Common::STYLESHEETS_DIR, 'appendix.css')
            return unless File.exist?(appendix_css_path)

            changed = safe_css_update(appendix_css_path) do |css|
              # appendix_color が指定されている場合のみ更新
              next css if appendix_color.to_s.strip.empty?

              # 色名または HEX として解釈
              appendix_accent_value = normalize_color_value(appendix_color, fallback: theme_accent_value)

              # --appendix-accent-color を更新
              css.sub(/(--appendix-accent-color:\s*)[^;]+(\s*;)/) do
                "#{::Regexp.last_match(1)}#{appendix_accent_value}#{::Regexp.last_match(2)}"
              end
            end

            Common.log_success("appendix.css を更新: appendix_color=#{appendix_color}") if changed
          rescue StandardError => e
            Common.log_warn("appendix.css の更新に失敗: #{e.message}")
          end

          # preface.css の前書き専用色を更新
          def update_preface_css(preface_color:, theme_accent_value:)
            preface_css_path = File.join(Common::STYLESHEETS_DIR, 'preface.css')
            return unless File.exist?(preface_css_path)

            using_theme_color = preface_color.to_s.strip.empty?
            preface_accent_value = normalize_color_value(preface_color, fallback: theme_accent_value)

            changed = safe_css_update(preface_css_path) do |css|
              result = css.sub(/(--color-preface-accent:\s*)[^;]+(\s*;)/) do
                "#{::Regexp.last_match(1)}#{preface_accent_value}#{::Regexp.last_match(2)}"
              end
              # デバッグ: 変換結果を確認
              if result.strip.empty?
                Common.log_warn("CSS変換結果が空です。元のCSS長: #{css.length}, 正規表現マッチ: #{css =~ /(--color-preface-accent:\s*)[^;]+(\s*;)/}")
              end
              result
            end

            if changed
              log_color = using_theme_color ? 'theme.color (fallback)' : preface_color.to_s.strip
              Common.log_success("preface.css を更新: preface_color=#{log_color} => #{preface_accent_value}")
            else
              Common.log_info("preface.css: 更新不要または変更なし (適用値 #{preface_accent_value})")
            end
          rescue StandardError => e
            Common.log_warn("preface.css の更新に失敗: #{e.message}")
            Common.log_warn("  スタックトレース: #{e.backtrace.first(3).join("\n  ")}")
          end

          # chapter.css のヘッダ import を theme.style に連動して切替
          def update_chapter_css(theme_style:)
            chapter_css_path = File.join(Common::STYLESHEETS_DIR, 'chapter.css')
            return unless File.exist?(chapter_css_path)

            ccss = File.read(chapter_css_path, encoding: 'utf-8')
            desired = theme_style == 'image' ? 'image-header.css' : 'simple-header.css'

            if ccss.include?('@import url("simple-header.css");') || ccss.include?('@import url("image-header.css");')
              updated = ccss
                        .sub(/@import\s+url\("simple-header\.css"\);/, "@import url(\"#{desired}\");")
                        .sub(/@import\s+url\("image-header\.css"\);/, "@import url(\"#{desired}\");")

              if updated == ccss
                Common.log_info("chapter.css のヘッダーimportは既に最新です: #{desired}")
              else
                File.write(chapter_css_path, updated, encoding: 'utf-8')
                Common.log_success("chapter.css のヘッダーimportを切替: #{desired}")
              end
            else
              # importが存在しない場合は追加
              insert_point = begin
                ccss.index(';', ccss.index('@import')).to_i + 1
              rescue StandardError
                0
              end
              insert_point = ccss.index("\n", insert_point).to_i + 1
              insert_point = 0 if insert_point.negative?
              header_import = "@import url(\"#{desired}\");\n"
              updated = ccss.dup.insert(insert_point, header_import)
              File.write(chapter_css_path, updated, encoding: 'utf-8')
              Common.log_success("chapter.css にヘッダーimportを追加: #{desired}")
            end
          rescue StandardError => e
            Common.log_warn("chapter.css の更新に失敗: #{e.message}")
          end

          # chapter-common.css の章・付録共通マーカー（h3/h4）を設定
          def update_chapter_common_css(markers:)
            chapter_common_css_path = File.join(Common::STYLESHEETS_DIR, 'chapter-common.css')
            return unless File.exist?(chapter_common_css_path)

            mark_h3 = markers['h3'].to_s
            mark_h4 = markers['h4'].to_s

            mark_h3 = '♣' if mark_h3.strip.empty?
            mark_h4 = '♦' if mark_h4.strip.empty?

            changed = safe_css_update(chapter_common_css_path) do |css|
              # マーカーをエスケープして正規表現置換
              esc_h3 = mark_h3.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
              esc_h4 = mark_h4.gsub('\\', '\\\\\\\\').gsub('"', '\\"')

              # 正規表現を修正：絵文字などの複数バイト文字にも対応
              css = css.sub(/(--h3-marker:\s*)"[^"]*"(\s*;)/, "\\1\"#{esc_h3}\"\\2")
              css = css.sub(/(--h4-marker:\s*)"[^"]*"(\s*;)/, "\\1\"#{esc_h4}\"\\2")
              css
            end

            if changed
              Common.log_success("chapter-common.css にマーカーを反映: h3='#{mark_h3}', h4='#{mark_h4}'")
            else
              Common.log_info('theme.markers による変更はありません（既存定義を維持）')
            end
          rescue StandardError => e
            Common.log_warn("chapter-common.css のマーカー更新に失敗: #{e.message}")
          end

          # page-settings.css の各種変数を反映
          def update_page_settings_css(page_cfg:, typo_cfg:)
            # typography セクションからフォント設定を読み込み、page_cfg にマージ
            page_cfg[:main_text_font]   = typo_cfg&.dig(:body, :font)
            page_cfg[:header_font]      = typo_cfg&.dig(:heading, :font)
            page_cfg[:column_font]      = typo_cfg&.dig(:column, :font)
            page_cfg[:code_font]        = typo_cfg&.dig(:code, :font)
            page_cfg[:folio_font]       = typo_cfg&.dig(:folio, :font)
            page_cfg[:column_font_size] = typo_cfg&.dig(:column, :font_size)
            page_cfg[:folio_placement]  = typo_cfg&.dig(:folio, :placement)

            # 紙サイズを正規化
            Common.normalize_page_size!(page_cfg)

            # 用紙スケールを算出（A4=1.0 基準）
            page_cfg[:paper_scale] = calculate_paper_scale(page_cfg[:width], page_cfg[:height])

            # .align-* ブロックの最大行長を算出（A5=26em, B5=36em, A4=40em）
            page_cfg[:align_max_width] = calculate_align_max_width(page_cfg[:width])

            # ノンブル配置
            apply_folio_placement!(page_cfg)

            page_cfg[:frontispiece_binding_offset] = calculate_frontispiece_binding_offset(
              page_cfg[:margin_inner], page_cfg[:margin_outer]
            )

            # CSS変数マッピング
            mappings = build_css_variable_mappings(page_cfg)

            # 更新対象のCSSファイル
            candidates = [
              File.join(Common::STYLESHEETS_DIR, 'page-settings.css'),
              File.join('awesomebook', 'stylesheets', 'page-settings.css')
            ].uniq

            candidates.each do |css_path|
              next unless File.exist?(css_path)

              changed = safe_css_update(css_path) do |css|
                updated = css.dup
                mappings.each do |name, val, kind|
                  next if val.nil? || val.to_s.strip.empty?

                  v = val.to_s.strip
                  v = "\"#{v}\"" if (kind == :font) && !v.include?(',') && v !~ /^\s*".*"\s*$/

                  updated = updated.sub(/(#{Regexp.escape(name)}:\s*)[^;]+(\s*;)/) do
                    "#{::Regexp.last_match(1)}#{v}#{::Regexp.last_match(2)}"
                  end
                end
                updated
              end

              # @page { size } をリテラル値で更新（var() は @page size で使用不可）
              changed2 = safe_css_update(css_path) do |css|
                w = page_cfg[:width].to_s.strip
                h = page_cfg[:height].to_s.strip
                next css if w.empty? || h.empty?

                css.sub(/(@page\s*\{[^}]*?\bsize:\s*)[^;]+(;)/) do
                  "#{::Regexp.last_match(1)}#{w} #{h}#{::Regexp.last_match(2)}"
                end
              end

              if changed || changed2
                Common.log_success("#{File.basename(css_path)} を更新: #{css_path}")
              else
                Common.log_info("#{File.basename(css_path)} に適用すべき差分はありません")
              end
            end
            # vivliostyle.config.js の size プロパティも同期
            sync_vivliostyle_config_size!(page_cfg[:width], page_cfg[:height], page_cfg[:size])
            # vivliostyle.config.js の title プロパティも同期
            sync_vivliostyle_config_title!
          rescue StandardError => e
            Common.log_warn("page-settings.css の更新に失敗: #{e.message}")
          end

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

            cfg = Common::CONFIG
            book = cfg[:book] || cfg['book'] || {}
            title_raw = book[:title] || book['title']
            main_title = (book[:main_title] || book['main_title']).to_s.strip
            subtitle = (book[:subtitle] || book['subtitle']).to_s.strip

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
            w_mm = parse_to_mm(width)
            return '40em' unless w_mm.positive?
            return '26em' if w_mm <= 155 # A5 相当（148mm）
            return '36em' if w_mm <= 190 # B5 相当（JIS 182mm / ISO 176mm）

            '40em'                       # A4 以上
          end

          # 用紙スケールを算出（A4基準）
          def calculate_paper_scale(width, height)
            a4_w_mm = 210.0
            a4_h_mm = 297.0
            w_mm = parse_to_mm(width)
            h_mm = parse_to_mm(height)

            return 1.0 unless w_mm.positive? && h_mm.positive?

            scale_w = w_mm / a4_w_mm
            scale_h = h_mm / a4_h_mm
            paper_scale = [scale_w, scale_h].min

            # 0.5〜1.0 の安全域に丸める
            paper_scale.clamp(0.5, 1.0).round(4)
          end

          # CSS長さ文字列をmm単位に変換
          def parse_to_mm(val)
            s = val.to_s.strip
            if (m = s.match(/^([0-9]+(?:\.[0-9]+)?)\s*(mm|pt)$/i))
              num = m[1].to_f
              unit = m[2].downcase
              unit == 'pt' ? (num * 0.3527777778) : num
            else
              s.to_f
            end
          end

          def calculate_frontispiece_binding_offset(margin_inner, margin_outer)
            inner_mm = parse_to_mm(margin_inner)
            outer_mm = parse_to_mm(margin_outer)
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
end
