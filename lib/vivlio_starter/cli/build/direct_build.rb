# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/direct_build.rb
# ================================================================
# 責務:
#   `vs build myawesome.md` — config/book.yml や config/catalog.yml を介さず、
#   単一 Markdown を閲覧用 PDF にする軽量経路（direct-build-spec.md）。
#
# 設計方針（案A: 一時ワークスペース方式）:
#   専用パイプラインは作らない。一時ディレクトリに「最小プロジェクト相当」
#   （stylesheets ＋ 既定 CONFIG ＋ 原稿 1 章）を組み立て、chdir して既存の
#   :single パイプラインをそのまま流す。Common のパス定数がすべて相対パスのため、
#   前処理・VFM 変換・Vivliostyle 呼び出し・リネームの実証済みコードが無改修で
#   ワークスペース内に閉じる——これが案A の最大の利点。
#
# 意図的な制約:
#   - 章種は常に本章（chapter）。catalog を引かないため 00-/99- でも前書き扱いしない
#   - theme.style は simple 固定。扉絵・節絵アセットの生成は軽量経路の趣旨に反する
#   - 出力は閲覧用 PDF のみ（print_pdf / EPUB / Kindle は対象外）
#
# 仕様書との差分（実装時に判明した都合）:
#   - stylesheets は「コピーではなくシンボリックリンク」。実体は fonts / twemoji を
#     含み 90MB 超あり、毎回コピーしては軽量経路たり得ない（ビルドは読むだけ）
#   - 参照画像は実体コピーのうえ png/jpg を WebP 化する。ImagePathNormalizer が
#     参照を .webp へ正規化するため、変換しないと画像が黙って落ちる
#   - config/ には page_presets.yml と最小 catalog.yml を置く。前者は版面の解決に、
#     後者は同一ファイル内クロスリファレンスのラベル収集に要る
# ================================================================

require 'fileutils'
require 'pathname'
require 'tmpdir'

require_relative '../common'
require_relative '../masking'
require_relative '../new'
require_relative '../resize'
require_relative '../token_resolver'
require_relative 'build_lock'
require_relative 'pipeline'

module VivlioStarter
  module CLI
    module BuildCommands
      # 設定ファイルを経由しない単一 Markdown の PDF 化
      class DirectBuild
        WORKSPACE_PREFIX = 'vs-direct-'

        # 扉絵・節絵を使わない simple 固定（spec §1.2）。既定色は yellow。
        FIXED_THEME_STYLE = 'simple'
        DEFAULT_THEME_COLOR = 'yellow'

        # 章番号を持たない（または本章の範囲外の）原稿へ割り当てる番号と slug。
        # 01–89 は本章の範囲であり、10 はその中庸。
        FALLBACK_NUMBER = '10'
        FALLBACK_SLUG = 'document'

        # stylesheets 配下で唯一ビルドが書き込む生成物（FontManager が更新し
        # page-settings.css が @import する）。ワークスペース側の実体コピーへ逃がす対象。
        FONTS_DIR = 'fonts'
        GOOGLE_FONTS_DIR = 'google'
        GOOGLE_FONTS_BUNDLE = 'google-fonts.css'

        # 生成 config が ESM（import 文）のため、ワークスペースにも type: module が要る。
        PACKAGE_JSON = %({\n  "name": "vs-direct",\n  "private": true,\n  "type": "module"\n}\n)

        # UnifiedBuildPipeline が command から参照するのは options だけ（pipeline.rb #initialize）。
        # 直接ビルドは CLI オプションを素通ししないため、固定値の器を渡す。
        PipelineCommand = Data.define(:options)

        # 画像記法のローカル参照（URL・data: は除外）
        LOCAL_IMAGE_PATTERN = %r{!\[[^\]]*\]\((?!https?://|data:)([^)\s]+)\)}

        # @param source [String] 入力 Markdown のパス（呼び出し元 cwd 基準）
        # @param theme [String, nil] --theme の値（省略時 yellow）
        def initialize(source, theme: nil)
          # ワークスペースへ chdir した後も同じファイルを指せるよう絶対パスで保持する
          @source = File.expand_path(source.to_s)
          @theme = theme
        end

        # @return [Integer] 終了コード
        def call
          # ensure で必ず復帰させるため、いかなる早期 return よりも先に退避する
          saved_config = Common::CONFIG
          workspace = nil
          return 1 unless valid_theme?

          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          workspace = Dir.mktmpdir(WORKSPACE_PREFIX)

          # --- Phase: 最小プロジェクトを組み立て、その中で :single パイプラインを回す ---
          prepare_workspace!(workspace)
          Dir.chdir(workspace) do
            Common.install_configuration!(direct_configuration)
            run_pipeline
          end

          # --- Phase: 成果物を呼び出し元へ回収する（CONFIG は PdfOpener のため未復帰）---
          # 所要時間はワークスペース組み立てを含む実時間。フル/単章ビルドが集計する
          # 「パイプライン各ステップの合計」に対し、直接ビルドは組み立て・画像同伴・回収も
          # 著者の待ち時間なので、それらを含めて 1 つの数字で示す。
          deliver(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at)
        ensure
          Common.install_configuration!(saved_config)
          discard(workspace)
        end

        # ワークスペース内の章 basename（NN-slug）。
        # 01–89 の番号付きファイルだけ番号を保ち、それ以外（番号なし・00・90–99）は
        # 10 に付け替える＝常に本章扱い（spec §1.1）。
        def basename
          @basename ||= begin
            number, slug = source_name.match(/\A(\d+)[-_](.+)\z/)&.captures
            number = format('%02d', number.to_i) if number
            number = FALLBACK_NUMBER unless number && (1..89).cover?(number.to_i)
            "#{number}-#{sanitize_slug(slug || source_name)}"
          end
        end

        # PDF のタイトル。先頭の `# 見出し` を拾い、無ければファイル名。
        # フロントマターを除いたうえで Masking に地の文だけを走査させる
        # （コードフェンス中の `# コメント` を拾わないため）。
        def title
          @title ||= begin
            body = File.read(source, encoding: 'utf-8').sub(/\A---\r?\n.*?^---\r?\n/m, '')
            found = nil
            Masking.each_prose_line(body) do |line, _lineno|
              next unless (m = line.match(/\A\#[ \t]+(.+)/))

              found = m[1].strip
              break
            end
            found.to_s.empty? ? source_name : found
          end
        end

        # 出力 PDF 名・タイトルの既定に使う元ファイル名（拡張子なし）
        def source_name = File.basename(source, '.md')

        private

        attr_reader :source, :theme

        # --theme の値を既存 ThemeValidator の受理条件で検証する。
        # 無効値は既定へ倒さず 🔴 で止める（--theme は著者の明示指定のため）。
        def valid_theme?
          return true if theme.nil? || PreProcessCommands::ThemeValidator.valid_color?(theme.to_s.strip)

          Common.log_error(
            "--theme '#{theme}' は無効な色名です。",
            detail: "指定できる色: #{PreProcessCommands::ThemeValidator::VALID_COLORS.join(' / ')}\n" \
                    "または '#ff0000' のような HEX（シェルの # 解釈を避けるため引用符で囲む）\n" \
                    "例: vs build #{File.basename(source)} --theme blue"
          )
          false
        end

        def theme_color = theme.to_s.strip.empty? ? DEFAULT_THEME_COLOR : theme.to_s.strip

        # 中間ファイル名・画像ディレクトリ名に使う slug。シェル経由で vfm を呼ぶ経路が
        # あるため、日本語ファイル名などは ASCII の安全な形へ寄せる（出力 PDF 名には無関係）。
        def sanitize_slug(raw)
          slug = raw.to_s.gsub(/[^0-9A-Za-z_-]+/, '-').gsub(/-{2,}/, '-').gsub(/\A-|-\z/, '')
          slug.empty? ? FALLBACK_SLUG : slug
        end

        # 直接ビルド用の CONFIG（book.yml を読まず既定値＋上書きで組む・spec §2.3-3）
        def direct_configuration
          Common.build_direct_configuration(
            book: { main_title: title, language: 'ja' },
            project: { name: sanitize_slug(source_name) },
            theme: { style: FIXED_THEME_STYLE, color: theme_color },
            output: { targets: ['pdf'] }
          )
        end

        # ------------------------------------------------------------
        # ワークスペースの組み立て
        # ------------------------------------------------------------

        def prepare_workspace!(workspace)
          Common.log_action("[direct] 一時ワークスペースを組み立てます: #{workspace}")

          FileUtils.mkdir_p(File.join(workspace, Common::CONTENTS_DIR))
          FileUtils.mkdir_p(File.join(workspace, Common::CONFIG_DIR))
          link_stylesheets(workspace)
          link_node_modules(workspace)
          File.write(File.join(workspace, 'package.json'), PACKAGE_JSON, encoding: 'utf-8')

          FileUtils.cp(File.join(NewCommands::SCAFFOLD_SOURCE, Common::PAGE_PRESETS_FILE),
                       File.join(workspace, Common::PAGE_PRESETS_FILE))
          File.write(File.join(workspace, Build::CatalogLoader::CATALOG_FILE),
                     "CHAPTERS:\n  - #{basename}\n", encoding: 'utf-8')

          FileUtils.cp(source, File.join(workspace, Common::CONTENTS_DIR, "#{basename}.md"))
          copy_referenced_images(workspace)
        end

        # stylesheets の実体。プロジェクト内で実行されたときはルートの stylesheets/ を
        # 優先する——推敲中の章をプロジェクトの見た目で軽量プレビューする用途を殺さない
        # ため（book.yml の値を使わない点は不変・spec §2.3-2）。
        def stylesheets_source
          local = File.expand_path(Common::STYLESHEETS_DIR)
          return local if Dir.exist?(local) && File.file?(File.expand_path(Common::CONFIG_FILE))

          File.join(NewCommands::SCAFFOLD_SOURCE, Common::STYLESHEETS_DIR)
        end

        # stylesheets は参照のみ張る（実体は fonts / twemoji を含み 90MB 超あり、毎回コピーしては
        # 「軽量経路」たり得ない）。ただし丸ごと 1 本の symlink にすると、BookSettingsCss 経由で
        # 呼ばれる FontManager が毎ビルド書き直す fonts/google-fonts.css（page-settings.css が
        # @import する生成物）が**リンク先の実体**——著者のプロジェクトや gem 同梱の scaffold——へ
        # 書き込まれてしまう（書込み不可の場所なら無関係な 🟡 が出る）。
        # そこで stylesheets/ と stylesheets/fonts/ だけ実体ディレクトリにし、直下の各エントリへ
        # symlink を張ったうえで、この 1 ファイルだけワークスペース側の実体コピーへ逃がす。
        # フォント本体のダウンロード経路には入らない——直接ビルドの CONFIG は typography.*.font が
        # 常に nil で、FontManager は名前が空なら何も取りに行かないため。
        def link_stylesheets(workspace)
          source = stylesheets_source
          dest = File.join(workspace, Common::STYLESHEETS_DIR)

          mirror_with_symlinks(source, dest, except: [FONTS_DIR])
          mirror_with_symlinks(File.join(source, FONTS_DIR), File.join(dest, FONTS_DIR),
                               except: [GOOGLE_FONTS_BUNDLE, GOOGLE_FONTS_DIR])
          # google/ まで実体ディレクトリにするのは、FontManager が書き込み先を
          # `fonts/google/../google-fonts.css` と組み立てるため——google/ が symlink だと
          # `..` が物理的にリンク先の fonts/ へ抜け、退避したはずの書き込みが実体へ届く。
          mirror_with_symlinks(File.join(source, FONTS_DIR, GOOGLE_FONTS_DIR),
                               File.join(dest, FONTS_DIR, GOOGLE_FONTS_DIR))

          bundle = File.join(source, FONTS_DIR, GOOGLE_FONTS_BUNDLE)
          FileUtils.cp(bundle, File.join(dest, FONTS_DIR, GOOGLE_FONTS_BUNDLE)) if File.file?(bundle)
        end

        # 実体ディレクトリを作り、直下の各エントリへ symlink を張る（浅いミラー）。
        def mirror_with_symlinks(source, dest, except: [])
          return unless Dir.exist?(source)

          FileUtils.mkdir_p(dest)
          (Dir.children(source) - except).each do |name|
            link_or_copy(File.join(source, name), File.join(dest, name))
          end
        end

        # 参照を張る。symlink を作れない環境ではコピーへ退避する。
        def link_or_copy(target, link)
          File.symlink(target, link)
        rescue StandardError
          FileUtils.cp_r(target, link)
        end

        # npx は「ローカル node_modules → PATH」の順に解決する。プロジェクト内から
        # 呼ばれたときはそのプロジェクトの @vivliostyle/cli を使わせる（無い場合は
        # グローバル導入分が PATH 経由で使われる）。
        def link_node_modules(workspace)
          found = Pathname.new(Dir.pwd).ascend.map { it.join('node_modules').to_s }.find { Dir.exist?(it) }
          return unless found

          link_or_copy(found, File.join(workspace, 'node_modules'))
        end

        # 原稿が参照するローカル画像を章画像ディレクトリへ実体コピーする。
        # 不在の参照は触らない（既存 normalizer が 🔴 ＋ プレースホルダー data URI を
        # 出す従来動作に委ねる・spec §2.4）。
        def copy_referenced_images(workspace)
          images_root = File.join(workspace, Common::IMAGES_DIR)
          chapter_dir = File.join(images_root, basename)

          copied = File.read(source, encoding: 'utf-8').scan(LOCAL_IMAGE_PATTERN).flatten.uniq.filter_map do |ref|
            src = image_search_bases.map { File.expand_path(ref, it) }.find { File.file?(it) }
            # 参照の相対構造ごと持ち込む。ImagePathNormalizer が images/<章>/<参照文字列>
            # へ正規化するため、ファイル名だけ平らにコピーすると参照が外れる。
            dest = File.expand_path(ref, chapter_dir)
            next unless src && dest.start_with?("#{images_root}/")

            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(src, dest)
            ref
          end

          return if copied.empty?

          Common.log_info("[direct] 参照画像を同伴しました: #{copied.join(', ')}")
          convert_copied_images!(images_root) if copied.any? { it.match?(/\.(png|jpe?g)\z/i) }
        end

        # 画像参照の探索元。基本は入力 .md と同じディレクトリ（spec §2.4）だが、
        # プロジェクトの章（contents/NN-slug.md）を直接指定したときは章の画像が
        # images/NN-slug/ にあるため、そこも見る——さもないと推敲プレビュー用途で
        # 図版が全滅する。
        def image_search_bases
          @image_search_bases ||= begin
            own = File.dirname(source)
            chapter_images = File.expand_path(File.join('..', Common::IMAGES_DIR, source_name), own)
            Dir.exist?(chapter_images) ? [own, chapter_images] : [own]
          end
        end

        # 同伴した png/jpg を WebP へ寄せる。ImagePathNormalizer が画像参照を .webp へ
        # 正規化するため、ここで変換しないと HTML から参照が外れて画像が黙って消える。
        # 変換対象はワークスペース内のコピーのみで、著者の原本には触れない。
        def convert_copied_images!(images_root)
          ResizeCommands.execute_resize_medium(images_root)
          return if Dir.glob(File.join(images_root, '**', '*.webp')).any?

          Common.log_warn(
            '画像の WebP 変換ができませんでした。PDF では代替画像が表示されます。',
            detail: '対処: brew install imagemagick で ImageMagick を導入するか、' \
                    '画像をあらかじめ .webp / .svg で用意してください。'
          )
        end

        # ------------------------------------------------------------
        # ビルドと回収
        # ------------------------------------------------------------

        # 既存の :single パイプラインをワークスペース内で実行する。
        # options は CLI から素通しせず固定値を渡す（直接ビルドでは画像最適化・圧縮・
        # クリーン指定を受け付けないため・spec §1.4）。resize: false は必須——
        # symlink 先である著者の stylesheets/images を書き換えさせないため。
        def run_pipeline
          Thread.current[:vs_verify_options] = { verify_images: true, verify_bare_urls: true,
                                                 verify_external_links: false }
          PreProcessCommands::LinkImageValidator.reset!
          PreProcessCommands::IssueRegistry.reset!
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = [basename]

          BuildLock.with_lock do
            pipeline = UnifiedBuildPipeline.new(
              PipelineCommand.new(options: { resize: false, compress: false, verify: true, clean: !debug? }),
              entries: [entry], mode: :single
            )
            pipeline.run
            name = pipeline.generated_pdf_name
            @generated_pdf = File.expand_path(name) if name && File.file?(name)
          end

          PreProcessCommands::LinkImageValidator.print_summary
        end

        # catalog を引かずに手組みする Entry。常に本章（chapter）扱い（spec §1.1）。
        def entry
          number, slug = basename.split('-', 2)
          TokenResolver::Entry.new(
            number:, slug:, kind: :chapter, label: 'CHAPTERS',
            path: File.join(Common::CONTENTS_DIR, "#{basename}.md"),
            exists: true, in_catalog: true, valid: true
          )
        end

        # 生成 PDF を呼び出し元 cwd の <元basename>.pdf へ移す（既存ファイルは上書き）。
        # 報告はフル/単章ビルドと同じ「📚 <ファイル> を作成しました (N.Ns)」の書式で揃える。
        # @param elapsed [Float] 実行開始からの経過秒
        def deliver(elapsed)
          unless @generated_pdf && File.exist?(@generated_pdf)
            Common.log_error('PDF を生成できませんでした。',
                             detail: '対処: --log=debug を付けて再実行すると、原因のログと作業ディレクトリが残ります。')
            return 1
          end

          destination = "#{source_name}.pdf"
          FileUtils.rm_f(destination)
          FileUtils.mv(@generated_pdf, destination)
          Common.log_result("#{destination} を作成しました (#{format('%.1f', elapsed)}s)", status: :artifact)
          open_pdf(destination)
          0
        end

        def open_pdf(path)
          PdfCommands::PdfOpener.new({}, path).call
        rescue StandardError
          # macOS 専用機能のため、失敗しても成果物には影響させない
        end

        # --log=debug のときはワークスペースを残す（トラブルシュート用・spec §2.3-7）。
        # remove_entry は symlink をリンクごと外すため、実体の stylesheets は消えない。
        def discard(workspace)
          return unless workspace && Dir.exist?(workspace)

          if debug?
            Common.log_always("[direct] ワークスペースを残しました: #{workspace}")
          else
            FileUtils.remove_entry(workspace)
          end
        end

        def debug? = Common.current_log_level >= 3
      end
    end
  end
end
