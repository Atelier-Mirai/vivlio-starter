# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/inject_heading_images.rb
# ================================================================
# 責務:
#   扉絵（h1）・節絵（h2）の合成画像を見出しへ入れる
# ================================================================

require 'digest'
require 'fileutils'
require_relative '../../epub/workspace'
require_relative '../../heading_image_composer'
require_relative '../context'
require_relative '../dom'
require_relative '../../../pre_process/book_settings_css'
require_relative '../../../pre_process/frontmatter_generator'

module VivlioStarter
  module CLI
    module Build
      # 扉絵（h1）・節絵（h2）の合成画像を見出しへ入れる
      module Transforms::Shared::InjectHeadingImages
        module_function

        # ================================================================
        # EPUB 用 扉絵（h1）・節絵（h2）の合成画像注入（③-a）
        # ================================================================
        # PDF は @page 背景＋固定寸法で扉絵を全面描画するが、リフロー型 EPUB は
        # 背景・固定寸法・重ね合わせが（特に Kindle で）描画されない。そこで EPUB
        # 経路でのみ、飾り画像＋見出しを 1 枚に焼き込んだ合成画像（HeadingImageComposer
        # が SVG を組み JPEG にラスタライズ）を <img> として見出しに差し込む。
        # Kindle は SVG 内 base64 を非対応のため SVG ではなくフラット JPEG を配る。
        # 目次（nav）は各章の <title> から生成され h1 テキストに依存しないため、見出しを
        # 画像へ置換しても目次は壊れない（見出しテキストは <img alt> に保持）。
        # PDF 完成後に共有 HTML を書き換えるため PDF 経路へ副作用はない（Step E）。
        # ================================================================

        # 扉絵・節絵を合成画像として見出しに焼き込む（theme.style=image のときのみ）。
        # 画像解決や合成に失敗したファイルは注入をスキップし simple 相当へ縮退する（§B-5）。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          features = BuildPlan.current.features
          return unless features.frontispiece || features.ornament

          context = ctx.remember(:heading_images) { heading_image_context(ctx.flavor) }
          inject_heading_images!(doc, ctx.path, context) if context
        end

        # 本の全部のページで同じ値（テーマの画像・書体・寸法）。テーマの画像が無ければ nil
        def heading_image_context(flavor)
          theme = read_theme_heading_assets
          return nil unless theme

          {
            frontispiece: theme[:frontispiece],
            ornament: theme[:ornament],
            font_family: epub_heading_font_family,
            metrics: epub_heading_metrics,
            number_color: theme[:number_color],
            flavor:
          }
        end

        # 見出しの寸法。合成画像側の字面・折返しをこれで決める。
        # 既定値は PDF 側（BookSettingsCss::DEFAULT_*_CHARS ＝ tokens.css の既定）と共有する
        # ——別々に持つと同じ原稿の扉・節絵が PDF と EPUB で違う字数に組まれる（§5-2）。
        # 節題だけは、字数でなく章題との大きさの比を PDF にそろえる（epub_ornament_chars）。
        # @return [Hash]
        def epub_heading_metrics(settings = nil)
          settings ||= PreProcessCommands::FrontmatterGenerator.parse_theme_settings
          bsc = PreProcessCommands::BookSettingsCss
          heading_chars = settings[:heading_chars_value] || bsc::DEFAULT_HEADING_CHARS
          ornament_chars = settings[:ornament_heading_chars_value] || bsc::DEFAULT_ORNAMENT_HEADING_CHARS
          { heading_chars:, ornament_chars: epub_ornament_chars(heading_chars, ornament_chars) }
        end

        # EPUB の節題の字数。章題に対する節題の大きさを、PDF と同じ比にそろえる。
        #
        # PDF の章題は判型で決まる大きさ、節題は版面幅 ÷ ornament.heading_chars で、A4 なら
        # 節題は章題の 0.73 倍になる。EPUB の章扉は横長の帯で、左右の飾りを避けて章題を
        # 中央 60% に組むぶん、PDF より小さい。節題を book.yml の字数のまま組むと、章題と
        # ほぼ同じ大きさに見える（Kindle Previewer で 0.94 倍）。そこで節題を、PDF の比に
        # なる字数へ置き換える（A4・章題 10 字・節題 14 字なら 18 字）。
        def epub_ornament_chars(heading_chars, ornament_chars)
          bsc = PreProcessCommands::BookSettingsCss
          page_cfg = bsc.build_page_cfg(Common::CONFIG)
          scale = bsc.paper_scale_of(page_cfg)
          section_q = bsc.section_title_font_q(ornament_chars, bsc.text_area_width_mm(page_cfg), scale).to_f
          ratio = section_q / bsc.chapter_title_font_q(scale)
          HeadingImageComposer::ORNAMENT_TEXT_WIDTH / (ratio * HeadingImageComposer.frontispiece_title_ratio(heading_chars))
        rescue StandardError
          ornament_chars
        end

        # 扉絵・節絵の実画像パスと節番号色を取得する。
        # PDF と同一画像を単一の参照元から使う（二重解決を避ける・§B-4）。
        #
        # P3 以降、tokens.css は読み取り専用のテーマ資産となり book.yml の設定は
        # book-settings.css へ書き出されるため、tokens.css の正規表現読みでは設定変更を
        # 拾えず既定値に化ける（調査報告 §7.1）。そこで生成器と同じ参照元
        # （parse_theme_settings の計算値）を直接使う。節番号色（--book-color-section-number）は
        # in-place 版でも書換対象外で常に var(--book-color-accent) だったため、book.yml で選ばれた
        # theme accent を、パレット定義（tokens.css の --book-accent-* は P3 でも不変）で具体色へ解決する。
        #
        # @return [Hash, nil] { frontispiece:, ornament:, number_color: }。解決不能時は nil
        def read_theme_heading_assets
          settings = PreProcessCommands::FrontmatterGenerator.parse_theme_settings
          theme_css_path = File.join(Common::STYLESHEETS_DIR, 'tokens.css')
          palette_css = File.exist?(theme_css_path) ? File.read(theme_css_path, encoding: 'utf-8') : ''

          {
            frontispiece: resolve_theme_image_file(theme_image_rel(frontispiece_landscape_path(settings))),
            ornament: resolve_theme_image_file(theme_image_rel(settings[:ornament_path])),
            number_color: resolve_css_color(palette_css, settings[:theme_accent_value])
          }
        rescue StandardError => e
          Common.log_warn("[EPUB] テーマ設定の読み取りに失敗（扉絵の画像化をスキップ）: #{e.message}")
          nil
        end

        # EPUB の扉絵に使う、theme.frontispiece.image の横長（landscape）版。PDF の章扉は縦長版を
        # ページの背景に敷くが、EPUB の章扉は見出しだけの横長の帯にする（chapter-lead-size-spec.md §2.2.1）。
        # 横長版は節絵と同じ解決で探し、無ければ生成する（著者が置いた画像でも作れる。
        # 未指定なら既定の sakura）。
        def frontispiece_landscape_path(settings)
          raw = settings[:theme_cfg]&.dig(:frontispiece)
          source = raw.is_a?(String) ? raw : raw&.dig(:image)
          PreProcessCommands::ThemeImageResolver.resolve_ornament_path(source, allow_generation: true)
        end

        # テーマ画像の解決結果（素の相対パス or url(...) or 外部 URL）から
        # stylesheets/ 基準の相対パスを取り出す。url(...) 形式ならその内側を返す。
        def theme_image_rel(value)
          v = value.to_s.strip
          return v unless v.start_with?('url(')

          v[/\Aurl\(\s*["']?(.*?)["']?\s*\)\z/i, 1].to_s
        end

        # テーマ画像の url(...) 値を実ファイルパスへ解決する。
        # 生成バリアント（theme-images/…）は生成キャッシュ基準、それ以外（images/…・../themes/…）は
        # stylesheets/ 基準で解決する（返却形は ThemeImageResolver の冒頭・移設仕様 §3.1/§3.2）。
        #
        # @param rel [String, nil] 例: "theme-images/themes/standard/images/sakura_portrait.webp" / "images/mypic.webp"
        # @return [String, nil] 存在する実ファイルパス、無ければ nil
        def resolve_theme_image_file(rel)
          return nil if rel.nil? || rel.strip.empty?
          return nil if rel.start_with?('data:', 'http://', 'https://')

          path = if rel.start_with?('theme-images/')
                   File.join(Common.cache_dir, rel)
                 else
                   File.join(Common::STYLESHEETS_DIR, rel)
                 end
          File.exist?(path) ? path : nil
        end

        # CSS 色値を具体色へ解決する。var(--book-color-accent) → var(--book-accent-yellow) → #f0a000 の
        # 連鎖を tokens.css 内の定義から辿る。解決できなければ既定のダークを返す。
        #
        # @param css [String] tokens.css 全文
        # @param value [String, nil] --book-color-section-number の値
        # @return [String] 具体的な CSS 色
        def resolve_css_color(css, value, depth = 0)
          v = value.to_s.strip
          return '#333333' if v.empty? || depth > 5

          if (m = v.match(/\Avar\(\s*(--[a-z0-9-]+)\s*\)\z/i))
            referenced = css[/#{Regexp.escape(m[1])}:\s*([^;]+);/, 1]
            return resolve_css_color(css, referenced, depth + 1)
          end

          v
        end

        # EPUB の見出し <text> 用フォントスタック（フォント非埋め込み・§B-3）。
        # book の見出しフォントを先頭に、リーダー標準の和文 sans フォールバックを併記する。
        # SVG 属性内に直接入れるため各名は単一引用符で囲む（属性は二重引用符）。
        #
        # @return [String]
        def epub_heading_font_family
          book_font = Common::CONFIG.typography.heading.font.to_s.strip
          stack = []
          stack << "'#{book_font}'" unless book_font.empty?
          stack.concat(["'Hiragino Sans'", "'Hiragino Kaku Gothic ProN'", "'Noto Sans JP'",
                        "'Noto Sans CJK JP'", 'sans-serif'])
          stack.join(', ')
        end

        # 1 ページの h1（扉絵）・h2（節絵）へ合成画像を注入する。
        # 本文章（番号 1..89）のみが対象。付録・前付・後付は simple 版とする（§B-4・PDF と整合）。
        #
        # 写しに注入し、全部できたときだけ元の DOM と差し替える。途中で失敗したページは、
        # どの見出しも文字のまま残す（simple 縮退）。
        def inject_heading_images!(doc, path, context)
          return unless main_chapter_file?(path)

          # 合成画像は HTML と同じ消費者 dir 配下（images/headings/）へ生成する（P4 §5.2-b）
          context = context.merge(base_dir: File.dirname(path))

          work = doc.dup
          changed = false
          changed |= inject_frontispiece_headings!(work, context)
          changed |= inject_ornament_headings!(work, context)
          return unless changed

          doc.root.replace(work.root)
          Common.log_info("[EPUB] #{File.basename(path)} に扉絵/節絵の合成画像を注入しました")
        rescue StandardError => e
          Common.log_warn("[EPUB] #{File.basename(path)} の扉絵注入に失敗（simple 縮退）: #{e.message}")
        end

        # 本文章か。付録・前書き・後書き・特殊ページ（_toc 等）は対象外として simple 版にする。
        # 種類は catalog.yml の区分で決まる（catalog-section-kind-spec.md §2.1）
        def main_chapter_file?(path)
          base = File.basename(path, '.html')
          base.match?(/\A\d{2}(?=-|\z)/) && TokenResolver::Resolver.new.resolve_file(base).kind == :chapter
        end

        # 本文の章の h1 へ扉絵の合成画像を注入する。
        # 横長の扉絵に章番号と章題だけを焼き込む。リード（chapter-lead）は焼き込まず、扉絵の
        # 次に本文の文字として残す——端末の文字サイズに従い、切れない（chapter-lead-size-spec.md §2.2.1）。
        #
        # 章扉かどうかは番号ではなく章の種類で決める（呼び出し側の main_chapter_file?）。
        # 章番号を振らない本（heading-numbering-spec.md R4）でも、番号の行を空けて題を焼き込む
        def inject_frontispiece_headings!(doc, context)
          return false unless context[:frontispiece]

          changed = false
          doc.css('h1').each do |h1|
            next if h1['class'].to_s.split.include?('vs-image-heading-epub') # 冪等ガード（§4.5）

            number = h1['data-chapter-number-display'].to_s.strip
            title = h1['data-chapter-title'].to_s.strip
            next if number.empty? && title.empty?

            src = heading_image_src(
              image_path: context[:frontispiece], number:, title:, kind: :frontispiece,
              metrics: context[:metrics],
              font_family: context[:font_family], flavor: context[:flavor], base_dir: context[:base_dir]
            )
            next unless src

            apply_image_heading!(h1, src, [number, title], doc)
            changed = true
          end
          changed
        end

        # 節扉（article.section-topic 直下の h2）に節絵画像を注入する。
        def inject_ornament_headings!(doc, context)
          return false unless context[:ornament]

          changed = false
          doc.css('article.section-topic > h2').each do |h2|
            number = h2['data-section-number-display'].to_s.strip
            title  = h2['data-section-title'].to_s.strip
            next if number.empty? && title.empty?

            src = heading_image_src(
              image_path: context[:ornament], number:, title:, kind: :ornament,
              font_family: context[:font_family], number_color: context[:number_color],
              metrics: context[:metrics],
              flavor: context[:flavor], base_dir: context[:base_dir]
            )
            next unless src

            apply_image_heading!(h2, src, [number, title], doc)
            mark_section_topic!(h2)
            changed = true
          end
          changed
        end

        # 見出し要素の中身を合成画像 <img> へ置換する。
        # 目次（nav）は各章 HTML の <title> から生成され h1 テキストに依存しないため、
        # 見出しテキストは <img alt> に格納する（読み上げ・検索・画像非表示時のフォールバック）。
        #
        # 中身と一緒に消える索引・用語集のアンカーは、空の <span> として見出しに残す。
        # 索引・用語集はこの id を行き先にしているので、要素ごと失うと行き先の無い
        # リンクになり epubcheck が RSC-012 ERROR を出す。主要参照は
        # 「章題にしか無い語は、その章題を指すほかない」（IndexMatchScanner#main_reference?）
        # の分岐で見出し・章リードへ着地しやすく、実測では 89 件中 27 件がここで消えていた。
        # 見出しは章・節の入口そのものなので、着地点としても主要参照の意図と一致する。
        #
        # 相互参照のアンカー（見出しラベル・暗黙の章ラベルの span.vs-sec-anchor）も同じ理由で残す。
        # `@chapref:ch-build` は章題の中のアンカーを行き先にしているので、章扉を画像にすると
        # 章への参照がすべて行き先を失う（chapter-reference-spec.md §6）。
        #
        def apply_image_heading!(heading, src, segments, doc)
          label = segments.reject(&:empty?).join(' ')
          anchor_ids = link_anchor_ids_within(heading)

          heading.children.remove
          Transforms::Dom.add_class(heading, 'vs-image-heading-epub')

          img = Nokogiri::XML::Node.new('img', doc)
          img['class'] = 'vs-image-heading-img'
          img['src'] = src
          img['alt'] = label
          heading.add_child(img)

          anchor_ids.each { heading.add_child(link_anchor_span(it, doc)) }
        end

        # 索引・用語集がリンク先にしているアンカー id の綴り。
        # 2 種の接頭辞に絞るのは、脚注 id のように別のフェーズが意図して外した id を
        # ここで復活させないため（Transforms::Shared::StripInlineFootnoteIds と競合する）。
        INDEX_ANCHOR_ID_PATTERN = /\A(?:idx|gls-src)-/

        # 消える要素の中から、リンクの行き先になっているアンカー id を集める
        # （索引・用語集のアンカーと、相互参照の span.vs-sec-anchor）。
        def link_anchor_ids_within(*nodes)
          nodes.compact
               .flat_map { |node| node.css('[id]').to_a }
               .select { INDEX_ANCHOR_ID_PATTERN.match?(it['id']) || it['class'].to_s.split.include?('vs-sec-anchor') }
               .map { it['id'] }
               .uniq
        end

        # 中身の無いアンカー。紙面・画面の見た目には出さず、リンクの着地点だけを担う。
        def link_anchor_span(id, doc)
          span = Nokogiri::XML::Node.new('span', doc)
          span['id'] = id
          span['class'] = 'vs-epub-anchor'
          span
        end

        # 節絵を入れた h2 の親 article.section-topic に EPUB 用クラスを付け、
        # PDF 用の固定寸法グリッド（150px 行など）を parts/epub-reflow.css で解除できるようにする。
        def mark_section_topic!(h2)
          article = h2.parent
          Transforms::Dom.add_class(article, 'vs-section-topic-epub') if article && article['class'].to_s.split.include?('section-topic')
        end

        # 合成画像を生成・キャッシュし、HTML から参照する相対パスを返す。
        # クリーン EPUB（:epub）は高画質の合成 SVG（base64 画像を内包）をそのまま配り、
        # Kindle（:kindle）は SVG 内 base64 を非対応のため平坦 JPEG へラスタライズして配る（§1-2）。
        # 入力（フレーバ・種別・画像・番号・タイトル・フォント・色）のハッシュをファイル名にして
        # 同一見出しを使い回す。フレーバを鍵に含め SVG/JPEG のキャッシュ衝突を避ける。
        # 出力先は base_dir（消費者 dir）配下の images/headings/（著者 dir を汚さない・P4 §5.2-b）。
        # ツール不在・合成失敗時は nil（→ simple 縮退）。
        def heading_image_src(image_path:, number:, title:, kind:, font_family:,
                              number_color: '#333333', flavor: :epub, base_dir: '.', metrics: nil)
          # LAYOUT_VERSION ソルトでレイアウト刷新（縦長→横長の扉絵など）を鍵に反映する——
          # image_path/番号/タイトルが同じでもレイアウトが変わるため、--no-clean 時に残る旧画像を
          # 掴む事故を防ぐ（§4.4）。metrics も鍵に含め、文字数指定の差異を取りこぼさない
          # （字数を変えたのに旧画像が使われる事故を防ぐ）。
          key = Digest::SHA256.hexdigest(
            [HeadingImageComposer::LAYOUT_VERSION, flavor, kind, image_path,
             number, title, metrics, font_family, number_color].join('|')
          )[0, 16]
          dir = File.join(base_dir, Common.images_dir, Epub::Workspace::HEADINGS_REL_SUBDIR)
          filename = "#{kind}-#{key}.#{flavor == :kindle ? 'jpg' : 'svg'}"
          abs = File.join(dir, filename)

          unless File.exist?(abs)
            composer_args = { image_path:, number:, title:, kind:, font_family:, number_color: }
            composer_args[:metrics] = metrics if metrics
            data = if flavor == :kindle
                     HeadingImageComposer.render(**composer_args)
                   else
                     HeadingImageComposer.compose(**composer_args)
                   end
            return nil unless data

            FileUtils.mkdir_p(dir)
            File.binwrite(abs, data)
          end

          "#{Common.images_dir}/#{Epub::Workspace::HEADINGS_REL_SUBDIR}/#{filename}"
        end
      end
    end
  end
end
