# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pdf/reader"

require_relative "mecab_newline_cleaner"

require_relative "../common"
require_relative "../token_resolver"
require_relative "../build/catalog_updater"

module Vivlio
  module Starter
    module Commands
      # PDF を Markdown に変換するコマンド
      #
      # Standard Mode（テキストのみ）と Enhanced Mode（HexaPDF + 画像 + OCR）の
      # 2 段階で機能を提供する。vivlio-starter-pdf gem がインストール済みなら
      # 自動的に Enhanced Mode へ切り替わる。
      class PdfReadCommand
        # 「1.2 見出しテキスト」形式の柱（ランニングヘッド）を検出する正規表現
        NUMERIC_PILLAR_PREFIX_REGEX = /\A[0-9０-９]+(?:[.\-][0-9０-９]+)*\.?\s+.+\z/.freeze
        # 「— 42 —」形式のダッシュ付きページ番号を検出する正規表現
        DASHED_PAGE_NUMBER_REGEX = /\A[\-–—]\s*[0-9０-９ivxlcdmIVXLCDM]+\s*[\-–—]\z/.freeze
        Error = Class.new(StandardError)
        InvalidInputError = Class.new(Error)
        MissingPdfError = Class.new(Error)

        # PDF 格納ディレクトリの既定名
        SOURCES_DIR = "sources"
        # 自動割り当て章番号の上限（01〜98）
        MAX_AUTO_CHAPTER = 98

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
          raise InvalidInputError, "PDF を指定してください" if input.empty?

          entry, pdf_path = resolve_entry_and_pdf
          entry = ensure_unique_output_entry(entry)
          mode = resolved_mode

          ensure_entry_has_slug!(entry)
          add_catalog_entry_if_needed(entry)

          CLI::Common.log_action("[pdf:read] PDF からテキストを抽出します (#{entry.basename}, mode=#{mode})")

          result = mode == :enhanced ? convert_enhanced(pdf_path, entry) : convert_standard(pdf_path, entry)

          CLI::Common.log_success("[pdf:read] 変換が完了しました -> #{result[:markdown_path]}")

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
        # TokenResolver で解決できない場合は新しい章番号を自動割り当てする
        def entry_from_pdf_path
          base = normalized_basename(expanded_input_path)
          entry = resolve_with_single_token(base)

          return entry if entry&.valid? && entry.slug

          allocate_entry_for(base)
        end

        # 章トークン文字列から Entry を解決する
        # 新規登録時は slug 必須とし、不足時は InvalidInputError を送出
        def entry_from_token
          entry = resolve_with_single_token(token_candidate)
          raise InvalidInputError, "章トークンを解決できません: #{input.inspect}" unless entry&.valid?

          if !entry.in_catalog? && entry.slug.to_s.empty?
            raise InvalidInputError, "新規 PDF 登録時は slug を含む章トークンを指定してください (例: 10-foo)"
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

          raise InvalidInputError, "slug を含む章トークンを指定してください (例: 10-foo)"
        end

        # 出力先 Markdown が既存なら、上書きを避けて新しい章番号を割り当てる
        def ensure_unique_output_entry(entry)
          return entry unless markdown_exists?(entry.basename)

          CLI::Common.log_info("[pdf:read] #{entry.basename}.md を上書きしないため、新しい章番号を割り当てます。")

          slug_source = entry.slug.to_s.empty? ? entry.basename : entry.slug
          new_basename = next_available_basename(slug_source)

          build_entry_from_basename(entry, new_basename)
        end

        # Entry が catalog.yml 未登録なら CatalogUpdater で自動追記する
        def add_catalog_entry_if_needed(entry)
          return if entry.in_catalog?

          CLI::Build::CatalogUpdater.add_chapter(entry.basename)
          @catalog_entries = nil
          CLI::Common.log_info("[pdf:read] catalog.yml に #{entry.basename} を追加しました")
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
            [$1, $2]
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
        # 見つからなければ MissingPdfError を送出
        def determine_pdf_path(entry)
          slug = entry.slug.to_s.strip
          candidates = []
          candidates << File.join(sources_dir, "#{slug}.pdf") unless slug.empty?
          candidates << File.join(sources_dir, "#{entry.basename}.pdf")
          candidates.uniq!

          return candidates.find { File.exist?(it) } if candidates.any? { File.exist?(it) }

          details = candidates.map { "- 探索パス: #{_1}" }.join("\n")

          raise MissingPdfError, <<~MSG.strip
            PDF ファイルが見つかりませんでした。
            - 指定トークン: #{entry.basename}
            #{details}
            sources ディレクトリに PDF を配置するか、ファイルパスを直接指定してください。
          MSG
        end

        # book.yml の directories.sources または既定の "sources" ディレクトリを返す
        # 存在しなければ自動作成する
        def sources_dir
          return @sources_dir if defined?(@sources_dir)

          configured = CLI::Common::CONFIG.dig(:directories, :sources)
          dir = configured || SOURCES_DIR
          FileUtils.mkdir_p(dir)
          @sources_dir = dir
        rescue StandardError
          FileUtils.mkdir_p(SOURCES_DIR)
          @sources_dir = SOURCES_DIR
        end

        # 原稿出力先ディレクトリ（contents/）
        def contents_dir
          CLI::Common::CONTENTS_DIR
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

          File.write(markdown_path, markdown, mode: "w", encoding: "UTF-8")

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

          File.write(markdown_path, markdown, mode: "w", encoding: "UTF-8")

          CLI::Common.log_info("[pdf:read] ページ数: #{pages}")

          { markdown_path:, pages: }
        rescue LoadError
          raise InvalidInputError, missing_enhanced_plugin_message
        rescue StandardError => e
          raise Error, "Enhanced mode の解析に失敗しました: #{e.message}"
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
          body = "" if body.nil?
          body = body.strip
          body += "\n" unless body.empty? || body.end_with?("\n")
          body
        end

        # テキストの汎用サニタイズ: NBSP 除去・改行正規化・末尾空白除去・連続空行の圧縮
        def sanitize(text)
          text
            .to_s
            .gsub("\u00A0", " ")
            .gsub(/\r\n?/, "\n")
            .gsub(/[ \t]+$/, "")
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

            if current_y && (current_y - run.y).abs <= line_merge_tolerance
              line_buffer << run.text
            else
              unless line_buffer.empty?
                lines << line_buffer.dup
                line_buffer.clear
              end
              current_y = run.y
              line_buffer << run.text
            end
          end

          lines << line_buffer unless line_buffer.empty?
          text = lines.join("\n")
          capture_first_page_headings(text) if index.zero?
          text
        rescue StandardError => e
          CLI::Common.log_warn("[pdf:read] ページ#{index + 1} の text_runs 解析に失敗: #{e.message}. fallback モードで処理します。")
          extract_with_fallback(page, index)
        end

        # PDF::Reader::Page から text_runs を安全に取得する
        # 未対応や例外時は nil を返して fallback に委ねる
        def fetch_text_runs(page)
          return nil unless page.respond_to?(:text_runs)

          page.text_runs
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

          tokens = text.to_s.split("\n").map { normalize_heading_token(_1) }.map { strip_chapter_prefix(_1) }.map { strip_numeric_prefix(_1) }.map(&:strip).reject(&:empty?)
          @first_page_heading_tokens = tokens.first(3)
        end

        # 見出しトークンの正規化: 全角スペース→半角、連続空白を圧縮
        def normalize_heading_token(line)
          line.to_s.tr("　", " ").gsub(/\s+/, " ").strip
        end

        # 「第N章」形式の接頭辞を除去する
        def strip_chapter_prefix(line)
          line.sub(/\A第[一二三四五六七八九十百千0-9０-９]+章\s*/, "")
        end

        # 「1.2」「3-1」形式の数字接頭辞を除去する
        def strip_numeric_prefix(line)
          line.sub(/\A[0-9０-９]+(?:[.\-][0-9０-９]+)*\.?\s*/, "")
        end

        # 1 ページ目の見出しと一致する数字付き柱（ランニングヘッド）行かどうか
        def numeric_pillar_line?(line)
          tokens = @first_page_heading_tokens
          return false unless tokens&.any?
          return false unless line.match?(NUMERIC_PILLAR_PREFIX_REGEX)

          stripped = strip_numeric_prefix(strip_chapter_prefix(normalize_heading_token(line)))
          return false if stripped.empty?

          tokens.any? { stripped.start_with?(_1) }
        end

        # ミリメートルを PDF ポイント（1pt = 1/72 inch）に変換する
        def mm_to_pt(value)
          return 0.0 unless value
          value.to_f * (72.0 / 25.4)
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

        # book.yml の pdf_read 設定全体を取得する
        def pdf_read_settings
          return unless CLI::Common::CONFIG.respond_to?(:pdf_read)

          CLI::Common::CONFIG.pdf_read
        rescue StandardError
          nil
        end

        # vivlio-starter-pdf の有無に応じて :enhanced / :standard を返す
        def resolved_mode = plugin_available? ? :enhanced : :standard

        # vivlio-starter-pdf を外部プロセスで実行し、JSON 形式の解析結果を取得する
        def enhanced_result(pdf_path, entry)
          ensure_enhanced_plugin_loaded!

          stdout, status = capture_enhanced_command(*enhanced_command(pdf_path, entry))
          raise Error, stdout.strip unless status.success?

          JSON.parse(stdout)
        rescue Errno::ENOENT
          raise LoadError, missing_enhanced_plugin_message
        rescue JSON::ParserError => e
          raise Error, "Enhanced mode の応答解析に失敗しました: #{e.message}"
        end

        # Enhanced Mode の結果からページごとのテキスト配列を取り出す
        def enhanced_page_texts(result)
          page_texts = result[:page_texts] || result["page_texts"]
          Array(page_texts)
        end

        # Enhanced Mode の結果からページごとの処理済みチャンク配列を取り出す
        def enhanced_page_chunks(result)
          page_chunks = result[:page_chunks] || result["page_chunks"]
          Array(page_chunks)
        end

        # Enhanced Mode の結果から { ページ番号 => [画像参照パス, ...] } マップを構築する
        def enhanced_image_reference_map(result)
          enhanced_images(result).each_with_object({}) do |asset, refs|
            page = (asset[:page] || asset["page"]).to_i
            reference_path = asset[:reference_path] || asset["reference_path"]
            next if page <= 0 || reference_path.to_s.empty?

            refs[page] ||= []
            refs[page] << reference_path
          end
        end

        # Enhanced Mode の結果から画像情報の配列を取り出す
        def enhanced_images(result)
          images = result[:images] || result["images"]
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
                             .gsub(/(?<=\S)[ \t]*(!\[[^\]]*\]\([^\)]+\))/, "\n\\1")
                             .gsub(/(!\[[^\]]*\]\([^\)]+\))[ \t]*(?=\S)/, "\\1\n")

          rebuilt = []

          isolated.split("\n", -1).each do |line|
            stripped = line.strip

            if markdown_image_reference_line?(stripped)
              rebuilt << "" unless rebuilt.empty? || rebuilt.last.empty?
              rebuilt << stripped
              rebuilt << ""
            else
              rebuilt << line
            end
          end

          rebuilt.join("\n").gsub(/\n{3,}/, "\n\n")
        end

        # 行が Markdown 画像参照のみで構成されているか
        def markdown_image_reference_line?(line)
          line.to_s.match?(/\A!\[[^\]]*\]\([^\)]+\)\z/)
        end

        # Enhanced Mode の結果からページ数を取得する（報告値がなければテキスト配列長で代替）
        def enhanced_page_count(result, page_texts)
          reported = result[:pages] || result["pages"]
          count = reported.to_i
          count.positive? ? count : page_texts.length
        end

        # vivlio-starter-pdf へ渡すコマンド引数を組み立てる
        # OCR 設定・マージン・画像出力先などを JSON エンコードして引き渡す
        def enhanced_command(pdf_path, entry)
          [
            *enhanced_plugin_command,
            "read",
            File.expand_path(pdf_path, Dir.pwd),
            "page_separator=#{pdf_read_page_separator?}",
            "text_area=#{JSON.generate(text_area_margin_points)}",
            "line_merge_tolerance=#{line_merge_tolerance}",
            "images_dir=#{enhanced_images_output_dir(entry)}",
            "image_reference_dir=#{enhanced_images_reference_dir(entry)}",
            "ocr=#{JSON.generate(enhanced_ocr_settings)}"
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
          case value.to_s.strip.downcase.tr("-", "_")
          in "" then ""
          in "japanese" then "jpn"
          in "japanese_vertical" then "jpn_vert"
          else value.to_s.strip
          end
        end

        # inline_image_text の設定値を include / exclude / captionize のいずれかに正規化する
        def normalize_inline_image_text(value)
          case value.to_s.strip.downcase
          in "" | "include" then "include"
          in "exclude" | "remove" then "exclude"
          in "captionize" | "caption_only" | "caption" then "captionize"
          else "include"
          end
        end

        # Enhanced Mode で抽出した画像の保存先ディレクトリ（images/{basename}/）
        def enhanced_images_output_dir(entry)
          File.expand_path(File.join(CLI::Common.images_dir, entry.basename), Dir.pwd)
        end

        # Markdown 内の画像参照パスの基底ディレクトリ（空文字で相対パス出力）
        def enhanced_images_reference_dir(_entry)
          ""
        end

        # vivlio-starter-pdf の実行コマンドを決定する
        # ローカル開発環境では bundle exec 経由、それ以外はインストール済み実行ファイルを使用
        def enhanced_plugin_command
          return [enhanced_plugin_executable] unless local_enhanced_plugin_root

          ["bundle", "exec", "ruby", "-Ilib", "exe/vivlio-starter-pdf"]
        end

        # インストール済み vivlio-starter-pdf の実行ファイル名
        def enhanced_plugin_executable = "vivlio-starter-pdf"

        # ローカル開発用の vivlio-starter-pdf リポジトリが隣接ディレクトリにあるか検出する
        # Gemfile と exe/vivlio-starter-pdf の両方が存在すれば開発モードとして扱う
        def local_enhanced_plugin_root
          candidate = File.expand_path("../../../../../../vivlio-starter-pdf", __dir__)
          return nil unless File.exist?(File.join(candidate, "Gemfile"))
          return nil unless File.exist?(File.join(candidate, "exe", "vivlio-starter-pdf"))

          candidate
        end

        # Enhanced Mode が利用不可時のエラーメッセージ
        def missing_enhanced_plugin_message
          "Enhanced mode を利用するには vivlio-starter-pdf をインストールしてください"
        end

        # MeCab を使った日本語改行補正器（メモ化）
        def newline_cleaner
          @newline_cleaner ||= Vivlio::Starter::PDF::MecabNewlineCleaner.new
        end

        # 任意文字列を URL 安全な slug に正規化する（小文字化・記号除去・ハイフン化）
        def normalize_slug(value)
          slug = value.to_s.downcase
                        .tr(" ", "-")
                        .gsub(/[^a-z0-9\-]+/, "-")
                        .gsub(/-+/, "-")
                        .gsub(/\A-+|-+\z/, "")
          slug = "imported" if slug.empty?
          slug
        end

        # vivlio-starter-pdf がインストール済みで実行可能かどうかを判定する（結果をキャッシュ）
        def plugin_available?
          return @plugin_available if @plugin_checked

          _stdout, status = capture_enhanced_command(*enhanced_plugin_command, "--version")
          @plugin_available = status.success?
        rescue Errno::ENOENT
          @plugin_available = false
        ensure
          @plugin_checked = true
        end

        # vivlio-starter-pdf を外部プロセスとして実行し、stdout と status を返す
        # Bundler 環境下では with_unbundled_env でプラグイン側の Gemfile を使わせる
        def capture_enhanced_command(*command)
          options = local_enhanced_plugin_command?(command) ? { chdir: local_enhanced_plugin_root } : {}
          return Open3.capture2e(*command, **options) unless defined?(Bundler)

          Bundler.with_unbundled_env do
            Open3.capture2e(*command, **options)
          end
        end

        # コマンド配列がローカル開発用の bundle exec 形式かどうかを判定する
        def local_enhanced_plugin_command?(command)
          command.first(5) == ["bundle", "exec", "ruby", "-Ilib", "exe/vivlio-starter-pdf"]
        end

        # Enhanced Mode のプラグインが利用可能でなければ LoadError を送出する
        def ensure_enhanced_plugin_loaded!
          return if plugin_available?

          raise LoadError, missing_enhanced_plugin_message
        end

        # Enhanced Mode が利用可能な旨をログに出力する（情報提供用）
        def log_enhanced_hint
          CLI::Common.log_info("[pdf:read] vivlio-starter-pdf (Enhanced Mode) が利用可能です。連携は近日追加予定です。")
        end
      end
    end
  end
end
