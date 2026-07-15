# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/showcase_transformer.rb
# ================================================================
# 責務:
#   図解注釈記法 :::{.showcase} ブロックを前処理で丸ごと消費し、
#   「元画像＋注釈を焼き込んだ合成 SVG」への <figure><img> 参照へ置換する
#   （explanatory-diagram-spec.md §6.1）。
#
# なぜ前処理で合成 SVG を焼くのか（§6.2）:
#   HTML + position:absolute の重ね合わせは PDF では動くが、リフロー型 EPUB
#   （特に Kindle）は固定寸法・重ね合わせを描画しない（章扉 ③-a で実証済み）。
#   合成 SVG に一本化すれば PDF/EPUB/Kindle が 1 つの生成物を共有でき、出力は
#   素の <figure><img> なので Kindle 向けの CSS 劣化対策がそもそも不要になる。
#
# 出力（§6.3）:
#   - SVG: PDF 用（注釈がベクタのまま印刷解像度で出る）。元画像は base64 PNG で埋め込む
#     （<img> から参照される SVG は外部リソースを読めないため）。
#   - ラスター: EPUB/Kindle 用（Kindle は SVG 内 base64 を非対応）。EpubBuilder が src を
#     data-vs-raster の値へ差し替える（§7.9）。形式は元画像の素性で選び分ける（下記）。
#
# ラスター形式の自動判定（PHOTO_COLOR_THRESHOLD）:
#   スクリーンショットは平坦色で、JPEG にすると文字端にリンギングが出るうえ PNG より
#   むしろ大きい（実測: 2600px 幅で PNG 6.7KB / JPEG 19KB）。一方、写真は PNG が可逆ゆえに
#   極端に太る（同 PNG 3.0MB / JPEG 412KB）——保護すべき文字端が無いので、その差は利益を
#   生まない。そこで元画像のユニーク色数で写真かどうかを判定し、PNG と JPEG を選び分ける。
#   色数の実測: PDF ページ描画（スクショ相当）664〜875 / 平坦なロゴ 5,648 / 写真 17,122〜92,141。
#   「色数 ÷ 画素数」の比率は小さなロゴが写真と重なるため使えず、絶対値で判定する。
#
# フォールバック（§6.4）:
#   magick / rsvg-convert のどちらかが欠ける・画像が解決できない場合は
#   「注釈なしの通常画像」へ縮退する（画像行だけを残す）。原稿がビルド不能になることはない。
# ================================================================

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require_relative '../common'
require_relative 'markdown_utils'
require_relative 'showcase_svg_builder'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # :::{.showcase} ブロックを合成画像へ変換するモジュール
      module ShowcaseTransformer
        module_function

        # 生成物の出力先（images/ 配下）。著者画像（images/<章>/…）とは別系統に置く。
        REL_BASE = 'showcase'

        # ブロック全体（開きフェンス〜閉じフェンス）。中身を丸ごと消費する。
        BLOCK_PATTERN = /^:::\s*\{\s*\.showcase\s*\}[ \t]*\n(.*?)^:::[ \t]*\n?/m

        # SVG へ埋め込む元画像の最大長辺（スクリーンショットの文字が潰れない上限）。
        EMBED_MAX_EDGE = 2000

        # ラスタライズ倍率と上限幅（リーダー側の縮小表示で鮮明に見せるため 2 倍で焼く）。
        RASTER_SCALE     = 2
        RASTER_MAX_WIDTH = 2600

        # 元画像を「写真」とみなすユニーク色数の下限（冒頭コメントの実測値に基づく。
        # ロゴ 5,648 と写真 17,122 の谷に置いた）。これ以上なら JPEG、未満なら PNG。
        PHOTO_COLOR_THRESHOLD = 8192

        # 本文中の showcase ブロックをすべて <figure> へ置換する。
        #
        # コードスパンを退避してから走査する——記法そのものを解説する原稿（拡張記法
        # リファレンス）では ```markdown フェンスの中に showcase ブロックの**書き方の例**が
        # 書かれており、退避しないと作例が変換に食われて消える。
        #
        # @param content [String] 処理対象の Markdown 本文
        # @param chapter_slug [String] 生成物の出力先章ディレクトリ名（例: "10-intro"）
        # @param source_filename [String] 警告に出す原稿ファイル名
        # @param tools [#available?, #image_dimensions, #data_uri, #rasterize] 外部ツール
        #   （テスト差し替え用。既定は magick + rsvg-convert）
        # @return [String] 置換後の本文
        def transform(content, chapter_slug:, source_filename:, tools: default_tools)
          return content unless content.match?(BLOCK_PATTERN)

          text, spans = MarkdownUtils.extract_code_spans(content)
          text = text.gsub(BLOCK_PATTERN) do
            render_block(::Regexp.last_match(1).lines, chapter_slug:, source_filename:, tools:)
          end
          MarkdownUtils.restore_code_spans(text, spans)
        end

        # ブロック 1 つ分を HTML（または縮退した画像記法）へ変換する。
        def render_block(lines, chapter_slug:, source_filename:, tools:)
          image = ShowcaseSvgBuilder.scan_image(lines)
          unless image
            warn_no_image(source_filename)
            return ''
          end
          warn_extra_images(source_filename) if ShowcaseSvgBuilder.image_line_count(lines) > 1

          composed = compose(image, lines, chapter_slug:, source_filename:, tools:)
          return plain_image(image) unless composed

          block, svg_rel, raster_rel = composed
          figure(svg_rel, raster_rel, ShowcaseSvgBuilder.alt_text(block), block.width)
        end

        # 合成 SVG とラスターを（必要なら）生成し、参照パスを返す。縮退すべき場合は nil。
        # @return [Array(ShowcaseSvgBuilder::ShowcaseBlock, String, String), nil]
        #   [ブロック, SVG 参照パス, ラスター参照パス]
        def compose(image, lines, chapter_slug:, source_filename:, tools:)
          source = resolve_image_file(image.path, source_filename)
          return nil unless source

          unless tools.available?
            warn_tools_missing(source_filename)
            return nil
          end

          dims = tools.image_dimensions(source)
          unless dims
            warn_tools_missing(source_filename)
            return nil
          end

          orig_w, orig_h = dims
          block = ShowcaseSvgBuilder.parse(lines, orig_w:, orig_h:,
                                                  on_warn: ->(line) { warn_unparsable(line, source_filename) })
          key = cache_key(source, block)
          out_dir = File.join(Common::BUILD_HTML_DIR, 'images', REL_BASE, chapter_slug)
          # 元画像の素性でラスター形式を選ぶ（冒頭コメント参照）。同じ画像なら判定も同じに
          # なるため、キャッシュキーに形式を含める必要はない。
          ext = tools.photographic?(source) ? 'jpg' : 'png'
          return nil unless write_assets!(block, key, out_dir, ext, source:, orig_w:, orig_h:, tools:)

          # <img> の参照は消費者 dir 相対（asset_prefix 無し）。数式 SVG と同じ理由で、
          # ビルド生成物は workspace 内実体のため EPUB の prefix 剥がしを素通りし、
          # PDF は pdf/ ミラーで解決する（math_transformer.rb P4b §2.1 コメント参照）。
          rel_dir = "images/#{REL_BASE}/#{chapter_slug}"
          [block, "#{rel_dir}/#{key}.svg", "#{rel_dir}/#{key}.#{ext}"]
        end

        # 未生成なら SVG とラスターを対で書き出す。既に両方あればスキップ（--no-clean で効く）。
        # @return [Boolean] 参照可能な生成物が揃ったか
        def write_assets!(block, key, out_dir, ext, source:, orig_w:, orig_h:, tools:)
          svg_path    = File.join(out_dir, "#{key}.svg")
          raster_path = File.join(out_dir, "#{key}.#{ext}")
          return true if File.exist?(svg_path) && File.exist?(raster_path)

          data_uri = tools.data_uri(source)
          return false unless data_uri

          svg = ShowcaseSvgBuilder.build(block, orig_w:, orig_h:, data_uri:)
          raster = tools.rasterize(svg, raster_width(block, orig_w:, orig_h:), format: ext.to_sym)
          return false unless raster

          FileUtils.mkdir_p(out_dir)
          File.write(svg_path, svg, encoding: 'utf-8')
          File.binwrite(raster_path, raster)
          true
        end

        # 画像内容をキーに含めるため、著者がスクリーンショットを撮り直せば再生成される。
        def cache_key(source, block)
          payload = [
            'v1',
            Digest::SHA256.file(source).hexdigest,
            block.crop.join(','),
            JSON.generate(block.annotations.map(&:to_h))
          ].join('|')
          Digest::SHA256.hexdigest(payload)[0, 16]
        end

        def raster_width(block, orig_w:, orig_h:)
          width, = ShowcaseSvgBuilder.cropped_size(block, orig_w:, orig_h:)
          [(width * RASTER_SCALE).round, RASTER_MAX_WIDTH].min
        end

        # 正規化済みの画像参照（asset_prefix + images/…）から実ファイルパスを解決する。
        # ImagePathNormalizer が既に .webp 寄せ・存在チェックを済ませているため、
        # ここでは prefix を剥がして Common::IMAGES_DIR 基準で引き当てるだけでよい。
        def resolve_image_file(src, source_filename)
          # 画像不在時に normalizer が差し込む data URI プレースホルダ（既に 🔴 で報告済み）
          return nil if src.start_with?('data:')

          if src.start_with?('http://', 'https://')
            warn_remote_image(source_filename, src)
            return nil
          end

          rel = src.delete_prefix(Common.asset_prefix)
          return nil unless rel.start_with?('images/')

          path = File.expand_path(rel.delete_prefix('images/'), Common::IMAGES_DIR)
          File.exist?(path) ? path : nil
        end

        # 置換後の HTML。前後に空行を補い独立段落として組ませる。
        # ラスターの参照を data-vs-raster に明示して持たせる——形式が png / jpg のどちらにも
        # なりうるため、EpubBuilder 側で拡張子を推測させない（推測させると --no-clean ビルドで
        # 前回形式の残骸を拾いうる）。EpubBuilder は使用後にこの属性を取り除く。
        def figure(svg_rel, raster_rel, alt, width)
          "\n\n<figure class=\"vs-showcase\">\n" \
            "<img class=\"vs-showcase\" src=\"#{svg_rel}\" data-vs-raster=\"#{raster_rel}\" " \
            "alt=\"#{escape_attr(alt)}\" style=\"width: #{escape_attr(width)};\">\n" \
            "</figure>\n\n"
        end

        # 縮退時の出力。注釈を捨て、画像行だけを通常の画像記法として残す。
        def plain_image(image) = "\n\n![#{image.alt}](#{image.path})\n\n"

        def escape_attr(str)
          str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
        end

        # --- 警告（§7.10: 修正例と出現位置を必ず添える） ---

        def warn_no_image(source_filename)
          Common.log_warn(
            "[showcase] #{source_filename}: showcase ブロックに画像がありません。ブロックを出力しません",
            detail: '→ 先頭に ![説明](screenshot.png) を置いてください'
          )
        end

        def warn_extra_images(source_filename)
          Common.log_warn(
            "[showcase] #{source_filename}: showcase ブロック内に画像が 2 枚あります。2 枚目以降は無視します",
            detail: '→ 1 ブロック 1 画像です。別の :::{.showcase} ブロックに分けてください'
          )
        end

        def warn_tools_missing(source_filename)
          Common.log_warn(
            "[showcase] #{source_filename}: ImageMagick / librsvg が見つからないため注釈なしの画像に縮退します",
            detail: '→ `vs doctor --fix` で導入できます（brew install imagemagick librsvg）'
          )
        end

        def warn_unparsable(line, source_filename)
          Common.log_warn(
            %([showcase] #{source_filename} 内の記法を解釈できません: "#{line}"),
            detail: '→ 座標はカンマ区切りです。例: rect:1 190, 30, 360, 90 {pos=right} コメント'
          )
        end

        def warn_remote_image(source_filename, src)
          Common.log_warn(
            "[showcase] #{source_filename}: 外部 URL の画像（#{src}）は注釈できません。通常の画像として出力します",
            detail: '→ 画像を images/ 配下へ置き ![説明](screenshot.png) と書いてください'
          )
        end

        # 既定の外部ツール（magick + rsvg-convert）。
        def default_tools = (@default_tools ||= ImageTools.new)

        # 外部ツール依存をこのクラスへ隔離する（builder は純関数のまま保つ・§7.1）。
        class ImageTools
          # magick と rsvg-convert が両方揃っているか。
          def available?
            return @available unless @available.nil?

            @available = tool_ok?('magick', '-version') && tool_ok?('rsvg-convert', '--version')
          end

          # 元画像の実寸（px→パーミル変換・viewBox 計算に使う）。
          # @return [Array(Integer, Integer), nil]
          def image_dimensions(path)
            out, status = Open3.capture2('magick', 'identify', '-format', '%w %h', path)
            return nil unless status.success?

            width, height = out.split.map(&:to_i)
            (width.to_i.positive? && height.to_i.positive?) ? [width, height] : nil
          rescue StandardError
            nil
          end

          # 元画像が写真か（＝ユニーク色数が多いか）。スクリーンショットは平坦色で色数が
          # 桁違いに少ない（冒頭コメントの実測値）。判定はキャッシュ未ヒット時のみ走り、
          # 実測 0.2〜0.35 秒。
          def photographic?(path)
            out, status = Open3.capture2('magick', 'identify', '-format', '%k', path)
            return false unless status.success?

            out.strip.to_i > PHOTO_COLOR_THRESHOLD
          rescue StandardError
            false
          end

          # 元画像を PNG の base64 data URI へ。EMBED_MAX_EDGE まで縮小して軽量化する
          # （viewBox は元画像実寸で張るため、縮小しても座標計算には影響しない）。
          def data_uri(path)
            png, status = Open3.capture2(
              'magick', path, '-resize', "#{EMBED_MAX_EDGE}x#{EMBED_MAX_EDGE}>", 'png:-', binmode: true
            )
            return nil unless status.success? && !png.empty?

            # base64 は Ruby 3.4+ で default gem 外のため Array#pack('m0')（改行なし base64）で代替
            "data:image/png;base64,#{[png].pack('m0')}"
          rescue StandardError
            nil
          end

          # 合成 SVG をラスター（バイト列）へ変換する。JPEG は透過を持てないため白で
          # フラット化する（リーダーの白ページと馴染ませる。HeadingImageComposer と同じ流儀）。
          #
          # @param format [Symbol] :png（可逆・透過保持）/ :jpg（写真向け）
          def rasterize(svg, width, format: :png)
            png, status = Open3.capture2('rsvg-convert', '-w', width.to_s, '-f', 'png',
                                         stdin_data: svg, binmode: true)
            return nil unless status.success? && !png.empty?
            return png if format == :png

            jpg, jpg_status = Open3.capture2('magick', 'png:-', '-background', 'white', '-flatten',
                                             '-quality', '85', 'jpg:-', stdin_data: png, binmode: true)
            (jpg_status.success? && !jpg.empty?) ? jpg : nil
          rescue StandardError
            nil
          end

          private

          def tool_ok?(command, flag) = system(command, flag, out: File::NULL, err: File::NULL) || false
        end
      end
    end
  end
end
