# frozen_string_literal: true

require 'yaml'
require_relative '../common'
require_relative '../font_manager'
require_relative 'css_updater'
require_relative 'theme_image_resolver'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # フロントマター生成・更新処理を担当するモジュール
        module FrontmatterGenerator
          ALLOWED_COLORS = %w[yellow amber orange peach coral red magenta plum purple indigo navy blue cyan teal mint green lime].freeze

          module_function

          # CSS更新のみを実行（ビルド時にStep 2で呼ばれる）
          def update_css_only!(cfg = nil)
            cfg ||= Common::CONFIG
            theme_cfg = (cfg && cfg['theme']) || {}
            
            # テーマカラーを決定
            theme_name, theme_accent_value = parse_theme_color(theme_cfg['color'])
            
            # テーマスタイルを決定（simple または image）
            theme_style = parse_theme_style(theme_cfg['style'])
            
            # frontispiece 設定を解析
            frontispiece_raw = theme_cfg['frontispiece']
            frontispiece_cfg = frontispiece_raw.is_a?(Hash) ? frontispiece_raw : {}
            frontispiece_source = frontispiece_cfg.key?('image') ? frontispiece_cfg['image'] : frontispiece_raw
            frontispiece_path = ThemeImageResolver.resolve_frontispiece_path(frontispiece_source, allow_generation: true)
            
            # CSS長さ値を正規化
            door_padding_value = normalize_css_length(frontispiece_cfg['padding'], label: 'theme.frontispiece.padding', default: '0mm')
            heading_width_value = normalize_css_length(frontispiece_cfg['heading_width'], label: 'theme.frontispiece.heading_width')
            lead_width_value = normalize_css_length(frontispiece_cfg['lead_width'], label: 'theme.frontispiece.lead_width')
            
            # ornament 設定を解析
            ornament_path = ThemeImageResolver.resolve_ornament_path(theme_cfg['ornament'], allow_generation: true)
            
            # 各CSSファイルを更新
            update_all_css_files(
              theme_name: theme_name,
              theme_accent_value: theme_accent_value,
              theme_style: theme_style,
              theme_cfg: theme_cfg,
              frontispiece_path: frontispiece_path,
              door_padding_value: door_padding_value,
              heading_width_value: heading_width_value,
              lead_width_value: lead_width_value,
              ornament_path: ornament_path
            )

            Common.log_success('[Step 2] CSS設定を更新しました')
          rescue StandardError => e
            Common.log_warn("[Step 2] CSS更新に失敗: #{e.message}")
          end

          # フロントマターを生成
          def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
            # テーマ設定を取得
            cfg = Common::CONFIG
            theme_cfg = (cfg && cfg['theme']) || {}
            
            # テーマカラーを決定
            theme_name, theme_accent_value = parse_theme_color(theme_cfg['color'])
            
            # テーマスタイルを決定（simple または image）
            theme_style = parse_theme_style(theme_cfg['style'])
            
            # frontispiece 設定を解析
            frontispiece_raw = theme_cfg['frontispiece']
            frontispiece_cfg = frontispiece_raw.is_a?(Hash) ? frontispiece_raw : {}
            frontispiece_source = frontispiece_cfg.key?('image') ? frontispiece_cfg['image'] : frontispiece_raw
            frontispiece_path = ThemeImageResolver.resolve_frontispiece_path(frontispiece_source, allow_generation: true)
            
            # CSS長さ値を正規化
            door_padding_value = normalize_css_length(frontispiece_cfg['padding'], label: 'theme.frontispiece.padding', default: '0mm')
            heading_width_value = normalize_css_length(frontispiece_cfg['heading_width'], label: 'theme.frontispiece.heading_width')
            lead_width_value = normalize_css_length(frontispiece_cfg['lead_width'], label: 'theme.frontispiece.lead_width')
            
            # ornament 設定を解析（cinema バリアント生成を許可）
            ornament_path = ThemeImageResolver.resolve_ornament_path(theme_cfg['ornament'], allow_generation: true)
            
            # 各CSSファイルを更新
            update_all_css_files(
              theme_name: theme_name,
              theme_accent_value: theme_accent_value,
              theme_style: theme_style,
              theme_cfg: theme_cfg,
              frontispiece_path: frontispiece_path,
              door_padding_value: door_padding_value,
              heading_width_value: heading_width_value,
              lead_width_value: lead_width_value,
              ornament_path: ornament_path
            )
            
            # フロントマターのCSS linkを構築
            chapter_css = if existing_frontmatter['stylesheet']
                            existing_frontmatter['stylesheet']
                          elsif file_type == 'chapter'
                            'chapter.css'
                          else
                            "#{file_type}.css"
                          end
            
            stylesheets = ['theme.css', chapter_css]

            lang = (Common::CONFIG.dig('book', 'language') || 'ja').to_s.strip
            lang = 'ja' if lang.empty?

            # 新しいフロントマターのベースを作成
            new_frontmatter = {
              'link' => stylesheets.map do |css|
                { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
              end,
              'lang' => lang
            }
            
            # 既存のフロントマターと新しいフロントマターを併合
            merge_frontmatter(existing_frontmatter, new_frontmatter)
          end

          # 既存フロントマターを併合するか新規生成して Markdown に反映する
          def apply_frontmatter(content, file_type, chapter_num)
            text = content.dup
            if text.start_with?('---')
              frontmatter_match = text.match(/\A---\n(.*?)\n---\n/m)
              return text unless frontmatter_match

              frontmatter_yaml = frontmatter_match[1]
              begin
                existing_frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [], aliases: true) || {}
                merged_frontmatter = generate_frontmatter(file_type, chapter_num, existing_frontmatter)
                new_frontmatter_yaml = YAML.dump(merged_frontmatter)
                Common.log_success('フロントマター併合')
                Common.log_success('フロントマター更新')
                return text.sub(/\A---\n.*?\n---\n/m, "#{new_frontmatter_yaml}---\n")
              rescue StandardError => e
                report_frontmatter_error(e, frontmatter_yaml)
                return text
              end
            else
              new_frontmatter = generate_frontmatter(file_type, chapter_num)
              new_frontmatter_yaml = YAML.dump(new_frontmatter)
              Common.log_success('フロントマター追加')
              "#{new_frontmatter_yaml}---\n\n#{text}"
            end
          end

          # フロントマター解析時のエラー内容を詳細ログへ出力する
          def report_frontmatter_error(error, frontmatter_yaml)
            line = error.respond_to?(:line) && error.line ? error.line.to_i : error.message[/line (\d+)/i, 1]&.to_i
            column = error.respond_to?(:column) && error.column ? error.column.to_i : error.message[/column (\d+)/i, 1]&.to_i

            if line&.positive?
              Common.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります（位置: 行#{line} 列#{column&.positive? ? column : '?'}）。内容を見直してください。")
            else
              Common.log_warn('フロントマター（--- ～ ---）の記述に誤りがあります。内容を見直してください。')
            end

            begin
              fm_lines = frontmatter_yaml.to_s.lines
              if line&.positive? && line <= fm_lines.length
                idx = line - 1
                start = [idx - 2, 0].max
                finish = [idx + 2, fm_lines.length - 1].min
                snippet = fm_lines[start..finish].each_with_index.map do |l, i2|
                  "#{start + i2 + 1}: #{l.chomp}"
                end.join("\n")
                err_line_text = fm_lines[idx].to_s.chomp
                caret_line = column&.positive? ? "#{' ' * (column - 1)}^" : ''
                Common.log_info("問題のフロントマター（抜粋）:\n---\n#{snippet}\n---\n該当行:\n#{err_line_text}\n#{caret_line}")
              else
                Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
              end
            rescue StandardError
              Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
            end
          end

          # テーマカラーをパース
          def parse_theme_color(raw_color)
            s = raw_color.to_s.strip
            t = s.downcase
            
            hex_ok      = t.match(/^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
            hex_bare_ok = t.match(/^(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
            hex_0x_ok   = t.match(/^0x(?:[0-9a-f]{6}|[0-9a-f]{8})$/i)
            
            if t.empty?
              ['yellow', 'var(--accent-yellow)']
            elsif hex_ok
              [t, t]
            elsif hex_bare_ok
              normalized = "##{t}"
              [normalized, normalized]
            elsif hex_0x_ok
              normalized = "##{t.sub(/^0x/i, '')}"
              [normalized, normalized]
            elsif ALLOWED_COLORS.include?(t)
              [t, "var(--accent-#{t})"]
            else
              Common.log_error("設定エラー: theme.color は #{ALLOWED_COLORS.join('/')} または #rrggbb/#rrggbbaa のHEXを指定してください（現在: '#{raw_color}'）。ファイル: #{Common::CONFIG_FILE}")
              exit 1
            end
          end

          # テーマスタイルをパース
          def parse_theme_style(raw_style)
            s = (raw_style || 'image').to_s.strip.downcase
            %w[simple image].include?(s) ? s : 'image'
          rescue StandardError
            'image'
          end

          # CSS長さ値を正規化
          def normalize_css_length(value, label:, default: nil, fallback_unit: 'mm')
            return default if value.nil?
            v = value.to_s.strip
            return default if v.empty?

            if v =~ /^-?\d+(?:\.\d+)?$/
              "#{v}#{fallback_unit}"
            elsif v =~ /^-?\d+(?:\.\d+)?(?:mm|cm|in|px|pt|pc|em|rem|vw|vh|vmin|vmax|%)$/i
              v
            else
              Common.log_warn("#{label} の形式が想定外です (#{v})。#{fallback_unit}単位として扱います。")
              numeric = v.gsub(/[^0-9.\-]/, '')
              return default if numeric.empty?
              "#{numeric}#{fallback_unit}"
            end
          end

          # 全CSSファイルを更新
          def update_all_css_files(theme_name:, theme_accent_value:, theme_style:, theme_cfg:,
                                   frontispiece_path:, door_padding_value:, heading_width_value:,
                                   lead_width_value:, ornament_path:)
            # theme.css を更新
            CssUpdater.update_theme_css(
              theme_name: theme_name,
              theme_accent_value: theme_accent_value,
              theme_style: theme_style,
              frontispiece_path: frontispiece_path,
              door_padding_value: door_padding_value,
              ornament_path: ornament_path,
              heading_width_value: heading_width_value,
              lead_width_value: lead_width_value
            )

            # appendix.css を更新
            CssUpdater.update_appendix_css(
              appendix_color: theme_cfg['appendix_color'],
              theme_accent_value: theme_accent_value
            )

            # preface.css を更新
            CssUpdater.update_preface_css(
              preface_color: theme_cfg['preface_color'],
              theme_accent_value: theme_accent_value
            )

            # chapter.css を更新
            CssUpdater.update_chapter_css(theme_style: theme_style)

            # chapter-common.css のマーカーを更新
            markers = theme_cfg['markers'].is_a?(Hash) ? theme_cfg['markers'] : {}
            CssUpdater.update_chapter_common_css(markers: markers)

            # page-settings.css を更新
            cfg = Common::CONFIG
            page_cfg = (cfg && cfg['page']).is_a?(Hash) ? cfg['page'] : {}
            typo_cfg = (cfg && cfg['typography']).is_a?(Hash) ? cfg['typography'] : {}

            # フォント設定をマージ
            font_names = [
              typo_cfg.dig('body', 'font'),
              typo_cfg.dig('heading', 'font'),
              typo_cfg.dig('column', 'font'),
              typo_cfg.dig('code', 'font'),
              typo_cfg.dig('folio', 'font')
            ]
            FontManager.ensure_fonts_available(font_names)

            CssUpdater.update_page_settings_css(page_cfg: page_cfg, typo_cfg: typo_cfg)
          end

          # フロントマターをマージ
          def merge_frontmatter(existing_frontmatter, new_frontmatter)
            merged_frontmatter = existing_frontmatter.dup
            # stylesheet フィールドは link に変換されるので削除
            merged_frontmatter.delete('stylesheet')
            
            if merged_frontmatter['link'].is_a?(Array)
              merged_frontmatter['link'] = merged_frontmatter['link'].reject do |lnk|
                href = (lnk && lnk['href']).to_s
                href.match(%r{stylesheets/(theme-(yellow|blue|red|accent)\.css|theme-overrides\.css)})
              end
            end

            new_frontmatter.each do |key, value|
              if key == 'link' && merged_frontmatter['link']
                existing_links = merged_frontmatter['link']
                new_links = value

                merged_frontmatter['link'] = existing_links + new_links.reject do |new_link|
                  existing_links.any? do |existing_link|
                    existing_link['href'] == new_link['href']
                  end
                end
              else
                merged_frontmatter[key] = value
              end
            end

            merged_frontmatter
          end
        end
      end
    end
  end
end
