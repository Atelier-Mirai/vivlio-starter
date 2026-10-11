# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pdf/reader'

require_relative 'mecab_newline_cleaner'
require_relative 'structure_reader'
require_relative 'ocr_page'
require_relative 'ocr_postprocess'
require_relative 'image_matcher'

require_relative '../common'
require_relative '../token_resolver'
require_relative '../chapter_names'
require_relative '../build/catalog_updater'

module VivlioStarter
  module Commands
    # PDF を Markdown に変換するコマンド
    #
    # Standard Mode（テキストのみ）と Enhanced Mode（HexaPDF + 画像 + OCR）の
    # 2 段階で機能を提供する。vivlio-starter-pdf gem がインストール済みなら
    # 自動的に Enhanced Mode へ切り替わる。
    class PdfReadCommand
      # 「1.2 見出しテキスト」形式の柱（ランニングヘッド）を検出する正規表現
      NUMERIC_PILLAR_PREFIX_REGEX = /\A[0-9０-９]+(?:[.-][0-9０-９]+)*\.?\s+.+\z/
      # 「— 42 —」形式のダッシュ付きページ番号を検出する正規表現
      DASHED_PAGE_NUMBER_REGEX = /\A[-–—]\s*[0-9０-９ivxlcdmIVXLCDM]+\s*[-–—]\z/
      class Error < StandardError
      end

      class InvalidInputError < Error
      end

      class MissingPdfError < Error
      end

      # PDF 格納ディレクトリの既定名
      SOURCES_DIR = 'sources'
      # 経路 B（紙面の推定）に入るのに要る、文字の層のあるページの割合。下回ればスキャンとみなして OCR に任せる
      LAYOUT_TEXT_PAGE_RATIO = 0.9
      # 自動割り当て章番号の上限（01〜98）
      MAX_AUTO_CHAPTER = 98
      # 章として解決してよい PDF のファイル名（「10-intro」「heidelberg」）。論文のファイル名（「73-4-218」「Vol.53_09_482」
      # 「245」）は章の番号・範囲・拡張子と読まれるので、空き番号を割り当てる
      CHAPTER_FILE_NAME = /\A(?:\d{2}-)?[a-z][a-z0-9_-]*\z/i
      # 数字で始まる slug の前に付ける語。「01-245」は章の範囲（1〜245 章）と読まれる
      NUMERIC_SLUG_PREFIX = 'pdf'

      # @param input [String] 章トークンまたは PDF ファイルパス
      # @param options [Hash] CLI から渡されるオプション
      def initialize(input, options = {})
        @input = input.to_s.strip
        @options = options || {}
        @resolver = CLI::TokenResolver::Resolver.new
        @catalog_entries = nil
        @plugin_checked = false
        @plugin_available = false
      end

      # PDF → Markdown 変換を実行する
      # 入力を解決し、モードに応じて Standard / Enhanced の変換パイプラインを呼び出す
      # @return [Hash] :mode, :entry, :markdown_path, :source_pdf_path, :pages を含む結果
      def call
        raise InvalidInputError, 'PDF を指定してください' if input.empty?

        entry, pdf_path = resolve_entry_and_pdf
        entry = ensure_chapter_name!(entry, pdf_path)
        mode = resolved_mode
        log_enhanced_install_hint if mode == :standard
        check_images_from!(mode)

        ensure_entry_has_slug!(entry)

        CLI::Common.log_action("[pdf:read] PDF からテキストを抽出します (#{entry.basename}, mode=#{mode})")

        result = convert_structured(pdf_path, entry, mode) ||
                 (mode == :enhanced ? convert_enhanced(pdf_path, entry) : convert_standard(pdf_path, entry))

        # catalog.yml へは変換が済んでから載せる。文字を取り出せずに止まったとき、
        # 中身の無い章が目次に残らないように
        add_catalog_entry_if_needed(entry)

        CLI::Common.log_result("Markdown に変換しました: #{result[:markdown_path]}", status: :success)

        {
          mode:,
          entry:,
          markdown_path: result[:markdown_path],
          source_pdf_path: pdf_path,
          pages: result[:pages]
        }
      end

      private

      attr_reader :input, :options, :resolver

      # --- Phase: Entry & PDF resolution ---

      # 入力が PDF パスか章トークンかを判定し、Entry と PDF パスの組を返す
      def resolve_entry_and_pdf
        if pdf_path_argument?
          entry = entry_from_pdf_path
          [entry, expanded_input_path]
        else
          entry = entry_from_token
          [entry, determine_pdf_path(entry)]
        end
      end

      # PDF ファイルパスから Entry を生成する
      # 章の名前の形のファイル名だけを TokenResolver で解決し、解決できないときと、ほかの形のときは新しい章番号を自動割り当てする
      def entry_from_pdf_path
        base = normalized_basename(expanded_input_path)
        entry = resolve_with_single_token(base) if base.match?(CHAPTER_FILE_NAME)

        return entry if entry&.valid? && entry.slug

        allocate_entry_for(base)
      end

      # 章トークン文字列から Entry を解決する
      # 新規登録時は slug 必須とし、不足時は InvalidInputError を送出
      def entry_from_token
        entry = resolve_with_single_token(token_candidate)
        raise InvalidInputError, "章トークンを解決できません: #{input.inspect}" unless entry&.valid?

        if !entry.in_catalog? && entry.slug.to_s.empty?
          raise InvalidInputError, '新規 PDF 登録時は slug を含む章トークンを指定してください (例: 10-foo)'
        end

        entry
      end

      # 単一トークンを TokenResolver で解決し、最初の Entry を返す
      def resolve_with_single_token(token)
        resolver.resolve([token]).first
      end

      # 空き章番号を自動割り当てし、新規 Entry を生成する
      def allocate_entry_for(slug_source)
        basename = next_available_basename(slug_source)
        resolve_with_single_token(basename)
      end

      # slug を正規化し、空き番号と結合して「NN-slug」形式の basename を生成する
      def next_available_basename(slug_source)
        slug = normalize_slug(slug_source)
        number = next_available_number
        "#{number}-#{slug}"
      end

      # catalog.yml と contents/ の既存章を調べ、01〜98 の空き番号を返す
      def next_available_number
        used_numbers = (catalog_entries.map(&:number) + existing_markdown_numbers).uniq

        (1..MAX_AUTO_CHAPTER).each do |candidate|
          number = format('%02d', candidate)
          return number unless used_numbers.include?(number)
        end

        raise Error, "01-#{format('%02d', MAX_AUTO_CHAPTER)} までの章番号がすべて使用済みです"
      end

      # catalog.yml に登録されている全章エントリを取得する（結果をメモ化）
      def catalog_entries
        @catalog_entries ||= resolver.resolve([])
      end

      # contents/ に存在する Markdown から使用済み章番号（2桁）を抽出する
      def existing_markdown_numbers
        Dir.glob(File.join(contents_dir, '*.md')).filter_map do |path|
          File.basename(path, '.md')[/\A(\d{2})/, 1]
        end
      end

      # Entry に slug が設定されていなければ InvalidInputError を送出する
      def ensure_entry_has_slug!(entry)
        return unless entry.slug.to_s.empty?

        raise InvalidInputError, 'slug を含む章トークンを指定してください (例: 10-foo)'
      end

      # 読み込み先の章の名前を決まりの形（ChapterNames::VALID_BASENAME）に整え、ほかの章と重ならないか確かめる
      # （pdf-read-file-naming-spec.md §4.1・§5・§7）。大文字と `_` は整えて知らせる（「Hajimete_no_Rust」→
      # 「hajimete-no-rust」）。次のときは章を作らずに止め、そのまま打てるコマンドを示す。
      # - 決まりの形にできない（点を含む「01-vol.53_09_482」は、章の解決が「01-vol」と読み、ビルドを壊していた）
      # - 同じ章が既にある。これまでは別の番号でもう一章作り、スラッグの重なった章が増えていた
      # - 番号かスラッグを別の章が使っている（`vs pdf:read 97-sample-ocr` が 97-sample と同じ番号で作っていた）
      # @return [CLI::TokenResolver::Entry]
      def ensure_chapter_name!(entry, pdf_path)
        taken = CLI::ChapterNames.existing_basenames
        normalized = CLI::ChapterNames.normalize(entry.basename)
        unless normalized
          raise InvalidInputError, name_problem_message("#{entry.basename} は章の名前に使えません" \
                                                        '（2 桁の番号と、英小文字・数字・ハイフンのスラッグで付けます）',
                                                        entry.basename, taken, pdf_path)
        end

        if normalized != entry.basename
          CLI::Common.log_info("[pdf:read] 章の名前を整えます: #{entry.basename} -> #{normalized}")
          entry = build_entry_from_basename(entry, normalized)
        end
        raise InvalidInputError, reread_message(entry.basename, taken) if markdown_exists?(entry.basename)

        problems = CLI::ChapterNames.conflicts(entry.basename, taken)
        return entry if problems.empty?

        raise InvalidInputError, name_problem_message("#{entry.basename} は作れません（#{problems.join('、')}）",
                                                      entry.basename, taken, pdf_path)
      end

      # 名前の問題と、PDF の名前を直した名前に変えて読み直すコマンド。今の pdf:read は章の名前を
      # PDF のファイル名から決めるので、PDF の名前を変えてもらう（sources/ の外の PDF は写す）
      def name_problem_message(problem, basename, taken, pdf_path)
        suggested = CLI::ChapterNames.suggestion(basename, taken)
        return problem unless suggested

        source = File.expand_path(pdf_path)
        verb = File.dirname(source) == File.expand_path(sources_dir) ? 'mv' : 'cp'
        shown = source.delete_prefix("#{Dir.pwd}/")
        [problem,
         "→ #{verb} #{CLI::ChapterNames.shell_word(shown)} #{File.join(sources_dir, "#{suggested}.pdf")}",
         "→ vs pdf:read #{suggested}"].join("\n")
      end

      # 同じ章が既にあるとき。読み直すなら先に消してもらう（置き換えは --force で行う予定。§5）。
      # 残したいときは、番号もスラッグも変えておかないと、読み直した章と重なる
      def reread_message(basename, taken)
        number = CLI::ChapterNames.number_of(basename)
        slug = CLI::ChapterNames.slug_of(basename)
        free = number && CLI::ChapterNames.free_number(number, taken)
        keep = "#{free}-#{slug}-old" if free && slug
        ["contents/#{basename}.md は既にあります。読み直すときは、先にこの章を消してください",
         "→ vs delete #{basename}",
         *(keep && "→ 残すなら名前を変える: vs rename #{basename} #{keep}")].join("\n")
      end

      # Entry が catalog.yml 未登録なら CatalogUpdater で自動追記する。
      # 追加の知らせは CatalogUpdater が節名つきで出すので、ここでは重ねない
      def add_catalog_entry_if_needed(entry)
        return if entry.in_catalog?

        CLI::Build::CatalogUpdater.add_chapter(entry.basename)
        @catalog_entries = nil
      rescue StandardError => e
        raise Error, "catalog.yml の更新に失敗しました: #{e.message}"
      end

      # contents/ に指定 basename の Markdown ファイルが存在するか
      def markdown_exists?(basename)
        File.exist?(File.join(contents_dir, "#{basename}.md"))
      end

      # basename（「NN-slug」形式）から新しい Entry を構築する
      # kind / label は元の Entry から引き継ぐ
      def build_entry_from_basename(original_entry, basename)
        number, slug = parse_basename(basename)
        CLI::TokenResolver::Entry.new(
          number:,
          slug:,
          kind: original_entry.kind,
          label: original_entry.label,
          path: File.join(contents_dir, "#{basename}.md"),
          exists: false,
          in_catalog: false,
          valid: true
        )
      end

      # 「NN-slug」形式の basename を [number, slug] に分解する
      def parse_basename(basename)
        if basename =~ /(\A\d{2})(?:[-_](.+))?\z/
          [::Regexp.last_match(1), ::Regexp.last_match(2)]
        else
          [basename, nil]
        end
      end

      # 章トークンの候補（ユーザー入力そのもの）
      def token_candidate = input

      # ファイルパスから拡張子を除いたベース名を返す
      def normalized_basename(path)
        File.basename(path, File.extname(path))
      end

      # ユーザー入力が実在する PDF ファイルのパスかどうか
      def pdf_path_argument?
        File.file?(expanded_input_path) && pdf_extension?(expanded_input_path)
      rescue Errno::ENOENT
        false
      end

      # パスの拡張子が .pdf であるか（大文字小文字不問）
      def pdf_extension?(path)
        File.extname(path).casecmp('.pdf').zero?
      end

      # ユーザー入力を絶対パスに展開する（メモ化）
      def expanded_input_path
        @expanded_input_path ||= File.expand_path(input)
      end

      # Entry の slug / basename から sources/ 内の PDF パスを探索する
      # 見つからなければ MissingPdfError を送出。
      # 打ったとおりの名前（「Vol.53_09_482」）を先に探す。slug は小文字に整えた名前なので、大文字と小文字を
      # 区別するファイルシステム（Linux・WSL）では、それだけでは見つからない（pdf-read-file-naming-spec.md §2.1）
      def determine_pdf_path(entry)
        slug = entry.slug.to_s.strip
        candidates = [File.join(sources_dir, "#{File.basename(input).sub(/\.pdf\z/i, '')}.pdf")]
        candidates << File.join(sources_dir, "#{slug}.pdf") unless slug.empty?
        candidates << File.join(sources_dir, "#{entry.basename}.pdf")
        candidates.uniq!

        return candidates.find { File.exist?(it) } if candidates.any? { File.exist?(it) }

        details = candidates.map { "- 探索パス: #{it}" }.join("\n")

        raise MissingPdfError, <<~MSG.strip
          PDF ファイルが見つかりませんでした。
          - 指定トークン: #{entry.basename}
          #{details}
          sources ディレクトリに PDF を配置するか、ファイルパスを直接指定してください。
        MSG
      end

      # 入力 PDF の置き場。存在しなければ自動作成する。
      # かつては book.yml の directories.sources で変更できたが、他の directories.* と
      # ともに 2026-08-08 にシステム定数へ戻した。
      def sources_dir
        return @sources_dir if defined?(@sources_dir)

        FileUtils.mkdir_p(SOURCES_DIR)
        @sources_dir = SOURCES_DIR
      end

      # 原稿出力先ディレクトリ（contents/）
      def contents_dir
        CLI::Common::CONTENTS_DIR
      end

      # 見出し・段落・リスト・表・コード・脚注を戻して原稿を書く（pdf-read-structure-spec.md）。
      # どちらのモードでも pdf-reader（MIT）だけで読む。
      # - 経路 A: 構造ツリーが本文の 9 割以上を覆うタグ付き PDF は、構造ツリーから戻す（§3）
      # - 経路 B: そうでなく、9 割以上のページに文字の層があれば、紙面の文字の大きさ・位置・
      #   フォントから推定する（§4）
      # どちらにも当たらない（スキャンした PDF）ときは nil を返し、これまでの読み方（OCR）に任せる。
      # 構造でページをまたぐ段落をつなぐので、page_separator の区切りは入れない
      # @return [Hash, nil] :markdown_path, :pages
      def convert_structured(pdf_path, entry, mode)
        # 無い PDF・壊れた PDF は、これまでの読み方が理由を添えて止める
        return nil unless File.file?(pdf_path)

        reader = ::PDF::Reader.new(pdf_path)
        structure = VivlioStarter::PDF::StructureReader.new(reader)
        CLI::Common.log_debug(format('[pdf:read] 構造ツリーが覆う本文: %.1f%%', structure.coverage * 100))
        route = if structure.usable? then :tree
                elsif structure.text_page_ratio >= LAYOUT_TEXT_PAGE_RATIO then :layout
                end
        return nil unless route

        CLI::Common.log_info(route == :tree ? '[pdf:read] 構造ツリー（タグ）から、見出し・段落・表・コードを戻します' :
                                                '[pdf:read] 文字の大きさと位置から、見出し・段落・表・コードを推定します')
        images = mode == :enhanced ? structured_images(pdf_path, entry) : []
        images += vector_figure_images(pdf_path, entry, reader, structure) if mode == :enhanced && route == :layout
        markdown = if route == :tree
                     structure.markdown(images:)
                   else
                     structure.layout_markdown(images:, text_area: specified_text_area)
                   end
        pages = reader.page_count
        ensure_text_extracted!(markdown, pages, mode)

        markdown_path = File.join(contents_dir, "#{entry.basename}.md")
        FileUtils.mkdir_p(File.dirname(markdown_path))
        File.write(markdown_path, markdown, mode: 'w', encoding: 'UTF-8')
        CLI::Common.log_info("[pdf:read] ページ数: #{pages}")

        { markdown_path:, pages: }
      rescue Error
        raise
      rescue ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError
        nil
      rescue StandardError => e
        # 構造の読み違いで止めず、これまでの読み方で原稿を作る
        CLI::Common.log_warn("[pdf:read] 構造を戻せなかったので、文字の並びから読みます: #{e.message}")
        nil
      end

      # text_area は、book.yml で指定したときだけ効かせる（論点 6）。柱とノンブルは、経路 B が
      # ページをまたいだ繰り返しから見分ける
      def specified_text_area
        margins = text_area_margin_points
        margins.values.all?(&:zero?) ? nil : margins
      end

      # Enhanced Mode で画像を抜き出し、構造ツリーの Figure と位置で結ぶための一覧にする。
      # 文字は構造ツリーから読むので、プラグインの OCR は切る。抜き出しに失敗しても、
      # 画像の参照を書かないだけで原稿は作る
      def structured_images(pdf_path, entry)
        image_placements(enhanced_result(pdf_path, entry, ocr: { mode: 'disable' }))
      rescue Error, LoadError => e
        CLI::Common.log_warn("[pdf:read] 画像を抜き出せなかったので、画像の参照は書きません: #{e.message}")
        []
      end

      # プラグインが抜き出した画像を、図と位置で結ぶための一覧にする（page は 0 から数える）。
      # --images-from を渡したときは、元の画像に差し替える（substitute_original_images）
      def image_placements(result)
        pairs = enhanced_images(result).filter_map do |asset|
          left, bottom, right, top = %w[left bottom right top].map { (asset[it.to_sym] || asset[it]).to_f }
          path = asset[:reference_path] || asset['reference_path']
          page = (asset[:page] || asset['page']).to_i - 1
          next if path.to_s.empty? || page.negative?

          [VivlioStarter::PDF::StructureMarkdown::ImagePlacement.new(page:, left:, bottom:, right:, top:, path:),
           asset[:output_path] || asset['output_path']]
        end
        images_from ? substitute_original_images(pairs) : pairs.map(&:first)
      end

      # --- Phase: 線で描いた図（pdf-read-structure-spec.md §4.11） ---

      # 線で描いた図の範囲を、ページから PNG に切り抜いて描き出し、図と位置で結ぶ一覧にする。埋め込みの画像では
      # ないのでプラグインは取り出せない。描き出しは poppler の pdftoppm（Enhanced Mode の前提）で、見つからなければ
      # 画像の参照を書かないだけで原稿は作る
      def vector_figure_images(pdf_path, entry, reader, structure)
        dir = enhanced_images_output_dir(entry)
        FileUtils.mkdir_p(dir)
        structure.vector_figures.each_with_index.flat_map do |boxes, index|
          boxes.each_with_index.filter_map do |box, number|
            name = format('page-%03d-figure-%02d.png', index + 1, number + 1)
            next unless render_vector_figure(pdf_path, reader.page(index + 1), box, File.join(dir, name))

            VivlioStarter::PDF::StructureMarkdown::ImagePlacement.new(page: index, left: box.left, bottom: box.bottom, right: box.right,
                                                                      top: box.top, path: name)
          end
        end
      rescue Errno::ENOENT
        CLI::Common.log_warn('[pdf:read] pdftoppm が見つからないので、線で描いた図は画像にしません（brew install poppler）')
        []
      end

      VECTOR_FIGURE_DPI = 300
      # 図の線が範囲の端で切れないよう、四方に足す余白（pt）
      VECTOR_FIGURE_PADDING = 4

      # pdftoppm の切り抜きは、メディアボックスの左上を原点にしたピクセルで指定する
      def render_vector_figure(pdf_path, page, box, output_path)
        left, _bottom, _right, top = page.attributes[:MediaBox].map(&:to_f)
        scale = VECTOR_FIGURE_DPI / 72.0
        pad = VECTOR_FIGURE_PADDING
        crop = {
          '-x' => (box.left - pad - left) * scale, '-y' => (top - box.top - pad) * scale,
          '-W' => (box.right - box.left + (pad * 2)) * scale, '-H' => (box.top - box.bottom + (pad * 2)) * scale
        }.flat_map { |flag, value| [flag, [value.round, 0].max.to_s] }
        number = page.number.to_s
        _out, error, status = Open3.capture3('pdftoppm', '-f', number, '-l', number, '-r', VECTOR_FIGURE_DPI.to_s, *crop, '-png', '-singlefile',
                                             pdf_path, output_path.delete_suffix('.png'))
        CLI::Common.log_warn("[pdf:read] #{page.number} ページの線の図を描き出せませんでした: #{error.strip}") unless status.success?
        status.success?
      end

      # --- Phase: 元の画像への差し替え（pdf-read-ocr-improvement-notes.md §4.18） ---

      def images_from
        dir = options[:images_from].to_s.strip
        dir.empty? ? nil : File.expand_path(dir, Dir.pwd)
      end

      # 元の画像のフォルダが無ければ止める。Standard Mode は画像を抜き出さないので、渡しても使わない
      def check_images_from!(mode)
        return unless images_from
        raise InvalidInputError, "--images-from のフォルダが見つかりません: #{options[:images_from]}" unless File.directory?(images_from)
        return unless mode == :standard

        CLI::Common.log_warn('[pdf:read] Standard Mode では画像を抜き出さないので、--images-from は使いません')
      end

      # 抜き出した図を元の画像と見た目で突き合わせ（ImageMatcher）、一致したものは元の画像を同じ名前で
      # 章の画像のフォルダへ写し、参照をその名前にして、抜き出した画像は消す。一致しなかった図は抜き出した
      # ままにする。どの図とも結び付かなかった元の画像は、原稿へ書き足せるよう名前を挙げて知らせる
      # @param pairs [Array(ImagePlacement, String)] 図の位置と、抜き出した画像のファイル
      def substitute_original_images(pairs)
        matcher = VivlioStarter::PDF::ImageMatcher.new(images_from)
        used = []
        placements = pairs.map do |placement, extracted|
          name, original = matcher.match(extracted.to_s) if extracted && File.file?(extracted)
          next placement unless name

          FileUtils.cp(original, File.join(File.dirname(extracted), name))
          FileUtils.rm_f(extracted) unless File.basename(extracted) == name
          used << name
          placement.with(path: name)
        end
        report_original_images(pairs.size, used, matcher.names - used)
        placements
      end

      def report_original_images(total, used, unused)
        CLI::Common.log_info("[pdf:read] 抜き出した図 #{total} 枚のうち #{used.size} 枚を、元の画像に差し替えました")
        return if unused.empty?

        CLI::Common.log_warn(<<~MESSAGE.chomp)
          [pdf:read] 元の画像のうち、紙面の図と結び付かなかったものが #{unused.size} 枚あります: #{unused.join('、')}
            図を見つけられなかったか、切り出しが図の一部を欠いています。原本と見比べ、該当する位置に書き足してください
            例: ![](#{unused.first})
        MESSAGE
      end

      # OCR したページを含む PDF も、紙面の推定（経路 B）で構造を戻す（pdf-read-structure-spec.md §6）。
      # プラグインが返す OCR の語を字に割り、文字の層のあるページと合わせて読む。組み上がった原稿には
      # OCR の後処理（数字の前後の空白・形の似た字・括弧・補正表。pdf-read-ocr-postprocess-spec.md §3）をかける。語を返さない 1.2.0 より前のプラグインなら nil を返し、
      # これまでの読み方（ページごとの文字列）に任せる
      # @return [Hash, nil] :markdown_path, :pages
      def convert_ocr_layout(pdf_path, entry, result)
        words = result['page_words'] || result[:page_words]
        return nil unless words.is_a?(Array) && words.any?

        placements = image_placements(result)
        sizes = Array(result['page_sizes'] || result[:page_sizes])
        scans = VivlioStarter::PDF::StructureReader.new(::PDF::Reader.new(pdf_path)).page_scans
        pages = scans.each_with_index.map do |scan, index|
          next scan unless words[index]

          boxes = placements.select { it.page == index }.map do |image|
            VivlioStarter::PDF::MarkedContentReceiver::ImageBox.new(page: index, left: image.left, bottom: image.bottom,
                                                                     right: image.right, top: image.top)
          end
          VivlioStarter::PDF::OcrPage.new(words[index], page: index, size: sizes[index] || scan.page_size, images: boxes)
        end

        CLI::Common.log_info('[pdf:read] OCR で読んだ文字の大きさと位置から、見出し・段落・表・コードを推定します')
        root = VivlioStarter::PDF::LayoutStructure.new(pages, text_area: specified_text_area).root
        markdown = VivlioStarter::PDF::OcrPostprocess.apply(VivlioStarter::PDF::StructureMarkdown.new(root, images: placements).render)
        ensure_text_extracted!(markdown, pages.size, :enhanced)

        markdown_path = File.join(contents_dir, "#{entry.basename}.md")
        FileUtils.mkdir_p(File.dirname(markdown_path))
        File.write(markdown_path, markdown, mode: 'w', encoding: 'UTF-8')
        CLI::Common.log_info("[pdf:read] ページ数: #{pages.size}")
        { markdown_path:, pages: pages.size }
      rescue Error
        raise
      rescue StandardError => e
        CLI::Common.log_warn("[pdf:read] OCR の結果から構造を戻せなかったので、ページごとの文字列で書きます: #{e.message}")
        nil
      end

      # Standard Mode: PDF::Reader でテキストを抽出し Markdown に変換する
      # @param pdf_path [String] 入力 PDF のパス
      # @param entry [Entry] 出力先の章エントリ
      # @return [Hash] :markdown_path, :pages
      def convert_standard(pdf_path, entry)
        markdown_path = File.join(contents_dir, "#{entry.basename}.md")
        FileUtils.mkdir_p(File.dirname(markdown_path))

        reader = ::PDF::Reader.new(pdf_path)
        pages_text = reader.pages.each_with_index.map do |page, idx|
          extracted = extract_text_from_page(page, idx)
          cleaned = newline_cleaner.clean(extracted)
          sanitize(cleaned)
        end
        pages = reader.page_count
        markdown = build_markdown(pages_text)
        ensure_text_extracted!(markdown, pages, :standard)

        File.write(markdown_path, markdown, mode: 'w', encoding: 'UTF-8')

        CLI::Common.log_info("[pdf:read] ページ数: #{pages}")

        { markdown_path:, pages: }
      rescue ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError => e
        raise Error, "PDF の解析に失敗しました: #{e.message}"
      rescue Errno::ENOENT => e
        raise MissingPdfError, "PDF の読み込みに失敗しました: #{e.message}"
      end

      # Enhanced Mode: vivlio-starter-pdf を外部プロセスで呼び出し、
      # テキスト・画像・OCR 結果を統合して Markdown に変換する
      # @param pdf_path [String] 入力 PDF のパス
      # @param entry [Entry] 出力先の章エントリ
      # @return [Hash] :markdown_path, :pages
      def convert_enhanced(pdf_path, entry)
        markdown_path = File.join(contents_dir, "#{entry.basename}.md")
        FileUtils.mkdir_p(File.dirname(markdown_path))

        result = enhanced_result(pdf_path, entry)
        layout = convert_ocr_layout(pdf_path, entry, result)
        return layout if layout

        page_texts = enhanced_page_texts(result)
        pages_text = if enhanced_page_chunks(result).length == page_texts.length && !page_texts.empty?
                       enhanced_page_chunks(result).each_with_index.map do |chunk, index|
                         process_extracted_page_text(chunk, index)
                       end
                     else
                       image_references = enhanced_image_reference_map(result)
                       page_texts.each_with_index.map do |text, index|
                         cleaned = process_extracted_page_text(text, index)
                         append_image_references(cleaned, image_references[index + 1])
                       end
                     end
        pages = enhanced_page_count(result, page_texts)
        markdown = build_markdown(pages_text)
        ensure_text_extracted!(markdown, pages, :enhanced)

        File.write(markdown_path, markdown, mode: 'w', encoding: 'UTF-8')

        CLI::Common.log_info("[pdf:read] ページ数: #{pages}")

        { markdown_path:, pages: }
      rescue LoadError
        raise InvalidInputError, missing_enhanced_plugin_message
      rescue Error
        # 自前の Error は案内まで書き終えているので、包まずにそのまま渡す
        raise
      rescue StandardError => e
        raise Error, "Enhanced mode の解析に失敗しました: #{e.message}"
      end

      # 1 文字も取り出せなかったら、原稿を書かずに止める。
      # 空の Markdown を「変換しました」と報告すると、スキャンした PDF を Standard Mode で
      # 読んだ著者は、OCR が要ることに気づけない
      def ensure_text_extracted!(markdown, pages, mode)
        return unless markdown.strip.empty?

        hint = case mode
               in :standard
                 <<~HINT
                   スキャンした PDF のように文字の層が無いと、Standard Mode では読めません。
                   OCR で読む Enhanced Mode を使うには、次を入れてから実行し直してください。
                     gem install vivlio-starter-pdf
                     brew install tesseract tesseract-lang poppler vips
                 HINT
               in :enhanced
                 <<~HINT
                   文字の層が無い PDF は OCR で読みます。次を確かめてください。
                   - config/book.yml の pdf_read.ocr.mode が disable になっていないか
                   - vs doctor で tesseract と日本語の学習データ（tesseract-lang）が入っているか
                 HINT
               end

        raise Error, "PDF から文字を一つも取り出せませんでした（#{pages} ページ）。原稿と catalog.yml には何も書いていません。\n#{hint.chomp}"
      end

      # ページごとのテキストチャンクを結合して最終 Markdown を組み立てる
      # page_separator 設定に応じて "---" 区切りまたは連結で出力する
      def build_markdown(chunks)
        body = if pdf_read_page_separator?
                 chunks.join("\n\n---\n\n")
               else
                 newline_cleaner.clean(chunks.reject(&:empty?).join("\n"))
               end
        body = normalize_image_reference_blocks(body)
        body = '' if body.nil?
        body = body.strip
        body += "\n" unless body.empty? || body.end_with?("\n")
        body
      end

      # テキストの汎用サニタイズ: NBSP 除去・改行正規化・末尾空白除去・連続空行の圧縮
      def sanitize(text)
        text
          .to_s
          .gsub("\u00A0", ' ')
          .gsub(/\r\n?/, "\n")
          .gsub(/[ \t]+$/, '')
          .gsub(/\n{3,}/, "\n\n")
          .strip
      end

      # 抽出済みテキストからヘッダ・フッタを除去し、MeCab 改行補正とサニタイズを適用する
      def process_extracted_page_text(text, index)
        lines = text.to_s.split("\n", -1)
        trimmed = drop_header_footer_candidates(lines, index:)
        page_text = trimmed.join("\n")
        capture_first_page_headings(page_text) if index.zero?
        cleaned = newline_cleaner.clean(page_text)
        sanitize(cleaned)
      end

      # Standard Mode のページテキスト抽出
      # text_runs が利用可能なら座標ベースで版面内テキストを取得し、
      # 利用不可なら fallback（page.text）に切り替える
      def extract_text_from_page(page, index)
        runs = fetch_text_runs(page)
        return extract_with_fallback(page, index) unless runs&.any?

        bounds = text_area_bounds(page, index)
        sorted = runs.sort_by { |run| [-run.y, run.x] }
        current_y = nil
        line_buffer = String.new
        lines = []

        sorted.each do |run|
          next unless within_text_area?(run, bounds)

          unless current_y && (current_y - run.y).abs <= line_merge_tolerance
            unless line_buffer.empty?
              lines << line_buffer.dup
              line_buffer.clear
            end
            current_y = run.y
          end
          line_buffer << run.text
        end

        lines << line_buffer unless line_buffer.empty?
        text = lines.join("\n")
        capture_first_page_headings(text) if index.zero?
        text
      rescue StandardError => e
        CLI::Common.log_warn("[pdf:read] ページ#{index + 1} の text_runs 解析に失敗: #{e.message}. fallback モードで処理します。")
        extract_with_fallback(page, index)
      end

      # PDF::Reader::Page から座標付きの文字列（runs）を安全に取得する
      # 未対応や例外時は nil を返して fallback に委ねる。
      # pdf-reader のメソッド名は `runs` で、`text_runs` ではない。以前は `text_runs` を
      # 問い合わせていたため毎回 fallback へ落ち、版面の外を座標で除けず、脚注が消え、
      # 重なった字が欠けていた
      def fetch_text_runs(page)
        return nil unless page.respond_to?(:runs)

        page.runs
      rescue StandardError => e
        CLI::Common.log_warn("[pdf:read] text_runs の取得に失敗: #{e.message}. fallback モードに切り替えます。")
        nil
      end

      # text_runs が使えないページの代替抽出: page.text から直接テキストを取得する
      def extract_with_fallback(page, index)
        CLI::Common.log_debug("[pdf:read] ページ#{index + 1}: text_runs 利用不可のため raw text fallback")

        text = page.text.to_s
        return text if text.strip.empty?

        lines = text.split("\n", -1)

        trimmed = strip_fallback_borders(lines, page, index:)
        text = trimmed.join("\n")
        capture_first_page_headings(text) if index.zero?
        text
      end

      # fallback テキストの先頭行 strip・余白行除去・ヘッダフッタ除去を一括適用する
      def strip_fallback_borders(lines, page, index: nil)
        purified = lines.each_with_index.map { _2.zero? ? _1.strip : _1.rstrip }
        trimmed = drop_margin_lines(purified, page, index:)
        drop_header_footer_candidates(trimmed, index:)
      end

      # ページの MediaBox 高さとマージン設定から下端の不要行を比率で除去する
      def drop_margin_lines(lines, page, index: nil)
        box = media_box(page)
        return lines unless box

        height = box[3] - box[1]
        return lines if height <= 0

        margins = text_area_margin_points
        bottom_ratio = margins[:bottom] / height

        remove_bottom = (lines.length * bottom_ratio).round
        remove_bottom = 0 if index == 0

        start_index = 0
        end_index = lines.length - remove_bottom
        end_index = start_index if end_index < start_index

        lines[start_index...end_index] || []
      end

      # テキスト先頭・末尾からヘッダ・フッタ候補行（ページ番号・柱など）を除去する
      def drop_header_footer_candidates(lines, index: nil)
        trimmed = lines.drop_while { header_or_footer_candidate?(it, index:) }
        trimmed = trimmed.reverse.drop_while { header_or_footer_candidate?(it, index:) }.reverse
        trimmed.empty? ? lines : trimmed
      end

      # 行がヘッダ・フッタの候補かどうかを判定する
      # ページ番号、章見出し柱、短すぎる行などを検出する
      def header_or_footer_candidate?(line, index: nil)
        stripped = line.strip
        return true if stripped.empty?
        return true if stripped.match?(/\A\d+\z/)
        return true if stripped.match?(/\AChapter\s+\d+/i)
        return true if stripped.match?(DASHED_PAGE_NUMBER_REGEX)
        return true if index.to_i.positive? && stripped.match?(/\A第[一二三四五六七八九十百千0-9]+章\s+.+\z/)
        return true if index.to_i.positive? && numeric_pillar_line?(stripped)

        stripped.length <= 2
      end

      # text_run の座標が版面（text_area）の矩形内に収まっているか
      def within_text_area?(run, bounds)
        x = run.x
        y = run.y
        x.between?(bounds[:left], bounds[:right]) && y.between?(bounds[:bottom], bounds[:top])
      end

      # ページの MediaBox とマージン設定からテキスト抽出領域の座標境界を算出する
      # 奇数/偶数ページで綴じ側（inner）と小口側（outer）を左右反転する
      def text_area_bounds(page, index)
        @text_area_bounds ||= {}
        @text_area_bounds[index] ||= begin
          x_min, y_min, x_max, y_max = media_box(page)
          margins = text_area_margin_points
          parity = (index + 1).odd?
          inner = margins[:inner]
          outer = margins[:outer]

          {
            top: y_max - margins[:top],
            bottom: y_min + margins[:bottom],
            left: x_min + (parity ? inner : outer),
            right: x_max - (parity ? outer : inner)
          }
        end
      end

      # ページの MediaBox（用紙サイズ座標）を安全に取得する
      def media_box(page)
        return page.mediabox if page.respond_to?(:mediabox)

        box = page.attributes[:MediaBox] if page.respond_to?(:attributes)
        return box if box.is_a?(Array) && box.length >= 4

        nil
      rescue StandardError
        nil
      end

      # book.yml の pdf_read.text_area 設定を mm → pt に変換したマージン値を返す
      def text_area_margin_points
        @text_area_margin_points ||= begin
          cfg = pdf_read_text_area
          {
            top: mm_to_pt(value_from_config(cfg, :top_margin)),
            bottom: mm_to_pt(value_from_config(cfg, :bottom_margin)),
            inner: mm_to_pt(value_from_config(cfg, :inner_margin)),
            outer: mm_to_pt(value_from_config(cfg, :outer_margin))
          }
        end
      end

      # text_runs の Y 座標差がこの値以下なら同一行と見なす閾値（pt）
      def line_merge_tolerance = 2.0

      # 1 ページ目のテキストから見出し候補トークンを最大 3 件記録する
      # 後続ページの柱（ランニングヘッド）検出に使用する
      def capture_first_page_headings(text)
        return if @first_page_heading_tokens

        tokens = text.to_s.split("\n").map do |line|
          normalize_heading_token(line)
        end.map { strip_chapter_prefix(it) }.map { strip_numeric_prefix(it) }.map(&:strip).reject(&:empty?)
        @first_page_heading_tokens = tokens.first(3)
      end

      # 見出しトークンの正規化: 全角スペース→半角、連続空白を圧縮
      def normalize_heading_token(line)
        line.to_s.tr('　', ' ').gsub(/\s+/, ' ').strip
      end

      # 「第N章」形式の接頭辞を除去する
      def strip_chapter_prefix(line)
        line.sub(/\A第[一二三四五六七八九十百千0-9０-９]+章\s*/, '')
      end

      # 「1.2」「3-1」形式の数字接頭辞を除去する
      def strip_numeric_prefix(line)
        line.sub(/\A[0-9０-９]+(?:[.-][0-9０-９]+)*\.?\s*/, '')
      end

      # 1 ページ目の見出しと一致する数字付き柱（ランニングヘッド）行かどうか
      def numeric_pillar_line?(line)
        tokens = @first_page_heading_tokens
        return false unless tokens&.any?
        return false unless line.match?(NUMERIC_PILLAR_PREFIX_REGEX)

        stripped = strip_numeric_prefix(strip_chapter_prefix(normalize_heading_token(line)))
        return false if stripped.empty?

        tokens.any? { stripped.start_with?(it) }
      end

      # ミリメートルを PDF ポイント（1pt = 1/72 inch）に変換する
      def mm_to_pt(value)
        return 0.0 unless value

        value.to_f * CLI::Units::PT_PER_MM
      end

      # 設定オブジェクトから安全にキー値を取得する（メソッド呼び出し or Hash アクセス）
      def value_from_config(cfg, key)
        return nil unless cfg

        if cfg.respond_to?(key)
          cfg.public_send(key)
        else
          cfg[key]
        end
      rescue StandardError
        nil
      end

      # book.yml の pdf_read.text_area セクションを取得する
      def pdf_read_text_area = fetch_pdf_read_section(:text_area)

      # book.yml の pdf_read.ocr セクションを取得する
      def pdf_read_ocr = fetch_pdf_read_section(:ocr)

      # book.yml の pdf_read.page_separator 設定値を取得する
      def pdf_read_page_separator
        fetch_pdf_read_section(:page_separator)
      end

      # ページ区切り（---）を挿入するかどうか
      def pdf_read_page_separator? = pdf_read_page_separator != false

      # book.yml の pdf_read セクションから指定キーの設定を取得する
      def fetch_pdf_read_section(key)
        settings = pdf_read_settings
        return unless settings

        if settings.respond_to?(key)
          settings.public_send(key)
        else
          settings[key]
        end
      rescue StandardError
        nil
      end

      # book.yml の pdf_read 設定全体を取得する（プロジェクト外では nil）
      def pdf_read_settings = CLI::Common::CONFIG&.pdf_read

      # vivlio-starter-pdf の有無に応じて :enhanced / :standard を返す。
      # VIVLIO_PDF_PLUGIN=disable なら、プラグインがあっても Standard にする
      # （Pdf.provider と同じ取り決め。以前は pdf:read だけがこの指定を見ていなかった）
      def resolved_mode
        return :standard if ENV['VIVLIO_PDF_PLUGIN'] == 'disable'

        plugin_available? ? :enhanced : :standard
      end

      # vivlio-starter-pdf を外部プロセスで実行し、JSON 形式の解析結果を取得する。
      # JSON は標準出力だけから読む。OCR 中に libvips などが標準エラーへ警告を出すと、
      # 混ぜて受けた出力は JSON として壊れるため
      def enhanced_result(pdf_path, entry, ocr: enhanced_ocr_settings)
        ensure_enhanced_plugin_loaded!

        stdout, stderr, status = run_plugin(enhanced_command(pdf_path, entry, ocr:))
        raise Error, enhanced_failure_message(stderr) unless status.success?

        JSON.parse(stdout)
      rescue Errno::ENOENT
        raise LoadError, missing_enhanced_plugin_message
      rescue JSON::ParserError => e
        raise Error, "Enhanced mode の応答解析に失敗しました: #{e.message}"
      end

      # プラグインを起動し、[標準出力, 標準エラー, 終了状態] を返す。標準エラーは流しながら読み、
      # 経過の行（progress: ocr 5/24）は --log のときに「OCR しています」と中継する。OCR は 24 ページで
      # 3 分ほどかかるので、黙って待たせない（pdf-read-ocr-postprocess-spec.md §4.3）。
      # ほかの行は、これまでどおり失敗の知らせに使う
      def run_plugin(command)
        with_plugin_env do
          Open3.popen3(*command) do |stdin, stdout, stderr, wait|
            stdin.close
            errors = +''
            relay = Thread.new do
              stderr.each_line do |line|
                if (page, total = line.match(%r{\Aprogress: ocr (\d+)/(\d+)})&.captures)
                  CLI::Common.log_info("[pdf:read] OCR しています（#{page}/#{total} ページ）")
                else
                  errors << line
                end
              end
            end
            output = stdout.read
            relay.join
            [output, errors, wait.value]
          end
        end
      end

      # プラグインが失敗したときの知らせ。`read` を持たない 1.1.x のプラグインは
      # 「Unknown option 'read'」で終わるので、更新の手順を添える
      def enhanced_failure_message(stderr)
        detail = stderr.to_s.strip
        return "Enhanced mode の解析に失敗しました: #{detail}" unless detail.include?("Unknown option 'read'")

        <<~MSG.chomp
          vivlio-starter-pdf が古く、PDF の読み取り（read）に対応していません。1.2.0 以降へ更新してください。
            gem update vivlio-starter-pdf
          更新せずに読むなら、Standard Mode に切り替えます。
            VIVLIO_PDF_PLUGIN=disable vs pdf:read #{input}
        MSG
      end

      # Enhanced Mode の結果からページごとのテキスト配列を取り出す
      def enhanced_page_texts(result)
        page_texts = result[:page_texts] || result['page_texts']
        Array(page_texts)
      end

      # Enhanced Mode の結果からページごとの処理済みチャンク配列を取り出す
      def enhanced_page_chunks(result)
        page_chunks = result[:page_chunks] || result['page_chunks']
        Array(page_chunks)
      end

      # Enhanced Mode の結果から { ページ番号 => [画像参照パス, ...] } マップを構築する
      def enhanced_image_reference_map(result)
        enhanced_images(result).each_with_object({}) do |asset, refs|
          page = (asset[:page] || asset['page']).to_i
          reference_path = asset[:reference_path] || asset['reference_path']
          next if page <= 0 || reference_path.to_s.empty?

          refs[page] ||= []
          refs[page] << reference_path
        end
      end

      # Enhanced Mode の結果から画像情報の配列を取り出す
      def enhanced_images(result)
        images = result[:images] || result['images']
        Array(images)
      end

      # テキスト末尾に Markdown 画像参照（![](path)）を追加する
      def append_image_references(text, references)
        refs = Array(references).reject { it.to_s.empty? }
        return text if refs.empty?

        parts = []
        parts << text unless text.to_s.empty?
        parts.concat(refs.map { "![](#{it})" })
        parts.join("\n\n")
      end

      # Markdown 内の画像参照を独立ブロックに整形する
      # 本文に埋もれた ![](…) を前後に空行を入れて分離する
      def normalize_image_reference_blocks(markdown)
        isolated = markdown.to_s
                           .gsub(/(?<=\S)[ \t]*(!\[[^\]]*\]\([^)]+\))/, "\n\\1")
                           .gsub(/(!\[[^\]]*\]\([^)]+\))[ \t]*(?=\S)/, "\\1\n")

        rebuilt = []

        isolated.split("\n", -1).each do |line|
          stripped = line.strip

          if markdown_image_reference_line?(stripped)
            rebuilt << '' unless rebuilt.empty? || rebuilt.last.empty?
            rebuilt << stripped
            rebuilt << ''
          else
            rebuilt << line
          end
        end

        rebuilt.join("\n").gsub(/\n{3,}/, "\n\n")
      end

      # 行が Markdown 画像参照のみで構成されているか
      def markdown_image_reference_line?(line)
        line.to_s.match?(/\A!\[[^\]]*\]\([^)]+\)\z/)
      end

      # Enhanced Mode の結果からページ数を取得する（報告値がなければテキスト配列長で代替）
      def enhanced_page_count(result, page_texts)
        reported = result[:pages] || result['pages']
        count = reported.to_i
        count.positive? ? count : page_texts.length
      end

      # vivlio-starter-pdf へ渡すコマンド引数を組み立てる
      # OCR 設定・マージン・画像出力先などを JSON エンコードして引き渡す
      def enhanced_command(pdf_path, entry, ocr: enhanced_ocr_settings)
        [
          *enhanced_plugin_command,
          'read',
          File.expand_path(pdf_path, Dir.pwd),
          "page_separator=#{pdf_read_page_separator?}",
          "text_area=#{JSON.generate(text_area_margin_points)}",
          "line_merge_tolerance=#{line_merge_tolerance}",
          "images_dir=#{enhanced_images_output_dir(entry)}",
          "image_reference_dir=#{enhanced_images_reference_dir(entry)}",
          "ocr=#{JSON.generate(ocr)}",
          'progress=true'
        ]
      end

      # book.yml の pdf_read.ocr 設定を読み取り、正規化した OCR パラメータ Hash を返す
      def enhanced_ocr_settings
        cfg = pdf_read_ocr
        {
          mode: value_from_config(cfg, :mode),
          languages: normalize_ocr_languages(value_from_config(cfg, :languages)),
          dpi: value_from_config(cfg, :dpi),
          psm: value_from_config(cfg, :psm),
          inline_image_text: normalize_inline_image_text(value_from_config(cfg, :inline_image_text))
        }.compact
      end

      # OCR 言語指定を正規化する（配列化 + エイリアス解決 + 重複排除）
      def normalize_ocr_languages(value)
        raw = case value
              in Array then value
              else value.to_s.split(/[+,]/)
              end

        raw.map { normalize_ocr_language_alias(it) }.reject(&:empty?).uniq
      end

      # "japanese" → "jpn" など、人間が読みやすいエイリアスを Tesseract 言語コードに変換する
      def normalize_ocr_language_alias(value)
        case value.to_s.strip.downcase.tr('-', '_')
        in '' then ''
        in 'japanese' then 'jpn'
        in 'japanese_vertical' then 'jpn_vert'
        in 'english' then 'eng'
        else value.to_s.strip
        end
      end

      # inline_image_text の設定値を include / exclude / captionize のいずれかに正規化する
      def normalize_inline_image_text(value)
        case value.to_s.strip.downcase
        in '' | 'include' then 'include'
        in 'exclude' | 'remove' then 'exclude'
        in 'captionize' | 'caption_only' | 'caption' then 'captionize'
        else 'include'
        end
      end

      # Enhanced Mode で抽出した画像の保存先ディレクトリ（images/{basename}/）
      def enhanced_images_output_dir(entry)
        File.expand_path(File.join(CLI::Common.images_dir, entry.basename), Dir.pwd)
      end

      # Markdown 内の画像参照パスの基底ディレクトリ（空文字で相対パス出力）
      def enhanced_images_reference_dir(_entry)
        ''
      end

      # vivlio-starter-pdf の実行コマンドを決定する
      def enhanced_plugin_command
        [enhanced_plugin_executable]
      end

      # インストール済み vivlio-starter-pdf の実行ファイル名
      def enhanced_plugin_executable = 'vivlio-starter-pdf'

      # Enhanced Mode が利用不可時のエラーメッセージ
      def missing_enhanced_plugin_message
        'Enhanced mode を利用するには vivlio-starter-pdf をインストールしてください'
      end

      # Standard Mode での実行時に Enhanced Mode への切り替え方法を案内する。
      # VIVLIO_PDF_PLUGIN=disable で自分から切ったときは、入れてある gem の導入を勧めない
      def log_enhanced_install_hint
        return if ENV['VIVLIO_PDF_PLUGIN'] == 'disable'

        CLI::Common.log_info('[pdf:read] Enhanced Mode を利用するには `gem install vivlio-starter-pdf` を実行してください。')
      end

      # MeCab を使った日本語改行補正器（メモ化）
      def newline_cleaner
        @newline_cleaner ||= VivlioStarter::PDF::MecabNewlineCleaner.new
      end

      # 任意文字列を URL 安全な slug に正規化する（小文字化・記号除去・ハイフン化）。
      # 数字で始まる slug は、番号と続けると章の範囲や番号に読まれるので、前に語を付ける（「245」→「pdf-245」）
      def normalize_slug(value)
        slug = value.to_s.downcase
                    .tr(' ', '-')
                    .gsub(/[^a-z0-9-]+/, '-')
                    .gsub(/-+/, '-')
                    .gsub(/\A-+|-+\z/, '')
        return 'imported' if slug.empty?

        slug.match?(/\A\d/) ? "#{NUMERIC_SLUG_PREFIX}-#{slug}" : slug
      end

      # vivlio-starter-pdf がインストール済みで実行可能かどうかを判定する（結果をキャッシュ）
      def plugin_available?
        return @plugin_available if @plugin_checked

        _stdout, status = capture_enhanced_command(*enhanced_plugin_command, '--version')
        @plugin_available = status.success?
      rescue Errno::ENOENT
        @plugin_available = false
      ensure
        @plugin_checked = true
      end

      # vivlio-starter-pdf を外部プロセスとして実行し、stdout と status を返す
      # Bundler 環境下では with_unbundled_env で実行する
      def capture_enhanced_command(*command)
        with_plugin_env { Open3.capture2e(*command) }
      end

      # プラグインは書籍プロジェクトの Gemfile の外にあるので、Bundler 環境を外して起動する
      def with_plugin_env(&)
        return yield unless defined?(Bundler)

        Bundler.with_unbundled_env(&)
      end

      # Enhanced Mode のプラグインが利用可能でなければ LoadError を送出する
      def ensure_enhanced_plugin_loaded!
        return if plugin_available?

        raise LoadError, missing_enhanced_plugin_message
      end

    end
  end
end
