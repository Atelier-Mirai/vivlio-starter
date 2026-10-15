# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/image_trimmer.rb
# ================================================================
# 責務:
#   画像の「絵の範囲」を測り、余白を詰めて載せる（`trim=on`・image-trim-spec.md）。
#   - 測る: 四隅の色を背景とみなし、ImageMagick の trim で絵の範囲を得る（§3.2）。
#     結果は `crop` と同じ「上・右・下・左」のパーミルで返す。著者が同じ値を
#     `crop` に書いた場合と同じ出力になる。
#   - SVG を詰める: 写しの `viewBox` を書き換える（§3.4・§4）。`<image>` に埋め込むと
#     PNG に焼かれて文字がぼやけるため、`crop` も SVG ではこちらを通す。
#   - 余白の多い画像を `vs preflight` で知らせる（§5）。
#
# ラスターの切り抜きは ShowcaseTransformer#crop_assets（今の `crop`）に任せる。
# ここが受け持つのは「値を測ること」と「SVG の窓を変えること」だけである。
#
# ShowcaseTransformer はこのファイルを require し、こちらは呼び出し時に参照するだけにする
# （showcase の中の trim=on を測るため、両者は互いを使う）。
# ================================================================

require 'digest'
require 'json'
require 'monitor'
require 'nokogiri'
require 'open3'
require_relative '../common'
require_relative '../masking'
require_relative '../build/derived_svg'
require_relative 'generated_asset_cache'
require_relative 'image_path_normalizer'
require_relative 'issue_registry'
require_relative 'showcase_svg_builder'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 画像の余白を測って詰めるモジュール（image-trim-spec.md）
      module ImageTrimmer
        module_function

        # 生成物の種別名。キャッシュは .cache/vs/trim/、詰めた SVG は html/images/trim/<章>/。
        KIND = 'trim'

        # 測り方を変えたら上げる（既存の測定値と詰めた SVG を捨てさせるため）。
        # v2: SVG を書籍の書体で描いて測る（2026-10-15）。
        SCHEMA = 'v2'

        # どこまでを背景と同じ色とみなすか（§2.2）。WebP・JPEG の圧縮の揺れは 2% で消え、
        # 写真は 3% まで 1 画素も削られなかった。5% では写真や影の縁を削り始める。
        FUZZ_PERCENT = 2

        # 詰めた後に残す余白。詰めた絵の幅に対する割合で、四辺に同じ量を足す（§2.3）。
        # 全幅で約 3mm になり、23 章の SVG の雛形の上下の余白（12 単位 = 3mm）とそろう。
        MARGIN_RATIO = 0.02

        # 絵が画像の幅のこの割合に満たなければ、preflight で 💡 を出す（§5）。
        # 85% の画像を詰めると約 1.13 倍で載る。
        HINT_USAGE_BELOW = 0.85

        # SVG を測るときに描く長い辺の画素数（幅の 0.05% の精度で測れる）。
        MEASURE_EDGE = 2000

        # この中の要素は描かれない定義なので、背景の四角とみなさない（§3.3）。
        UNRENDERED_CONTAINERS = %w[defs clipPath mask pattern symbol marker].freeze

        # OS の fontconfig の既定の設定（Homebrew の Apple Silicon・Intel、Linux の順）。
        SYSTEM_FONTCONFIGS = %w[
          /opt/homebrew/etc/fonts/fonts.conf /usr/local/etc/fonts/fonts.conf /etc/fonts/fonts.conf
        ].freeze

        # SVG のルート要素の開始タグ。
        ROOT_TAG = /<svg\b[^>]*>/m

        # 💡 を出さない囲み。中の画像を記法が自前で組み、trim=on が効かない（§3.1）。
        HINT_EXCLUDED_CONTAINERS = %w[book-card].freeze

        # 測った結果。crop は [上, 右, 下, 左] のパーミル（余白を足し戻した後）、
        # usage は絵が画像の幅に占める割合（余白を足す前）。
        Measurement = Data.define(:crop, :usage) do
          def trimmed? = crop.any?(&:positive?)

          # 詰めた後、同じ幅に載せたときに何倍になるか。
          def scale = 1000.0 / (1000.0 - crop[1] - crop[3])
        end

        # 💡 の候補（原稿の位置と、画像の書き方）。
        HintCandidate = Data.define(:chapter, :line, :markdown, :attributes, :source)

        @hint_monitor = Monitor.new
        @hint_candidates = nil

        # --- 測る ---

        # 画像の絵の範囲を測る。結果は画像の中身をキーに .cache/vs/trim/ に残す。
        # @param source [String] 画像の実ファイル
        # @return [Measurement, nil] 測れない（一色だけ・ツールが無い・読めない）なら nil
        def measure(source, tools: default_tools)
          cache_file = File.join(GeneratedAssetCache.dir(KIND), "#{measure_key(source)}.json")
          return read_measurement(cache_file) if File.exist?(cache_file)
          return nil unless tools.available?

          box = tools.content_box(source)
          return nil unless box

          measurement = measurement_from(box)
          write_measurement(cache_file, measurement)
          measurement
        end

        # 描いた画像の大きさと絵の範囲（画素）から、余白を足し戻した crop を作る。
        # 余白は元の余白より大きくしない（画像の外へは広げない）。
        # @param box [Hash] { width:, height:, x:, y:, w:, h: }。w・h が 0 なら一色だけの画像
        # @return [Measurement, nil]
        def measurement_from(box)
          width, height, x, y, w, h = box.values_at(:width, :height, :x, :y, :w, :h)
          return nil unless w.positive? && h.positive?

          margin = w * MARGIN_RATIO
          top    = [y - margin, 0].max
          right  = [width - x - w - margin, 0].max
          bottom = [height - y - h - margin, 0].max
          left   = [x - margin, 0].max
          crop = [top / height, right / width, bottom / height, left / width].map { (it * 1000).round(2) }
          Measurement.new(crop:, usage: (w.to_f / width).round(4))
        end

        def measure_key(source)
          # SVG の字の範囲は書籍の書体で決まるので、書体の設定も鍵に入れる（DerivedSvg#fingerprint と同じ）。
          embedder = SvgFontEmbedder
          payload = [SCHEMA, Digest::SHA256.file(source).hexdigest, FUZZ_PERCENT, MARGIN_RATIO,
                     embedder.configured_heading_font, embedder.configured_body_font, embedder.configured_code_font].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        # 一色だけの画像も「測れない」と残し、次から描き直さない。
        def read_measurement(cache_file)
          data = JSON.parse(File.read(cache_file))
          data['crop'] && Measurement.new(crop: data['crop'], usage: data['usage'])
        rescue JSON::ParserError
          nil
        end

        def write_measurement(cache_file, measurement)
          FileUtils.mkdir_p(File.dirname(cache_file))
          File.write(cache_file, JSON.generate(measurement ? measurement.to_h : { blank: true }))
        end

        # --- SVG の背景の四角 ---

        # 測るときだけ、viewBox の全面を覆う背景の四角を取り除く（§3.3）。紙面では残る。
        # 線のある四角は枠なので残す。塗りを明示していない四角は、CSS のクラスで
        # `fill: none` の枠を描いているかもしれないので残す（外すと枠の内側まで詰めてしまう）。
        # @return [String] 測る用の SVG
        def strip_background(svg)
          doc = Nokogiri::XML(svg)
          viewbox = viewbox_of(svg[ROOT_TAG].to_s)
          return svg unless doc.root && viewbox

          backgrounds = doc.css('rect').select { background_rect?(it, viewbox) }
          return svg if backgrounds.empty?

          backgrounds.each(&:remove)
          doc.to_xml
        end

        def background_rect?(rect, viewbox)
          return false if rect.ancestors.any? { UNRENDERED_CONTAINERS.include?(it.name) }
          return false if rect['class']

          style = style_of(rect)
          fill = rect['fill'] || style['fill']
          stroke = rect['stroke'] || style['stroke']
          return false if fill.nil? || fill.strip == 'none'
          return false unless stroke.nil? || stroke.strip == 'none'

          covers?(rect, viewbox)
        end

        def style_of(node)
          node['style'].to_s.split(';').to_h do |decl|
            key, value = decl.split(':', 2)
            [key.to_s.strip, value.to_s.strip]
          end
        end

        # x・y が viewBox の原点で、幅・高さが viewBox と同じ（または 100%）か。
        def covers?(rect, viewbox)
          vx, vy, vw, vh = viewbox
          spans = lambda do |value, size|
            value.to_s.strip == '100%' || (value && (value.to_f - size).abs < 0.5)
          end
          (rect['x'].to_f - vx).abs < 0.5 && (rect['y'].to_f - vy).abs < 0.5 &&
            spans.call(rect['width'], vw) && spans.call(rect['height'], vh)
        end

        # --- SVG の窓 ---

        # ルートの viewBox（[x, y, 幅, 高さ]）。無ければ数値の width・height から作る。
        # @return [Array<Float>, nil]
        def viewbox_of(root)
          if (box = root[/\bviewBox\s*=\s*["']([^"']+)["']/, 1])
            values = box.split(/[\s,]+/).map(&:to_f)
            return values if values.size == 4 && values[2].positive? && values[3].positive?
          end

          width = absolute_length(root, 'width')
          height = absolute_length(root, 'height')
          width && height ? [0.0, 0.0, width[0], height[0]] : nil
        end

        # 属性の長さを [数値, 単位] で返す。% や無指定は nil。
        def absolute_length(root, name)
          value = root[/\s#{name}\s*=\s*["']\s*([\d.]+)([a-z]*)\s*["']/, 1]
          value && [value.to_f, root[/\s#{name}\s*=\s*["']\s*[\d.]+([a-z]*)\s*["']/, 1]]
        end

        # SVG の写しの viewBox を、crop（パーミル）で切り取った窓へ書き換える（§3.4）。
        # width・height は、% ならそのまま（詰めた分だけ大きく載る）、絶対値なら
        # viewBox の縮みと同じ比で縮める（描く縮尺は変わらず、余白だけが消える）。
        # @return [String, nil] viewBox を決められない SVG なら nil
        def window_svg(svg, crop)
          root = svg[ROOT_TAG]
          viewbox = root && viewbox_of(root)
          return nil unless viewbox

          top, right, bottom, left = crop
          vx, vy, vw, vh = viewbox
          w_ratio = (1000.0 - left - right) / 1000.0
          h_ratio = (1000.0 - top - bottom) / 1000.0
          window = [vx + (vw * left / 1000.0), vy + (vh * top / 1000.0), vw * w_ratio, vh * h_ratio]

          rewritten = set_attribute(root, 'viewBox', window.map { number(it) }.join(' '))
          { 'width' => w_ratio, 'height' => h_ratio }.each do |name, ratio|
            value, unit = absolute_length(root, name)
            rewritten = set_attribute(rewritten, name, "#{number(value * ratio)}#{unit}") if value
          end
          svg.sub(root) { rewritten }
        end

        def set_attribute(tag, name, value)
          pattern = /(\s#{name}\s*=\s*)(["'])[^"']*\2/
          return tag.sub(pattern) { "#{::Regexp.last_match(1)}\"#{value}\"" } if tag.match?(pattern)

          tag.sub(/<svg\b/) { "<svg #{name}=\"#{value}\"" }
        end

        def number(value) = format('%.2f', value).sub(/\.?0+\z/, '')

        # 詰めた SVG をワークスペースへ用意する。
        # @return [Array(String, String), nil] [HTML からの参照, data-vs-source に書く実ファイル]
        #   data-vs-source は PDF の差し替え（PdfBuilder#swap_images_for_pdf!）が書体を抱かせる
        #   入口になる。生成物の参照は asset_prefix を持たず、そのままでは差し替えの対象から外れ、
        #   図の文字が Type 3 で埋め込まれる（§3.4）。
        def svg_window_asset(source, crop, chapter_slug:)
          windowed = window_svg(File.read(source, encoding: 'utf-8'), crop)
          return nil unless windowed

          name = "#{Digest::SHA256.hexdigest("#{SCHEMA}|#{windowed}")[0, 16]}.svg"
          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', KIND, chapter_slug)
          ok = GeneratedAssetCache.fetch(KIND, [name], out_dir:) do |cache_dir|
            File.write(File.join(cache_dir, name), windowed, encoding: 'utf-8')
            true
          end
          ok ? ["images/#{KIND}/#{chapter_slug}/#{name}", File.join(GeneratedAssetCache.dir(KIND), name)] : nil
        end

        # --- 図の画像を切り抜く（段落に単独で置いた画像） ---

        # `crop` か `trim=on` のある画像を、切り抜いた画像の参照へ置き換える。
        # SVG は viewBox を書き換えた写し、ラスターは ShowcaseTransformer#crop_assets の合成画像。
        # `crop` と `trim=on` を併記したら `crop` を使う（警告は前処理の検証が原稿の行番号で出す）。
        # @return [Hash, nil] { svg:, source: }（SVG）／{ svg:, raster: }（ラスター）。
        #   切り抜かない・切り抜けないなら nil（元の画像のまま組む）
        def framed_image(image_line, chapter_slug:, source_filename:, tools: default_tools)
          image = ShowcaseSvgBuilder.scan_image([image_line])
          return nil unless image

          crop_value = image.attributes['crop']
          trim = image.attributes['trim'] == 'on'
          return nil unless crop_value || trim
          return framed_svg(image, chapter_slug:, source_filename:, tools:) if svg?(image.path)
          # ラスターの crop は値をそのまま crop_assets へ渡す。trim=on は先に測り、
          # 詰める余白が無ければ元の画像のまま組む（crop_assets 側でも同じ値を測り直すが、
          # 結果はキャッシュから読むだけで描き直さない）。
          return nil if crop_value.nil? && !trimmable_raster?(image, source_filename, tools:)

          svg, raster = ShowcaseTransformer.crop_assets(image_line, chapter_slug:, source_filename:)
          svg && { svg:, raster: }
        end

        def trimmable_raster?(image, source_filename, tools:)
          source = ShowcaseTransformer.resolve_image_file(image.path, source_filename)
          !source.nil? && !measured_trim(source, image, source_filename, tools:).nil?
        end

        def framed_svg(image, chapter_slug:, source_filename:, tools:)
          source = ShowcaseTransformer.resolve_image_file(image.path, source_filename)
          return nil unless source

          crop =
            if (value = image.attributes['crop'])
              viewbox = viewbox_of(File.read(source, encoding: 'utf-8')[ROOT_TAG].to_s)
              viewbox && ShowcaseSvgBuilder.parse_crop(value, orig_w: viewbox[2], orig_h: viewbox[3])
            else
              measured_trim(source, image, source_filename, tools:)&.crop
            end
          return nil unless crop&.any?(&:positive?)

          svg, original = svg_window_asset(source, crop, chapter_slug:)
          svg && { svg:, source: original }
        end

        # trim=on の測定。詰める余白が無ければ nil（元の画像のまま）。測れなければ 🟡 を出して nil。
        def measured_trim(source, image, source_filename, tools:)
          unless tools.available?
            ShowcaseTransformer.warn_tools_missing(source_filename)
            return nil
          end

          measurement = measure(source, tools:)
          warn_unmeasurable(source_filename, image.path) unless measurement
          measurement&.trimmed? ? measurement : nil
        end

        def svg?(path) = File.extname(path).casecmp?('.svg')

        def warn_unmeasurable(source_filename, image_path)
          Common.log_warn(
            "[trim] #{source_filename}: #{File.basename(image_path)} は一色だけの画像なので、余白を測れません。元の画像のまま組みます",
            detail: '→ 切り抜く範囲を自分で決めるときは crop を使ってください: {crop="30 100"}'
          )
        end

        # --- 余白の多い画像を知らせる（vs build・vs preflight の 🟡・§5） ---

        # 集めた候補を捨てる。章の前処理（SectionBuilder.preprocess_sections!）の最初に呼ぶ。
        def reset_hints!
          @hint_monitor.synchronize { @hint_candidates = [] }
        end

        # 原稿 1 章分から、trim=on が効くのに crop・trim を書いていない画像を拾う。
        # 前処理の最初（原稿そのままの行番号が使える時点）で呼ぶ。章の前処理は並列に
        # 走るので、測るのは report_hints! で全章を集めた後にまとめて行う。
        # build でも preflight でも同じものを出す（preflight を経ずに build する著者もいる）。
        def note_hint_candidates(content, chapter:)
          found = []
          containers = []
          Masking.each_prose_line(content) do |line, line_number|
            next if track_container(containers, line)
            next if containers.any? { HINT_EXCLUDED_CONTAINERS.include?(it) }

            candidate = hint_candidate(line, line_number, chapter)
            found << candidate if candidate
          end
          @hint_monitor.synchronize { (@hint_candidates ||= []).concat(found) }
        end

        # 囲みの開き・閉じを追う。囲みの行なら true。
        def track_container(containers, line)
          if (open = line.match(/\A\s*:{3,}\s*\{([^}]*)\}/))
            containers << open[1][/\.([\w-]+)/, 1].to_s
          elsif line.match?(/\A\s*:{3,}\s*\z/)
            containers.pop
          else
            return false
          end
          true
        end

        def hint_candidate(line, line_number, chapter)
          match = line.strip.match(/\A(!\[[^\]]*\]\(([^)\s]+)\))(?:\{([^}]*)\})?\z/)
          return nil unless match

          markdown, path, attributes = match.captures
          return nil if attributes.to_s.match?(/(?<![\w-])(?:crop|trim)=/)

          source = resolve_source(path, chapter)
          source && HintCandidate.new(chapter:, line: line_number, markdown:, attributes:, source:)
        end

        # 原稿の画像の書き方から実ファイルを引く（ImagePathNormalizer と同じ規則）。
        def resolve_source(path, chapter)
          return nil if path.match?(%r{\A(?:https?:|data:)})

          normalized = path.start_with?('images/') ? path : "images/#{chapter.delete_suffix('.md')}/#{path}"
          resolved = ImagePathNormalizer.resolve_existing_image(normalized)
          resolved && File.expand_path(resolved.delete_prefix('images/'), Common::IMAGES_DIR)
        end

        # 集めた候補を測り、余白の多い画像を 🟡 で知らせる。原稿の行を指し、直し方（before → after）と
        # 黙らせ方（{trim=off}）を添える指摘なので、lint の改善提案と同じ 🟡 にそろえる（💡 は原稿の
        # 場所を指さない補足に使う・terminal-output-notes.md）。終了コードは変えない。
        # 同じ画像を何か所で使っていても、知らせるのは最初の 1 か所（ほかの数を添える）。
        def report_hints!(tools: default_tools)
          candidates = @hint_monitor.synchronize { @hint_candidates.to_a.dup }
          return if candidates.empty? || !tools.available?

          candidates.sort_by { [it.chapter, it.line] }.group_by(&:source).each_value do |uses|
            measurement = measure(uses.first.source, tools:)
            next unless measurement && measurement.usage < HINT_USAGE_BELOW

            warn_wide_margin(uses, measurement)
          end
        end

        def warn_wide_margin(uses, measurement)
          first = uses.first
          others = uses.size > 1 ? "（ほか #{uses.size - 1} か所）" : ''
          message = "#{File.basename(first.source)} は、絵が画像の幅の #{(measurement.usage * 100).floor}% しか" \
                    "使っていません。余白を詰めると約 #{format('%.2f', measurement.scale)} 倍で載ります#{others}"
          before = first.attributes ? "#{first.markdown}{#{first.attributes}}" : first.markdown
          after = "#{first.markdown}{#{[first.attributes, 'trim=on'].compact.join(' ').strip}}"
          Common.log_warn(
            "#{first.chapter}:#{first.line} - #{message}",
            detail: "→ #{before} を #{after} に直してください。\n" \
                    '  余白を意図して残すときは {trim=off} と書くと、この指摘は出なくなります。'
          )
          IssueRegistry.record(chapter: first.chapter, line: first.line, severity: :warn, category: :image, message:)
        end

        # --- 外部ツール ---

        def default_tools = (@default_tools ||= Tools.new)

        # magick・rsvg-convert への依存をここへ隔離する（テストで差し替える）。
        class Tools
          def available? = ShowcaseTransformer.default_tools.available?

          # 絵の範囲を測る。SVG は背景の四角を外し、透明な背景に長い辺 MEASURE_EDGE で描く。
          # @return [Hash, nil] { width:, height:, x:, y:, w:, h: }（描いた画像の画素）
          def content_box(source)
            # SVG を描けなければ測らない（magick 自身の SVG の描き方は rsvg と結果が違う）。
            svg = File.extname(source).casecmp?('.svg')
            image = svg ? render_svg(source) : nil
            return nil if svg && image.nil?

            out, status = Open3.capture2(
              'magick', image ? 'png:-' : source, '-fuzz', "#{FUZZ_PERCENT}%", '-format', '%@ %w %h', 'info:',
              stdin_data: image.to_s, binmode: true, err: File::NULL
            )
            return nil unless status.success?

            parse_box(out)
          rescue StandardError
            nil
          end

          # `%@ %w %h` の出力（例: "565x550+40+30 680 600"）を読む。一色だけの画像は "0x0+W+H"。
          def parse_box(out)
            geometry, width, height = out.split
            w, h, x, y = geometry.to_s.match(/\A(\d+)x(\d+)([+-]\d+)([+-]\d+)\z/)&.captures&.map(&:to_i)
            return nil unless w

            { width: width.to_i, height: height.to_i, x:, y:, w:, h: }
          end

          private

          # **紙面と同じ書体で描く。** 書体を寄せた派生（DerivedSvg・PDF と EPUB が実際に使う SVG）を
          # 描き、rsvg には fontconfig 経由で書籍の書体（stylesheets/fonts/）を見せる。
          # macOS の rsvg は既定で CoreText を使い、書体名を見ずに OS の書体で描く。図の端に
          # 欧文の大きな字があると、紙面の字のほうが幅で 7%・上へ 12 単位はみ出し、詰めた窓で
          # 切れていた（実測 2026-10-15。和文中心の図は 1 画素差で一致）。派生の @font-face
          # （data: URI）は rsvg が読まないので、書体の実体は fontconfig から渡す。
          def render_svg(source)
            drawn = Build::DerivedSvg.prepare(source) || source
            svg = ImageTrimmer.strip_background(File.read(drawn, encoding: 'utf-8'))
            _, _, vw, vh = ImageTrimmer.viewbox_of(svg[ROOT_TAG].to_s) || [0, 0, 1, 1]
            size = vw >= vh ? ['-w', MEASURE_EDGE.to_s] : ['-h', MEASURE_EDGE.to_s]
            env = { 'PANGOCAIRO_BACKEND' => 'fc', 'FONTCONFIG_FILE' => fontconfig_file }
            png, status = Open3.capture2(env, 'rsvg-convert', *size, '-f', 'png', stdin_data: svg, binmode: true,
                                                                               err: File::NULL)
            status.success? && !png.empty? ? png : nil
          end

          # OS の既定の設定を読み込み、書籍の書体のフォルダを足した fontconfig の設定。
          # 既定の設定の場所は入れ方で違うので、あるものだけを読む（ignore_missing）。
          # **絶対パスで渡す。** fontconfig は相対パスを作業ディレクトリでなく自分の設定の置き場から引き、
          # 見つからないと黙って OS の既定へ落ちる（字の幅が紙面とずれる）。
          def fontconfig_file
            path = File.expand_path(File.join(GeneratedAssetCache.dir(KIND), 'fonts.conf'))
            content = <<~XML
              <?xml version="1.0"?>
              <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
              <fontconfig>
              #{SYSTEM_FONTCONFIGS.map { %(  <include ignore_missing="yes">#{it}</include>) }.join("\n")}
                <dir>#{File.expand_path(File.join(Common.stylesheets_dir, 'fonts'))}</dir>
              </fontconfig>
            XML
            unless File.exist?(path) && File.read(path) == content
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, content)
            end
            path
          end
        end
      end
    end
  end
end
