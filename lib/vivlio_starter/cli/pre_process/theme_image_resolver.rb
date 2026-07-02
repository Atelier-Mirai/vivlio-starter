# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/theme_image_resolver.rb
# ================================================================
# 責務:
#   テーマ画像（扉絵・飾り画像）のパスを解決する。
#   指定された名前から実際のファイルパスまたはプレースホルダーを返す。
#
# 探索順序:
#   1. images/bundled/{name}_portrait.webp（バリアント）
#   2. images/{name}.webp
#   3. images/{name}.png/.jpg/.jpeg
#   4. プレースホルダー SVG（見つからない場合）
#
# バリアント:
#   - portrait: 縦長（扉絵用、ページ比率に合わせてクロップ）
#   - landscape: 横長（飾り画像用、2.39:1 シネマスコープ）
#
# 依存:
#   - ImageGenerator: バリアント画像の生成
# ================================================================

require 'cgi'
require 'uri'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # テーマ画像パス解決モジュール
      module ThemeImageResolver
        THEME_IMAGE_EXTENSIONS = %w[.webp .png .jpg .jpeg].freeze

        # 扉絵・飾り画像の既定画像スラッグ。未指定時も無効な指定時もこの画像に寄せる。
        # （無効な color が yellow へフォールバックするのと揃えた挙動。バンドルの桜を使う）
        FALLBACK_THEME_IMAGE_SLUG = 'sakura'

        # 万一バリアント解決に失敗したときの最終フォールバックパス（通常は到達しない）。
        FRONTISPIECE_DEFAULT_PATH = 'images/bundled/sakura_portrait.webp'
        ORNAMENT_DEFAULT_PATH = 'images/bundled/sakura_landscape.webp'

        DEFAULT_PAGE_WIDTH_MM = 210.0
        DEFAULT_PAGE_HEIGHT_MM = 297.0
        MIN_BINDING_RATIO = 1.35
        MAX_BINDING_RATIO = 2.2
        FRONTISPIECE_RATIO_TOLERANCE = 0.05

        FRONTISPIECE_PLACEHOLDER_SVG = <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 210 297" width="210" height="297">
            <rect width="210" height="297" fill="#e3e3e3"/>
            <text x="105" y="150" font-family="monospace" font-size="14" fill="#666" text-anchor="middle">filename.webp</text>
          </svg>
        SVG

        ORNAMENT_PLACEHOLDER_SVG = <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 297 210" width="297" height="210">
            <rect width="297" height="210" fill="#e3e3e3"/>
            <text x="148.5" y="110" font-family="monospace" font-size="14" fill="#666" text-anchor="middle">filename.webp</text>
          </svg>
        SVG

        module_function

        # frontispiece (扉絵) の解決（未指定時は既定画像 sakura を生成して使う）
        def resolve_frontispiece_path(raw, allow_generation: false)
          source = raw.nil? || raw.to_s.strip.empty? ? FALLBACK_THEME_IMAGE_SLUG : raw
          resolve_theme_image_path(
            source,
            variant: :portrait,
            default_path: FRONTISPIECE_DEFAULT_PATH,
            placeholder_svg: FRONTISPIECE_PLACEHOLDER_SVG,
            allow_generation: allow_generation,
            fallback_slug: FALLBACK_THEME_IMAGE_SLUG,
            slug_transform: lambda do |value|
              value =~ /^door[1-7](?:_portrait)?(?:\.[^.]+)?$/i ? value.downcase : value
            end
          )
        end

        # ornament (装飾画像) の解決（未指定時は既定画像 sakura を生成して使う）
        def resolve_ornament_path(raw, allow_generation: false)
          raw = FALLBACK_THEME_IMAGE_SLUG if raw.nil? || raw.to_s.strip.empty?

          value = raw.to_s.strip
          return value if value =~ /^url\(/i || value =~ %r{^https?://}i

          slug_value = value =~ /^frame-[a-z0-9_-]+(?:_landscape)?(?:\.[^.]+)?$/i ? value.downcase : value
          slug = normalize_theme_image_slug(slug_value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)

          # ornament用に landscape バリアント（2.39:1）を使用
          if requested_variant == :landscape
            if (direct = find_existing_theme_image(slug, location_order: %i[user bundled]))
              return theme_relative_path(direct)
            end
          elsif (variant_specific = find_existing_theme_image("#{base_slug}_landscape",
                                                              location_order: %i[user bundled]))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (direct = find_existing_theme_image(base_query, location_order: %i[user bundled]))
            if allow_generation
              require_relative 'image_generator'
              # ornamentはlandscapeバリアントを生成
              if (generated = ImageGenerator.ensure_variant_generated(direct, :landscape))
                return theme_relative_path(generated)
              end
            end

            return theme_relative_path(direct)
          end

          resolve_theme_image_path(
            slug,
            variant: :landscape,
            default_path: ORNAMENT_DEFAULT_PATH,
            placeholder_svg: ORNAMENT_PLACEHOLDER_SVG,
            allow_generation: allow_generation,
            fallback_slug: FALLBACK_THEME_IMAGE_SLUG
          )
        end

        # 汎用: 画像ライクな指定を解決して CSS 用相対パス/URL を返す
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

        # テーマ画像パスの解決
        def resolve_theme_image_path(raw, variant:, default_path:, placeholder_svg:, allow_generation: false,
                                     slug_transform: nil, fallback_slug: nil)
          return default_path if raw.nil? || raw.to_s.strip.empty?

          value = raw.to_s.strip
          return value if value =~ /^url\(/i || value =~ %r{^https?://}i

          slug_value = slug_transform ? slug_transform.call(value) : value
          slug = normalize_theme_image_slug(slug_value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)

          if (requested_variant == variant) && (direct = find_existing_theme_image(slug,
                                                                                   location_order: %i[user bundled]))
            return theme_relative_path(direct)
          end

          if (variant_specific = find_existing_theme_variant(base_slug, variant))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (user_source = find_existing_theme_image(base_query, location_order: [:user]))
            ratio = image_ratio(user_source)
            return theme_relative_path(user_source) if ratio && ratio_accepted_for_frontispiece?(ratio)

            if allow_generation
              require_relative 'image_generator'
              if (generated = ImageGenerator.ensure_variant_generated(user_source, variant))
                return theme_relative_path(generated)
              end
            end
          end

          if allow_generation && (bundled_source = find_existing_theme_image(base_query, location_order: [:bundled],
                                                                                         allowed_extensions: ['.webp']))
            require_relative 'image_generator'
            if (generated = ImageGenerator.ensure_variant_generated(bundled_source, variant))
              return theme_relative_path(generated)
            end
          end

          # 指定名が解決できない場合は既定画像（sakura 等）へフォールバックする。
          # フォールバック自身も無ければ（fallback_slug: nil の再帰）プレースホルダーを返す。
          if fallback_slug && normalize_theme_image_slug(fallback_slug) != base_slug
            fallback = resolve_theme_image_path(
              fallback_slug, variant: variant, default_path: default_path,
              placeholder_svg: placeholder_svg, allow_generation: allow_generation
            )
            return fallback unless fallback.start_with?('data:')
          end

          placeholder_uri(base_slug, placeholder_svg)
        end

        # 指定されたテーマ画像名が実在する（またはバリアント生成の元になる画像が存在する）かを返す。
        # resolve_* が allow_generation: true でプレースホルダーではなく実画像を返せるかと一致する。
        # 未指定・URL/url() 指定は検証対象外として true（既定画像・外部指定のため）。
        # @param raw [String, nil] book.yml の frontispiece/ornament 指定値
        # @param variant [:portrait, :landscape] 判定するバリアント
        # @return [Boolean]
        def theme_image_available?(raw, variant:)
          return true if raw.nil? || raw.to_s.strip.empty?

          value = raw.to_s.strip
          return true if value =~ /^url\(/i || value =~ %r{^https?://}i

          slug = normalize_theme_image_slug(value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)
          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          # 既に該当バリアントがある / バリアント名を直接指定している / 生成元の base 画像がある、のいずれか
          return true if find_existing_theme_variant(base_slug, variant)
          return true if requested_variant && find_existing_theme_image(slug)

          !find_existing_theme_image(base_query).nil?
        end

        # バリアント画像を探索
        def find_existing_theme_variant(base_slug, variant)
          find_existing_theme_image("#{base_slug}_#{variant}", location_order: %i[user bundled],
                                                               allowed_extensions: ['.webp'])
        end

        # テーマ画像スラッグを正規化
        def normalize_theme_image_slug(value)
          value.to_s.strip.sub(%r{\Aimages/}, '').sub(%r{\A/+}, '')
        end

        # スラッグをベース名、バリアント、拡張子に分割
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

        # 既存テーマ画像を探索
        def find_existing_theme_image(slug, location_order: %i[user bundled],
                                      allowed_extensions: THEME_IMAGE_EXTENSIONS)
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

        # テーマ画像のルートディレクトリ
        def theme_images_root
          @theme_images_root ||= File.join(Common::STYLESHEETS_DIR, 'images')
        end

        # テーマ画像の相対パスを取得
        def theme_relative_path(path)
          path.sub(%r{\A#{Regexp.escape(theme_images_root)}/}, 'images/')
        end

        # 画像のアスペクト比を取得
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

        # frontispiece 用の許容アスペクト比かチェック
        def ratio_accepted_for_frontispiece?(ratio)
          frontispiece_allowed_ratios.any? do |allowed|
            next false if allowed.zero?

            ((ratio - allowed).abs / allowed) <= FRONTISPIECE_RATIO_TOLERANCE
          end
        end

        def frontispiece_allowed_ratios
          [binding_safe_portrait_ratio, 1.414].uniq
        end

        def binding_safe_portrait_ratio
          # page の版面キー（width 等）は page_presets 由来で存在保証がないため [] で参照する
          page_cfg = Common::CONFIG.page
          width_mm = Units.length_to_mm(page_cfg[:width]) || DEFAULT_PAGE_WIDTH_MM
          height_mm = Units.length_to_mm(page_cfg[:height]) || DEFAULT_PAGE_HEIGHT_MM
          margin_inner_mm = Units.length_to_mm(page_cfg[:margin_inner]) || 0
          margin_outer_mm = Units.length_to_mm(page_cfg[:margin_outer]) || 0

          binding_delta = [margin_inner_mm - margin_outer_mm, 0].max
          effective_width = width_mm - binding_delta
          effective_width = width_mm * 0.4 if effective_width <= width_mm * 0.4
          ratio = height_mm / [effective_width, 1.0].max

          ratio.clamp(MIN_BINDING_RATIO, MAX_BINDING_RATIO)
        rescue StandardError
          1.414
        end

        # プレースホルダーURIを生成
        def placeholder_uri(base_slug, placeholder_svg)
          base_name = base_slug.to_s.strip.empty? ? 'missing' : File.basename(base_slug)
          filename = "#{base_name}.webp"
          svg_placeholder_uri(placeholder_svg, filename)
        end

        # SVGプレースホルダーをdata URIに変換
        def svg_placeholder_uri(svg_template, filename)
          replaced = svg_template.gsub('filename.webp', CGI.escapeHTML(filename))
          svg_to_data_uri(replaced)
        rescue StandardError => e
          Common.log_warn("プレースホルダー生成に失敗しました: #{e.message}")
          'data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E'
        end

        # SVGをdata URIに変換
        def svg_to_data_uri(svg_content)
          # シンプルにURL encoding
          encoded = URI.encode_www_form_component(svg_content)
          "data:image/svg+xml;charset=utf-8,#{encoded}"
        end
      end
    end
  end
end
