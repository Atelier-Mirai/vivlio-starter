# frozen_string_literal: true

require 'yaml'
require 'shellwords'
require 'cgi'
require 'fileutils'
require 'open3'
require 'tmpdir'

require_relative 'font_manager'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: pre_process（Markdown 前処理）
      # ------------------------------------------------
      # - 目的: Markdown ファイルに対して前処理を実行
      # - 提供コマンド: pre_process
      # - 主な処理: フロントマター生成/更新, 画像パス修正, ソースコード取込,
      #            book-card/table-rotate ブロックのHTML化, リンク脚注化
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module PreProcessCommands
        DEFAULT_WAIFU2X_BIN = ENV['WAIFU2X_BIN'] || File.expand_path('~/.local/bin/waifu2x/waifu2x-ncnn-vulkan')
        FRONTISPIECE_VARIANTS = {
          portrait: Math.sqrt(2),
          landscape: 1.0 / 2.39
        }.freeze
        FRONTISPIECE_SCALE = 2
        FRONTISPIECE_TARGET_WIDTH = 2880
        FRONTISPIECE_WEBP_QUALITY = 90
        FRONTISPIECE_WAIFU2X_NOISE = 0
        FRONTISPIECE_ALLOWED_RATIOS = [4.0 / 3.0, Math.sqrt(2)].freeze
        FRONTISPIECE_RATIO_TOLERANCE = 0.10
        FRONTISPIECE_DEFAULT_PATH = 'images/door2.webp'
        ORNAMENT_DEFAULT_PATH = 'images/frame-yellow.webp'
        THEME_IMAGE_EXTENSIONS = %w[.webp .png .jpg .jpeg].freeze

        # プレースホルダーSVGテンプレート（ハードコーディング）
        FRONTISPIECE_PLACEHOLDER_SVG = <<~SVG.freeze
          <svg width="2880" height="4072" viewBox="0 0 2880 4072" fill="none" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="vivlioTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#4a86e8;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#1c4587;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="starterTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#6aa84f;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#38761d;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" style="stop-color:#E0F2F7;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#E8F5E9;stop-opacity:1" />
              </linearGradient>
            </defs>
            <rect x="0" y="0" width="2880" height="4072" fill="url(#backgroundGradient)" />
            <text
              x="1440"
              y="1748"
              font-family="Arial, sans-serif"
              font-size="345.6"
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#vivlioTextGradient)">filename.webp</tspan>
            </text>
            <text
              x="1440"
              y="2324"
              font-family="Arial, sans-serif"
              font-size="345.6"
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#starterTextGradient)">No Image</tspan>
            </text>
          </svg>
        SVG

        ORNAMENT_PLACEHOLDER_SVG = <<~SVG.freeze
          <svg width="2880" height="1205" viewBox="0 0 2880 1205" fill="none" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="vivlioTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#4a86e8;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#1c4587;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="starterTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#6aa84f;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#38761d;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" style="stop-color:#E0F2F7;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#E8F5E9;stop-opacity:1" />
              </linearGradient>
            </defs>
            <rect x="0" y="0" width="2880" height="1205" fill="url(#backgroundGradient)" />
            <text
              x="1440"
              y="314.5"
              font-family="Arial, sans-serif"
              font-size="345.6"
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#vivlioTextGradient)">filename.webp</tspan>
            </text>
            <text
              x="1440"
              y="890.5"
              font-family="Arial, sans-serif"
              font-size="345.6"
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#starterTextGradient)">No Image</tspan>
            </text>
          </svg>
        SVG

        NO_IMAGE_PLACEHOLDER_SVG = <<~SVG.freeze
          <svg width="600" height="400" viewBox="0 0 600 400" fill="none" xmlns="http://www.w3.org/2000/svg">
            <defs>
                  <linearGradient id="vivlioTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#4a86e8;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#1c4587;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="starterTextGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" style="stop-color:#6aa84f;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#38761d;stop-opacity:1" />
              </linearGradient>
              <linearGradient id="backgroundGradient" x1="0%" y1="0%" x2="0%" y2="100%">
                <stop offset="0%" style="stop-color:#E0F2F7;stop-opacity:1" />
                <stop offset="100%" style="stop-color:#E8F5E9;stop-opacity:1" />
              </linearGradient>
            </defs>

            <rect x="0" y="0" width="600" height="400" fill="url(#backgroundGradient)" />

            <text 
              x="300" 
              y="140" 
              font-family="Arial, sans-serif" 
              font-size="72" 
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#vivlioTextGradient)">filename.webp</tspan>
            </text>

            <text 
              x="300" 
              y="260" 
              font-family="Arial, sans-serif" 
              font-size="72" 
              font-weight="bold"
              text-anchor="middle"
              dominant-baseline="middle"
            >
              <tspan fill="url(#starterTextGradient)">No Image</tspan>
            </text>
          </svg>
        SVG

        PreProcessContext = Struct.new(
          :source_path,
          :output_path,
          :filename,
          :file_type,
          :chapter_number,
          :content,
          keyword_init: true
        )

        # Markdown 前処理を段階的に実行するクラス
        class MarkdownPreprocessor
          attr_reader :context

          def initialize(md_file)
            filename = File.basename(md_file)
            @context = PreProcessContext.new(
              source_path: md_file,
              output_path: filename,
              filename: filename,
              file_type: Common.get_file_type(filename),
              chapter_number: Common.get_chapter_number(filename),
              content: File.read(md_file, encoding: 'utf-8')
            )
          end

          # 指定Markdownの前処理パイプラインを順次実行する
          def run
            Common.log_info("#{context.source_path} → #{context.output_path}")
            apply_frontmatter!
            normalize_image_paths!
            process_code_includes!
            transform_book_cards!
            transform_table_rotations!
            transform_links!
            write_output!
          end

          private

          # フロントマターを生成または併合して更新する
          def apply_frontmatter!
            context.content = PreProcessCommands.apply_frontmatter(
              context.content,
              context.file_type,
              context.chapter_number
            )
          end

          # 画像パスを生成規約に従って正規化する
          def normalize_image_paths!
            context.content = PreProcessCommands.fix_image_paths(context.content, context.filename)
            Common.log_success("画像パスを修正しました: #{context.filename}")
          end

          # include 記法によるソースコード取り込みを実行する
          def process_code_includes!
            Common.log_action('ソースコード読み込み記法をスキャンしています…')
            context.content = PreProcessCommands.process_code_include(context.content)
            Common.log_success('ソースコード読み込み処理が完了しました')
          end

          # book-card 記法をHTMLに変換し、内部Markdownを整形する
          def transform_book_cards!
            context.content, opened, closed = PreProcessCommands.convert_container_blocks(
              context.content,
              class_name: 'book-card'
            )
            Common.log_success("book-cardブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")

            Common.log_action('book-card内のMarkdownをHTMLへ変換しています…')
            context.content = PreProcessCommands.convert_book_card_inner_markdown(context.content)
            Common.log_success('book-card内のMarkdownをHTMLへ変換しました')
          end

          # table-rotate 記法をHTMLに変換し、内部Markdownを整形する
          def transform_table_rotations!
            context.content, opened, closed = PreProcessCommands.convert_container_blocks(
              context.content,
              class_name: 'table-rotate'
            )
            Common.log_success("table-rotateブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")

            Common.log_action('table-rotate内のMarkdownをHTMLへ変換しています…')
            context.content = PreProcessCommands.convert_table_rotate_inner_markdown(context.content)
            Common.log_success('table-rotate内のMarkdownをHTMLへ変換しました')
          end

          # 外部リンクを脚注化して本文を整える
          def transform_links!
            Common.log_action('リンク記法を脚注化しています…')
            before = context.content.dup
            context.content = PreProcessCommands.transform_links_to_footnotes(context.content)
            if context.content == before
              Common.log_info('脚注化の対象リンクはありません')
            else
              Common.log_success('リンクの脚注化を適用しました')
            end
          end

          # 加工済みコンテンツを書き戻す
          def write_output!
            File.write(context.output_path, context.content, encoding: 'utf-8')
            Common.log_success('保存が完了しました')
          end
        end

        module_function

        PRE_PROCESS_DESC = {
          short: 'Markdownファイルの前処理を行います',
          long: <<~DESC
            指定した Markdown ファイルの前処理を行います。指定が無い場合は contents/ 配下の全 .md を対象にします。

            処理内容:
            - フロントマターの生成/更新
            - 画像パスの修正
            - ソースコードインクルード
            - book-card/table-rotate ブロックの変換
            - リンクの脚注化

            例:
              vs pre_process 11-install
              vs pre_process 11-install.md 12-tutorial
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'pre_process [TOKENS...]', PRE_PROCESS_DESC[:short]
            long_desc PRE_PROCESS_DESC[:long]
            # ================================================================
            # Command: pre_process（Markdown 前処理）
            # ------------------------------------------------
            # - 概要: 指定 Markdown を対象に前処理を適用
            # - 入力: contents/*.md または引数で指定した章
            # - 出力: 上書き保存（フロントマター、パス、ブロック変換等を反映）
            # - オプション: --verbose (-v)
            # ================================================================
            def pre_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              # 引数を正規化
              files = Common.normalize_tokens(tokens)

              # 処理対象のファイルを決定
              md_files = if files.any?
                           # 存在しないファイルをチェック
                           missing_files = files.reject { |f| File.exist?("#{Common::CONTENTS_DIR}/#{f}.md") }
                           if missing_files.any?
                             Common.log_error("エラー: 次のファイルが存在しません: #{missing_files.join(', ')}")
                             Common.log_warn('前処理を中止します')
                             exit(1)
                           end
                           files.map { |f| "#{Common::CONTENTS_DIR}/#{f}.md" }
                         else
                           # 引数がない場合は全Markdownファイルを処理
                           Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                         end

              # 各Markdownファイルを処理
              Common.log_action('Markdownファイルの前処理を行っています...')
              md_files.each do |md_file|
                process_single_markdown_file(md_file)
              end

              Common.log_success('Markdownの前処理が完了しました')
            end
          end
        end

        private

        # 汎用: 画像ライクな指定を解決して CSS 用相対パス/URL を返す
        # - raw が nil/空の場合は default_when_nil を返す（nil 指定可）
        # - url("...") / http(s)://... はそのまま返す
        # - それ以外はファイル名/相対パスとして扱い、images/ 補完・.webp 補完を行う
        # - .webp が無ければ .png/.jpg/.jpeg を探索し、見つかったディレクトリで vs resize:high を実行
        # - downcase_if: 与えた正規表現にマッチする場合は小文字化してから解決
        def resolve_image_path(raw, default_when_nil:, downcase_if: nil)
          return default_when_nil if raw.nil? || raw.to_s.strip.empty?

          s = raw.to_s.strip
          return s if s =~ /^url\(/i || s =~ %r{^https?://}i

          path = s
          path = path.downcase if downcase_if && path =~ downcase_if
          path = "images/#{path}" unless path.include?('/')

          styles_dir = Common::STYLESHEETS_DIR
          abs_path   = File.join(styles_dir, path)
          base_noext = File.extname(abs_path).empty? ? abs_path : abs_path.sub(/\.[^.]+\z/, '')
          webp_abs   = "#{base_noext}.webp"

          unless File.exist?(webp_abs)
            candidates = ["#{base_noext}.png", "#{base_noext}.jpg", "#{base_noext}.jpeg"]
            src = candidates.find { |p| File.exist?(p) }
            if src
              dir = File.dirname(src)
              Common.log_action("WebP を生成します: #{File.basename(src)} → #{File.basename(webp_abs)}")
              system("vs resize:high #{Shellwords.escape(dir)}")
            end
          end

          rel = base_noext.sub(%r{\A#{Regexp.escape(styles_dir)}/}, '')
          rel += '.webp'
          rel
        end

        # frontispiece (扉絵) の解決（未指定時は door2.webp を返す）
        def resolve_frontispiece_path(raw, allow_generation: false)
          resolve_theme_image_path(
            raw,
            variant: :portrait,
            default_path: FRONTISPIECE_DEFAULT_PATH,
            placeholder_svg: FRONTISPIECE_PLACEHOLDER_SVG,
            allow_generation: allow_generation,
            slug_transform: lambda do |value|
              value =~ /^door[1-7](?:_portrait)?(?:\.[^.]+)?$/i ? value.downcase : value
            end
          )
        end

        def resolve_ornament_path(raw, allow_generation: false)
          return ORNAMENT_DEFAULT_PATH if raw.nil? || raw.to_s.strip.empty?

          value = raw.to_s.strip
          return value if value =~ /^url\(/i || value =~ %r{^https?://}i

          slug_value = value =~ /^frame-[a-z0-9_-]+(?:_landscape)?(?:\.[^.]+)?$/i ? value.downcase : value
          slug = normalize_theme_image_slug(slug_value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)

          if requested_variant == :landscape
            if (direct = find_existing_theme_image(slug, location_order: [:user, :bundled]))
              return theme_relative_path(direct)
            end
          elsif (variant_specific = find_existing_theme_image("#{base_slug}_landscape", location_order: [:user, :bundled]))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (direct = find_existing_theme_image(base_query, location_order: [:user, :bundled]))
            if allow_generation && (generated = ensure_variant_generated(direct, :landscape))
              return theme_relative_path(generated)
            end

            return theme_relative_path(direct)
          end

          resolve_theme_image_path(
            slug,
            variant: :landscape,
            default_path: ORNAMENT_DEFAULT_PATH,
            placeholder_svg: ORNAMENT_PLACEHOLDER_SVG,
            allow_generation: allow_generation
          )
        end

        def ensure_magick_available!
          _out, status = Open3.capture2('magick', '-version')
          raise 'ImageMagick (magick) が見つかりません。インストールを確認してください。' unless status.success?
        rescue Errno::ENOENT
          raise 'magick コマンドが見つかりません。ImageMagick をインストールしてください。'
        end

        def command_available?(cmd)
          return File.executable?(cmd) if cmd.include?(File::SEPARATOR)

          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            candidate = File.join(path, cmd)
            File.executable?(candidate)
          end
        end

        def resolve_image_reference(images_root, image_spec)
          spec = image_spec.to_s.strip
          raise '画像指定が空です' if spec.empty?

          normalized_root = File.expand_path(images_root)
          base_dir = normalized_root.end_with?(File::SEPARATOR) ? normalized_root : normalized_root + File::SEPARATOR
          relative = spec.sub(%r{^/+}, '')
          absolute = File.expand_path(relative, base_dir)

          unless absolute == normalized_root || absolute.start_with?(normalized_root + File::SEPARATOR)
            raise "画像指定が不正です: #{spec}"
          end

          return absolute if File.exist?(absolute)

          if File.extname(relative).empty?
            %w[.webp .png .jpg .jpeg].each do |ext|
              candidate = absolute + ext
              return candidate if File.exist?(candidate)
            end
          else
            stem = absolute.sub(/\.[^.]+\z/, '')
            exts = %w[.webp .png .jpg .jpeg]
            ([absolute] + exts.map { |ext| "#{stem}#{ext}" }).each do |candidate|
              return candidate if File.exist?(candidate)
            end
          end

          raise "画像が見つかりません: #{spec}"
        end

        def trim_image_to(source_path, destination_path, fuzz)
          FileUtils.mkdir_p(File.dirname(destination_path))
          command = ['magick', source_path, '-alpha', 'set']
          command += ['-fuzz', fuzz] if fuzz
          command += ['-bordercolor', 'none', '-border', '1x1', '-trim', '+repage', "PNG32:#{destination_path}"]
          run_command!(command, label: "トリミング (#{File.basename(source_path)})")
        end

        def generate_diagonal_variant(input_png, output_png, ratio)
          dims, status = Open3.capture2('magick', 'identify', '-format', '%w %h', input_png)
          raise "寸法取得に失敗しました: #{input_png}" unless status.success?

          width_str, height_str = dims.strip.split
          width = width_str.to_i
          height = height_str.to_i
          raise "不正な寸法です: #{input_png}" if width <= 0 || height <= 0

          ratio = ratio.to_f
          current_ratio = height.to_f / width
          if ratio >= current_ratio
            new_width = width
            new_height = (width * ratio).round
            bottom_x_offset = 0
            bottom_y_offset = new_height - height
          else
            new_height = height
            new_width = (height / ratio).round
            bottom_x_offset = new_width - width
            bottom_y_offset = 0
          end

          top_path = output_png.sub(/\.png\z/, '_top.png')
          bottom_path = output_png.sub(/\.png\z/, '_bottom.png')

          top_cmd = [
            'magick', input_png,
            '-background', 'white', '-flatten',
            '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon 0,0 #{width},0 0,#{height}", ')',
            '-compose', 'CopyAlpha', '-composite', "PNG32:#{top_path}"
          ]
          bottom_cmd = [
            'magick', input_png,
            '-background', 'white', '-flatten',
            '(', '-size', "#{width}x#{height}", 'xc:none', '-fill', 'white', '-draw', "polygon #{width},#{height} #{width},0 0,#{height}", ')',
            '-compose', 'CopyAlpha', '-composite', "PNG32:#{bottom_path}"
          ]
          composite_cmd = [
            'magick',
            '-size', "#{new_width}x#{new_height}",
            'xc:white',
            '-alpha', 'set',
            '+repage',
            top_path, '-geometry', "+0+0", '-compose', 'Over', '-composite',
            bottom_path, '-geometry', "+#{bottom_x_offset}+#{bottom_y_offset}", '-compose', 'Over', '-composite',
            '-transparent', 'white',
            "PNG32:#{output_png}"
          ]

          run_command!(top_cmd, label: '対角線分割 (上)')
          run_command!(bottom_cmd, label: '対角線分割 (下)')
          run_command!(composite_cmd, label: '対角線分割 (合成)')
        ensure
          FileUtils.rm_f(top_path)
          FileUtils.rm_f(bottom_path)
        end

        def generate_variant_output(input_png, target_path, variant:, waifu2x_available:, waifu2x:, waifu2x_args:,
                                     waifu2x_noise:, scale:, target_width:, webp_quality:, keep_intermediate:)
          FileUtils.mkdir_p(File.dirname(target_path))

          variant_label = File.basename(target_path)

          if waifu2x_available
            alpha_path = target_path.sub(/\.webp\z/, '_alpha.png')
            alpha_scaled_path = target_path.sub(/\.webp\z/, "_alpha_x#{scale}.png")
            color_path = target_path.sub(/\.webp\z/, "_color_x#{scale}.png")
            merged_path = target_path.sub(/\.webp\z/, "_merged_x#{scale}.png")

            run_command!(
              ['magick', input_png, '-alpha', 'extract', "PNG32:#{alpha_path}"],
              label: "アルファ抽出 (#{variant_label})"
            )

            waifu_cmd = [waifu2x, '-i', input_png, '-o', color_path, '-n', waifu2x_noise.to_s, '-s', scale.to_s] + waifu2x_args
            run_command!(
              waifu_cmd,
              label: "waifu2x (#{variant_label})",
              stream_output: Common.current_log_level >= 3
            )

            scale_percent = format('%.2f%%', scale.to_f * 100)
            run_command!(
              ['magick', alpha_path, '-filter', 'catrom', '-resize', scale_percent, "PNG32:#{alpha_scaled_path}"],
              label: "アルファ拡大 (#{variant_label})"
            )

            run_command!(
              ['magick', color_path, alpha_scaled_path, '-compose', 'CopyAlpha', '-composite', "PNG32:#{merged_path}"],
              label: "アルファ再適用 (#{variant_label})"
            )

            source_for_webp = merged_path
          else
            source_for_webp = input_png
            alpha_path = alpha_scaled_path = color_path = merged_path = nil
          end

          convert_cmd = [
            'magick', source_for_webp,
            '-alpha', 'set',
            '-background', 'none',
            '-transparent', 'white',
            '-resize', "#{target_width}x",
            '-quality', webp_quality.to_s,
            target_path
          ]
          run_command!(convert_cmd, label: "WebP 変換 (#{variant_label})")

          unless keep_intermediate
            [alpha_path, alpha_scaled_path, color_path, merged_path].compact.each { |path| FileUtils.rm_f(path) }
          end
        end

        def run_command!(cmd, label:, stream_output: false)
          Common.log_action("  $ #{Shellwords.join(cmd.map(&:to_s))}")

          if stream_output
            success = system(*cmd)
            raise "#{label} に失敗しました" unless success
            return
          end

          stdout_str, stderr_str, status = Open3.capture3(*cmd)

          if status.success?
            if Common.current_log_level >= 3
              [stdout_str, stderr_str].each do |chunk|
                next if chunk.nil? || chunk.strip.empty?
                chunk.each_line { |line| Common.log_debug("#{label}: #{line.rstrip}") }
              end
            end
            return
          end

          combined = [stdout_str, stderr_str].map(&:to_s).reject(&:empty?).join("\n")
          message = combined.empty? ? "#{label} に失敗しました" : "#{label} に失敗しました:\n#{combined}"
          raise message
        end

        def resolve_theme_image_path(raw, variant:, default_path:, placeholder_svg:, allow_generation: false, slug_transform: nil)
          return default_path if raw.nil? || raw.to_s.strip.empty?

          value = raw.to_s.strip
          return value if value =~ /^url\(/i || value =~ %r{^https?://}i

          slug_value = slug_transform ? slug_transform.call(value) : value
          slug = normalize_theme_image_slug(slug_value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)

          if requested_variant == variant
            if (direct = find_existing_theme_image(slug, location_order: [:user, :bundled]))
              return theme_relative_path(direct)
            end
          end

          if (variant_specific = find_existing_theme_variant(base_slug, variant))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (user_source = find_existing_theme_image(base_query, location_order: [:user]))
            ratio = image_ratio(user_source)
            if ratio && ratio_accepted_for_frontispiece?(ratio)
              return theme_relative_path(user_source)
            end

            if allow_generation && (generated = ensure_variant_generated(user_source, variant))
              return theme_relative_path(generated)
            end
          end

          if allow_generation && (bundled_source = find_existing_theme_image(base_query, location_order: [:bundled], allowed_extensions: ['.webp']))
            if (generated = ensure_variant_generated(bundled_source, variant))
              return theme_relative_path(generated)
            end
          end

          placeholder_uri(base_slug, placeholder_svg)
        end

        def ensure_variant_generated(source_path, variant)
          images_root = theme_images_root
          relative = source_path.sub(%r{\A#{Regexp.escape(images_root)}/}, '')
          return nil if relative.empty?

          base = relative.sub(/\.[^.]+\z/, '')
          target = File.join(images_root, "#{base}_#{variant}.webp")
          return target if File.exist?(target)

          spec = relative
          success = generate_frontispiece_and_ornament_from(spec)
          success ? target : nil
        end
        module_function :ensure_variant_generated

        def find_existing_theme_variant(base_slug, variant)
          find_existing_theme_image("#{base_slug}_#{variant}", location_order: [:user, :bundled], allowed_extensions: ['.webp'])
        end
        module_function :find_existing_theme_variant

        def normalize_theme_image_slug(value)
          value.to_s.strip.sub(%r{\Aimages/}, '').sub(%r{\A/+}, '')
        end

        def split_slug_and_variant(slug)
          ext = File.extname(slug)
          without_ext = ext.empty? ? slug : slug.sub(/\.[^.]+\z/, '')
          case without_ext.downcase
          when /_portrait\z/
            [without_ext.sub(/_portrait\z/i, ''), :portrait, ext]
          when /_landscape\z/
            [without_ext.sub(/_landscape\z/i, ''), :landscape, ext]
          else
            [without_ext, nil, ext]
          end
        end

        def find_existing_theme_image(slug, location_order: [:user, :bundled], allowed_extensions: THEME_IMAGE_EXTENSIONS)
          base = normalize_theme_image_slug(slug)
          ext = File.extname(base)
          stem = ext.empty? ? base : base.sub(/\.[^.]+\z/, '')
          candidates = if ext.empty?
                         allowed_extensions.map { |e| "#{stem}#{e}" }
                       else
                         ["#{stem}#{ext}"]
                       end

          location_order.each do |loc|
            dir = loc == :user ? theme_images_root : File.join(theme_images_root, 'bundled')
            candidates.each do |candidate|
              path = File.join(dir, candidate)
              return path if File.exist?(path)
            end
          end

          nil
        end

        def theme_images_root
          @theme_images_root ||= File.join(Common::STYLESHEETS_DIR, 'images')
        end

        def theme_relative_path(path)
          path.sub(%r{\A#{Regexp.escape(theme_images_root)}/}, 'images/')
        end

        def image_ratio(path)
          out, status = Open3.capture2('magick', 'identify', '-format', '%w %h', path)
          return nil unless status.success?

          width_str, height_str = out.strip.split
          width = width_str.to_f
          height = height_str.to_f
          return nil if width <= 0 || height <= 0

          height / width
        rescue StandardError
          nil
        end

        def ratio_accepted_for_frontispiece?(ratio)
          FRONTISPIECE_ALLOWED_RATIOS.any? do |allowed|
            ((ratio - allowed).abs / allowed) <= FRONTISPIECE_RATIO_TOLERANCE
          end
        end

        def placeholder_uri(base_slug, placeholder_svg)
          base_name = base_slug.to_s.strip.empty? ? 'missing' : File.basename(base_slug)
          filename = "#{base_name}.webp"
          svg_placeholder_uri(placeholder_svg, filename)
        end

        def svg_placeholder_uri(svg_template, filename)
          replaced = svg_template.gsub('filename.webp', CGI.escapeHTML(filename))
          svg_to_data_uri(replaced)
        rescue StandardError => e
          Common.log_warn("プレースホルダー生成に失敗しました: #{e.message}")
          'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E'
        end

        def generate_frontispiece_and_ornament_from(image_spec, fuzz: nil, waifu2x: DEFAULT_WAIFU2X_BIN,
                                                    waifu2x_args: [], waifu2x_noise: FRONTISPIECE_WAIFU2X_NOISE,
                                                    scale: FRONTISPIECE_SCALE, target_width: FRONTISPIECE_TARGET_WIDTH,
                                                    webp_quality: FRONTISPIECE_WEBP_QUALITY, keep_intermediate: false)
          ensure_magick_available!

          images_root = File.join(Common::STYLESHEETS_DIR, 'images')
          source_path = resolve_image_reference(images_root, image_spec)
          base_dir = File.dirname(source_path)
          basename = File.basename(source_path, '.*')

          Common.log_action("frontispiece/ornament 生成: #{image_spec} → #{basename}_portrait.webp / #{basename}_landscape.webp")

          waifu2x_available = waifu2x && !waifu2x.strip.empty? && command_available?(waifu2x)
          unless waifu2x_available
            Common.log_warn("waifu2x (#{waifu2x}) が見つかりません。ImageMagick のみで生成します。")
          end

          Dir.mktmpdir('frontispiece-one') do |tmpdir|
            trimmed_path = File.join(tmpdir, "#{basename}_trimmed.png")
            trim_image_to(source_path, trimmed_path, fuzz)

            FRONTISPIECE_VARIANTS.each do |variant, ratio|
              variant_png = File.join(tmpdir, "#{basename}_#{variant}.png")
              generate_diagonal_variant(trimmed_path, variant_png, ratio)

              target_path = File.join(base_dir, "#{basename}_#{variant}.webp")
              generate_variant_output(
                variant_png,
                target_path,
                variant: variant,
                waifu2x_available: waifu2x_available,
                waifu2x: waifu2x,
                waifu2x_args: waifu2x_args,
                waifu2x_noise: waifu2x_noise,
                scale: scale,
                target_width: target_width,
                webp_quality: webp_quality,
                keep_intermediate: keep_intermediate
              )

              Common.log_success("生成しました: #{target_path}")
            end
          end

          true
        rescue StandardError => e
          Common.log_error("frontispiece/ornament 生成に失敗しました: #{e.message}")
          false
        end

        # 拡張子→言語の対応表
        EXT_TO_LANG = {
          'c' => 'c',
          'cc' => 'cpp',
          'cpp' => 'cpp',
          'cs' => 'csharp',
          'css' => 'css',
          'cxx' => 'cpp',
          'go' => 'go',
          'html' => 'html',
          'java' => 'java',
          'js' => 'javascript',
          'json' => 'json',
          'kt' => 'kotlin',
          'md' => 'markdown',
          'php' => 'php',
          'py' => 'python',
          'rb' => 'ruby',
          'rs' => 'rust',
          'scala' => 'scala',
          'scss' => 'scss',
          'sh' => 'bash',
          'sql' => 'sql',
          'swift' => 'swift',
          'ts' => 'typescript',
          'xml' => 'xml',
          'yaml' => 'yaml',
          'yml' => 'yaml'
        }.freeze

        # 拡張子からPrism等で使う言語名を推定（未知拡張子は 'text'）
        def detect_language(file_path)
          ext = File.extname(file_path).downcase.delete_prefix('.')
          EXT_TO_LANG.fetch(ext, 'text')
        end

        # 簡易Markdown→HTML 変換
        # - まず Kramdown を使用（利用不可の場合は最小限の自前パーサにフォールバック）
        # - フォールバックでは「画像」「太字見出し相当」「番号リスト」「段落」のみを扱う
        # - 段落バッファ flush_p により空行で段落を確定、<ol> の開閉も整合性を保つ
        # - 認識優先順位: 空行 → 画像 → 太字行 → 番号リスト → それ以外は段落としてバッファ
        # - 未対応のMarkdown記法はそのまま段落テキストとして残る（厳密な互換は目的外）
        def render_markdown_to_html(md_text)
          # まずはKramdownを試す

          require 'kramdown'
          Kramdown::Document.new(md_text).to_html
        rescue LoadError
          # フォールバック: 最小限のMarkdownをHTMLへ
          lines = md_text.to_s.split(/\r?\n/)
          html_parts = []
          in_ol = false
          buffer_p = []

          flush_p = lambda do
            unless buffer_p.empty?
              paragraph = buffer_p.join(' ').strip
              html_parts << "<p>#{paragraph}</p>" unless paragraph.empty?
              buffer_p.clear
            end
          end

          lines.each do |line|
            if line.strip.empty?
              flush_p.call
              next
            end

            # 画像
            if (m = line.match(/^\s*!\[[^\]]*\]\(([^)]+)\)\s*$/))
              flush_p.call
              src = m[1]
              html_parts << "<img src=\"#{src}\">"
              next
            end

            # 見出し相当の太字行
            if (m = line.match(/^\s*\*\*(.+?)\*\*\s*$/))
              flush_p.call
              html_parts << "<p><strong>#{m[1]}</strong></p>"
              next
            end

            # 番号リスト
            # - 連続する行に対して <ol> を1回だけ開き、非連続になったら </ol> を閉じる
            if (m = line.match(/^\s*(\d+)\.\s+(.*)$/))
              flush_p.call
              html_parts << '<ol>' unless in_ol
              in_ol = true
              html_parts << "<li>#{m[2]}</li>"
              next
            elsif in_ol
              html_parts << '</ol>'
              in_ol = false
            end

            buffer_p << line
          end

          flush_p.call
          html_parts << '</ol>' if in_ol
          html_parts.join("\n")
        end

        # Markdown内のリンク記法を脚注化
        # - 画像リンクは (?<!\!) により除外
        # - 既存の [^urlN] を検出して最大番号から連番を継続
        # - 本文のリンク直後に脚注参照を追記し、末尾に定義を追加（既存定義は重複作成しない）
        def transform_links_to_footnotes(md_text)
          text = md_text.to_s

          # 既存の url 脚注番号の最大を取得
          max_n = 0
          text.scan(/\[\^url(\d+)\]:/).each do |m|
            n = m[0].to_i
            max_n = n if n > max_n
          end

          url_id = {}
          replacements = []

          # リンク本体を置換
          # - パターン: (?<!\!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\[\^url\d+\])
          #   - (?<!\!) で画像記法 ![]() を除外
          #   - (https?:...) の外部URLのみ対象（相対リンク/アンカーは対象外）
          #   - (?!\[\^url\d+\]) で既に脚注参照 [^urlN] が直後にあるケースを除外
          # - 同一URLは同一脚注IDに束ね、章内で連番を継続（既存最大番号から開始）
          # - 末尾の脚注定義は既存定義があれば重複作成しない
          replaced = text.gsub(/(?<!!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\[\^url\d+\])/) do |_match|
            label = ::Regexp.last_match(1)
            url   = ::Regexp.last_match(2)
            id = (url_id[url] ||= begin
              max_n += 1
              "url#{max_n}"
            end)
            replacements << [id, url]
            "[#{label}](#{url}) [^#{id}]"
          end

          # 追加する脚注定義を生成
          existing_defs = {}
          text.scan(/\[\^(url\d+)\]:\s*(\S+)/) { |id, u| existing_defs[id] = u }

          new_defs = url_id.map do |u, id|
            next nil if existing_defs.key?(id)

            "[^#{id}]: #{u}"
          end.compact

          return replaced if new_defs.empty?

          # 文末に空行2つを挟んで脚注定義を追記
          if replaced.strip.end_with?("\n")
            "#{replaced}\n#{new_defs.join("\n")}\n"
          else
            "#{replaced}\n\n#{new_defs.join("\n")}\n"
          end
        end

        # book-card 内のMarkdownを事前整形
        # - 画像のみの行/太字のみの行の直後に空行を補い、後段のHTML整形を安定化
        def normalize_book_card_md(md_text)
          lines = md_text.to_s.split(/\r?\n/, -1)
          out = []
          lines.each_with_index do |line, i|
            out << line
            next_line = lines[i + 1]

            # 画像のみの行の直後に空行を補う
            if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
              out << '' if next_line && next_line.strip != ''
            # 太字のみの行の直後に空行を補う
            elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
              out << '' if next_line && next_line.strip != ''
            end
          end
          out.join("\n")
        end

        # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
        # - 内側Markdownを normalize → 簡易レンダラでHTML化 → 本テンプレ構造に組み替え
        def convert_book_card_inner_markdown(content)
          # 開始/終了タグの直後に改行が入っているテンプレ構造を前提に、内側をキャプチャ
          content.gsub(%r{<div class="book-card">\n(.*?)\n</div>}m) do
            inner = ::Regexp.last_match(1)
            normalized = normalize_book_card_md(inner)
            html = render_markdown_to_html(normalized)
            formatted = format_book_card_inner_html(html)
            "<div class=\"book-card\">\n#{formatted}\n</div>"
          end
        end

        # パイプテーブルを簡易HTML化
        # - 1行目をヘッダ、2行目の区切り行（-|:|\s）で判定
        # - セル内の `code` と <>& エスケープに対応
        # - アラインメントや複雑なMarkdown表現は非対応の簡易実装
        def pipe_table_to_html(md_text)
          text = md_text.to_s.strip
          lines = text.split(/\r?\n/).map(&:rstrip)
          return nil if lines.size < 2

          header = lines[0]
          sep    = lines[1]
          return nil unless header.include?('|')
          return nil unless sep && sep =~ /^\s*\|?[\s:\-|]+\|?\s*$/

          rows = lines[2..] || []

          to_cells = lambda do |line|
            parts = line.split('|')
            parts.shift if parts.first&.strip == ''
            parts.pop   if parts.last&.strip  == ''
            parts.map(&:strip)
          end

          esc_code = lambda do |s|
            s.gsub(/`([^`]+)`/) { "<code>#{::Regexp.last_match(1)}</code>" }
             .gsub('&', '&amp;')
             .gsub('<', '&lt;')
             .gsub('>', '&gt;')
          end

          thead_cells = to_cells.call(header)
          tbody_rows  = rows.map { |r| to_cells.call(r) }

          html = []
          html << '<table>'
          html << '  <thead>'
          html << "    <tr>#{thead_cells.map { |c| "<th>#{esc_code.call(c)}</th>" }.join}</tr>"
          html << '  </thead>'
          if tbody_rows.any?
            html << '  <tbody>'
            tbody_rows.each do |cells|
              html << "    <tr>#{cells.map { |c| "<td>#{esc_code.call(c)}</td>" }.join}</tr>"
            end
            html << '  </tbody>'
          end
          html << '</table>'
          html.join("\n")
        end

        # <div class="table-rotate"> ... </div> の内側MarkdownをHTMLへ
        # - 通常は簡易レンダラでHTML化
        # - HTMLに<table>が含まれないが '|' を含む場合、pipe_table_to_html にフォールバック
        def convert_table_rotate_inner_markdown(content)
          content.gsub(%r{<div class="table-rotate">\s*(.*?)\s*</div>}m) do
            inner = ::Regexp.last_match(1)
            normalized = "\n\n#{inner.to_s.strip}\n\n"
            html = render_markdown_to_html(normalized).to_s.strip

            # フォールバック
            # - 簡易レンダラが<table>を生成していないが、Markdownパイプテーブルらしき記号'|'がある場合のみ
            #   文字列ヒューリスティックで pipe_table_to_html を試す
            if !html.include?('<table') && inner.include?('|')
              table_html = pipe_table_to_html(inner)
              html = table_html if table_html
            end

            "<div class=\"table-rotate\">\n#{html}\n</div>"
          end
        end

        # book-card の内側を整形
        # - 画像タグ(<img ...>)と太字タイトル(<strong>...</strong>)を抽出
        # - 残りを説明HTMLとして扱い、所定の .book-info 構造に再配置
        def format_book_card_inner_html(inner_html)
          html = inner_html.to_s.strip

          # 1) 画像タグを抽出
          img_match = html.match(/<img[^>]*>/i)
          # 必須要素が欠ける場合（画像やタイトルがない等）は変換せず原文を返す
          return inner_html unless img_match

          img_tag = img_match[0]
          img_tag = img_tag.gsub(%r{\s*/?>}i) { |_m| '>' }

          # 画像のみの<p>ラッパーを除去
          if html.sub!(%r{<p>\s*#{Regexp.escape(img_match[0])}\s*</p>}i, '')
            # removed wrapped <p> with img
          else
            html.sub!(img_match[0], '')
          end

          # 2) タイトルを抽出
          title_match = html.match(%r{<p>\s*<strong>(.*?)</strong>\s*</p>}im)
          # タイトルが見つからない場合も変換不可
          return inner_html unless title_match

          title_text = title_match[1].strip
          html.sub!(title_match[0], '')

          # 3) 残りを説明HTMLとする
          description_html = html.strip

          # 4) 目標の構造で出力
          parts = []
          parts << "  #{img_tag}"
          parts << '  <div class="book-info">'
          parts << "    <p class=\"book-title\">#{title_text}</p>"
          parts << '    <div class="book-description">'
          parts << "      #{description_html}"
          parts << '    </div>'
          parts << '  </div>'
          parts.join("\n")
        end

        # フロントマターを生成
        # - config を参照して theme.css / appendix.css / page-settings.css を更新
        # - page 設定を CSS 変数へ写像（フォント名は引用符で囲み、既存値は簡易置換で更新）
        # - frontmatter の link 配列は重複を避けつつマージ
        def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
          # ファイルタイプに対応する基本スタイルシート
          # 設定キー: theme.color（必須ではないが、指定時は厳密に検証）
          theme_name, theme_accent_value = begin
            cfg = Common::CONFIG
            raw = cfg && cfg['theme'] && cfg['theme']['color']
            s = raw.to_s.strip
            t = s.downcase
            allowed = %w[yellow amber orange peach coral red magenta plum purple indigo navy blue cyan teal mint green lime]
            hex_ok      = t.match(/^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
            hex_bare_ok = t.match(/^(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
            hex_0x_ok   = t.match(/^0x(?:[0-9a-f]{6}|[0-9a-f]{8})$/i)
            if t.empty?
              ['yellow', 'var(--accent-yellow)']
            elsif hex_ok
              # HEX 指定があればそのまま CSS 値として適用
              [t, t]
            elsif hex_bare_ok
              # 先頭#なし（ff0000 / f00 / rrggbbaa）にも対応
              normalized = "##{t}"
              [normalized, normalized]
            elsif hex_0x_ok
              # 0xRRGGBB / 0xRRGGBBAA にも対応
              normalized = "##{t.sub(/^0x/i, '')}"
              [normalized, normalized]
            elsif allowed.include?(t)
              [t, "var(--accent-#{t})"]
            else
              Common.log_error("設定エラー: theme.color は #{allowed.join('/')} または #rrggbb/#rrggbbaa のHEXを指定してください（現在: '#{raw}'）。ファイル: #{Common::CONFIG_FILE}")
              exit 1
            end
          end

          # テーマのスタイル（simple: 画像なし / image: 画像あり）
          theme_style = begin
            cfg = Common::CONFIG
            s = (cfg && cfg['theme'] && cfg['theme']['style']) || 'image'
            s = s.to_s.strip.downcase
            %w[simple image].include?(s) ? s : 'image'
          rescue StandardError
            'image'
          end

          # theme.color の救済は行わない（不正値は直前でエラー終了）

          # 扉画像の選択（frontispiece のみを使用）
          # - 受理形式:
          #   1) ファイルパス/ファイル名（拡張子省略時は .webp を補う）
          #   2) http(s) URL（そのまま使用）
          #   3) url("...") 文字列（そのまま使用）
          cfg = Common::CONFIG
          theme_cfg = (cfg && cfg['theme']) || {}
          frontispiece_raw = theme_cfg['frontispiece']
          frontispiece_cfg = frontispiece_raw.is_a?(Hash) ? frontispiece_raw : {}
          frontispiece_source = frontispiece_cfg.key?('image') ? frontispiece_cfg['image'] : frontispiece_raw
          frontispiece_path = resolve_frontispiece_path(frontispiece_source)
          normalize_css_length = lambda do |value, label:, default: nil, fallback_unit: 'mm'|
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

          door_padding_value = normalize_css_length.call(frontispiece_cfg['padding'], label: 'theme.frontispiece.padding', default: '0mm')
          heading_width_value = normalize_css_length.call(frontispiece_cfg['heading_width'], label: 'theme.frontispiece.heading_width')
          lead_width_value = normalize_css_length.call(frontispiece_cfg['lead_width'], label: 'theme.frontispiece.lead_width')

          # テーマCSSを更新
          begin
            theme_css_path = File.join(Common::STYLESHEETS_DIR, 'theme.css')
            # TODO: gem公開時にはパスが変わるので更新すること
            template_path = File.expand_path('../../../project_scaffold/stylesheets/theme.css', __dir__)
            css = File.read(theme_css_path, encoding: 'utf-8') if File.exist?(theme_css_path)
            required_tokens = ['--theme-accent', '--section-bg-image', '--frontispiece-image']
            if css.nil? || css.strip.empty? || required_tokens.any? { |token| !css.include?(token) }
              Common.log_info("theme.css をテンプレートから再展開します: #{theme_css_path}")
              css = File.read(template_path, encoding: 'utf-8')
              File.write(theme_css_path, css, encoding: 'utf-8')
            end

            # --theme-accent を named の場合は var(--accent-<name>)、HEX の場合は生の色に設定
            css = css.sub(/(--theme-accent:\s*)[^;]+(\s*;)/) do
              pre = ::Regexp.last_match(1)
              post = ::Regexp.last_match(2)
              "#{pre}#{theme_accent_value}#{post}"
            end

            # 強調色・強意の下線色もテーマアクセントに追従させる
            css = css.sub(/(--color-strong:\s*)[^;]+(\s*;)/, '\\1var(--theme-accent)\\2')
            css = css.sub(/(--color-em-underline:\s*)[^;]+(\s*;)/, '\\1var(--theme-accent)\\2')

            if theme_style == 'simple'
              # 画像を使わないシンプルスタイル
              css = css.sub(/(--section-bg-image:\s*)[^;]+(\s*;)/, '\\1none\\2')
              css = css.sub(/(--frontispiece-image:\s*)[^;]+(\s*;)/, '\\1none\\2')
            else
              # 画像ありスタイル（従来通り）
              # none でも url("...") でも置換できるように包括的なパターンで上書き
              # ornament の指定があればそれを優先。なければ従来のテーマ色マップ
              ornament_path = resolve_ornament_path(theme_cfg['ornament'])
              if ornament_path
                ornament_value = if ornament_path =~ /^url\(/i
                                   ornament_path
                                 else
                                   "url(\"#{ornament_path}\")"
                                 end
                css = css.sub(/(--section-bg-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                  pre = ::Regexp.last_match(1)
                  post = ::Regexp.last_match(2)
                  "#{pre}#{ornament_value}#{post}"
                end
              else
                # ornament 未指定時は既定の frame-yellow.webp を使用
                css = css.sub(/(--section-bg-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                  pre = ::Regexp.last_match(1)
                  post = ::Regexp.last_match(2)
                  "#{pre}url(\"images/frame-yellow.webp\")#{post}"
                end
              end

              # frontispiece_path は url(...) / http(s) / 相対パスのいずれか。
              # CSS の値として url("...") を組み立てる（url(...) が既に含まれていればそのまま）。
              door_value = if frontispiece_path =~ /^url\(/i
                             frontispiece_path
                           else
                             "url(\"#{frontispiece_path}\")"
                           end

              css = css.sub(/(--frontispiece-image:\s*)(?:url\("[^"]+"\)|none)(\s*;)/) do
                pre = ::Regexp.last_match(1)
                post = ::Regexp.last_match(2)
                "#{pre}#{door_value}#{post}"
              end

              css = css.sub(/(--frontispiece-padding:\s*)[^;]+(\s*;)/) do
                pre = ::Regexp.last_match(1)
                post = ::Regexp.last_match(2)
                "#{pre}#{door_padding_value}#{post}"
              end
            end

            if heading_width_value
              css = css.sub(/(--frontispiece-heading-width:\s*)[^;]+(\s*;)/) do
                pre = ::Regexp.last_match(1)
                post = ::Regexp.last_match(2)
                "#{pre}#{heading_width_value}#{post}"
              end
            end

            if lead_width_value
              css = css.sub(/(--frontispiece-lead-width:\s*)[^;]+(\s*;)/) do
                pre = ::Regexp.last_match(1)
                post = ::Regexp.last_match(2)
                "#{pre}#{lead_width_value}#{post}"
              end
            end

            File.write(theme_css_path, css, encoding: 'utf-8')
            Common.log_success("theme.css を更新: theme=#{theme_name}, style=#{theme_style}, door=#{frontispiece_path}, padding=#{door_padding_value}, ornament=#{theme_cfg['ornament']}")
          rescue StandardError => _e
            # 失敗しても前処理は継続
          end

          # appendix.css の付録専用色とマーカーを更新
          begin
            appendix_css_path = File.join(Common::STYLESHEETS_DIR, 'appendix.css')
            if File.exist?(appendix_css_path)
              appendix_css = File.read(appendix_css_path, encoding: 'utf-8')
              updated = false
              
              # 付録専用色を更新（theme.appendix_color が指定されている場合）
              appendix_color = theme_cfg['appendix_color']
              if appendix_color && !appendix_color.to_s.strip.empty?
                # appendix_color を色名または HEX として解釈
                appendix_accent_value = if appendix_color.start_with?('#')
                                          appendix_color
                                        else
                                          "var(--accent-#{appendix_color})"
                                        end
                
                # --appendix-accent-color を更新
                appendix_css = appendix_css.sub(/(--appendix-accent-color:\s*)[^;]+(\s*;)/) do
                  pre = ::Regexp.last_match(1)
                  post = ::Regexp.last_match(2)
                  "#{pre}#{appendix_accent_value}#{post}"
                end
                updated = true
              end
              
              # マーカー（h3/h4）を設定
              cfg = Common::CONFIG
              markers = (cfg && cfg['theme'] && cfg['theme']['markers']).is_a?(Hash) ? cfg['theme']['markers'] : {}
              mark_h3 = markers['h3'].to_s
              mark_h4 = markers['h4'].to_s
              
              mark_h3 = '♣' if mark_h3.strip.empty?
              mark_h4 = '♦' if mark_h4.strip.empty?
              
              set_marker = lambda do |css_text, var_name, value|
                esc = value.gsub('\\', '\\\\').gsub('"', '\\"')
                if css_text.match(/#{Regexp.escape(var_name)}:\s*[^;]+;/)
                  css_text.sub(/(#{Regexp.escape(var_name)}:\s*)[^;]+(;)/, "\\1\"#{esc}\"\\2")
                elsif css_text.match(/:root\s*\{/)
                  css_text.sub(/:root\s*\{/, ":root {\n  #{var_name}: \"#{esc}\";")
                else
                  ":root {\n  #{var_name}: \"#{esc}\";\n}\n\n" + css_text
                end
              end
              
              before_markers = appendix_css.dup
              appendix_css = set_marker.call(appendix_css, '--h3-marker', mark_h3)
              appendix_css = set_marker.call(appendix_css, '--h4-marker', mark_h4)
              updated = true if appendix_css != before_markers
              
              if updated
                File.write(appendix_css_path, appendix_css, encoding: 'utf-8')
                logs = []
                logs << "appendix_color=#{appendix_color}" if appendix_color
                logs << "h3='#{mark_h3}', h4='#{mark_h4}'"
                Common.log_success("appendix.css を更新: #{logs.join(', ')}")
              end
            end
          rescue StandardError => e
            Common.log_warn("appendix.css の更新に失敗: #{e.message}")
          end

          # preface.css の前書き専用色を更新
          begin
            preface_css_path = File.join(Common::STYLESHEETS_DIR, 'preface.css')
            if File.exist?(preface_css_path)
              preface_css = File.read(preface_css_path, encoding: 'utf-8')
              updated = false
              
              # 前書き専用色を更新（theme.preface_color が指定されている場合）
              preface_color = theme_cfg['preface_color']
              if preface_color && !preface_color.to_s.strip.empty?
                # preface_color を色名または HEX として解釈
                preface_accent_value = if preface_color.start_with?('#')
                                         preface_color
                                       else
                                         "var(--accent-#{preface_color})"
                                       end
                
                # --preface-accent-color を更新
                preface_css = preface_css.sub(/(--preface-accent-color:\s*)[^;]+(\s*;)/) do
                  pre = ::Regexp.last_match(1)
                  post = ::Regexp.last_match(2)
                  "#{pre}#{preface_accent_value}#{post}"
                end
                updated = true
              end
              
              if updated
                File.write(preface_css_path, preface_css, encoding: 'utf-8')
                Common.log_success("preface.css を更新: preface_color=#{preface_color}")
              end
            end
          rescue StandardError => e
            Common.log_warn("preface.css の更新に失敗: #{e.message}")
          end

          # chapter.css のヘッダ import を theme.style に連動して切替
          begin
            chapter_css_path = File.join(Common::STYLESHEETS_DIR, 'chapter.css')
            if File.exist?(chapter_css_path)
              ccss = File.read(chapter_css_path, encoding: 'utf-8')
              desired = theme_style == 'image' ? 'image_header.css' : 'simple_header.css'

              if ccss.include?('@import url("simple_header.css");') || ccss.include?('@import url("image_header.css");')
                updated = ccss
                          .sub(/@import\s+url\("simple_header\.css"\);/, "@import url(\"#{desired}\");")
                          .sub(/@import\s+url\("image_header\.css"\);/, "@import url(\"#{desired}\");")

                if updated == ccss
                  Common.log_info("chapter.css のヘッダーimportは既に最新です: #{desired}")
                else
                  File.write(chapter_css_path, updated, encoding: 'utf-8')
                  Common.log_success("chapter.css のヘッダーimportを切替: #{desired}")
                end
              else
                insert_point = ccss.index(';', ccss.index('@import')).to_i + 1 rescue 0
                insert_point = ccss.index("\n", insert_point).to_i + 1
                insert_point = 0 if insert_point.negative?
                header_import = "@import url(\"#{desired}\");\n"
                updated = ccss.dup.insert(insert_point, header_import)
                File.write(chapter_css_path, updated, encoding: 'utf-8')
                Common.log_success("chapter.css にヘッダーimportを追加: #{desired}")
              end

              # 章見出しマーカー（h3/h4 の ::before）を設定
              # - keys (後方互換なし):
              #   - theme.markers.h3
              #   - theme.markers.h4
              begin
                cfg = Common::CONFIG
                markers = (cfg && cfg['theme'] && cfg['theme']['markers']).is_a?(Hash) ? cfg['theme']['markers'] : {}
                mark_h3 = markers['h3'].to_s
                mark_h4 = markers['h4'].to_s

                mark_h3 = '♣' if mark_h3.strip.empty?
                mark_h4 = '◆' if mark_h4.strip.empty?

                css = File.read(chapter_css_path, encoding: 'utf-8')

                set_marker = lambda do |css_text, var_name, value|
                  esc = value.gsub('\\', '\\').gsub('"', '\\"')
                  if css_text.match(/#{Regexp.escape(var_name)}:\s*[^;]+;/)
                    css_text.sub(/(#{Regexp.escape(var_name)}:\s*)[^;]+(;)/, "\\1\"#{esc}\"\\2")
                  elsif css_text.match(/:root\s*\{/) # :root ブロックに追加
                    css_text.sub(/:root\s*\{/, ":root {\n  #{var_name}: \"#{esc}\";")
                  else
                    " :root {\n  #{var_name}: \"#{esc}\";\n }\n\n" + css_text
                  end
                end

                before_css = css.dup
                css = set_marker.call(css, '--h3-marker', mark_h3)
                css = set_marker.call(css, '--h4-marker', mark_h4)

                if css == before_css
                  Common.log_info('theme.markers による変更はありません（既存定義を維持）')
                else
                  File.write(chapter_css_path, css, encoding: 'utf-8')
                  logs = []
                  logs << "h3='#{mark_h3}'"
                  logs << "h4='#{mark_h4}'"
                  Common.log_success("chapter.css にマーカーを反映: #{logs.join(', ')}")
                end
              rescue StandardError => _e
                # 続行（マーカー設定は任意）
              end
            else
              Common.log_info("chapter.css が見つかりません: #{chapter_css_path}")
            end
          rescue StandardError => _e
            # 続行
          end

          # appendix.css のアクセント色を設定
          begin
            appendix_choice = begin
              cfg = Common::CONFIG
              a = (cfg && cfg['theme'] && cfg['theme']['appendix_accent']) || 'blue'
              a = a.to_s.strip.downcase
              %w[neutral red blue].include?(a) ? a : 'blue'
            rescue StandardError
              'blue'
            end

            color_map = {
              'neutral' => '#111',
              'red' => '#c62828',
              'blue' => '#3da8c9'
            }
            hex = color_map[appendix_choice]

            appendix_css_path = File.join(Common::STYLESHEETS_DIR, 'appendix.css')
            if File.exist?(appendix_css_path)
              a_css = File.read(appendix_css_path, encoding: 'utf-8')
              replaced = a_css.sub(/(--appendix-accent-color:\s*)#[0-9a-fA-F]{3,8}(\s*;)/, "\\1#{hex}\\2")
              if replaced == a_css
                Common.log_info('appendix.css に --appendix-accent-color の定義が見つかりません（置換なし）')
              else
                File.write(appendix_css_path, replaced, encoding: 'utf-8')
                Common.log_success("appendix.css を更新: appendix_accent=#{appendix_choice} (#{hex})")
              end
            else
              Common.log_info("appendix.css が見つかりません: #{appendix_css_path}")
            end
          rescue StandardError => _e
            # 前処理続行
          end

          # page-settings.css の各種変数を反映
          begin
            cfg = Common::CONFIG
            page_cfg = (cfg && cfg['page']).is_a?(Hash) ? cfg['page'] : {}

            font_names = [
              page_cfg['main_text_font'],
              page_cfg['header_font'],
              page_cfg['column_font'],
              page_cfg['code_font'],
              page_cfg['folio_font']
            ]
            FontManager.ensure_fonts_available(font_names)

            # 紙サイズ（size/width/height）を共通ヘルパで正規化
            Common.normalize_page_size!(page_cfg)

            # 用紙スケール（A4=1.0 基準）を算出して CSS 変数として注入
            # - 例: B5(182x257) およそ min(182/210, 257/297) ≒ 0.867
            # - 例: A5(148x210) およそ min(148/210, 210/297) ≒ 0.704
            parse_to_mm = lambda do |val|
              s = val.to_s.strip
              if (m = s.match(/^([0-9]+(?:\.[0-9]+)?)\s*(mm|pt)$/i))
                num = m[1].to_f
                unit = m[2].downcase
                unit == 'pt' ? (num * 0.3527777778) : num
              else
                # 単位未指定などの場合は数値として扱い mm とみなす
                s.to_f
              end
            end

            a4_w_mm = 210.0
            a4_h_mm = 297.0
            w_mm = parse_to_mm.call(page_cfg['width'])
            h_mm = parse_to_mm.call(page_cfg['height'])
            if w_mm.positive? && h_mm.positive?
              scale_w = w_mm / a4_w_mm
              scale_h = h_mm / a4_h_mm
              paper_scale = [scale_w, scale_h].min
              # 0.5〜1.0 の安全域に丸め（極端値の暴れを抑制）
              paper_scale = [[paper_scale, 0.5].max, 1.0].min
              page_cfg['paper_scale'] = paper_scale.round(4)
            end

            # ノンブル配置
            placement = page_cfg['folio_placement'].to_s.strip.downcase
            placement = 'center' unless %w[center sides].include?(placement)
            case placement
            when 'center'
              page_cfg['folio_center'] = 'counter(page)'
              page_cfg['folio_left']   = 'none'
              page_cfg['folio_right']  = 'none'
            when 'sides'
              page_cfg['folio_center'] = 'none'
              page_cfg['folio_left']   = 'counter(page)'
              page_cfg['folio_right']  = 'counter(page)'
            end

            mappings = [
              ['--page-width',            page_cfg['width']],
              ['--page-height',           page_cfg['height']],
              ['--paper-scale',           page_cfg['paper_scale']],
              ['--base-font-size',        page_cfg['base_font_size']],
              ['--base-line-height',      page_cfg['base_line_height']],
              ['--letters-per-line',      page_cfg['letters_per_line']],
              ['--lines-per-page',        page_cfg['lines_per_page']],
              ['--page-margin-top',       page_cfg['margin_top']],
              ['--page-margin-xshift',    page_cfg['margin_xshift']],
              ['--column-font-size',      page_cfg['column_font_size']],
              ['--main-text-font',        page_cfg['main_text_font'],  :font],
              ['--header-font',           page_cfg['header_font'],     :font],
              ['--code-font',             page_cfg['code_font'],       :font],
              ['--column-font',           page_cfg['column_font'],     :font],
              ['--folio-font',            page_cfg['folio_font'],      :font],
              ['--folio-font-size',       page_cfg['folio_font_size']],
              ['--folio-color',           page_cfg['folio_color']],
              ['--folio-center-content',  page_cfg['folio_center']],
              ['--folio-left-content',    page_cfg['folio_left']],
              ['--folio-right-content',   page_cfg['folio_right']]
            ]

            candidates = []
            primary_new = File.join(Common::STYLESHEETS_DIR, 'page-settings.css')
            candidates << primary_new
            alt_new = File.join('awesomebook', 'stylesheets', 'page-settings.css')
            candidates << alt_new unless alt_new == primary_new

            candidates.uniq.each do |css_path|
              next unless File.exist?(css_path)

              css = File.read(css_path, encoding: 'utf-8')

              updated = css.dup
              mappings.each do |name, val, kind|
                next if val.nil? || val.to_s.strip.empty?

                v = val.to_s.strip
                v = "\"#{v}\"" if (kind == :font) && !v.include?(',') && v !~ /^\s*".*"\s*$/

                updated = updated.sub(/(#{Regexp.escape(name)}:\s*)[^;]+(\s*;)/) do
                  pre = ::Regexp.last_match(1)
                  post = ::Regexp.last_match(2)
                  "#{pre}#{v}#{post}"
                end
              end

              if updated == css
                Common.log_info("#{File.basename(css_path)} に適用すべき差分はありません: #{css_path}")
              else
                File.write(css_path, updated, encoding: 'utf-8')
                Common.log_success("#{File.basename(css_path)} を更新: #{css_path}")
              end
            end
          rescue StandardError => _e
            # 失敗しても続行
          end

          # フロントマターのCSS
          # front matterに stylesheet が指定されている場合はそれを優先
          chapter_css = if existing_frontmatter['stylesheet']
                          existing_frontmatter['stylesheet']
                        elsif file_type == 'chapter'
                          'chapter.css'
                        else
                          "#{file_type}.css"
                        end
          stylesheets = [
            'theme.css',
            chapter_css
          ]

          # 新しいフロントマターのベースを作成
          new_frontmatter = {
            'link' => stylesheets.map do |css|
              { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
            end,
            'lang' => 'ja'
          }

          # 既存のフロントマターと新しいフロントマターを併合

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

        # 画像パスを修正
        # - 相対パス画像を images/<章basename>/ 配下に正規化
        # - png/jpg は .webp に拡張子を変換（生成物の指針に合わせる）

        # Markdown 内の画像リンクを生成規約に合わせて正規化する
        def fix_image_paths(content, filename)
          chapter_dir = filename.sub(/\.md$/, '')

          content.gsub(%r{!\[(.*?)\]\((?!https?://)([^)]+)\)}) do
            alt_text = ::Regexp.last_match(1)
            image_path = ::Regexp.last_match(2)

            # すでに images/ から始まる場合はそのまま。相対パスは images/<章ディレクトリ>/ に正規化
            normalized = if image_path.start_with?('images/')
                           image_path
                         else
                           "images/#{chapter_dir}/#{image_path}"
                         end

            # 生成物ポリシーに合わせて拡張子を .webp に寄せる（png/jpg のみ対象）
            normalized = normalized.sub(/\.(png|jpe?g)\z/i, '.webp')

            resolved_placeholder_or_path(alt_text, normalized)
          end
        end

        # 既存画像なら元のパスを、無い場合はプレースホルダーを返す
        def resolved_placeholder_or_path(alt_text, normalized_path)
          return "![#{alt_text}](#{normalized_path})" if image_exists_for?(normalized_path)

          Common.log_warn("画像が見つかりません: #{normalized_path} プレースホルダーを使用します")
          placeholder_path = placeholder_image_path(normalized_path)
          "![#{alt_text}](#{placeholder_path})"
        end

        # 画像ディレクトリ内の拡張子違いを含めて存在を確認する
        def image_exists_for?(normalized_path)
          relative_path = normalized_path.sub(%r{\Aimages/}, '')
          base_path = File.expand_path(relative_path, Common::IMAGES_DIR)
          
          # SVGの場合は直接チェック
          if base_path.end_with?('.svg')
            return File.exist?(base_path)
          end
          
          # その他の画像形式は拡張子違いをチェック
          base_without_ext = base_path.sub(/\.webp\z/i, '')
          %w[.webp .png .jpg .jpeg].any? do |ext|
            File.exist?("#{base_without_ext}#{ext}")
          end
        end

        # プレースホルダーSVGを使用してデータURIを生成する
        def placeholder_image_path(missing_image_path = nil)
          return 'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E' unless missing_image_path

          begin
            filename = File.basename(missing_image_path)
            replacement = sanitize_placeholder_text(filename)
            svg_with_filename = NO_IMAGE_PLACEHOLDER_SVG.gsub('filename.webp', replacement)
            svg_to_data_uri(svg_with_filename)
          rescue StandardError => e
            Common.log_warn("プレースホルダー画像の生成に失敗しました: #{e.class}: #{e.message}")
            'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E'
          end
        end

        # プレースホルダーに差し込むファイル名をサニタイズする
        def sanitize_placeholder_text(filename)
          text = filename.to_s.strip
          text = 'missing image' if text.empty?
          CGI.escapeHTML(text)
        end

        # SVGコンテンツをURLエンコードした data URI に変換する
        def svg_to_data_uri(svg_content)
          escaped = CGI.escape(svg_content.encode('utf-8'))
          escaped = escaped.gsub('+', '%20')
          "data:image/svg+xml;charset=utf-8,#{escaped}"
        end

        # ソースコード読み込み処理
        # - ```include:path[:start-end]``` を検出し、codes/ または絶対パスから読込
        # - 行範囲が指定されていればその部分のみを抽出
        # - 言語は拡張子から推定し、```lang:original_path タグで注釈
        def process_code_include(content)
          matches_found = 0

          content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
            matches_found += 1
            original_path = ::Regexp.last_match(1)
            start_line = ::Regexp.last_match(2)&.to_i
            end_line = ::Regexp.last_match(3)&.to_i

            Common.log_action("マッチ発見: #{match.strip}")
            Common.log_info("元のパス: #{original_path}")

            file_path = if original_path.start_with?('/')
                          original_path
                        else
                          File.join(Common::CODES_DIR, original_path)
                        end
            Common.log_info("解決されたパス: #{file_path}")

            if File.exist?(file_path)
              source_content = File.read(file_path)
              lines = source_content.lines

              code_content = if start_line && end_line
                               # 1-origin の範囲指定を Ruby の配列スライスに合わせて 0-origin に補正（end も含む）
                               selected_lines = lines[(start_line - 1)..(end_line - 1)]
                               # join は末尾改行を付与しないため、原文の改行をそのまま連結
                               selected_lines.join
                             else
                               # 範囲未指定時はファイル全体を取り込み、コードブロックの体裁が崩れないよう末尾に改行を追加
                               "#{source_content}\n"
                             end

              language = detect_language(file_path)
              replacement = "```#{language}:#{original_path}\n#{code_content}```"
              Common.log_success("置換完了: #{original_path} (#{language})")

              replacement
            else
              Common.log_error("ファイルが見つかりません: #{file_path}")
              match
            end
          end

          Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found.positive?
          content
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

        # ::: {.class} 記法で囲まれたコンテナを div に変換して件数を返す
        def convert_container_blocks(content, class_name:)
          opened_count = 0
          closed_count = 0
          in_block = false

          converted = content.lines.map do |line|
            if line.match(/^\s*:::\{\.(#{Regexp.escape(class_name)})\}\s*$/)
              in_block = true
              opened_count += 1
              "<div class=\"#{class_name}\">\n"
            elsif in_block && line.match(/^\s*:::\s*$/)
              in_block = false
              closed_count += 1
              "</div>\n"
            else
              line
            end
          end.join

          [converted, opened_count, closed_count]
        end

        module_function :apply_frontmatter, :report_frontmatter_error, :convert_container_blocks,
                        :generate_frontmatter, :resolve_image_path, :resolve_frontispiece_path,
                        :resolve_ornament_path, :resolve_theme_image_path, :ensure_magick_available!,
                        :command_available?, :resolve_image_reference, :trim_image_to,
                        :generate_diagonal_variant, :generate_variant_output, :run_command!,
                        :generate_frontispiece_and_ornament_from, :fix_image_paths,
                        :resolved_placeholder_or_path, :image_exists_for?, :placeholder_image_path,
                        :placeholder_uri, :svg_placeholder_uri, :ensure_variant_generated,
                        :normalize_theme_image_slug, :split_slug_and_variant, :find_existing_theme_image,
                        :find_existing_theme_variant,
                        :theme_images_root, :theme_relative_path, :image_ratio,
                        :ratio_accepted_for_frontispiece?, :sanitize_placeholder_text,
                        :svg_to_data_uri,
                        :process_code_include, :normalize_book_card_md, :convert_book_card_inner_markdown,
                        :convert_table_rotate_inner_markdown, :transform_links_to_footnotes,
                        :normalize_book_card_md, :render_markdown_to_html, :pipe_table_to_html,
                        :format_book_card_inner_html
        module_function :detect_language

        def process_single_markdown_file(md_file)
          MarkdownPreprocessor.new(md_file).run
        end
      end
    end
  end
end
