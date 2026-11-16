# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/theme_image_resolver.rb
# ================================================================
# 責務:
#   テーマ画像（扉絵・飾り画像）のパスを解決する。
#   指定された名前から実際のファイルパスまたはプレースホルダーを返す。
#
# 画像の置き場（v2-migration-plan.md §5.3 の 4。この順に探す）:
#   1. 本の直下からのパス（「/」を含み、そのファイルがあるとき。例: images/door/rose.png）
#   2. stylesheets/images/ の中の名前（:user。1.x からの著者の置き場）
#   3. 選ばれたテーマの images/ の中の名前（:theme。テーマ → 土台の順。standard の 12 枚の花）
#
# 名前で探すときの順序:
#   1. {name}_portrait.{webp,png,jpg,jpeg}（バリアント。手置き → 生成キャッシュ .cache/vs/theme-images/）
#   2. {name}.webp
#   3. {name}.png/.jpg/.jpeg
#   4. プレースホルダー SVG（見つからない場合）
#
# 返却形（generated-assets 移設仕様 §3.1）:
#   - stylesheets/images/ 内の実体   → 'images/<サブパス>'（stylesheets/ 基準・従来形）
#   - 生成キャッシュ内のバリアント   → 'theme-images/<サブパス>'（book-settings.css の
#     生成位置 .cache/vs/ 基準。BookSettingsCss.rebase_relative はこの形を素通しする）
#   - ほかの実体（テーマの images/・本の直下からのパス） → '../<本のルートからのパス>'
#     （stylesheets/ 基準）
#
# 生成キャッシュの中の名前（cache_stem）:
#   stylesheets/images/ の画像はそこからの相対（1.x と同じ）、ほかは本のルートからの相対
#   （themes/standard/images/sakura.webp → theme-images/themes/standard/images/sakura_portrait.webp）。
#   テーマごとに分けるので、テーマを替えても同じ名前の別の画像のバリアントを使わない。
#
# バリアント:
#   - portrait: 縦長（扉絵用、ページ比率に合わせて飾りの間を広げる）
#   - landscape: 横長（飾り画像用、2.39:1 シネマスコープ）
#
# 依存:
#   - ImageGenerator: バリアント画像の生成
# ================================================================

require 'cgi'
require 'uri'
require_relative '../common'
require_relative '../theme'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # テーマ画像パス解決モジュール
      module ThemeImageResolver
        THEME_IMAGE_EXTENSIONS = %w[.webp .png .jpg .jpeg].freeze

        # 扉絵・飾り画像の既定画像スラッグ。未指定時も無効な指定時もこの画像に寄せる。
        # （無効な color が既定色へフォールバックするのと揃えた挙動。standard テーマの桜を使う）
        FALLBACK_THEME_IMAGE_SLUG = 'sakura'

        # 万一バリアント解決に失敗したときの最終フォールバックパス（通常は到達しない）。
        # バリアントは生成キャッシュに出るため theme-images/ 形で指す（移設仕様 §3.1）。
        FRONTISPIECE_DEFAULT_PATH = 'theme-images/themes/standard/images/sakura_portrait.webp'
        ORNAMENT_DEFAULT_PATH = 'theme-images/themes/standard/images/sakura_landscape.webp'

        DEFAULT_PAGE_WIDTH_MM = 210.0
        DEFAULT_PAGE_HEIGHT_MM = 297.0
        MIN_BINDING_RATIO = 1.35
        MAX_BINDING_RATIO = 2.2
        FRONTISPIECE_RATIO_TOLERANCE = 0.05

        # 生成済みの扉絵の縦横比が、今の判型から求めた比とこれ以上ずれたら作り直す。
        # 生成時の丸め（画素の整数化・幅 2880px への縮小）より大きく、判型の違い
        # （ノドと小口の差が 2mm 変わるだけでも約 1%）を見逃さない幅
        CACHED_VARIANT_RATIO_TOLERANCE = 0.005

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
          book_path = book_root_image(value)

          # ornament用に landscape バリアント（2.39:1）を使用
          if requested_variant == :landscape
            if (direct = book_path || find_existing_theme_image(slug))
              return theme_relative_path(direct)
            end
          elsif !book_path && (variant_specific = find_existing_theme_image("#{base_slug}_landscape"))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (direct = book_path || find_existing_theme_image(base_query))
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
              # かつて `system("vs resize:high …")` と書いていたが、**そんなコマンドは無い**
              # （`vs resize --high` であって `resize:high` は登録されていない）。存在しない
              # サブコマンドを渡すと `vs` はヘルプを出して終わるので、WebP は 1 枚も
              # 生成されていなかった（2026-08-17 に実測して発覚）。素材が既に WebP の
              # プロジェクトでは通らない経路のため、長く露見しなかった。
              # 直接呼べばプロセスの起動も要らない。
              ResizeCommands.execute_resize_high(dir)
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
          book_path = book_root_image(value)

          if (requested_variant == variant) && (direct = book_path || find_existing_theme_image(slug))
            return theme_relative_path(direct)
          end

          if !book_path && (variant_specific = find_existing_theme_variant(base_slug, variant))
            return theme_relative_path(variant_specific)
          end

          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          if (user_source = book_path || find_existing_theme_image(base_query, location_order: [:user]))
            ratio = image_ratio(user_source)
            return theme_relative_path(user_source) if ratio && ratio_accepted_for_frontispiece?(ratio)

            if allow_generation
              require_relative 'image_generator'
              if (generated = ImageGenerator.ensure_variant_generated(user_source, variant))
                return theme_relative_path(generated)
              end
            end
          end

          if allow_generation && (theme_source = find_existing_theme_image(base_query, location_order: [:theme],
                                                                                       allowed_extensions: ['.webp']))
            require_relative 'image_generator'
            if (generated = ImageGenerator.ensure_variant_generated(theme_source, variant))
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
          return true if book_root_image(value)

          slug = normalize_theme_image_slug(value)
          base_slug, requested_variant, ext = split_slug_and_variant(slug)
          base_query = ext.empty? ? base_slug : "#{base_slug}#{ext}"

          # 既に該当バリアントがある / バリアント名を直接指定している / 生成元の base 画像がある、のいずれか
          return true if find_existing_theme_variant(base_slug, variant)
          return true if requested_variant && find_existing_theme_image(slug)

          !find_existing_theme_image(base_query).nil?
        end

        # バリアント画像を探索。
        # ユーザーが stylesheets/images/ に手置きしたバリアント（意図的な上書き）を優先し、
        # 次に生成キャッシュ（.cache/vs/theme-images/。ImageGenerator の出力先）を見る。
        # 手置きは元画像と同じく WebP・PNG・JPEG を受ける（ornament の直接探索と揃える）。
        def find_existing_theme_variant(base_slug, variant)
          find_existing_theme_image("#{base_slug}_#{variant}") || find_cached_theme_variant(base_slug, variant)
        end

        # 生成キャッシュ内のバリアントを探索する（名前の決まりはファイル冒頭の cache_stem）。
        # stylesheets/images/ の画像のバリアントはキャッシュの直下の同じサブパスに、テーマの画像の
        # バリアントは theme-images/themes/<名前>/images/ に出る。
        def find_cached_theme_variant(base_slug, variant)
          stems = [base_slug, *theme_image_dirs.map { cache_stem(File.join(it, theme_slug(base_slug))) }]
          stems.uniq.each do |stem|
            path = File.join(theme_images_cache_root, "#{stem}_#{variant}.webp")
            return path if File.exist?(path) && cached_variant_current?(path, variant)
          end

          nil
        end

        # 生成キャッシュのバリアントが今も使えるか。元画像を描き直した（元のほうが新しい）とき、
        # 扉絵では判型が変わって縦横比が合わなくなったときは false（作り直す）。
        # 元画像が見つからないときは、残っているバリアントを使う。
        # @param cached_path [String] 生成キャッシュ内のバリアント
        # @param variant [:portrait, :landscape]
        # @return [Boolean]
        def cached_variant_current?(cached_path, variant)
          source = variant_source(cached_path, variant)
          return true unless source
          return false if File.mtime(source) > File.mtime(cached_path)
          return true unless variant == :portrait

          ratio = image_ratio(cached_path)
          expected = binding_safe_portrait_ratio
          ratio.nil? || ((ratio - expected).abs / expected) <= CACHED_VARIANT_RATIO_TOLERANCE
        end

        # 生成キャッシュのバリアントの元画像。cache_stem の逆で、stylesheets/images/ の同じサブパスか、
        # 本のルートからの同じパス（テーマの images/ など）
        def variant_source(cached_path, variant)
          stem = cached_path.delete_prefix("#{theme_images_cache_root}/").delete_suffix("_#{variant}.webp")
          [File.join(theme_images_root, stem), stem].product(THEME_IMAGE_EXTENSIONS)
                                                    .map(&:join).find { File.exist?(it) }
        end

        # 生成キャッシュの中の、元画像に対応する名前（拡張子なし）。stylesheets/images/ の画像は
        # そこからの相対（1.x と同じ）、ほかは本のルートからの相対
        # @param source_path [String] 元画像（本のルートからの相対か、絶対パス）
        def cache_stem(source_path)
          stem = book_relative(source_path).sub(/\.[^.]+\z/, '')
          stem.delete_prefix("#{book_relative(theme_images_root)}/")
        end

        # 本のルートからの相対パス（作業ディレクトリの下の絶対パスを相対にする）
        def book_relative(path)
          path.to_s.delete_prefix("#{Dir.pwd}/")
        end

        # 置き場の 1（本の直下からのパス）。「/」を含み、本の中にその画像があるときだけ、そのパスを返す。
        # 名前だけの指定（sakura）は 2・3 の置き場で探す
        # @return [String, nil]
        def book_root_image(value)
          path = value.to_s.strip.delete_prefix('./')
          return nil unless path.include?('/') && !path.start_with?('/') && !path.split('/').include?('..')
          return nil unless THEME_IMAGE_EXTENSIONS.include?(File.extname(path).downcase)

          path if File.file?(path)
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

        # 既存テーマ画像を名前で探索する。:user は stylesheets/images/、:theme はテーマの images/
        def find_existing_theme_image(slug, location_order: %i[user theme],
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
            dirs, names = loc == :user ? [[theme_images_root], candidates] : [theme_image_dirs, candidates.map { theme_slug(it) }]
            dirs.product(names).each do |dir, name|
              path = File.join(dir, name)
              return path if File.exist?(path)
            end
          end

          nil
        end

        # テーマの images/ の中で探す名前。1.x の「bundled/<名前>」（同梱の画像を、同じ名前の独自画像より
        # 先に使う書き方。stylesheets/images/bundled/ にあった）は、テーマの画像の名前として読む
        def theme_slug(slug) = slug.delete_prefix('bundled/')

        # 著者のテーマ画像の置き場（stylesheets/images/）
        def theme_images_root
          @theme_images_root ||= File.join(Common::STYLESHEETS_DIR, 'images')
        end

        # 選ばれたテーマの images/（テーマ → 土台の順）。テーマが読めなければ空。
        # テストは @theme_image_dirs を差し替える
        def theme_image_dirs
          @theme_image_dirs || Theme.selected&.chain&.reverse&.map { File.join(it.dir, 'images') } || []
        end

        # 生成バリアントのキャッシュルート（.cache/vs/theme-images/）。
        # theme_images_root と同様に ivar でメモ化し、テストが一時 dir へ差し替えられるようにする。
        def theme_images_cache_root
          @theme_images_cache_root ||= Common.theme_images_cache_dir
        end

        # テーマ画像の CSS 用相対パスを取得（返却 2 形はファイル冒頭コメント参照）
        def theme_relative_path(path)
          cache_prefix = "#{theme_images_cache_root}/"
          return "theme-images/#{path.delete_prefix(cache_prefix)}" if path.start_with?(cache_prefix)

          user_prefix = "#{theme_images_root}/"
          return "images/#{path.delete_prefix(user_prefix)}" if path.start_with?(user_prefix)

          "../#{book_relative(path)}"
        end

        # 画像のアスペクト比（縦 / 横）を取得。章ごとに同じ画像を何度も調べるので、
        # パスと更新日時ごとに覚えておく（Common.image_size は magick を起動する）
        def image_ratio(path)
          key = [path, File.mtime(path)]
          @image_ratio_cache ||= {}
          return @image_ratio_cache[key] if @image_ratio_cache.key?(key)

          width, height = Common.image_size(path)
          @image_ratio_cache[key] = (height.to_f / width if width)
        rescue SystemCallError
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
          # 紙の幅・高さは book.yml に書かれず判型（size）から決まるので、
          # BookSettingsCss と同じく normalize_page_size! で補ってから読む
          page = Common::CONFIG.page
          page_cfg = Common.normalize_page_size!(page.respond_to?(:to_h) ? page.to_h : {})
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
        # フォームの符号化は空白を `+` にするが、data URI では `+` は空白に戻らない
        # （`<svg+xmlns=…` という読めない SVG になる）ので %20 に直す。文字の `+` は %2B になっている
        def svg_to_data_uri(svg_content)
          encoded = URI.encode_www_form_component(svg_content).gsub('+', '%20')
          "data:image/svg+xml;charset=utf-8,#{encoded}"
        end
      end
    end
  end
end
