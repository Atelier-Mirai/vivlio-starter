# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/frontmatter_generator.rb
# ================================================================
# 責務:
#   Markdown ファイルの YAML フロントマターを生成・更新する。
#   テーマ設定に基づいて CSS カスタムプロパティを設定する。
#
# 生成するフロントマター:
#   - title: 章タイトル
#   - class: body クラス（chapter/appendix/titlepage 等）
#   - theme: テーマカラー・スタイル設定
#
# CSS 更新内容:
#   - --theme-accent: テーマアクセントカラー
#   - --frontispiece-image: 扉絵画像パス
#   - --ornament-image: 飾り画像パス
#
# 依存:
#   - CssUpdater: CSS ファイルの更新
#   - ThemeImageResolver: テーマ画像パスの解決
#   - FontManager: フォントの準備
# ================================================================

require 'yaml'
require_relative '../common'
require_relative '../font_manager'
require_relative 'css_updater'
require_relative 'theme_image_resolver'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # フロントマター生成・CSS 更新を担当するモジュール
      module FrontmatterGenerator
        ALLOWED_COLORS = %w[yellow orange red magenta purple indigo navy blue cyan teal green lime].freeze

        module_function

        # テーマ設定を解析して構造化データを返す
        def parse_theme_settings(cfg = nil)
          cfg ||= Common::CONFIG
          theme_cfg = cfg[:theme] || {}

          theme_color = theme_cfg[:color]
          theme_style_raw = theme_cfg[:style]
          frontispiece_raw = theme_cfg[:frontispiece]
          ornament_raw = theme_cfg[:ornament]

          theme_name, theme_accent_value = parse_theme_color(theme_color)
          theme_style = parse_theme_style(theme_style_raw)

          frontispiece_cfg = parse_frontispiece_config(frontispiece_raw)
          ornament_path = ThemeImageResolver.resolve_ornament_path(
            ornament_raw, allow_generation: true
          )

          {
            theme_name: theme_name,
            theme_accent_value: theme_accent_value,
            theme_style: theme_style,
            theme_cfg: theme_cfg,
            frontispiece_path: frontispiece_cfg[:path],
            door_padding_value: frontispiece_cfg[:padding],
            heading_width_value: frontispiece_cfg[:heading_width],
            lead_width_value: frontispiece_cfg[:lead_width],
            ornament_path: ornament_path
          }
        end

        # frontispiece 設定を解析（Data オブジェクト前提）
        def parse_frontispiece_config(frontispiece_raw)
          # String の場合はそのまま image 名として使用
          source = frontispiece_raw.is_a?(String) ? frontispiece_raw : frontispiece_raw&.dig(:image)
          path = ThemeImageResolver.resolve_frontispiece_path(source, allow_generation: true)

          # padding/heading_width/lead_width を取得（String の場合は nil）
          padding = frontispiece_raw.is_a?(String) ? nil : frontispiece_raw&.dig(:padding)
          heading_width = frontispiece_raw.is_a?(String) ? nil : frontispiece_raw&.dig(:heading_width)
          lead_width = frontispiece_raw.is_a?(String) ? nil : frontispiece_raw&.dig(:lead_width)

          {
            path: path,
            padding: normalize_css_length(padding, label: 'theme.frontispiece.padding', default: '0mm'),
            heading_width: normalize_css_length(heading_width, label: 'theme.frontispiece.heading_width'),
            lead_width: normalize_css_length(lead_width, label: 'theme.frontispiece.lead_width')
          }
        end

        # CSS更新のみを実行（ビルド時にStep 2で呼ばれる）
        def update_css_only!(cfg = nil)
          settings = parse_theme_settings(cfg)
          update_all_css_files(**settings)
          Common.log_success('[Step 2] CSS設定を更新しました')
        rescue StandardError => e
          Common.log_warn("[Step 2] CSS更新に失敗: #{e.message}")
        end

        # フロントマターを生成
        def generate_frontmatter(file_type, _chapter_num = nil, existing_frontmatter = {})
          settings = parse_theme_settings
          update_all_css_files(**settings)

          chapter_css = resolve_chapter_css(file_type, existing_frontmatter)
          new_frontmatter = build_base_frontmatter(chapter_css)
          merge_frontmatter(existing_frontmatter, new_frontmatter)
        end

        # ファイルタイプに応じたCSS名を解決
        def resolve_chapter_css(file_type, existing_frontmatter)
          return existing_frontmatter['stylesheet'] if existing_frontmatter['stylesheet']
          return 'chapter.css' if file_type == 'chapter'
          return 'part-title.css' if file_type == 'part_title'

          "#{file_type}.css"
        end

        # フロントマターのベース構造を構築
        def build_base_frontmatter(chapter_css)
          stylesheets = ['theme.css', chapter_css, 'custom.css']
          lang = (Common::CONFIG.dig(:book, :language) || 'ja').to_s.strip
          lang = 'ja' if lang.empty?

          {
            'link' => stylesheets.map { |css| { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" } },
            'lang' => lang
          }
        end

        # 既存フロントマターを併合するか新規生成して Markdown に反映する
        # @param path [String, nil] 警告メッセージに含めるファイルパス（省略可）
        def apply_frontmatter(content, file_type, chapter_num, path: nil)
          text = content.dup
          if text.start_with?('---')
            # フロントマター終了の `---` を正確に検出する。
            # `/\A---\n(.*?)\n---\n/m` の最短マッチはコードブロック内の `---` で
            # 誤って止まるため、行単位で走査して最初の `---` 単独行を終端とする。
            frontmatter_end = find_frontmatter_end(text)
            unless frontmatter_end
              warn_unclosed_frontmatter(path)
              return text
            end

            frontmatter_yaml = text[4...frontmatter_end].chomp
            body_after = text[(frontmatter_end + 4)..]
            begin
              existing_frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [], aliases: true) || {}
              merged_frontmatter = generate_frontmatter(file_type, chapter_num, existing_frontmatter)
              new_frontmatter_yaml = YAML.dump(merged_frontmatter)
              Common.log_success('フロントマター併合')
              Common.log_success('フロントマター更新')
              "#{new_frontmatter_yaml}---\n#{body_after}"
            rescue StandardError => e
              report_frontmatter_error(e, frontmatter_yaml)
              text
            end
          else
            new_frontmatter = generate_frontmatter(file_type, chapter_num)
            new_frontmatter_yaml = YAML.dump(new_frontmatter)
            Common.log_success('フロントマター追加')
            "#{new_frontmatter_yaml}---\n\n#{text}"
          end
        end

        # フロントマター終了位置を行単位で検出する。
        # ファイル先頭の `---\n` の直後から走査し、
        # コードフェンス（```）に入る前に `---` 単独行が現れた位置を返す。
        # @param text [String] ファイル全体のテキスト
        # @return [Integer, nil] 終了 `---\n` の開始インデックス、見つからなければ nil
        def find_frontmatter_end(text)
          # 先頭の `---\n` をスキップ
          pos = 4
          in_code_fence = false
          while pos < text.length
            line_end = text.index("\n", pos)
            break unless line_end

            line = text[pos...line_end]
            if line.start_with?('```') || line.start_with?('~~~')
              in_code_fence = !in_code_fence
            elsif !in_code_fence && line == '---'
              return pos
            end
            pos = line_end + 1
          end
          nil
        end

        # フロントマター開始の `---` に対応する閉じ `---` が見つからない場合に警告を出す。
        # 著者が誤って `---` を書き忘れた/閉じ忘れたケースを検知し、
        # ビルド結果が意図せず本文扱いになる前に気付かせる。
        # @param path [String, nil] ファイルパス（警告メッセージ用）
        def warn_unclosed_frontmatter(path)
          location = path || '(unknown file)'
          warn "[frontmatter] 警告: #{location} のフロントマター開始 `---` に対応する閉じ `---` が" \
               'コードフェンス外に見つかりません。フロントマターは適用されず、本文として扱われます。'
        end

        # フロントマター解析時のエラー内容を詳細ログへ出力する
        def report_frontmatter_error(error, frontmatter_yaml)
          line, column = extract_error_position(error)
          log_frontmatter_error_message(line, column)
          log_frontmatter_snippet(frontmatter_yaml, line, column)
        end

        # エラーから行・列番号を抽出
        def extract_error_position(error)
          line = error.respond_to?(:line) && error.line ? error.line.to_i : error.message[/line (\d+)/i, 1]&.to_i
          column = if error.respond_to?(:column) && error.column
                     error.column.to_i
                   else
                     error.message[/column (\d+)/i,
                                   1]&.to_i
                   end
          [line, column]
        end

        # エラーメッセージをログ出力
        def log_frontmatter_error_message(line, column)
          if line&.positive?
            col_str = column&.positive? ? column : '?'
            Common.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります（位置: 行#{line} 列#{col_str}）。内容を見直してください。")
          else
            Common.log_warn('フロントマター（--- ～ ---）の記述に誤りがあります。内容を見直してください。')
          end
        end

        # フロントマターの該当箇所をログ出力
        def log_frontmatter_snippet(frontmatter_yaml, line, column)
          fm_lines = frontmatter_yaml.to_s.lines
          if line&.positive? && line <= fm_lines.length
            log_detailed_snippet(fm_lines, line, column)
          else
            Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
          end
        rescue StandardError
          Common.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
        end

        # 詳細なスニペットをログ出力
        def log_detailed_snippet(fm_lines, line, column)
          idx = line - 1
          start_idx = [idx - 2, 0].max
          finish_idx = [idx + 2, fm_lines.length - 1].min
          snippet = fm_lines[start_idx..finish_idx].each_with_index.map do |l, i|
            "#{start_idx + i + 1}: #{l.chomp}"
          end.join("\n")
          err_line_text = fm_lines[idx].to_s.chomp
          caret_line = column&.positive? ? "#{' ' * (column - 1)}^" : ''
          Common.log_info("問題のフロントマター（抜粋）:\n---\n#{snippet}\n---\n該当行:\n#{err_line_text}\n#{caret_line}")
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
            numeric = v.gsub(/[^0-9.-]/, '')
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
            appendix_color: theme_cfg&.dig(:appendix_color),
            theme_accent_value: theme_accent_value
          )

          # preface.css を更新
          CssUpdater.update_preface_css(
            preface_color: theme_cfg&.dig(:preface_color),
            theme_accent_value: theme_accent_value
          )

          # chapter.css を更新
          CssUpdater.update_chapter_css(theme_style: theme_style)

          # chapter-common.css のマーカーを更新
          markers_cfg = theme_cfg&.dig(:markers)
          CssUpdater.update_chapter_common_css(markers: safe_config_hash(markers_cfg))

          # page-settings.css を更新
          cfg = Common::CONFIG
          page_cfg = safe_config_hash(cfg&.dig(:page))
          typo_cfg = safe_config_hash(cfg&.dig(:typography))

          # フォント設定をマージ
          font_names = [
            typo_cfg&.dig(:body, :font),
            typo_cfg&.dig(:heading, :font),
            typo_cfg&.dig(:column, :font),
            typo_cfg&.dig(:code, :font),
            typo_cfg&.dig(:folio, :font)
          ]
          FontManager.ensure_fonts_available(font_names)

          CssUpdater.update_page_settings_css(page_cfg: page_cfg, typo_cfg: typo_cfg)
        end

        # フロントマターをマージ
        def merge_frontmatter(existing_frontmatter, new_frontmatter)
          merged = existing_frontmatter.dup
          merged.delete('stylesheet')
          merged['link'] = filter_legacy_theme_links(merged['link']) if merged['link'].is_a?(Array)

          new_frontmatter.each do |key, value|
            merged[key] = key == 'link' && merged['link'] ? merge_links(merged['link'], value) : value
          end
          merged
        end

        def safe_config_hash(obj)
          case obj
          when Hash
            obj.dup
          when nil
            {}
          else
            obj.respond_to?(:to_h) ? obj.to_h : {}
          end
        end

        # 古いテーマリンクを除外
        def filter_legacy_theme_links(links)
          links.reject do |lnk|
            href = (lnk && lnk['href']).to_s
            href.match(%r{stylesheets/(theme-(yellow|blue|red|accent)\.css|theme-overrides\.css)})
          end
        end

        # リンク配列をマージ（重複を除外）
        def merge_links(existing_links, new_links)
          existing_links + new_links.reject do |new_link|
            existing_links.any? { |existing| existing['href'] == new_link['href'] }
          end
        end
      end
    end
  end
end
