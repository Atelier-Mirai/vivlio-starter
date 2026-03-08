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
      # Convert a PDF into Markdown using the Standard (text-only) pipeline.
      # Enhanced (HexaPDF) mode detection is wired, delegation follows later.
      class PdfReadCommand
        NUMERIC_PILLAR_PREFIX_REGEX = /\A[0-9０-９]+(?:[.\-][0-9０-９]+)*\.?\s+.+\z/.freeze
        DASHED_PAGE_NUMBER_REGEX = /\A[\-–—]\s*[0-9０-９ivxlcdmIVXLCDM]+\s*[\-–—]\z/.freeze
        Error = Class.new(StandardError)
        InvalidInputError = Class.new(Error)
        MissingPdfError = Class.new(Error)

        SOURCES_DIR = "sources"
        MAX_AUTO_CHAPTER = 98

        def initialize(input, options = {})
          @input = input.to_s.strip
          @options = options || {}
          @resolver = CLI::TokenResolver::Resolver.new
          @catalog_entries = nil
          @plugin_checked = false
          @plugin_available = false
        end

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

        def resolve_entry_and_pdf
          if pdf_path_argument?
            entry = entry_from_pdf_path
            [entry, expanded_input_path]
          else
            entry = entry_from_token
            [entry, determine_pdf_path(entry)]
          end
        end

        def entry_from_pdf_path
          base = normalized_basename(expanded_input_path)
          entry = resolve_with_single_token(base)

          return entry if entry&.valid? && entry.slug

          allocate_entry_for(base)
        end

        def entry_from_token
          entry = resolve_with_single_token(token_candidate)
          raise InvalidInputError, "章トークンを解決できません: #{input.inspect}" unless entry&.valid?

          if !entry.in_catalog? && entry.slug.to_s.empty?
            raise InvalidInputError, "新規 PDF 登録時は slug を含む章トークンを指定してください (例: 10-foo)"
          end

          entry
        end

        def resolve_with_single_token(token)
          resolver.resolve([token]).first
        end

        def allocate_entry_for(slug_source)
          basename = next_available_basename(slug_source)
          resolve_with_single_token(basename)
        end

        def next_available_basename(slug_source)
          slug = normalize_slug(slug_source)
          number = next_available_number
          "#{number}-#{slug}"
        end

        def next_available_number
          used_numbers = (catalog_entries.map(&:number) + existing_markdown_numbers).uniq

          (1..MAX_AUTO_CHAPTER).each do |candidate|
            number = format('%02d', candidate)
            return number unless used_numbers.include?(number)
          end

          raise Error, "01-#{format('%02d', MAX_AUTO_CHAPTER)} までの章番号がすべて使用済みです"
        end

        def catalog_entries
          @catalog_entries ||= resolver.resolve([])
        end

        def existing_markdown_numbers
          Dir.glob(File.join(contents_dir, '*.md')).filter_map do |path|
            File.basename(path, '.md')[/\A(\d{2})/, 1]
          end
        end

        def ensure_entry_has_slug!(entry)
          return unless entry.slug.to_s.empty?

          raise InvalidInputError, "slug を含む章トークンを指定してください (例: 10-foo)"
        end

        def ensure_unique_output_entry(entry)
          return entry unless markdown_exists?(entry.basename)

          CLI::Common.log_info("[pdf:read] #{entry.basename}.md を上書きしないため、新しい章番号を割り当てます。")

          slug_source = entry.slug.to_s.empty? ? entry.basename : entry.slug
          new_basename = next_available_basename(slug_source)

          build_entry_from_basename(entry, new_basename)
        end

        def add_catalog_entry_if_needed(entry)
          return if entry.in_catalog?

          CLI::Build::CatalogUpdater.add_chapter(entry.basename)
          @catalog_entries = nil
          CLI::Common.log_info("[pdf:read] catalog.yml に #{entry.basename} を追加しました")
        rescue StandardError => e
          raise Error, "catalog.yml の更新に失敗しました: #{e.message}"
        end

        def markdown_exists?(basename)
          File.exist?(File.join(contents_dir, "#{basename}.md"))
        end

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

        def parse_basename(basename)
          if basename =~ /(\A\d{2})(?:[-_](.+))?\z/
            [$1, $2]
          else
            [basename, nil]
          end
        end

        def token_candidate = input

        def normalized_basename(path)
          File.basename(path, File.extname(path))
        end

        def pdf_path_argument?
          File.file?(expanded_input_path) && pdf_extension?(expanded_input_path)
        rescue Errno::ENOENT
          false
        end

        def pdf_extension?(path)
          File.extname(path).casecmp('.pdf').zero?
        end

        def expanded_input_path
          @expanded_input_path ||= File.expand_path(input)
        end

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

        def contents_dir
          CLI::Common::CONTENTS_DIR
        end

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

        def sanitize(text)
          text
            .to_s
            .gsub("\u00A0", " ")
            .gsub(/\r\n?/, "\n")
            .gsub(/[ \t]+$/, "")
            .gsub(/\n{3,}/, "\n\n")
            .strip
        end

        def process_extracted_page_text(text, index)
          lines = text.to_s.split("\n", -1)
          trimmed = drop_header_footer_candidates(lines, index:)
          page_text = trimmed.join("\n")
          capture_first_page_headings(page_text) if index.zero?
          cleaned = newline_cleaner.clean(page_text)
          sanitize(cleaned)
        end

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

        def fetch_text_runs(page)
          return nil unless page.respond_to?(:text_runs)

          page.text_runs
        rescue StandardError => e
          CLI::Common.log_warn("[pdf:read] text_runs の取得に失敗: #{e.message}. fallback モードに切り替えます。")
          nil
        end

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

        def strip_fallback_borders(lines, page, index: nil)
          purified = lines.each_with_index.map { _2.zero? ? _1.strip : _1.rstrip }
          trimmed = drop_margin_lines(purified, page, index:)
          drop_header_footer_candidates(trimmed, index:)
        end

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

        def drop_header_footer_candidates(lines, index: nil)
          trimmed = lines.drop_while { header_or_footer_candidate?(it, index:) }
          trimmed = trimmed.reverse.drop_while { header_or_footer_candidate?(it, index:) }.reverse
          trimmed.empty? ? lines : trimmed
        end

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

        def within_text_area?(run, bounds)
          x = run.x
          y = run.y
          x.between?(bounds[:left], bounds[:right]) && y.between?(bounds[:bottom], bounds[:top])
        end

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

        def media_box(page)
          return page.mediabox if page.respond_to?(:mediabox)

          box = page.attributes[:MediaBox] if page.respond_to?(:attributes)
          return box if box.is_a?(Array) && box.length >= 4

          nil
        rescue StandardError
          nil
        end

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

        def line_merge_tolerance = 2.0

        def capture_first_page_headings(text)
          return if @first_page_heading_tokens

          tokens = text.to_s.split("\n").map { normalize_heading_token(_1) }.map { strip_chapter_prefix(_1) }.map { strip_numeric_prefix(_1) }.map(&:strip).reject(&:empty?)
          @first_page_heading_tokens = tokens.first(3)
        end

        def normalize_heading_token(line)
          line.to_s.tr("　", " ").gsub(/\s+/, " ").strip
        end

        def strip_chapter_prefix(line)
          line.sub(/\A第[一二三四五六七八九十百千0-9０-９]+章\s*/, "")
        end

        def strip_numeric_prefix(line)
          line.sub(/\A[0-9０-９]+(?:[.\-][0-9０-９]+)*\.?\s*/, "")
        end

        def numeric_pillar_line?(line)
          tokens = @first_page_heading_tokens
          return false unless tokens&.any?
          return false unless line.match?(NUMERIC_PILLAR_PREFIX_REGEX)

          stripped = strip_numeric_prefix(strip_chapter_prefix(normalize_heading_token(line)))
          return false if stripped.empty?

          tokens.any? { stripped.start_with?(_1) }
        end

        def mm_to_pt(value)
          return 0.0 unless value
          value.to_f * (72.0 / 25.4)
        end

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

        def pdf_read_text_area = fetch_pdf_read_section(:text_area)

        def pdf_read_ocr = fetch_pdf_read_section(:ocr)

        def pdf_read_page_separator
          fetch_pdf_read_section(:page_separator)
        end

        def pdf_read_page_separator? = pdf_read_page_separator != false

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

        def pdf_read_settings
          return unless CLI::Common::CONFIG.respond_to?(:pdf_read)

          CLI::Common::CONFIG.pdf_read
        rescue StandardError
          nil
        end

        def resolved_mode = plugin_available? ? :enhanced : :standard

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

        def enhanced_page_texts(result)
          page_texts = result[:page_texts] || result["page_texts"]
          Array(page_texts)
        end

        def enhanced_page_chunks(result)
          page_chunks = result[:page_chunks] || result["page_chunks"]
          Array(page_chunks)
        end

        def enhanced_image_reference_map(result)
          enhanced_images(result).each_with_object({}) do |asset, refs|
            page = (asset[:page] || asset["page"]).to_i
            reference_path = asset[:reference_path] || asset["reference_path"]
            next if page <= 0 || reference_path.to_s.empty?

            refs[page] ||= []
            refs[page] << reference_path
          end
        end

        def enhanced_images(result)
          images = result[:images] || result["images"]
          Array(images)
        end

        def append_image_references(text, references)
          refs = Array(references).reject { it.to_s.empty? }
          return text if refs.empty?

          parts = []
          parts << text unless text.to_s.empty?
          parts.concat(refs.map { "![](#{it})" })
          parts.join("\n\n")
        end

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

        def markdown_image_reference_line?(line)
          line.to_s.match?(/\A!\[[^\]]*\]\([^\)]+\)\z/)
        end

        def enhanced_page_count(result, page_texts)
          reported = result[:pages] || result["pages"]
          count = reported.to_i
          count.positive? ? count : page_texts.length
        end

        def enhanced_command(pdf_path, entry)
          [
            enhanced_plugin_executable,
            "read",
            pdf_path,
            "page_separator=#{pdf_read_page_separator?}",
            "text_area=#{JSON.generate(text_area_margin_points)}",
            "line_merge_tolerance=#{line_merge_tolerance}",
            "images_dir=#{enhanced_images_output_dir(entry)}",
            "image_reference_dir=#{enhanced_images_reference_dir(entry)}",
            "ocr=#{JSON.generate(enhanced_ocr_settings)}"
          ]
        end

        def enhanced_ocr_settings
          cfg = pdf_read_ocr
          {
            mode: value_from_config(cfg, :mode),
            languages: normalize_ocr_languages(value_from_config(cfg, :languages)),
            dpi: value_from_config(cfg, :dpi),
            psm: value_from_config(cfg, :psm)
          }.compact
        end

        def normalize_ocr_languages(value)
          case value
          in Array then value.map { it.to_s.strip }.reject(&:empty?)
          else
            value.to_s.split(/[+,]/).map { it.strip }.reject(&:empty?)
          end
        end

        def enhanced_images_output_dir(entry)
          File.join(CLI::Common.images_dir, entry.basename)
        end

        def enhanced_images_reference_dir(entry)
          File.join("images", entry.basename)
        end

        def enhanced_plugin_executable = "vivlio-starter-pdf"

        def missing_enhanced_plugin_message
          "Enhanced mode を利用するには vivlio-starter-pdf をインストールしてください"
        end

        def newline_cleaner
          @newline_cleaner ||= Vivlio::Starter::PDF::MecabNewlineCleaner.new
        end

        def normalize_slug(value)
          slug = value.to_s.downcase
                        .tr(" ", "-")
                        .gsub(/[^a-z0-9\-]+/, "-")
                        .gsub(/-+/, "-")
                        .gsub(/\A-+|-+\z/, "")
          slug = "imported" if slug.empty?
          slug
        end

        def plugin_available?
          return @plugin_available if @plugin_checked

          _stdout, status = capture_enhanced_command(enhanced_plugin_executable, "--version")
          @plugin_available = status.success?
        rescue Errno::ENOENT
          @plugin_available = false
        ensure
          @plugin_checked = true
        end

        def capture_enhanced_command(*command)
          return Open3.capture2e(*command) unless defined?(Bundler)

          Bundler.with_unbundled_env do
            Open3.capture2e(*command)
          end
        end

        def ensure_enhanced_plugin_loaded!
          return if plugin_available?

          raise LoadError, missing_enhanced_plugin_message
        end

        def log_enhanced_hint
          CLI::Common.log_info("[pdf:read] vivlio-starter-pdf (Enhanced Mode) が利用可能です。連携は近日追加予定です。")
        end
      end
    end
  end
end
