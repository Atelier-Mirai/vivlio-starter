# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/workspace.rb
# ================================================================
# 責務:
#   消費者のディレクトリ・素材の複製（localize）・参照の切れた画像の回収
# ================================================================

require 'cgi'
require 'fileutils'
require_relative '../derived_image'
require_relative '../../pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Build
      # epub/ の下のモジュールの名前空間（ほかのファイルは、このファイルを先に読む）
      module Epub; end

      # 消費者のディレクトリ・素材の複製（localize）・参照の切れた画像の回収
      module Epub::Workspace
        module_function

        # EPUB で除外する特殊ページ
        # 目次は EPUB リーダーが自動生成するため不要
        EXCLUDED_BASENAMES = %w[_toc].freeze

        # ================================================================
        # ワークスペース消費者 dir（P4 段階 4・実験 E2 の確定案）
        # ================================================================
        # EPUB/Kindle はそれぞれ .cache/vs/build/{epub,kindle}/ で完結する。
        # html/ の原本から asset_prefix を剥がしてステージし、参照資産を dir 内へ
        # ローカライズ（選択コピー）することで、entryContext = dir がそのまま
        # EPUB パッケージルートになる（dot-dir 混入が構造的に起こらない・§4-1）。
        # ================================================================

        # html/ の全 HTML を消費者 dir へ展開する（asset_prefix 剥がし）。
        # 剥がした後の参照（stylesheets/… ・images/…）は dir 基準の相対となり、
        # ローカライズされた資産と対応する。章間リンクは同一 dir 内のため不変。
        #
        # `data-vs-source` も外す。詰めた SVG（image-trim-spec.md §3.4）が PDF の書体の差し替えへ
        # 渡すための控えで、ビルド機のパスを EPUB に残す理由はない。
        #
        # @param dir [String] 消費者 dir（BUILD_EPUB_DIR / BUILD_KINDLE_DIR）
        def stage_consumer_htmls!(dir)
          FileUtils.mkdir_p(dir)
          Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')).each do |src|
            content = File.read(src, encoding: 'utf-8').gsub(Common::ASSET_PREFIX, '')
                          .gsub(/\s+data-vs-source="[^"]*"/, '')
            File.write(File.join(dir, File.basename(src)), content, encoding: 'utf-8')
          end
        end

        # EPUB が参照する資産を消費者 dir 内へローカライズする（E2: 選択コピーが必須。
        # copyAsset は entryContext 配下を全同梱するため、「必要物だけを dir に置く」ことが
        # そのままパッケージ内容の選択になる。旧 copyAsset.excludes の知識はここへ移した）。
        # - images/**: _epub_assets/ と headings/ は除外（消費者 dir 内へ直接生成されるため、
        #   ルートの stale な残骸を拾わない）。kindle は WebP も除外（transcode 済み・非対応）。
        # - stylesheets/**: CSS は運ばない（styles/ の平らな CSS だけを読む・Epub::Stylesheets.bundle_flat!）。
        #   twemoji 直下（絵文字マスター・プレーン復元で未参照）とフォント実体（非埋め込み時）も除外。
        #   kindle は WebP も除外（CSS の参照は Css::TargetFilter が宣言ごと落とす）。
        # - theme-images/**: 生成バリアント webp（生成キャッシュ）のうち book-settings.css が
        #   参照する分を同梱（:epub のみ・移設仕様 §3.2）。
        # - カバー画像: embed 有効時のみ dir/covers/ へコピー（cover は entryContext 基準で解決）。
        #
        # @param dir [String] 消費者 dir
        # @param flavor [Symbol] :epub / :kindle
        def localize_assets!(dir, flavor:)
          copy_asset_tree!(Common.images_dir, dir, flavor:) { localized_image?(it, flavor) }
          # ビルド生成画像（数式 SVG）は workspace の html/images/ 配下から同梱する（P4b §2.3）。
          # EPUB 内の最終パスは images/math/… でルートの著者画像と同一階層に収まる。
          copy_asset_tree!(File.join(Common::BUILD_HTML_DIR, 'images'), dir, dest_root: 'images', flavor:) do
            localized_image?(it, flavor)
          end
          copy_asset_tree!(Common.stylesheets_dir, dir, flavor:) { localized_stylesheet?(it, flavor) }
          localize_theme_variant_images!(dir, flavor)
          localize_cover_image!(dir, flavor)
          Common.log_info("[EPUB] 参照資産を #{dir} 内へローカライズしました（flavor: #{flavor}）")
        end

        # 生成バリアント webp（.cache/vs/theme-images/）を dir/theme-images/ へ同梱する。
        # 旧配置（stylesheets/images/**）では stylesheets コピーへの相乗りで同梱されていたが、
        # 生成キャッシュへの移設で相乗りが消えたため、book-settings.css が url() で参照する
        # 分だけを選択コピーする（キャッシュに溜まった他テーマの変種を運ばない）。
        # url は CSS 位置からの相対のため組替不要（cache 内でもパッケージ内でも
        # 'theme-images/…' のまま解決する・移設仕様 §3.2）。
        # kindle は WebP 非対応で、url() を含む宣言ごと Css::TargetFilter が落とすためスキップする。
        def localize_theme_variant_images!(dir, flavor)
          return if flavor == :kindle

          source = PreProcessCommands::BookSettingsCss.output_path
          return unless File.exist?(source)

          css = File.read(source, encoding: 'utf-8')
          css.scan(%r{url\(\s*["']?(theme-images/[^"')\s]+)["']?\s*\)}).flatten.uniq.each do |rel|
            src = File.join(Common.cache_dir, rel)
            next unless File.exist?(src)

            dest = File.join(dir, rel)
            FileUtils.mkdir_p(File.dirname(dest))
            # 章扉・節絵も画面幅で頭打ちにする（2880px は 2048px 画面には過剰）。
            # ページ全面に敷かれるので割合は 1.0 になり、実質は上限だけが効く。
            copy_asset!(src, dest, flavor)
          end
        end

        # src_root 配下のファイルを、フィルタ（root からの相対パスを yield）を通して
        # dir/dest_root/ へミラーコピーする。dest_root 既定は src_root（cwd 相対の著者資産は
        # そのままの相対階層で dir 下へ接がる）。ワークスペース配下の生成物は src_root が
        # 深い絶対的相対になるため dest_root: 'images' 等で置き場を明示する（P4b §2.3）。
        def copy_asset_tree!(src_root, dir, dest_root: src_root, flavor: nil)
          return unless Dir.exist?(src_root)

          Dir.glob(File.join(src_root, '**', '*')).each do |src|
            next unless File.file?(src)

            rel = src.delete_prefix("#{src_root}/")
            next unless yield(rel)

            dest = File.join(dir, dest_root, rel)
            FileUtils.mkdir_p(File.dirname(dest))
            copy_asset!(src, dest, flavor)
          end
        end

        # 画面幅に対して過剰な画素数を落としてコピーする。画像以外はそのまま複製する。
        #
        # **リフローでは「組んでから測る」ができない。** ページが確定せず、表示幅は端末・
        # フォントサイズ・向きで変わるからである。しかし**版面に対する割合は組版系によらない**
        # ——版面の半分に並べた見本は EPUB でも画面の半分を占める。そこで PDF 側で測った割合
        # （`DerivedImage.viewport_target`）を画面幅に掛けて必要画素数を出す。`width=30%` の
        # 指定も 2 列に並べた表も、PDF の測定に既に現れている。
        #
        # PDF を組んでいなければ画面幅そのものが上限になる（＝安全側）。
        def copy_asset!(src, dest, flavor)
          edge = shrink_edge_for(src, flavor)
          return FileUtils.cp(src, dest) unless edge

          shrunk = system('magick', src, '-resize', "#{edge}x#{edge}>", '-strip', dest,
                          out: File::NULL, err: File::NULL) && File.size?(dest)
          # 変換に失敗しても運ばないより運ぶほうがよい（画像が欠けるより重いほうがまし）
          FileUtils.cp(src, dest) unless shrunk
        end

        # 縮小が要るなら長辺（px）を、要らなければ nil を返す。
        def shrink_edge_for(src, flavor)
          return nil unless src.match?(/\.(webp|png|jpe?g)\z/i)

          viewport = flavor == :kindle ? KINDLE_IMAGE_MAX_EDGE : EPUB_IMAGE_MAX_EDGE
          width, height = Common.image_size(src)
          return nil unless width&.positive?

          edge = DerivedImage.viewport_target(width, height, viewport)
          edge < [width, height].max ? edge : nil
        end

        # images/ 配下でローカライズ対象とするか（rel は images/ からの相対パス）。
        # 図解注釈（showcase）の合成 SVG・mermaid 図の SVG は、localize_showcase_images! が
        # 参照を対のラスターへ差し替え済みで未参照になるため、両フレーバとも同梱しない
        # （パッケージ肥大の防止・explanatory-diagram-spec §7.9・mermaid-diagram-spec §4.4）。
        def localized_image?(rel, flavor)
          return false if rel.start_with?("#{EPUB_ASSETS_REL_SUBDIR}/", "#{HEADINGS_REL_SUBDIR}/")
          return false if rel.start_with?("#{SHOWCASE_REL_SUBDIR}/", "#{MERMAID_REL_SUBDIR}/") && rel.match?(/\.svg\z/i)
          return false if flavor == :kindle && talk_avatar_asset?(rel)
          return false if flavor == :kindle && rel.match?(/\.webp\z/i)

          true
        end

        # 会話文のアバター（著者が置いた images/characters/… と自動生成の images/talk-avatars/…）。
        # Kindle は Transforms::Kindle::DecorateTalk が <img> ごと除去して inline 形式へ組み替えるため、
        # どのみち表示されない。WebP は既に拡張子で弾かれるが、png/jpg のアバターも
        # 未参照のまま同梱されてパッケージを太らせるので、サブディレクトリごと除外する。
        def talk_avatar_asset?(rel)
          rel.start_with?("#{TALK_CHARACTERS_REL_SUBDIR}/", "#{TALK_AVATARS_REL_SUBDIR}/")
        end

        # stylesheets/ 配下でローカライズ対象とするか（rel は stylesheets/ からの相対パス）。
        # twemoji 直下の絵文字マスターは Transforms::Shared::RestorePlainEmoji がプレーン絵文字へ
        # 戻すため未参照になる。両フレーバで除外する（vs-techbook/ サブツリーの囲み数字等は
        # 実際に参照されるので同梱維持）。**形式を問わず直下を丸ごと外す** —— 以前は
        # `\Atwemoji/[^/]+\.svg\z` と svg 限定だったため、実体である webp 3689 件（約 3MB）が
        # 未参照のままクリーン EPUB へ同梱され続けていた（Kindle は WebP 除外で偶然弾けていた）。クリーン EPUB（:epub）は
        # WebP を高画質のまま同梱維持する ── EPUB 3.3 では image/webp がコアメディアタイプ（§4）。
        def localized_stylesheet?(rel, flavor)
          return false if rel.end_with?('.css')
          return false if rel.match?(%r{\Atwemoji/[^/]+\z})
          return keyfont_asset?(rel) if rel.start_with?('fonts/') && !embed_fonts?
          return false if flavor == :kindle && rel.match?(/\.webp\z/i)

          true
        end

        # フォント非埋め込みの既定でも同梱する keyfont 資産（kbd キーキャップ描画用 TTF・約 90KB）。
        # 本文フォントと違いリーダー側に代替が存在せず、非同梱だと 〘Ctrl〙 が素の等幅文字へ
        # 落ちるため、この 1 書体だけ実体を運ぶ（Css::TargetFilter も対の @font-face を残す）。
        # OTF は PDF の Type 3 回避で TTF へ変換する前の原本なので運ばない（ライセンス表記は
        # gem 同梱の stylesheets/fonts/Keyboard_font/LICENSE* を正とする）。
        def keyfont_asset?(rel)
          rel.start_with?('fonts/Keyboard_font/') && rel.end_with?('.ttf')
        end

        # 表紙埋め込みが有効なフレーバに限り、カバー画像を dir/covers/ へコピーする。
        # config の cover: './covers/…' は entryContext 基準で解決されるため（CLI 実装確認済み）、
        # パッケージに必要なのは埋め込み対象の 1 枚のみ（frontcover/backcover PNG は同梱しない）。
        # コピー元は生成キャッシュ・コピー先は config が指すパッケージ内 covers/ 固定
        # （ソース相対を dest に流用しない・移設仕様 §3.2）。
        def localize_cover_image!(dir, flavor)
          embed = flavor == :kindle ? Common.kindle_embed? : Common.epub_embed?
          return unless embed

          cover = resolve_cover_image_path
          return unless cover && File.exist?(cover)

          dest = File.join(dir, 'covers', File.basename(cover))
          FileUtils.mkdir_p(File.dirname(dest))
          # **表紙は本文画像の上限を適用しない。** ストアが表紙に固有の寸法を求めており
          # （KDP の推奨は長辺 2560px で、既定の 1600×2560 はまさにその値）、本文と同じ
          # 基準で落とすと要件を割る。得られるものも 1 枚ぶんしかない。
          FileUtils.cp(cover, dest)
        end

        # 除外対象の basename かどうかを判定する
        #
        # @param html_path [String] HTML ファイルパス
        # @return [Boolean]
        def excluded_basename?(html_path)
          basename = File.basename(html_path, '.html')
          EXCLUDED_BASENAMES.include?(basename)
        end

        # EPUB にフォント実体を埋め込むかどうか。
        # 既定は false（非埋め込み = リーダーのフォントに委ねる）。技術書では
        # 明朝/ゴシック/等幅の generic フォールバック（tokens.css の --book-font-*）で
        # 十分なため、サイズ最適化を優先する。
        #
        # NOTE: v2.0 で小説等の執筆に対応する際、book.yml の設定
        # （例: output.epub.embed_fonts）でこの判定を切り替える拡張点。
        # true を返せば fonts/ の同梱と @font-face の保持が復活し、埋め込み EPUB を
        # 生成できる（コード経路は両対応のまま維持してある）。
        #
        # @return [Boolean]
        def embed_fonts?
          false
        end

        # 表紙画像のパスを解決する
        # 生成物 cover JPG は生成資産キャッシュ .cache/vs/covers/ に出る（移設仕様 §3.2）
        #
        # @return [String, nil] 表紙画像の相対パス
        def resolve_cover_image_path
          theme = Common.cover_theme
          return nil unless theme

          # 拡張子は .jpg / .jpeg のどちらでも表紙として受け付ける（.jpg 優先）。
          # 実在する方を返し、いずれも無ければ既定の .jpg パスを返して
          # 呼び出し側に「見つかりません」と判定させる。
          candidates = %w[jpg jpeg].map { File.join(Common.cover_cache_dir, "cover_#{theme}.#{it}") }
          candidates.find { File.exist?(it) } || candidates.first
        end

        # ================================================================
        # パッケージの中の置き場（images/ の下のサブディレクトリ）と、画像の大きさの上限
        # ================================================================

        # 合成画像の出力先（images/headings/）。クリーン対象（clean.rb）。
        HEADINGS_REL_SUBDIR = 'headings'

        # 図解注釈（showcase）の生成物サブディレクトリ（images/showcase/）。
        SHOWCASE_REL_SUBDIR = 'showcase'

        # mermaid 図の生成物サブディレクトリ（images/mermaid/）。SVG（PDF 用）と PNG（EPUB/
        # Kindle 用）を対で焼き、EPUB では PNG を参照する（mermaid-diagram-spec.md §4.4）。
        MERMAID_REL_SUBDIR = 'mermaid'

        # 会話文の話者アバター。著者が置く images/characters/ と、
        # 自動生成の images/talk-avatars/（TalkAvatarGenerator::REL_BASE と対）。
        TALK_CHARACTERS_REL_SUBDIR = 'characters'
        TALK_AVATARS_REL_SUBDIR = 'talk-avatars'

        # EPUB 用トランスコード出力の集約サブディレクトリ（images/ 配下）。クリーン対象（clean.rb）。
        EPUB_ASSETS_REL_SUBDIR = '_epub_assets'

        # クリーン EPUB 用画像の長辺上限（px）。iPad Pro 12.9" の画面幅が 2048px で、
        # ここを超える表示先が事実上ないため頭打ちにする。Kindle と違い Kobo / Apple Books
        # には配信料の従量課金が無いので、上限は緩めに取る。
        EPUB_IMAGE_MAX_EDGE = 2048

        # Kindle 用画像の長辺上限（px）。この変換経路は :kindle でしか呼ばれないため、
        # クリーン EPUB（iPad 等の高精細画面で読まれうる）には影響しない。
        #
        # 1024 にする根拠: Amazon は入稿 KPF の画像を**すべて JPEG へ再エンコード**して配信する
        # （実測: KFX resources は 244 件すべて JPEG・透過は白へフラット化）。1600px のまま送っても
        # 端末表示に対して過剰で、配信サイズだけが増える。クリーン EPUB は 1600px を維持し、
        # 高精細画面向けの画質を落とさない。
        KINDLE_IMAGE_MAX_EDGE = 1024

        # ================================================================
        # EPUB パッケージから、参照の切れた画像を回収する
        # ================================================================
        # ローカライズは images/・stylesheets/ を**参照を見ずに**丸ごと運ぶ。原稿から
        # 使っていない雛形の画像（扉絵の花・サンプル章の写真・絵文字の囲み数字）まで
        # 入り、1 章だけの本のクリーン EPUB が 19MB になっていた（うち 18.6MB が未参照・
        # 実測 2026-10-12）。差し替えを全部終えた後で、誰も見ていない画像を落とす。
        #
        # **Kindle では SVG を残すと KPF にならない。** Kindle Previewer 4 は同梱された
        # SVG を KVG へ変換しようとし、1 枚でも躓くと Enhanced Typesetting ごと無効にして
        # KPF ではなく Mobi を出す。参照されているかどうかは問わない——manifest に
        # 載っているだけで落ちる（実測 2026-09-22）。本文からの参照は、この時点で既に
        # 他の形式へ移っている。
        #
        #   ディスプレイ数式 → PNG   （`Transforms::Kindle::RasterizeDisplayMath`）
        #   インライン数式   → テキスト（`Transforms::Kindle::TextifySimpleMath`）
        #   図版・ロゴ・QR   → ラスタ （`Epub::Images.stage_author_svgs!`）
        #
        # **ローカライズと差し替えの両方より後に呼ぶこと。** 参照の有無で判断するので、
        # HTML の書き換えが終わっていないと、まだ使われている画像を落としてしまう。
        # 表紙（covers/）は Vivliostyle がこの後で作る cover.xhtml から参照されるので対象外。
        # ================================================================

        # 回収の対象にする画像の拡張子。
        SWEPT_IMAGE_GLOB = '*.{svg,png,jpg,jpeg,gif,webp}'

        def sweep_unreferenced_assets!(dir, flavor:)
          covers = File.join(dir, 'covers', '')
          images = Dir.glob(File.join(dir, '**', SWEPT_IMAGE_GLOB), File::FNM_CASEFOLD).reject { it.start_with?(covers) }
          return if images.empty?

          text = asset_reference_text(dir)
          kept, orphans = images.partition { text.include?(File.basename(it)) }

          freed = orphans.sum { File.size(it) }
          orphans.each { FileUtils.rm_f(it) }
          prune_empty_dirs!(dir)
          if orphans.any?
            Common.log_info("[EPUB] 参照の切れた画像をパッケージから外しました: #{orphans.size} 件" \
                            "（#{(freed / 1024.0).round} KB・flavor: #{flavor}）")
          end
          warn_svg_left_in_kindle_package(kept.grep(/\.svg\z/i)) if flavor == :kindle
        end

        # 参照元になりうるテキスト（章 HTML・CSS・SVG）をひとまとめにする。
        #
        # 照合はファイル名で行う（CSS の url() は CSS の場所からの相対で、パスでは突き合わせにくい）。
        # 同じ名前の画像が別の章にあれば両方残るが、消しすぎるより安全である。
        # 日本語のファイル名は href で %XX に符号化されうるので、復号した形も足しておく。
        # SVG を含めるのは、図版の中から別の画像を参照することがあるため。
        # EPUB に入らない目次（_toc）は数えない。章題の数式の画像がここから参照され続け、
        # Kindle パッケージに SVG が残っていた。
        def asset_reference_text(dir)
          text = Dir.glob(File.join(dir, '**', '*.{html,xhtml,css,svg}'))
                    .reject { excluded_basename?(it) }
                    .map { File.read(it, encoding: 'utf-8') }
                    .join("\n")
          "#{text}\n#{CGI.unescapeURIComponent(text.scrub)}"
        end

        # 落とせなかった SVG は、そのまま出すと KPF にならない。黙って通さない。
        def warn_svg_left_in_kindle_package(kept)
          return if kept.empty?

          names = kept.first(5).map { File.basename(it) }.join('、')
          names += "、ほか #{kept.size - 5} 件" if kept.size > 5
          Common.log_warn(
            "[EPUB] Kindle パッケージに SVG が #{kept.size} 件残りました: #{names}",
            detail: '→ Kindle Previewer は SVG があると Enhanced Typesetting を無効にし、KPF ではなく Mobi を出します。' \
                    '`vs doctor` で rsvg-convert（librsvg）が入っているかを確かめてください。'
          )
        end

        # 空になったディレクトリを畳む。
        #
        # **Kindle Previewer 4 は、空ディレクトリを含む EPUB の変換に失敗する**
        # （実測 2026-09-22: `Book Conversion failed` が 1 秒で返り、ログも出ない）。
        # epubcheck は PKG-014 の**警告**で通してしまうので、検証を足しても気づけない。
        # 入れ子で空になる場合があるため、変化がなくなるまで繰り返す。
        def prune_empty_dirs!(dir)
          loop do
            empty = Dir.glob(File.join(dir, '**', '*')).select { File.directory?(it) && Dir.children(it).empty? }
            break if empty.empty?

            empty.each { Dir.rmdir(it) }
          end
        end
      end
    end
  end
end
