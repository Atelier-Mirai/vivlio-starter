# frozen_string_literal: true

require 'nokogiri'
require 'pathname'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: toc（目次生成）
      # ------------------------------------------------
      # - 目的: 章HTMLから 03-toc.md/.html を生成
      # - 提供コマンド: toc
      # - 主な処理: 目次の <ul>/<li> 構築, 前書き/後書きの見出し追加, VFM 変換
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module TocCommands
        module_function

        TOC_DESC = {
          short: '目次HTMLを生成します（引数でHTMLを列挙した場合はそれらのみ対象）',
          long: <<~DESC
            指定した HTML を対象に目次を生成します。引数が無い場合はプロジェクト直下の HTML を自動検出し、
            以下を除外して処理します: 00-titlepage.html / 01-legalpage.html / 03-toc.html / 99-colophon.html。

            例:
              vs toc 11-gift.html 12-tutorial.html
              vs toc                # 自動検出
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'toc [HTMLs...]', TOC_DESC[:short]
            long_desc TOC_DESC[:long]

            # toc サブコマンドのエントリポイント
            def toc(*htmls)
              TocCommandExecutor.new(self, htmls).call
            end
          end
        end

        # toc コマンドのエントリ処理を統括する
        class TocCommandExecutor
          BASE_DIR = Pathname.new('.').expand_path

          def initialize(command, htmls)
            @command = command
            @resolver = HtmlTargetResolver.new(htmls, base_dir: BASE_DIR)
          end

          # コマンド全体の処理を実行する
          def call
            enable_verbose_if_requested
            targets = resolver.resolve
            return warn_no_targets if targets.empty?

            log_targets(targets)
            document = TocDocumentBuilder.new(targets, base_dir: BASE_DIR).build
            TocOutputWriter.new(document, base_dir: BASE_DIR).write
          end

          private

          attr_reader :command, :resolver

          # Thor の options を返す（なければ空ハッシュ）
          def options
            command.respond_to?(:options) ? command.options || {} : {}
          end

          # verbose オプション指定時に VERBOSE 環境変数を立てる
          def enable_verbose_if_requested
            ENV['VERBOSE'] = '1' if options[:verbose]
          end

          # 対象 HTML が無い場合の警告
          def warn_no_targets
            Common.log_warn('目次対象となるHTMLが見つかりません。処理を中止します')
          end

          # 目次生成対象のファイル名をログ出力する
          def log_targets(targets)
            names = targets.map { |path| File.basename(path) }.join(', ')
            Common.log_action("目次の生成を開始します… 対象: #{names}")
          end
        end

        # 対象となる HTML ファイルを解決する
        class HtmlTargetResolver
          EXCLUDE_FILES = %w[00-titlepage.html 01-legalpage.html 03-toc.html 99-colophon.html].freeze

          def initialize(htmls, base_dir:)
            @htmls = Array(htmls)
            @base_dir = Pathname.new(base_dir)
          end

          # 指定があればそれを、無ければ既定パターンを返す
          def resolve
            htmls.any? ? provided_targets : default_targets
          end

          private

          attr_reader :htmls, :base_dir

          # 指定されたファイル群から存在するものを取り出す
          def provided_targets
            paths = sanitized_inputs
            existing, missing = paths.partition { |path| File.exist?(path) }
            missing.each { |path| Common.log_warn("見つかりません: #{path}") }
            existing
          end

          # 指定ファイルを正規化してリスト化する
          def sanitized_inputs
            htmls.select { |name| name.end_with?('.html') }.map { |name| normalize_path(name) }
          end

          # デフォルトで base_dir 配下の対象 HTML を列挙する
          def default_targets
            Dir.glob(base_dir.join('*.html')).map { |path| normalize_path(path) }
               .reject { |path| EXCLUDE_FILES.include?(File.basename(path)) }
               .sort
          end

          # 渡されたパスを絶対パスに正規化する
          def normalize_path(name)
            path = Pathname.new(name)
            path = base_dir.join(path) unless path.absolute?
            path.cleanpath.to_s
          end
        end

        # TOC の Markdown ドキュメントを構築する
        class TocDocumentBuilder
          FRONT_MATTER = <<~MD
            ---
            link:
              - rel: "stylesheet"
                href: "stylesheets/toc.css"
            lang: 'ja'
            ---

            # 目次
            <nav id="toc" role="doc-toc">
            <ul>
          MD

          def initialize(targets, base_dir:)
            @targets = targets
            @base_dir = Pathname.new(base_dir)
          end

          # TOC の Markdown 文字列を構築する
          def build
            buffer = [FRONT_MATTER.dup]
            append_preface(buffer)
            append_headings(buffer)
            append_postface(buffer)
            buffer << "</ul>\n</nav>"
            buffer.join
          end

          private

          attr_reader :targets, :base_dir

          # 前書きエントリを必要に応じて追加する
          def append_preface(buffer)
            entry = SupplementEntryProvider.new(
              targets: targets,
              base_dir: base_dir,
              file_name: '02-preface.html'
            ).call
            buffer << entry if entry
          end

          # 各ターゲットから見出しを抽出し TOC のリストを構築
          def append_headings(buffer)
            list_state = ListState.new(buffer)

            targets.each do |target|
              HeadingExtractor.new(target).headings.each do |heading|
                list_state.transition_to(heading.level)
                list_state.open_item(heading.list_markup)
              end
            end

            list_state.prepare_for_postface
          end

          # 後書きエントリを必要に応じて追加する
          def append_postface(buffer)
            entry = SupplementEntryProvider.new(
              targets: targets,
              base_dir: base_dir,
              file_name: '98-postface.html'
            ).call
            buffer << entry if entry
          end

          # <ul>/<li> の入れ子状態を管理する
          class ListState
            BASE_LEVEL = 1

            def initialize(buffer)
              @buffer = buffer
              @current_level = BASE_LEVEL
              @item_open = false
            end

            # 指定レベルまでのネスト状態を調整する
            def transition_to(level)
              if level > current_level
                (level - current_level).times { buffer << "\n<ul>\n" }
                @item_open = false
              elsif level < current_level
                close_current_item
                (current_level - level).times { buffer << "</ul>\n</li>\n" }
              else
                close_current_item
              end
              @current_level = level
            end

            # <li> を開いてバッファへ追加する
            def open_item(markup)
              buffer << markup
              @item_open = true
            end

            # 後書き追加前に未閉じのリストを畳む
            def prepare_for_postface
              close_current_item
              while current_level > BASE_LEVEL
                buffer << "</ul>\n</li>\n"
                @current_level -= 1
              end
            end

            private

            attr_reader :buffer, :current_level

            # オープンしている <li> を閉じる
            def close_current_item
              return unless @item_open

              buffer << "</li>\n"
              @item_open = false
            end
          end
        end

        # 前書き／後書きのエントリを生成する
        class SupplementEntryProvider
          CSS_CLASS = 'toc-chapter-no-number'

          def initialize(targets:, base_dir:, file_name:)
            @targets = targets
            @base_dir = Pathname.new(base_dir)
            @file_name = file_name
          end

          # 指定された補助 HTML から TOC 項目を生成する
          def call
            return if included_in_targets?
            return unless File.exist?(html_path)

            build_entry(html_path)
          rescue StandardError
            nil
          end

          private

          attr_reader :targets, :base_dir, :file_name

          # 対象リストに既に該当ファイルが含まれているか判定する
          def included_in_targets?
            targets.any? { |path| File.basename(path) == file_name }
          end

          # 補助 HTML の絶対パスを返す
          def html_path
            @html_path ||= base_dir.join(file_name)
          end

          # HTML の h1 見出しから TOC エントリを構築する
          def build_entry(path)
            doc = Nokogiri::HTML(File.read(path, encoding: 'utf-8'))
            heading = doc.at_css('h1')
            return unless heading

            text = heading.text.to_s.strip
            heading_id = heading['id']
            return if text.empty? || heading_id.nil? || heading_id.empty?

            href = "#{file_name}##{heading_id}"
            %(<li class="#{CSS_CLASS}" data-href="#{href}">#{text}</li>\n)
          end
        end

        Heading = Struct.new(:level, :css_class, :href, :text, keyword_init: true) do
          # 見出し情報から TOC 用の <li> 文字列を生成する
          def list_markup
            href_attribute = href && !href.empty? ? %( data-href="#{href}") : ''
            %(<li class="#{css_class}"#{href_attribute}>#{text})
          end
        end

        # HTML 見出しから TOC 用項目を生成する
        class HeadingExtractor
          LEVEL_BY_TAG = { 'h1' => 1, 'h2' => 2, 'h3' => 3 }.freeze

          def initialize(target)
            @target = target
          end

          # ターゲット HTML から見出し情報を配列で返す
          def headings
            nodes.map { |node| build_heading(node) }.compact
          end

          private

          attr_reader :target

          # ファイル種別に応じて取り出す見出しタグを制御する
          def nodes
            case file_type
            when 'chapter'
              document.css('h1, h2, h3')
            when 'appendix'
              document.css('h1, h2')
            else
              document.css('h1')
            end
          end

          # 章/付録などのファイル種別を返す
          def file_type
            Common.get_file_type(target)
          end

          # Nokogiri ドキュメントを生成する（失敗時は空ドキュメント）
          def document
            @document ||= Nokogiri::HTML(File.read(target, encoding: 'utf-8'))
          rescue StandardError
            Nokogiri::HTML::Document.new
          end

          # 単一見出しノードから Heading 構造体を組み立てる
          def build_heading(node)
            node_id = node['id']
            return if node_id.nil? || node_id.empty?

            text = HeadingTextExtractor.extract(node)
            return if text.empty?

            Heading.new(
              level: level_for(node),
              css_class: css_class_for(node),
              href: href_for(node_id),
              text: text
            )
          end

          # 見出しタグに対応する TOC レベルを返す
          def level_for(node)
            LEVEL_BY_TAG.fetch(node.name, 3)
          end

          # 見出しタグに対応する CSS クラス名を返す
          def css_class_for(node)
            case node.name
            when 'h1'
              case file_type
              when 'chapter' then 'toc-chapter'
              when 'appendix' then 'toc-chapter-appendix'
              else 'toc-chapter-no-number'
              end
            when 'h2' then 'toc-section'
            else 'toc-subsection'
            end
          end

          # 見出しへのリンク用 href を生成する
          def href_for(node_id)
            rel = File.basename(target)
            "#{rel}##{node_id}"
          end
        end

        # 見出しから表示用テキストを抽出する
        class HeadingTextExtractor
          class << self
            # 見出しノードから表示用テキストを抽出する
            def extract(element)
              return '' unless element

              preferred_text = preferred_span_text(element)
              return preferred_text if preferred_text

              strip_numbers(element)
            end

            private

            # 見出しノードから優先的に抽出するテキストを返す
            def preferred_span_text(element)
              # 見出しノードと優先的に抽出するテキストのセレクタの対応
              selector_map = {
                'h1' => 'span.chapter-title',
                'h2' => 'span.section-title',
                'h3' => 'span.subsection-title'
              }
              selector = selector_map[element.name]
              span = selector ? element.at_css(selector) : nil
              text = span&.text&.strip
              text unless text.nil? || text.empty?
            end

            # 見出しノードから番号を除去したテキストを返す
            def strip_numbers(element)
              clone = element.dup
              clone.css('.chapter-number, .section-number, .subsection-number, .subsection-marker')&.each(&:remove)
              clone.text.to_s.strip
            rescue NoMethodError
              element.text.to_s.strip
            end
          end
        end

        # 生成した Markdown/HTML をファイルへ書き出す
        class TocOutputWriter
          def initialize(document, base_dir:)
            @document = document
            @base_dir = Pathname.new(base_dir)
          end

          # Markdown 生成から HTML 仕上げまでを実行する
          def write
            write_markdown
            generate_html
            finalize_html
          end

          private

          attr_reader :document, :base_dir

          # 03-toc.md を書き出す
          def write_markdown
            File.write(md_path, document, encoding: 'utf-8')
          end

          # VFM を呼び出し 03-toc.html を生成する
          def generate_html
            system(%(#{Common::VFM_COMMAND} "#{md_path}" > "#{html_path}"))
          end

          # HTML に class="toc" を付与して完了ログを出す
          def finalize_html
            if File.exist?(html_path)
              content = File.read(html_path, encoding: 'utf-8')
              content.sub!('<body>', '<body class="toc">')
              File.write(html_path, content, encoding: 'utf-8')
              Common.log_success('目次生成完了')
            else
              Common.log_warn('03-toc.html の生成に失敗しました（VFM 実行エラー）')
            end
          end

          # 03-toc.md のパスを返す
          def md_path
            @md_path ||= base_dir.join('03-toc.md')
          end

          # 03-toc.html のパスを返す
          def html_path
            @html_path ||= base_dir.join('03-toc.html')
          end
        end
      end
    end
  end
end
