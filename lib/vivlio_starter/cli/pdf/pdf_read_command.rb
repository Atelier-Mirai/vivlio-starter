# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'json'
require 'open3'
require 'pdf/reader'

require_relative 'mecab_newline_cleaner'
require_relative 'structure_reader'
require_relative 'ocr_page'
require_relative 'ocr_postprocess'
require_relative 'image_matcher'
require_relative 'pdf_to_jpeg'

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

      # PDF の置き場。一つ目の引数が `/` を含まなければ、ここだけを探す（pdf-read-file-naming-spec.md §2.1）
      SOURCES_DIR = 'sources'
      # 経路 B（紙面の推定）に入るのに要る、文字の層のあるページの割合。下回ればスキャンとみなして OCR に任せる
      LAYOUT_TEXT_PAGE_RATIO = 0.9
      # 章の名前を作ってよいファイル名（「整った名前」。§3.1）。英字で始まり、英字・数字・`-`・`_` だけ。頭の `NN-` は番号。
      # 論文のファイル名（「73-4-218」「Vol.53_09_482」「245」）や日本語の名前からは作らず、著者に名前を求める
      CHAPTER_FILE_NAME = /\A(?:\d{2}-)?[a-z][a-z0-9_-]*\z/i
      # 使える名前の決まり。名前を作れないとき・空白で分かれたときの案内で、同じ言葉を使う（論点 2）
      NAME_RULE = '英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）'
      NAME_EXAMPLES = %w[awesome my-reference_2047].freeze
      # 複製・ダウンロードでファイル名の末尾に付く印（§3.2）。「 (1)」「のコピー 2」「 copy 2」「 - コピー」「 - Copy (2)」
      FILE_NAME_DECORATION = /(?:\s*\(\d+\)|\s*のコピー(?:\s*\d+)?|\s+copy(?:\s+\d+)?|\s+-\s+(?:コピー|copy))\z/i
      # 原稿の頭に書く、どの PDF から読んだかの注記（§5）
      SOURCE_NOTE = /\A<!-- pdf:read: (?<source>.+?)(?: p\.(?<pages>[\d,-]+))?（sha256: (?<digest>\h{64})） -->/
      # 柱とノンブルを見分けるのに、--pages で指定したページの前後から読み足すページの数（§10.3・論点 6）
      CLUE_PAGE_MARGIN = 2
      # 番号の区分の呼び名（空いている番号を示す案内で使う）
      SECTION_NAMES = { 0..0 => 'まえがき', 1..89 => '本文', 90..98 => '付録', 99..99 => 'あとがき' }.freeze
      BODY_NUMBERS = 1..89

      # @param input [String] 読む PDF。`/` を含まなければ sources/ の中のファイル名（`.pdf` は省ける）
      # @param options [Hash] CLI から渡されるオプション。:chapter_name（二つ目の引数）、:stray_arguments（三つ目から後）、
      #   :force、:pages（読むページ。「31-48,52」）、:images_from
      def initialize(input, options = {})
        @input = input.to_s.strip
        @options = options || {}
        @plugin_checked = false
        @plugin_available = false
      end

      # PDF → Markdown 変換を実行する
      # 読む PDF と章の名前を決め、モードに応じて Standard / Enhanced の変換パイプラインを呼び出す
      # @return [Hash] :mode, :entry, :markdown_path, :source_pdf_path, :pages を含む結果
      def call
        raise InvalidInputError, 'PDF を指定してください' if input.empty?

        entry, pdf_path = resolve_entry_and_pdf
        mode = resolved_mode
        log_enhanced_install_hint if mode == :standard
        check_images_from!(mode)

        digest = Digest::SHA256.file(pdf_path).hexdigest
        warn_same_pdf_already_read(entry, digest)
        clear_previous_images(entry) if replacing?(entry)

        CLI::Common.log_action("[pdf:read] PDF からテキストを抽出します (#{entry.basename}, mode=#{mode})")

        result = convert_structured(pdf_path, entry, mode) ||
                 (mode == :enhanced ? convert_enhanced(pdf_path, entry) : convert_standard(pdf_path, entry))
        write_source_note(result[:markdown_path], pdf_path, digest)

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

      attr_reader :input, :options

      # --- Phase: 読む PDF と章の名前（pdf-read-file-naming-spec.md §2〜§5） ---

      # 読む PDF を探し、読み込み先の章を決める。章を作れないとき・ほかの章と重なるときは、
      # 何も書かずに止め、そのまま打てるコマンドを示す
      # @return [Array(CLI::TokenResolver::Entry, String)] 読み込み先の章と、PDF のパス
      def resolve_entry_and_pdf
        check_split_arguments!
        pdf_path = locate_pdf
        entry = decide_chapter(pdf_path)
        @selected_pages = select_pages(pdf_path)
        [entry, pdf_path]
      end

      def chapter_argument = options[:chapter_name]&.to_s&.strip&.then { it.empty? ? nil : it }
      def stray_arguments = Array(options[:stray_arguments]).map(&:to_s)

      # 空白を含むファイル名を引用符なしで打つと、シェルが空白で分けて渡す。つなぎ直さずに止め、名前を変えてもらう（§2.3・論点 1）。
      # 分かれて届いたと見なすのは、引数が 3 つ以上あるときと、二つ目以降が `.pdf` で終わるとき
      def check_split_arguments!
        rest = [chapter_argument, *stray_arguments].compact
        return if stray_arguments.empty? && rest.none? { it.match?(/\.pdf\z/i) }

        raise InvalidInputError, <<~MESSAGE.chomp
          ファイル名に空白があるため、読み込めません: #{shown_path(pdf_path_for([input, *rest].join(' ')))}
          ファイル名を、#{NAME_RULE}だけの名前に変えてから読んでください
          （例: #{NAME_EXAMPLES.map { "#{it}.pdf" }.join('、')}）
        MESSAGE
      end

      # 一つ目の引数が指す PDF。`/` を含めばそのパス、含まなければ sources/ の中（§2.1）
      def pdf_path_for(argument)
        return argument if argument.include?('/')

        File.join(SOURCES_DIR, argument.match?(/\.pdf\z/i) ? argument : "#{argument}.pdf")
      end

      # 打ったとおりの名前で探す。`/` を含まない引数は、今いるディレクトリを探さない（論点 5）。
      # 同じ名前の PDF が今いるディレクトリにあれば、`./` を付けたコマンドを添える
      def locate_pdf
        path = pdf_path_for(input)
        return path if File.file?(File.expand_path(path))

        here = File.basename(path)
        hint = "→ 今いるディレクトリの PDF なら: #{retyped(pdf: "./#{here}")}" if !input.include?('/') && File.file?(here)
        raise MissingPdfError, ["PDF が見つかりません: #{shown_path(path)}", *hint, *ampersand_hint(path)].join("\n")
      end

      # `&` を含むファイル名を引用符なしで打つと、シェルが `&` の所で分け、前の部分だけを渡す
      # （`vs pdf:read データ構造&アルゴリズム.pdf` は `データ構造` を探し、`アルゴリズム.pdf` をコマンドとして実行する）。
      # 打った名前に `&` が続く PDF が同じフォルダにあれば、それを示して名前を変えるよう案内する（§2.3）
      def ampersand_hint(path)
        directory = File.dirname(File.expand_path(path))
        # 打った名前と、フォルダの中の名前の濁点の表し方（NFC・NFD）がそろうとは限らないので、そろえて比べる
        stem = File.basename(path).sub(/\.pdf\z/i, '').unicode_normalize(:nfc)
        found = Dir.exist?(directory) && Dir.children(directory).sort.find do |name|
          name.unicode_normalize(:nfc).start_with?("#{stem}&") && name.match?(/\.pdf\z/i)
        end
        return [] unless found

        ["#{shown_path(File.join(directory, found))} があります。& を含むファイル名は、シェルが & の所で分けて渡すので読み込めません",
         "ファイル名を、#{NAME_RULE}だけの名前に変えてから読んでください",
         "（例: #{NAME_EXAMPLES.map { "#{it}.pdf" }.join('、')}）"]
      end

      # 読み込み先の章を決める（§3〜§5）。名前は二つ目の引数か、PDF のファイル名から作る。番号を省いたときは、
      # 名前が同じ章があればその章（読み直し）、無ければ本文の末尾の番号にする
      # @return [CLI::TokenResolver::Entry]
      def decide_chapter(pdf_path)
        taken = CLI::ChapterNames.existing_basenames
        raise InvalidInputError, unnamed_pages_message(pdf_path, taken) if options[:pages] && !chapter_argument

        number, slug = chapter_argument ? parts_from_argument(pdf_path, taken) : parts_from_file_name(pdf_path, taken)
        basename = if number then "#{number}-#{slug}"
                   else taken.find { CLI::ChapterNames.slug_of(it) == slug } || "#{next_body_number(taken)}-#{slug}"
                   end

        if markdown_exists?(basename)
          raise InvalidInputError, reread_message(basename, taken) unless options[:force]
        else
          problems = CLI::ChapterNames.conflicts(basename, taken)
          raise InvalidInputError, conflict_message(basename, problems, taken) if problems.any?
        end
        chapter_entry(basename)
      end

      # 二つ目の引数を、`vs create` と同じく整える（§2.2）。番号だけ（「21」）なら、名前はファイル名から作る。
      # 点・空白・日本語を含む名前は整えずに止める
      # @return [Array(String, String), Array(nil, String)] 番号（省けば nil）と名前
      def parts_from_argument(pdf_path, taken)
        argument = chapter_argument
        normalized = if argument.match?(/\A\d/) then CLI::ChapterNames.normalize(argument)
                     else argument.downcase.tr('_', '-').then { CLI::ChapterNames.valid?("01-#{it}") ? it : nil }
                     end
        raise InvalidInputError, invalid_argument_message(argument, taken) unless normalized

        CLI::Common.log_info("[pdf:read] 章の名前を整えます: #{argument} -> #{normalized}") if normalized != argument
        number = CLI::ChapterNames.number_of(normalized) if normalized.match?(/\A\d/)
        slug = CLI::ChapterNames.slug_of(normalized) if number
        slug ||= number ? parts_from_file_name(pdf_path, taken, number:).last : normalized
        [number, slug]
      end

      # PDF のファイル名から章の名前を作る（§3.1）。複製の印を外し（§3.2）、残りが整った名前なら整えて使う。
      # 整った名前でなければ、名前を変える道と、章の名前を添える道を示して止める
      # @param number [String, nil] 二つ目の引数で番号だけを決めたときの番号
      def parts_from_file_name(pdf_path, taken, number: nil)
        stem = File.basename(pdf_path).sub(/\.pdf\z/i, '')
        bare = stem.dup
        bare = bare.sub(FILE_NAME_DECORATION, '') while bare.match?(FILE_NAME_DECORATION)
        CLI::Common.log_info("[pdf:read] ファイル名の複製の印を外します: #{stem} -> #{bare}") if bare != stem

        named_number, slug = bare.downcase.tr('_', '-').match(/\A(?:(\d{2})-)?(.+)\z/).captures
        unless bare.match?(CHAPTER_FILE_NAME) && CLI::ChapterNames.valid?("01-#{slug}")
          raise InvalidInputError, unnamed_file_message(pdf_path, number, taken)
        end

        [number || named_number, slug]
      end

      # 本文（01〜89）でいま使われている一番大きい番号の次。89 まで使われていれば空いている一番小さい番号（§4.2）
      def next_body_number(taken)
        used = taken.filter_map { CLI::ChapterNames.number_of(it)&.to_i }.select { BODY_NUMBERS.cover?(it) }
        candidate = used.empty? ? BODY_NUMBERS.first : used.max + 1
        candidate = BODY_NUMBERS.find { !used.include?(it) } if candidate > BODY_NUMBERS.last
        raise InvalidInputError, '本文の番号（01〜89）がすべて使われています。付録などの番号を付けて読んでください' unless candidate

        format('%02d', candidate)
      end

      # number と同じ区分で空いている番号。本文は末尾の次（§4.2）、ほかの区分は空いている一番小さい番号
      def free_number_for(number, taken)
        return next_body_number(taken) if BODY_NUMBERS.cover?(number.to_i)

        CLI::ChapterNames.free_number(number, taken)
      end

      def section_name(number) = SECTION_NAMES.find { |range, _| range.cover?(number.to_i) }&.last

      # 案内に出す `vs pdf:read …`。著者が打った形を保ち、変えるところだけ差し替える（§2.4）。
      # sources/ を省いて打った人には省いた形で、パスで打った人には同じパスで返す
      def retyped(pdf: input, chapter: chapter_argument, force: options[:force])
        ['vs pdf:read', CLI::ChapterNames.shell_word(pdf), chapter, ('--force' if force),
         (options[:pages] && "--pages #{options[:pages]}"),
         (options[:images_from] && "--images-from #{CLI::ChapterNames.shell_word(options[:images_from].to_s)}")].compact.join(' ')
      end

      # 打った PDF の指定の、ファイル名だけを差し替えたもの（「~/Downloads/講座.pdf」→「~/Downloads/awesome.pdf」）
      def input_renamed_to(name)
        directory = input[0..input.rindex('/')] if input.include?('/')
        "#{directory}#{name}#{'.pdf' if input.match?(/\.pdf\z/i)}"
      end

      # どのファイルのことかを示す行に書く、実際の場所。プロジェクトの中は相対パス、ホームの下は「~/」で書く
      def shown_path(path)
        expanded = File.expand_path(path)
        return expanded.delete_prefix("#{Dir.pwd}/") if expanded.start_with?("#{Dir.pwd}/")

        expanded.sub(/\A#{Regexp.escape(Dir.home)}(?=\/)/, '~')
      end

      def name_rule_line = "使える名前: #{NAME_RULE}（例: #{NAME_EXAMPLES.join('、')}）"

      # ファイル名から章の名前を作れないとき（§3.1）。名前を変える道と、章の名前を添える道の両方を示す
      def unnamed_file_message(pdf_path, number, taken)
        suggested = number || next_body_number(taken)
        example = NAME_EXAMPLES.first
        ["ファイル名から章の名前を作れません: #{shown_path(pdf_path)}",
         name_rule_line,
         "→ ファイル名を変える: #{example}.pdf にしてから #{retyped(pdf: input_renamed_to(example))}",
         "→ 章の名前を添える:   #{retyped(chapter: "#{suggested}-#{example}")}",
         *("（番号を省くと #{suggested} 番になります）" unless number)].join("\n")
      end

      # 二つ目の引数が章の名前に使えないとき（§2.2）
      def invalid_argument_message(argument, taken)
        number = CLI::ChapterNames.number_of(argument) if argument.match?(/\A\d{1,2}(?:[-_]|\z)/)
        ["#{argument} は章の名前に使えません",
         name_rule_line,
         "→ #{retyped(chapter: "#{number || next_body_number(taken)}-#{NAME_EXAMPLES.first}")}"].join("\n")
      end

      # 番号か名前を別の章が使っているとき（§4.1）。番号だけなら同じ区分の空いている番号を、名前だけなら
      # その章を読み直すコマンドと別の名前を示す
      def conflict_message(basename, problems, taken)
        number = CLI::ChapterNames.number_of(basename)
        slug = CLI::ChapterNames.slug_of(basename)
        others = taken - [basename]
        number_owner = others.find { CLI::ChapterNames.number_of(it) == number }
        slug_owner = others.find { CLI::ChapterNames.slug_of(it) == slug }
        free = free_number_for(number, taken) if number_owner && !slug_owner

        hints = if free
                  ["→ 空いている#{section_name(number)}の番号: #{free}", "→ #{retyped(chapter: "#{free}-#{slug}")}"]
                elsif slug_owner && !number_owner
                  ["→ その章を読み直すなら: #{retyped(chapter: slug_owner, force: markdown_exists?(slug_owner))}",
                   "→ 別の章として読むなら: #{retyped(chapter: "#{number}-#{CLI::ChapterNames.free_slug(slug, taken)}")}"]
                else
                  [CLI::ChapterNames.suggestion(basename, taken)&.then { "→ #{retyped(chapter: it)}" }].compact
                end
        [problems.join('。'), *hints].join("\n")
      end

      # 読む先の章が既にあるとき（§5）。--force で置き換えるコマンドと、別の章として読むコマンドを示す
      def reread_message(basename, taken)
        source = source_note(basename)&.[](:source)
        number = CLI::ChapterNames.number_of(basename)
        slug = CLI::ChapterNames.slug_of(basename)
        another = "#{free_number_for(number, taken)}-#{CLI::ChapterNames.free_slug(slug, taken)}" if number && slug
        ["#{basename} は既にあります#{"（前回 #{source} から読みました）" if source}",
         "→ 読み直して置き換えるなら: #{retyped(force: true)}",
         *(another && "→ 別の章として読むなら: #{retyped(chapter: another, force: false)}")].join("\n")
      end

      def replacing?(entry) = options[:force] && markdown_exists?(entry.basename)

      # 置き換える前に、前回の画像（images/<章>/）を消す。今回の画像に前回の画像が混ざらないように
      def clear_previous_images(entry)
        dir = File.join(CLI::Common.images_dir, entry.basename)
        return unless File.directory?(dir)

        FileUtils.rm_rf(dir)
        CLI::Common.log_info("[pdf:read] 前回の画像を消しました: #{dir}/")
      end

      # 原稿の頭に、どの PDF から読んだかを残す（§5）。ページを指定したときはページも（§10.4）。
      # 前処理が HTML コメントを除くので、組版には出ない
      def write_source_note(markdown_path, pdf_path, digest)
        body = File.read(markdown_path, encoding: 'UTF-8')
        pages = " p.#{page_label(selected_pages.map { it + 1 }, '-')}" if selected_pages
        File.write(markdown_path, "<!-- pdf:read: #{shown_path(pdf_path)}#{pages}（sha256: #{digest}） -->\n\n#{body}", encoding: 'UTF-8')
      end

      # 原稿の頭の注記を読む。無ければ nil
      # @return [MatchData, nil] :source と :digest
      def source_note(basename)
        path = File.join(contents_dir, "#{basename}.md")
        File.file?(path) ? File.open(path, encoding: 'UTF-8', &:gets).to_s.match(SOURCE_NOTE) : nil
      end

      # 中身が同じ PDF（sha256 が一致）から読んだ別の章があれば知らせる。著者が名前を変えて読んでいるなら意図してのことなので、止めない。
      # ページを指定したときは、ページが重なるときだけ知らせる。同じ本を章ごとに分けて読むのは、ふつうの使い方なので（§10.4）
      def warn_same_pdf_already_read(entry, digest)
        mine = selected_pages&.map { it + 1 }
        other = CLI::ChapterNames.existing_basenames.find do |basename|
          note = source_note(basename) if basename != entry.basename
          next false unless note && note[:digest] == digest

          theirs = note[:pages] && Pdf::PdfToJpeg.parse_page_spec(note[:pages])
          mine.nil? || theirs.nil? || mine.intersect?(theirs)
        end
        CLI::Common.log_warn("[pdf:read] この PDF は #{other} として読み込み済みです（中身が同じです）") if other
      end

      # --- Phase: 読むページ（§10） ---

      # --pages で読むページ（0 から数える）。省けば nil（全ページ）。最後のページを越えた分は外して知らせ、
      # 一枚も残らなければ止める（§10.2・論点 7）
      # @return [Array<Integer>, nil]
      def select_pages(pdf_path)
        return nil unless options[:pages]

        last = @pdf_page_count = ::PDF::Reader.new(pdf_path).page_count
        requested = Pdf::PdfToJpeg.parse_page_spec(options[:pages], last_page: last)
        inside, beyond = requested.partition { it <= last }
        raise InvalidInputError, "ページ #{page_label(beyond, '〜')} はありません（#{shown_path(pdf_path)} は #{last} ページです）" if inside.empty?

        if beyond.any?
          CLI::Common.log_warn("[pdf:read] ページ #{page_label(beyond, '〜')} はありません。#{page_label(inside, '〜')} を読みます" \
                               "（#{shown_path(pdf_path)} は #{last} ページです）")
        end
        inside.map { it - 1 }
      rescue Pdf::PdfToJpeg::Error => e
        raise InvalidInputError, "--pages #{options[:pages]} を読めません: #{e.message}（例: --pages 12-30、--pages 31-48,52、--pages 238-）"
      rescue ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError => e
        raise Error, "PDF の解析に失敗しました: #{e.message}"
      end

      def selected_pages = @selected_pages

      # 指定のページと、その前後 CLUE_PAGE_MARGIN ページ。柱とノンブルを見分ける手がかりにだけ使う（§10.3）
      # @return [Array<Integer>, nil]
      def clue_pages
        return nil unless selected_pages

        selected_pages.flat_map { ((it - CLUE_PAGE_MARGIN)..(it + CLUE_PAGE_MARGIN)).to_a }.uniq.sort.select { it.between?(0, @pdf_page_count - 1) }
      end

      # ページ番号の並びを、続く番号をまとめて書く（[31, 32, 33, 52] → 「31-33,52」。dash を「〜」にすれば「31〜33、52」）
      def page_label(numbers, dash)
        runs = numbers.slice_when { |a, b| b != a + 1 }.map { it.size == 1 ? it.first.to_s : "#{it.first}#{dash}#{it.last}" }
        runs.join(dash == '-' ? ',' : '、')
      end

      # --pages を付けて、章の名前を省いたとき（§10.2）。ファイル名から作ると、同じ PDF のどの範囲も同じ名前になる
      def unnamed_pages_message(pdf_path, taken)
        number = next_body_number(taken)
        ["ページを指定して読むときは、章の名前を添えてください: #{shown_path(pdf_path)}",
         name_rule_line,
         "→ #{retyped(chapter: "#{number}-#{NAME_EXAMPLES.first}")}",
         "（番号を省くと #{number} 番になります）"].join("\n")
      end

      # 決めた basename の章。区分は番号から決める
      def chapter_entry(basename)
        number = CLI::ChapterNames.number_of(basename)
        CLI::TokenResolver::Entry.new(
          number:,
          slug: CLI::ChapterNames.slug_of(basename),
          kind: CLI::TokenResolver::Resolver::KIND_RANGES.find { |_, range| range.cover?(number.to_i) }&.first,
          label: nil,
          path: File.join(contents_dir, "#{basename}.md"),
          exists: markdown_exists?(basename),
          in_catalog: CLI::ChapterNames.catalog_basenames.include?(basename),
          valid: true
        )
      end

      # Entry が catalog.yml 未登録なら CatalogUpdater で自動追記する。
      # 追加の知らせは CatalogUpdater が節名つきで出すので、ここでは重ねない
      def add_catalog_entry_if_needed(entry)
        return if entry.in_catalog?

        CLI::Build::CatalogUpdater.add_chapter(entry.basename)
      rescue StandardError => e
        raise Error, "catalog.yml の更新に失敗しました: #{e.message}"
      end

      # contents/ に指定 basename の Markdown ファイルが存在するか
      def markdown_exists?(basename)
        File.exist?(File.join(contents_dir, "#{basename}.md"))
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
        structure = VivlioStarter::PDF::StructureReader.new(reader, pages: clue_pages, output_pages: selected_pages)
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
        pages = selected_pages&.size || reader.page_count
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
        image_placements(enhanced_result(pdf_path, entry, ocr: { mode: 'disable' }, pages: selected_pages))
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
        scans = VivlioStarter::PDF::StructureReader.new(::PDF::Reader.new(pdf_path), pages: clue_pages).page_scans
        numbers = clue_pages || scans.each_index.to_a
        pages = numbers.map do |index|
          scan = scans[index]
          next scan unless words[index]

          boxes = placements.select { it.page == index }.map do |image|
            VivlioStarter::PDF::MarkedContentReceiver::ImageBox.new(page: index, left: image.left, bottom: image.bottom,
                                                                     right: image.right, top: image.top)
          end
          VivlioStarter::PDF::OcrPage.new(words[index], page: index, size: sizes[index] || scan.page_size, images: boxes)
        end

        CLI::Common.log_info('[pdf:read] OCR で読んだ文字の大きさと位置から、見出し・段落・表・コードを推定します')
        root = VivlioStarter::PDF::LayoutStructure.new(pages, text_area: specified_text_area, page_numbers: numbers, output_pages: selected_pages).root
        markdown = VivlioStarter::PDF::StructureMarkdown.new(root, images: placements, read_pages: selected_pages).render
        markdown = VivlioStarter::PDF::OcrPostprocess.apply(markdown)
        count = selected_pages&.size || pages.size
        ensure_text_extracted!(markdown, count, :enhanced)

        markdown_path = File.join(contents_dir, "#{entry.basename}.md")
        FileUtils.mkdir_p(File.dirname(markdown_path))
        File.write(markdown_path, markdown, mode: 'w', encoding: 'UTF-8')
        CLI::Common.log_info("[pdf:read] ページ数: #{count}")
        { markdown_path:, pages: count }
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
        indexes = selected_pages || (0...reader.page_count).to_a
        pages_text = indexes.map do |idx|
          extracted = extract_text_from_page(reader.page(idx + 1), idx)
          cleaned = newline_cleaner.clean(extracted)
          sanitize(cleaned)
        end
        pages = indexes.size
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

        result = enhanced_result(pdf_path, entry, pages: clue_pages)
        layout = convert_ocr_layout(pdf_path, entry, result)
        return layout if layout

        page_texts = enhanced_page_texts(result)
        chunks = enhanced_page_chunks(result)
        indexes = selected_pages || page_texts.each_index.to_a
        pages_text = if chunks.length == page_texts.length && !page_texts.empty?
                       indexes.map { process_extracted_page_text(chunks[it].to_s, it) }
                     else
                       image_references = enhanced_image_reference_map(result)
                       indexes.map do |index|
                         cleaned = process_extracted_page_text(page_texts[index].to_s, index)
                         append_image_references(cleaned, image_references[index + 1])
                       end
                     end
        pages = selected_pages&.size || enhanced_page_count(result, page_texts)
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
      # 前後のページ（柱を見分ける手がかりにだけ読んだページ。§10.3）からプラグインが抜き出した画像は、原稿に使わないので消す
      def drop_clue_page_images(result)
        return result unless selected_pages

        key = result.key?('images') ? 'images' : :images
        kept, dropped = Array(result[key]).partition { selected_pages.include?((it['page'] || it[:page]).to_i - 1) }
        dropped.each { FileUtils.rm_f(it['output_path'] || it[:output_path]) }
        result.merge(key => kept)
      end

      # @param pages [Array<Integer>, nil] プラグインに読ませるページ（0 から数える）。省けば全ページ
      def enhanced_result(pdf_path, entry, ocr: enhanced_ocr_settings, pages: nil)
        ensure_enhanced_plugin_loaded!

        stdout, stderr, status = run_plugin(enhanced_command(pdf_path, entry, ocr:, pages:))
        raise Error, enhanced_failure_message(stderr) unless status.success?

        drop_clue_page_images(JSON.parse(stdout))
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
      def enhanced_command(pdf_path, entry, ocr: enhanced_ocr_settings, pages: nil)
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
          'progress=true',
          *(pages && "pages=#{JSON.generate(pages.map { it + 1 })}")
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
