# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/create.rb
# ================================================================
# 責務:
#   書籍プロジェクトにおける章ファイル・特殊ページの生成を担当する。
#
# 提供機能:
#   - execute_create: 章 Markdown と画像ディレクトリを生成
#   - execute_titlepage: タイトルページを config/book.yml から生成
#   - execute_colophon: 奥付を config/book.yml から生成
#   - execute_legalpage: 免責・商標ページを config/book.yml から生成
#   - execute_cover: 表紙・裏表紙を生成（SVGテンプレート置換方式）
#
# 生成規約:
#   - 章ファイル名は「数字-スラッグ.md」形式（例: 11-install.md）
#   - 画像は章ごとのサブディレクトリに配置（Vivliostyle の相対パス解決のため）
#   - 生成した章は config/catalog.yml に自動追記される
#
# カバー生成仕様:
#   book.yml の cover: <theme> に対し、以下の優先順位でソースを解決する:
#     1. covers/<side>cover_<theme>.png  (ユーザー用意のPNG)
#     2. covers/<side>cover_<theme>.svg  (ユーザー用意のSVG)
#     3. covers/bundled/<side>cover.svg  (gem同梱テンプレート、パレット＋テキスト置換)
#
#   bundled テンプレートは light テーマ値をデフォルト値として持つ。
#   dark テーマ指定時は DARK_PALETTE の値を正規表現で差し替える。
#   テキストプレースホルダー（{{title}} 等）は常に book.yml の値で置換する。
#
# SVGテンプレートのプレースホルダー仕様:
#   CSS変数（<style> ブロック内）:
#     --vs-bg-from, --vs-bg-to, --vs-text-main, --vs-text-sub,
#     --vs-text-author, --vs-text-label, --vs-grid-stroke,
#     --vs-stroke-outer, --vs-stroke-mid, --vs-stroke-inner,
#     --vs-node-fill, --vs-node-stroke, --vs-icon-color
#   グラデーション stop-color（rsvg-convert 制限のため直接プレースホルダー）:
#     {{bg-from}}, {{bg-to}}
#   テキスト:
#     {{title}}, {{subtitle}}, {{author}}, {{series}}, {{release}}
#
# 依存:
#   - Common: 設定読み込み・ログ出力・パス定数
#   - Build::CatalogUpdater: catalog.yml への章追記
#   - Build::NombreStamper: bleed_mm の取得
#   - config/book.yml: タイトル・著者情報などのメタデータ
# ================================================================

require 'fileutils'
require_relative 'build/pdf_merger'
require_relative 'cover'

module Vivlio
  module Starter
    module CLI
      # 章ファイル・特殊ページ生成ロジック
      #
      # Samovar CLI コマンドから呼び出される実行メソッド群。
      # 各メソッドは純粋な Hash オプションを受け取る。
      module CreateCommands
        module_function

        MAX_AUTO_CHAPTER = 98

        # ================================================================
        # カバーテーマパレット定数
        # ================================================================
        # bundled テンプレートの CSS 変数値を差し替えるための対応表。
        # キーは <style> ブロック内の CSS カスタムプロパティ名と一致させる。
        # グラデーション stop-color は rsvg-convert の CSS 変数非対応のため
        # {{bg-from}} / {{bg-to}} プレースホルダーとして別管理する。
        # ================================================================

        LIGHT_PALETTE = {
          # グラデーション（stop-color プレースホルダー）
          '{{bg-from}}' => '#f8f6f2',
          '{{bg-to}}' => '#f0ece4',
          # CSS 変数
          '--vs-text-main' => '#1e3a60',
          '--vs-text-sub' => '#8090a8',
          '--vs-text-author' => '#2a4070',
          '--vs-text-label' => '#7080a0',
          '--vs-grid-stroke' => '#d0d0d0',
          '--vs-stroke-outer' => '#e0e0e0',
          '--vs-stroke-mid' => '#e8e8e8',
          '--vs-stroke-inner' => '#d0d0d0',
          '--vs-node-fill' => '#ffffff',
          '--vs-node-stroke' => '#1e3a60',
          '--vs-icon-color' => '#1e3a60'
        }.freeze

        DARK_PALETTE = {
          # グラデーション（stop-color プレースホルダー）
          '{{bg-from}}' => '#0e1a2e',
          '{{bg-to}}' => '#060d1a',
          # CSS 変数
          '--vs-text-main' => '#f0e8d0',
          '--vs-text-sub' => '#a8b8d0',
          '--vs-text-author' => '#d0c0a0',
          '--vs-text-label' => '#7080a0',
          '--vs-grid-stroke' => '#1e3358',
          '--vs-stroke-outer' => '#1a3560',
          '--vs-stroke-mid' => '#1e4070',
          '--vs-stroke-inner' => '#2a5590',
          '--vs-node-fill' => '#0e2040',
          '--vs-node-stroke' => '#4a80c8',
          '--vs-icon-color' => '#5b9ef5'
        }.freeze

        # ================================================================
        # 章ファイル生成
        # ================================================================

        # 章ファイルと画像ディレクトリを一括生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        # @param names [Array<String>] 生成する章名のリスト
        #   - 形式: "XX-slug" または "XX-slug.md"（XX は並び順を示す数字）
        #   - 例: ['11-install', '12-tutorial']
        # @return [void]
        # @raise [SystemExit] 1つ以上の章生成に失敗した場合
        def execute_create(options, names)
          apply_verbose(options)
          ensure_names_present!(names)

          resolver = TokenResolver::Resolver.new
          normalized_names = normalize_name_inputs(names, resolver)
          entries = resolver.resolve(normalized_names)

          # 1. 不正な形式をチェック
          invalid_entries = entries.reject(&:valid?)
          if invalid_entries.any?
            Common.log_error("エラー: 不正な形式が含まれています: #{invalid_entries.map(&:slug).join(', ')}")
            exit 1
          end

          # 2. カタログとの重複をチェック
          duplicate_entries = entries.select(&:in_catalog?)
          if duplicate_entries.any?
            Common.log_error('エラー: 以下の章は既にカタログに存在します:')
            duplicate_entries.each { |e| Common.log_error("  - #{e.basename} (#{e.label})") }
            exit 1
          end

          # 3. すべてクリアしたら、一括で作成
          errors = false
          entries.each do |entry|
            fname = ensure_filename(entry.basename)
            unless fname
              Common.log_error("エラー: 無効なファイル名です: #{entry.basename}")
              errors = true
              next
            end

            create_single_chapter(fname, entry)
          rescue StandardError => e
            errors = true
            Common.log_error("作成に失敗しました: #{fname} (#{e.class}: #{e.message})")
          end

          exit 1 if errors
        end

        # ================================================================
        # カバー生成
        # ================================================================

        # 表紙・裏表紙を生成する
        #
        # book.yml の cover: <theme> 設定を読み取り、以下の優先順位で
        # ソースを決定してから PDF / JPG を生成する:
        #   1. covers/<side>cover_<theme>.png  ユーザー用意のPNG
        #   2. covers/<side>cover_<theme>.svg  ユーザー用意のSVG
        #   3. covers/bundled/<side>cover.svg  gem同梱テンプレート（置換後）
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        def execute_cover(options)
          apply_verbose(options)

          theme = resolve_cover_theme
          unless theme
            Common.log_error('output.cover 設定が見つかりません')
            return false
          end

          targets = resolve_cover_targets

          Common.log_action("カバーを生成しています（テーマ: #{theme}, targets: #{targets.join(', ')}）…")

          covers_dir = File.join(Dir.pwd, 'covers')
          book_config_path = File.join(Dir.pwd, 'config', 'book.yml')
          FileUtils.mkdir_p(covers_dir)

          %w[front back].each do |side|
            process_cover_side(side, theme, targets, covers_dir, book_config_path)
          end
        end

        # カバーテーマを解決する
        #
        # @return [String, nil] テーマ名。未設定・空の場合は nil
        def resolve_cover_theme
          theme = Common.cover_theme
          return nil unless theme
          return nil if theme.strip.empty?

          theme
        end

        # カバー targets を解決する
        #
        # @return [Array<String>] 対象フォーマット（例: ['pdf', 'print_pdf']）
        def resolve_cover_targets
          raw_targets = Common::CONFIG.dig(:output, :targets)
          targets = Build::PdfMerger.extract_targets(raw_targets) if raw_targets
          targets = ['pdf'] if targets.nil? || targets.empty?
          targets
        rescue StandardError
          ['pdf']
        end

        # 片面（front / back）のカバー処理を行う
        #
        # ソース解決 → SVG生成（必要な場合）→ PDF/JPG変換 の順に処理する。
        #
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param targets [Array<String>] 生成対象フォーマット
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        # @param book_config_path [String] config/book.yml のフルパス
        def process_cover_side(side, theme, targets, covers_dir, book_config_path)
          source = resolve_cover_source(side, theme, covers_dir)

          case source[:type]
          when :png
            # PNG がそのままソースになる場合は解像度チェックのみ
            check_image_resolution(source[:path], theme)
            generate_cover_outputs_from_png(source[:path], side, theme, targets, covers_dir)

          when :user_svg
            # ユーザー用意のSVG: テキスト置換のみ行い、そのまま変換
            svg_path = apply_text_placeholders_to_svg(source[:path], side, theme, covers_dir,
                                                      book_config_path)
            generate_cover_outputs_from_svg(svg_path, side, theme, targets, covers_dir)

          when :bundled_svg
            # gem同梱テンプレート: パレット置換＋テキスト置換してから変換
            svg_path = render_bundled_svg(source[:path], side, theme, covers_dir,
                                          book_config_path)
            generate_cover_outputs_from_svg(svg_path, side, theme, targets, covers_dir)
          end
        end

        # カバーのソースファイルを優先順位に従って解決する
        #
        # 優先順位:
        #   1. covers/<side>cover_<theme>.png  (ユーザー用意のPNG)
        #   2. covers/<side>cover_<theme>.svg  (ユーザー用意のSVG)
        #   3. covers/bundled/<side>cover.svg  (gem同梱テンプレート)
        #
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        # @return [Hash] { type: :png/:user_svg/:bundled_svg, path: String }
        def resolve_cover_source(side, theme, covers_dir)
          basename = "#{side}cover_#{theme}"

          # 1. covers/<side>cover_<theme>.png
          png_path = File.join(covers_dir, "#{basename}.png")
          return { type: :png, path: png_path } if File.exist?(png_path)

          # 2. covers/<side>cover_<theme>.svg
          user_svg_path = File.join(covers_dir, "#{basename}.svg")
          return { type: :user_svg, path: user_svg_path } if File.exist?(user_svg_path)

          # 3. covers/bundled/<side>cover.svg
          bundled_path = bundled_template_path("#{side}cover")
          return { type: :bundled_svg, path: bundled_path } if File.exist?(bundled_path)

          # ソースが一切見つからない場合
          Common.log_error(<<~MSG)
            #{side}cover のソースが見つかりません。
              確認先:
                #{png_path}
                #{user_svg_path}
                #{bundled_path}
          MSG
          { type: :missing, path: nil }
        end

        # gem同梱テンプレートのパスを返す
        #
        # covers/bundled/<name>.svg を参照する。
        # プロジェクトルートで実行されることを前提とする。
        #
        # @param name [String] 'frontcover' または 'backcover'
        # @return [String] フルパス
        def bundled_template_path(name)
          File.join(Dir.pwd, 'covers', 'bundled', "#{name}.svg")
        end

        # ================================================================
        # SVG レンダリング（テンプレート置換）
        # ================================================================

        # gem同梱テンプレートにパレット＋テキストを適用して出力SVGを生成する
        #
        # 生成したSVGは covers/<side>cover_<theme>.svg に保存する。
        # book.yml またはテンプレートが更新されている場合のみ再生成する。
        #
        # @param template_path [String] bundled テンプレートのパス
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        # @param book_config_path [String] config/book.yml のフルパス
        # @return [String] 生成されたSVGのパス
        def render_bundled_svg(template_path, side, theme, covers_dir, book_config_path)
          output_svg = File.join(covers_dir, "#{side}cover_#{theme}.svg")

          if needs_regeneration?(output_svg, book_config_path, template_path)
            palette = theme == 'dark' ? DARK_PALETTE : LIGHT_PALETTE
            svg = File.read(template_path, encoding: 'utf-8')
            svg = apply_palette(svg, palette)
            svg = apply_text_replacements(svg)
            safe_write(output_svg, svg)
            Common.log_info("#{side}表紙SVGを生成しました: #{output_svg}")
          end

          output_svg
        end

        # ユーザー用意のSVGにテキストプレースホルダーのみ適用して出力SVGを生成する
        #
        # パレットは適用しない（ユーザーが色を自由に設定しているため）。
        # ただし CSS カスタムプロパティ（var(--xxx)）は rsvg-convert が解釈できないため
        # インライン展開してから保存する。
        # 生成したSVGは covers/<side>cover_<theme>_rendered.svg に保存する。
        #
        # @param user_svg_path [String] ユーザー用意のSVGのパス
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        # @param book_config_path [String] config/book.yml のフルパス
        # @return [String] 生成されたSVGのパス
        def apply_text_placeholders_to_svg(user_svg_path, side, theme, covers_dir, book_config_path)
          output_svg = File.join(covers_dir, "#{side}cover_#{theme}_rendered.svg")

          if needs_regeneration?(output_svg, book_config_path, user_svg_path)
            svg = File.read(user_svg_path, encoding: 'utf-8')
            svg = apply_text_replacements(svg)
            svg = expand_css_custom_properties(svg)
            safe_write(output_svg, svg)
            Common.log_info("#{side}表紙SVGを適用しました: #{output_svg}")
          end

          output_svg
        end

        # CSS カスタムプロパティをインライン展開する
        #
        # rsvg-convert は CSS var() を完全サポートしていないため、
        # :root ブロックで定義された変数を実際の値に展開してから渡す。
        #
        # @param svg_content [String] SVG ファイルの内容
        # @return [String] カスタムプロパティを展開した SVG の内容
        def expand_css_custom_properties(svg_content)
          variables = extract_css_variables(svg_content)
          return svg_content if variables.empty?

          resolve_css_variables(svg_content, variables)
        end

        # <style> 内の :root { ... } からカスタムプロパティを抽出する
        #
        # @param svg_content [String]
        # @return [Hash{String => String}] { "--vs-text-main" => "#f0e8d0", ... }
        def extract_css_variables(svg_content)
          variables = {}
          style_blocks = svg_content.scan(%r{<style[^>]*>(.*?)</style>}m).flatten
          style_blocks.each do |block|
            root_blocks = block.scan(/:root\s*\{([^}]*)\}/m).flatten
            root_blocks.each do |root_block|
              root_block.scan(/(--[\w-]+)\s*:\s*([^;]+);/) do |name, value|
                variables[name.strip] = value.strip
              end
            end
          end
          variables
        end

        # var(--xxx) / var(--xxx, fallback) を再帰的に解決する
        #
        # @param svg_content [String]
        # @param variables [Hash{String => String}]
        # @param depth [Integer] 再帰深度の上限（循環参照対策）
        # @return [String]
        def resolve_css_variables(svg_content, variables, depth: 10)
          return svg_content if depth.zero?

          resolved = svg_content.gsub(/var\((--[\w-]+)(?:\s*,\s*([^)]*))?\)/) do
            var_name = ::Regexp.last_match(1)
            fallback = ::Regexp.last_match(2)&.strip
            variables.fetch(var_name, fallback || 'unset')
          end

          resolved.include?('var(') ? resolve_css_variables(resolved, variables, depth: depth - 1) : resolved
        end

        # SVGにパレット（CSS変数値 + stop-colorプレースホルダー）を適用する
        #
        # CSS変数の置換:
        #   <style> ブロック内の "--vs-xxx: <現在値>;" を新しい値で上書きする。
        #   正規表現: /--vs-xxx\s*:\s*[^;]+;/
        #
        # stop-colorプレースホルダーの置換:
        #   "{{bg-from}}" / "{{bg-to}}" をそのまま文字列置換する。
        #   rsvg-convert は stop-color に CSS 変数を適用できないため、
        #   テンプレート側でも {{}} 形式のプレースホルダーを使う。
        #
        # @param svg [String] SVGコンテンツ
        # @param palette [Hash] パレット定数（LIGHT_PALETTE / DARK_PALETTE）
        # @return [String] 置換後のSVGコンテンツ
        def apply_palette(svg, palette)
          palette.each do |key, value|
            svg = if key.start_with?('--')
                    # CSS変数: "--vs-text-main: #1e3a60;" の値部分を差し替える
                    svg.gsub(/#{Regexp.escape(key)}\s*:\s*[^;]+;/, "#{key}: #{value};")
                  else
                    # {{}} プレースホルダー: stop-color などの直接置換
                    svg.gsub(key, value)
                  end
          end
          svg
        end

        # SVGにテキストプレースホルダーを適用する
        #
        # book.yml から取得した書籍メタデータを {{}} プレースホルダーに埋め込む。
        # SVGの構造やスタイルには一切手を加えない。
        #
        # @param svg [String] SVGコンテンツ
        # @return [String] 置換後のSVGコンテンツ
        def apply_text_replacements(svg)
          title, subtitle = extract_title_and_subtitle
          placeholders = {
            '{{title}}' => title,
            '{{subtitle}}' => subtitle,
            '{{author}}' => fetch_config_value('book', 'author'),
            '{{series}}' => fetch_config_value('book', 'series'),
            '{{release}}' => fetch_config_value('book', 'release')
          }
          placeholders.each { |ph, val| svg = svg.gsub(ph, val.to_s) }
          svg
        end

        # SVGから最終成果物（PDF / JPG）を生成する
        #
        # targets の内容に応じて以下を生成する:
        #   - 'pdf'       → <side>cover_<theme>_<size>_rgb.pdf
        #   - 'print_pdf' → <side>cover_<theme>_<size>_cmyk.pdf  (トンボ付き)
        #   - 'epub'      → cover_<theme>.jpg  (front のみ)
        #
        # @param svg_path [String] ソースSVGのパス
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param targets [Array<String>] 生成対象フォーマット
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        def generate_cover_outputs_from_svg(svg_path, side, theme, targets, covers_dir)
          page_size = resolve_page_size

          if targets.include?('pdf')
            pdf_path = File.join(covers_dir, "#{side}cover_#{theme}_#{page_size}_rgb.pdf")
            convert_svg(svg_path, pdf_path, page_size: page_size)
          end

          if targets.include?('print_pdf')
            pdf_path = File.join(covers_dir, "#{side}cover_#{theme}_#{page_size}_cmyk.pdf")
            convert_svg(svg_path, pdf_path, page_size: page_size, crop_marks: true)
          end

          return unless targets.include?('epub') && side == 'front'

          jpg_path = File.join(covers_dir, "cover_#{theme}.jpg")
          convert_svg(svg_path, jpg_path, page_size: page_size)
        end

        # PNGから最終成果物（PDF / JPG）を生成する
        #
        # @param png_path [String] ソースPNGのパス
        # @param side [String] 'front' または 'back'
        # @param theme [String] テーマ名
        # @param targets [Array<String>] 生成対象フォーマット
        # @param covers_dir [String] covers/ ディレクトリのフルパス
        def generate_cover_outputs_from_png(png_path, side, theme, targets, covers_dir)
          page_size = resolve_page_size

          if targets.include?('pdf')
            pdf_path = File.join(covers_dir, "#{side}cover_#{theme}_#{page_size}_rgb.pdf")
            convert_png(png_path, pdf_path)
          end

          if targets.include?('print_pdf')
            pdf_path = File.join(covers_dir, "#{side}cover_#{theme}_#{page_size}_cmyk.pdf")
            convert_png(png_path, pdf_path)
          end

          return unless targets.include?('epub') && side == 'front'

          jpg_path = File.join(covers_dir, "cover_#{theme}.jpg")
          convert_png(png_path, jpg_path)
        end

        # ================================================================
        # 再生成判定
        # ================================================================

        # 出力ファイルの再生成が必要か判定する
        #
        # 出力が存在しない場合、またはソースファイル（book.yml / テンプレート）
        # のいずれかより古い場合に再生成が必要と判断する。
        #
        # @param output_path [String] 生成対象ファイルのパス
        # @param *source_paths [Array<String>] 参照するソースファイルのパス群
        # @return [Boolean]
        def needs_regeneration?(output_path, *source_paths)
          return true unless File.exist?(output_path)

          output_mtime = File.mtime(output_path)
          source_paths.any? { |sp| File.exist?(sp) && File.mtime(sp) > output_mtime }
        end

        # ================================================================
        # SVG 変換（PDF / ラスター）
        # ================================================================

        # SVGを変換する
        #
        # PDF出力: rsvg-convert でページサイズを正確に一致させる
        # JPG/PNG出力: ImageMagick でラスター変換
        #
        # @param input [String] 入力SVGのパス
        # @param output [String] 出力ファイルのパス
        # @param page_size [Symbol] :a4 / :b5 / :a5
        # @param crop_marks [Boolean] true で入稿用トンボ・塗り足し付きPDFを生成
        def convert_svg(input, output, page_size: :b5, crop_marks: false)
          # crop_marks: true の場合は常に再生成（トンボ設定変更を確実に反映）
          # crop_marks: false の場合はキャッシュを使用
          return if !crop_marks && File.exist?(output) && File.mtime(output) >= File.mtime(input)

          ext = File.extname(output).delete('.')
          size = COVER_SIZES.fetch(page_size, COVER_SIZES[:b5])
          w_mm = size[:width_mm]
          h_mm = size[:height_mm]

          if ext == 'pdf'
            if crop_marks
              convert_svg_to_pdf_with_crop_marks(input, output, w_mm, h_mm)
            else
              convert_svg_to_pdf(input, output, w_mm, h_mm)
            end
          else
            convert_svg_to_raster(input, output, w_mm, h_mm)
          end

          Common.log_info("カバーを生成しました: #{File.basename(output)}")
        end

        # SVG → PDF（rsvg-convert 優先、フォールバック: ImageMagick）
        def convert_svg_to_pdf(input, output, w_mm, h_mm)
          if CoverCommands.find_executable('rsvg-convert')
            system('rsvg-convert',
                   '-f', 'pdf',
                   '--page-width', "#{w_mm}mm",
                   '--page-height', "#{h_mm}mm",
                   '-w', "#{w_mm}mm",
                   '-h', "#{h_mm}mm",
                   '-o', output,
                   input)
          else
            convert_cmd = CoverCommands.imagemagick_convert_command
            unless convert_cmd
              Common.log_error('rsvg-convert も ImageMagick も見つかりません')
              return
            end
            w_px = (w_mm / MM_PER_INCH * DPI).round
            h_px = (h_mm / MM_PER_INCH * DPI).round
            system(*convert_cmd, '-density', DPI.to_s, input,
                   '-resize', "#{w_px}x#{h_px}!", output)
          end
        end

        # SVG → PDF（トンボ・塗り足し付き入稿用）
        # 1. rsvg-convert で大ページ（trim + bleed×2 + crop_offset×2）にSVGを配置
        # 2. Prawn でトンボ線のみのオーバーレイPDFを生成
        # 3. CombinePDF で合成
        def convert_svg_to_pdf_with_crop_marks(input, output, trim_w_mm, trim_h_mm)
          bleed_mm = Build::NombreStamper.bleed_mm_from_config
          crop_offset_mm = CROP_MARK_OFFSET_MM
          margin_mm = bleed_mm + crop_offset_mm

          page_w_mm = trim_w_mm + (2 * margin_mm)
          page_h_mm = trim_h_mm + (2 * margin_mm)

          # SVGをbleedサイズで描画（背景色が塗り足し領域まで伸びる）
          svg_w_mm = trim_w_mm + (2 * bleed_mm)
          svg_h_mm = trim_h_mm + (2 * bleed_mm)

          unless CoverCommands.find_executable('rsvg-convert')
            Common.log_warn('rsvg-convert が見つかりません。トンボなしで生成します')
            convert_svg_to_pdf(input, output, trim_w_mm, trim_h_mm)
            return
          end

          # rsvg-convert は CSS var() を完全サポートしないため、変換前にインライン展開する
          svg_content = File.read(input, encoding: 'utf-8')
          expanded    = expand_css_custom_properties(svg_content)
          input_to_use = if expanded == svg_content
                           input
                         else
                           tmp = "#{input}.expanded.svg"
                           File.write(tmp, expanded, encoding: 'utf-8')
                           tmp
                         end

          system('rsvg-convert',
                 '-f', 'pdf',
                 '--page-width', "#{page_w_mm}mm",
                 '--page-height', "#{page_h_mm}mm",
                 '-w', "#{svg_w_mm}mm",
                 '-h', "#{svg_h_mm}mm",
                 '--left', "#{crop_offset_mm}mm",
                 '--top', "#{crop_offset_mm}mm",
                 '-o', output,
                 input_to_use)

          FileUtils.rm_f(input_to_use) if input_to_use != input

          add_crop_marks_overlay(output, trim_w_mm, trim_h_mm, bleed_mm, crop_offset_mm)
        end

        # トンボ線オーバーレイを生成し、カバーPDFに合成する
        # crop offset 領域（bleed 外側）のみに描画し、カバー内部に食い込まない:
        #   - 角トンボ: trim境界位置の直線を bleed 外側に配置
        #   - センタートンボ: 丸十字 ⊕ を crop offset 帯の中央に配置
        def add_crop_marks_overlay(pdf_path, trim_w_mm, trim_h_mm, bleed_mm, crop_offset_mm)
          require 'prawn'
          require 'combine_pdf'

          mm2pt = 72.0 / 25.4
          margin_mm    = bleed_mm + crop_offset_mm
          page_w_pt    = (trim_w_mm + (2 * margin_mm)) * mm2pt
          page_h_pt    = (trim_h_mm + (2 * margin_mm)) * mm2pt
          margin_pt    = margin_mm * mm2pt
          bleed_pt     = bleed_mm * mm2pt
          crop_off_pt  = crop_offset_mm * mm2pt

          # 仕上がり線（trim）の座標（PDF座標: 左下原点）
          tx1 = margin_pt
          ty1 = margin_pt
          tx2 = margin_pt + (trim_w_mm * mm2pt)
          ty2 = margin_pt + (trim_h_mm * mm2pt)

          # bleed 境界の座標

          line_w_pt      = 0.24
          circle_r_pt    = 2.5 * mm2pt
          cross_arm_h_pt = 10.0 * mm2pt
          cross_arm_v_pt = 5.0 * mm2pt
          corner_len_pt  = 10.0 * mm2pt

          overlay_path = "#{pdf_path}.crop_marks.pdf"

          Prawn::Document.generate(overlay_path,
                                   page_size: [page_w_pt, page_h_pt],
                                   margin: 0) do |pdf|
            pdf.stroke_color '000000'
            pdf.line_width line_w_pt

            s  = corner_len_pt
            bl = bleed_pt

            draw_corner_crop_mark(pdf, tx1, ty2, -1,  1, s, bl)
            draw_corner_crop_mark(pdf, tx2, ty2,  1,  1, s, bl)
            draw_corner_crop_mark(pdf, tx1, ty1, -1, -1, s, bl)
            draw_corner_crop_mark(pdf, tx2, ty1,  1, -1, s, bl)

            cx = page_w_pt / 2.0
            cy = page_h_pt / 2.0
            mid_crop = crop_off_pt / 2.0

            draw_center_crop_mark(pdf, cx, page_h_pt - mid_crop,
                                  cross_arm_h_pt, cross_arm_v_pt, circle_r_pt)
            draw_center_crop_mark(pdf, cx, mid_crop,
                                  cross_arm_h_pt, cross_arm_v_pt, circle_r_pt)
            draw_center_crop_mark(pdf, mid_crop, cy,
                                  cross_arm_v_pt, cross_arm_h_pt, circle_r_pt)
            draw_center_crop_mark(pdf, page_w_pt - mid_crop, cy,
                                  cross_arm_v_pt, cross_arm_h_pt, circle_r_pt)
          end

          base    = CombinePDF.load(pdf_path)
          overlay = CombinePDF.load(overlay_path)
          base.pages.first << overlay.pages.first

          mm2pt_local = 72.0 / 25.4
          trim_x1_pt  = margin_pt
          trim_y1_pt  = margin_pt
          trim_x2_pt  = margin_pt + (trim_w_mm * mm2pt_local)
          trim_y2_pt  = margin_pt + (trim_h_mm * mm2pt_local)
          bleed_x1_pt = trim_x1_pt - bleed_pt
          bleed_y1_pt = trim_y1_pt - bleed_pt
          bleed_x2_pt = trim_x2_pt + bleed_pt
          bleed_y2_pt = trim_y2_pt + bleed_pt

          page_dict = base.pages.first
          page_dict[:TrimBox]  = [trim_x1_pt,  trim_y1_pt,  trim_x2_pt,  trim_y2_pt]
          page_dict[:BleedBox] = [bleed_x1_pt, bleed_y1_pt, bleed_x2_pt, bleed_y2_pt]

          base.save(pdf_path)
          FileUtils.rm_f(overlay_path)
        rescue StandardError => e
          Common.log_warn("トンボ描画中にエラー: #{e.message}")
          FileUtils.rm_f(overlay_path) if overlay_path && File.exist?(overlay_path)
        end

        # センタートンボ: ⊕（円＋十字線）
        def draw_center_crop_mark(pdf, cx, cy, half_h, half_v, radius)
          pdf.stroke_line [cx - half_h, cy], [cx + half_h, cy]
          pdf.stroke_line [cx, cy - half_v], [cx, cy + half_v]
          pdf.stroke_circle [cx, cy], radius
        end

        # 角トンボ: 二重L字交差型
        def draw_corner_crop_mark(pdf, x, y, dx, dy, s, bl)
          pdf.move_to(x + (bl * dx), y)
          pdf.line_to(x + ((s + bl) * dx), y)
          pdf.move_to(x, y + (bl * dy))
          pdf.line_to(x, y + ((s + bl) * dy))
          pdf.move_to(x, y + (bl * dy))
          pdf.line_to(x + (s * dx), y + (bl * dy))
          pdf.move_to(x + (bl * dx), y)
          pdf.line_to(x + (bl * dx), y + (s * dy))
          pdf.stroke
        end

        # SVG → JPG/PNG（ImageMagick）
        def convert_svg_to_raster(input, output, w_mm, h_mm)
          convert_cmd = CoverCommands.imagemagick_convert_command
          unless convert_cmd
            Common.log_error('ImageMagick（magick/convert）が見つかりません')
            return
          end
          raster_dpi = 150
          w_px = (w_mm / MM_PER_INCH * raster_dpi).round
          h_px = (h_mm / MM_PER_INCH * raster_dpi).round
          system(*convert_cmd, '-density', raster_dpi.to_s,
                 input,
                 '-resize', "#{w_px}x#{h_px}!",
                 '-quality', '90',
                 output)
        end

        # PNGを変換（ImageMagick）
        def convert_png(input, output)
          return if File.exist?(output) && File.mtime(output) >= File.mtime(input)

          convert_cmd = CoverCommands.imagemagick_convert_command
          unless convert_cmd
            Common.log_error('ImageMagick（magick/convert）が見つかりません')
            return
          end

          ext = File.extname(output).delete('.').downcase
          density = ext == 'pdf' ? '350' : '150'
          system(*convert_cmd, '-density', density, input, output)

          Common.log_info("カバーを生成しました: #{File.basename(output)}")
        end

        # ================================================================
        # 解像度チェック
        # ================================================================

        def check_image_resolution(image_path, theme)
          return unless File.exist?(image_path) && system('identify -version > /dev/null 2>&1')

          dpi_output = `identify -format '%x' #{image_path}`.strip
          unless dpi_output.match?(/\A\d+/)
            Common.log_warn("解像度情報を解析できません: #{dpi_output}")
            return
          end

          avg_dpi = dpi_output.scan(/\d+/).map(&:to_i).then { it.sum / it.size }
          case avg_dpi
          when ...300
            Common.log_warn("カスタム画像 '#{theme}' の解像度が不足しています")
            Common.log_warn("  現在: #{avg_dpi}dpi（推奨: 350dpi以上、最小: 300dpi以上）")
            Common.log_warn('  ビルドは続行しますが、印刷品質が低下する可能性があります')
          when 300...350
            Common.log_info("カスタム画像 '#{theme}' の解像度: #{avg_dpi}dpi（推奨: 350dpi以上）")
          end
        rescue StandardError => e
          Common.log_warn("解像度チェック中にエラーが発生しました: #{e.message}")
        end

        # ================================================================
        # ページサイズ解決
        # ================================================================

        # book.yml の page.use からページサイズシンボルを解決する
        #
        # @return [Symbol] :a4 / :b5 / :a5 のいずれか（デフォルト: :b5）
        def resolve_page_size
          page_use = Common::CONFIG.dig(:page, :use) || 'b5_standard'
          CoverCommands.detect_page_size(page_use)
        end

        # ================================================================
        # 定数
        # ================================================================

        COVER_SIZES = {
          a4: { width_mm: 210, height_mm: 297 },
          b5: { width_mm: 182, height_mm: 257 },
          a5: { width_mm: 148, height_mm: 210 }
        }.freeze

        DPI = 350
        MM_PER_INCH = 25.4
        CROP_MARK_OFFSET_MM = 13.0

        # ================================================================
        # タイトルページ生成
        # ================================================================

        # タイトルページ（扉）を config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: .cache/vs/_titlepage.md
        def execute_titlepage(options)
          apply_verbose(options)
          title, subtitle = extract_title_and_subtitle
          author  = fetch_config_value('book', 'author')
          series  = fetch_config_value('book', 'series')
          release = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"

          content = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="author"><span>[著]</span> #{author}</p>) unless author.empty?}

            #{%(<div class="publication-info">) unless series.empty? && release.empty?}
            #{%(    <p class="series">#{series}</p>) unless series.empty?}
            #{%(    <p class="release-info">#{release}</p>) unless release.empty?}
            #{%(</div>) unless series.empty? && release.empty?}
          MD

          path = File.join(Common::CACHE_DIR, '_titlepage.md')
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # ================================================================
        # 奥付生成
        # ================================================================

        # 奥付ページを config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: .cache/vs/_colophon.md
        def execute_colophon(options)
          apply_verbose(options)
          title, subtitle = extract_title_and_subtitle
          author    = fetch_config_value('book', 'author')
          publisher = fetch_config_value('book', 'publisher')
          publisher = fetch_config_value('book', 'publisher_name') if publisher.empty?
          contact   = fetch_config_value('book', 'contact')
          release   = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"
          current_wareki = "令和#{kanji_year(Time.now.year - 2018)}年"

          content = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="publication-info">#{release}</p>) unless release.empty?}

            <dl class="info-list">
                #{%(<dt>著者</dt>\n                <dd>#{author}</dd>) unless author.empty?}
                #{%(<dt>発行者</dt>\n                <dd>#{publisher}</dd>) unless publisher.empty?}
                #{%(<dt>連絡先</dt>\n                <dd>#{contact}</dd>) unless contact.empty?}
            </dl>

            <p class="copyright">
                <small>
                    &copy; #{current_wareki} #{author.empty? ? '著者' : author} All rights reserved.
                </small>
            </p>

            <p class="powered-by">
                <small>
                    (powered by Vivlio Starter)
                </small>
            </p>
          MD

          path = File.join(Common::CACHE_DIR, '_colophon.md')
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # ================================================================
        # リーガルページ生成
        # ================================================================

        # 免責事項・商標情報を含むリーガルページを生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: .cache/vs/_legalpage.md
        def execute_legalpage(options)
          apply_verbose(options)
          FileUtils.mkdir_p(Common::CACHE_DIR)
          target = File.join(Common::CACHE_DIR, '_legalpage.md')
          return if File.exist?(target) && !options[:force]

          disclaimer, trademark = legal_texts
          body = <<~MD
            <h1 style="display: none;">本書について</h1>
            <div class="disclaimer">
              <h2>■免責</h2>
              #{disclaimer.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>

            <div class="trademark">
              <h2>■商標</h2>
              #{trademark.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>
          MD

          safe_write(target, body)
          Common.log_success("生成しました: #{target}")
        end

        # ================================================================
        # 章ファイル生成ヘルパー
        # ================================================================

        # 単一の章ファイルと関連リソースを生成する
        #
        # @param fname [String] ファイル名（XX-slug.md 形式）
        # @param entry [TokenResolver::Entry] 章エントリ
        # @return [void]
        def create_single_chapter(fname, entry)
          title   = generate_title(fname)
          content = generate_content_from_template(entry, title)
          path    = create_markdown_file(fname, content)
          create_image_directory(fname, {})

          basename = File.basename(fname, '.md')
          Build::CatalogUpdater.add_chapter(basename)

          Common.log_success("#{path} を作成しました")
        end

        # 章名を正規化し、ファイル名形式（XX-slug.md）に変換する
        #
        # @param name [String, nil] 入力された章名
        # @return [String, nil] 正規化されたファイル名、無効な場合は nil
        def ensure_filename(name)
          return nil if name.nil?

          n = name.to_s.strip
          n = File.basename(n)
          n = File.basename(n, '.md')
          return nil unless n =~ /\A\d+(?:-[\w.-]+)?\z/

          "#{n}.md"
        rescue StandardError
          nil
        end

        # ファイル名から章タイトルを抽出する
        def generate_title(fname)
          basename = File.basename(fname.to_s, '.md')
          basename.sub(/\A\d+-/, '')
        end

        # slug を chapter 名として利用できる形式へ正規化する
        def normalize_slug(value)
          slug = value.to_s.downcase
                      .tr(' ', '-')
                      .gsub(/[^a-z0-9-]+/, '-')
                      .gsub(/-+/, '-')
                      .gsub(/\A-+|-+\z/, '')
          slug = 'chapter' if slug.empty?
          slug
        end

        # テンプレートから章コンテンツを生成する
        def generate_content_from_template(entry, title)
          tpl = template_path_for(entry)
          if tpl && File.exist?(tpl)
            File.read(tpl, encoding: 'utf-8').gsub('{{TITLE}}', title.to_s)
          else
            <<~MD
              # #{title}

              <!-- 章テンプレートが見つからなかったため、デフォルトの骨子を生成しました -->

              ここに#{title}の内容を記述してください。
            MD
          end
        end

        def template_path_for(entry)
          case entry&.kind
          when :preface  then Common.preface_template_path
          when :appendix then Common.appendix_template_path
          when :postface then Common.postface_template_path
          else                Common.chapter_template_path
          end
        end

        # Markdown ファイルを contents/ に作成する
        def create_markdown_file(fname, content)
          path = File.join(Common::CONTENTS_DIR, fname)
          raise "既に存在します: #{path}" if File.exist?(path)

          safe_write(path, content)
          path
        end

        # 章に対応する画像ディレクトリを生成する
        def create_image_directory(fname, _options = {})
          basename = File.basename(fname, '.md')
          dir = File.join(Common::IMAGES_DIR, basename)

          if Dir.exist?(dir)
            Common.log_info("画像ディレクトリは既に存在します: #{dir}")
            return dir
          end

          FileUtils.mkdir_p(dir)
          Common.log_success("画像ディレクトリを作成しました: #{dir}")
          dir
        end

        # ファイルを安全に書き込む（親ディレクトリを自動作成）
        def safe_write(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: 'utf-8')
        end

        # ================================================================
        # book.yml アクセスヘルパー
        # ================================================================

        # config/book.yml からタイトルとサブタイトルを取得する
        def extract_title_and_subtitle
          book = Common::CONFIG.fetch('book', {})
          title    = (book['main_title'] || book['title'] || '').to_s
          subtitle = (book['subtitle'] || '').to_s
          [title, subtitle]
        end

        # サブタイトルの装飾スタイルを取得する
        def subtitle_style
          style = fetch_config_value('book', 'subtitle_style').downcase
          %w[wave bar none].include?(style) ? style : 'wave'
        end

        # config/book.yml から指定キーの値を取得する
        def fetch_config_value(section, key)
          value = Common::CONFIG.dig(section, key)
          value ? value.to_s : ''
        end

        # 西暦から和暦の漢数字表記を生成する
        def kanji_year(num)
          km = %w[〇 一 二 三 四 五 六 七 八 九]
          return '〇' if num <= 0
          return km[num] if num < 10
          return '十' if num == 10

          tens = num / 10
          ones = num % 10
          result = ''
          result += "#{km[tens] unless tens == 1}十"
          result += km[ones] unless ones.zero?
          result
        end

        # config/book.yml から免責・商標文面を取得する
        def legal_texts
          legal = Common::CONFIG.fetch('legal', {})
          disclaimer = (legal['disclaimer'] || '').strip
          trademark  = (legal['trademark']  || '').strip

          if disclaimer.empty? && trademark.empty?
            Common.log_warn('config/book.yml の legal.disclaimer / legal.trademark が未設定です。テンプレート文面で生成します。')
            disclaimer = DEFAULT_DISCLAIMER
            trademark  = DEFAULT_TRADEMARK
          end

          [disclaimer, trademark]
        end

        DEFAULT_DISCLAIMER = <<~TXT.strip
          本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
          本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
        TXT

        DEFAULT_TRADEMARK = <<~TXT.strip
          本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
          本書では ™、®、© などのマークは省略しています。
        TXT

        # ================================================================
        # 章番号管理ヘルパー
        # ================================================================

        def apply_verbose(options)
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        def ensure_names_present?(names)
          !names.nil? && !names.empty?
        end

        def normalize_name_inputs(names, resolver)
          used_numbers = used_numbers_pool(resolver)

          Array(names).map do |raw|
            token    = raw.to_s.strip
            basename = strip_token_basename(token)

            if numbered_basename?(basename)
              number = extract_number(basename)
              used_numbers << number if number && !used_numbers.include?(number)
              token
            else
              slug      = normalize_slug(basename)
              number    = next_available_number!(used_numbers)
              generated = "#{number}-#{slug}"
              Common.log_info("[create] #{basename} -> #{generated}")
              generated
            end
          end
        end

        def strip_token_basename(token)
          base = File.basename(token.to_s.strip)
          base.sub(/\.(md|markdown)\z/i, '')
        rescue StandardError
          token.to_s
        end

        def numbered_basename?(basename)
          basename.match?(/\A\d+/)
        end

        def extract_number(basename)
          return unless basename =~ /\A(\d+)/

          format('%02d', Regexp.last_match(1).to_i)
        end

        def ensure_names_present!(names)
          return if ensure_names_present?(names)

          warn '使い方: vs create NAME [NAME ...]'
          exit 1
        end

        def used_numbers_pool(resolver)
          catalog_numbers  = resolver.resolve([]).map(&:number).compact
          markdown_numbers = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).filter_map do |path|
            File.basename(path, '.md')[/\A(\d{2})/, 1]
          end
          (catalog_numbers + markdown_numbers).uniq
        end

        def next_available_number!(used_numbers)
          (1..MAX_AUTO_CHAPTER).each do |candidate|
            number = format('%02d', candidate)
            next if used_numbers.include?(number)

            used_numbers << number
            return number
          end

          raise '01-98 までの章番号がすべて使用済みです'
        end
      end
    end
  end
end
