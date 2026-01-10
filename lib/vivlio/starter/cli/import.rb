# frozen_string_literal: true

require 'fileutils'
require 'yaml'

require_relative 'common'
require_relative 'build/catalog_updater'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: import（Re:VIEW Starter からの移行）
      # ================================================================
      # 責務:
      #   Re:VIEW Starter プロジェクトから vivlio-starter への移行処理を行う。
      #
      # 処理内容:
      #   1. 既存ディレクトリ（contents/, images/, codes/）の削除
      #   2. .re → .md 変換（Starter 付属スクリプト使用）
      #   3. 画像の WebP 変換（ResizeCommands 使用）
      #   4. source/ → codes/ コピー
      #   5. catalog.yml / config.yml の変換
      #
      # 依存:
      #   - ResizeCommands: 画像最適化
      #   - Common: ログ出力
      # ================================================================
      module ImportCommands
        module_function

        IMPORT_DESC = {
          default: {
            short: 'Re:VIEW Starter プロジェクトをインポートします',
            long: <<~DESC
              Re:VIEW Starter プロジェクトを vivlio-starter にインポートします。

              引数:
                STARTER_DIR    Re:VIEW Starter プロジェクトのディレクトリ（必須）

              オプション:
                --force    確認プロンプトをスキップ

              使用例:
                vs import ../review_starter_project
                vs import --force ../review_starter_project
            DESC
          }
        }.freeze

        # メイン実行メソッド
        def execute_import(starter_dir, options = {})
          @options = options
          @starter_dir = File.expand_path(starter_dir)

          validate_starter_directory!
          return 1 unless confirm_cleanup_or_force?

          cleanup_existing_directories!
          convert_re_to_md!
          convert_images_to_webp!
          copy_source_to_codes!
          convert_catalog!
          convert_config!

          Common.log_success('インポートが完了しました')
          0
        rescue StandardError => e
          Common.log_error("インポート中にエラーが発生しました: #{e.message}")
          Common.log_error(e.backtrace.join("\n")) if ENV['VS_DEBUG']
          1
        end

        # Starter ディレクトリの検証
        def validate_starter_directory!
          unless Dir.exist?(@starter_dir)
            raise "Starter ディレクトリが見つかりません: #{@starter_dir}"
          end

          # 必須スクリプトの存在確認
          markdownmaker = File.join(@starter_dir, 'lib/ruby/review-markdownmaker.rb')
          markdownbuilder = File.join(@starter_dir, 'lib/ruby/review-markdownbuilder.rb')

          unless File.exist?(markdownmaker)
            raise "変換スクリプトが見つかりません: #{markdownmaker}"
          end

          unless File.exist?(markdownbuilder)
            raise "変換スクリプトが見つかりません: #{markdownbuilder}"
          end

          Common.log_info("Starter ディレクトリ: #{@starter_dir}")
        end

        # 確認プロンプトまたは --force
        def confirm_cleanup_or_force?
          return true if @options[:force]

          dirs_to_delete = %w[contents images codes].select do |dir|
            Dir.exist?(dir)
          end

          if dirs_to_delete.empty?
            Common.log_info('削除対象のディレクトリはありません')
            return true
          end

          Common.log_warn("以下のディレクトリを削除してインポートを行います:")
          dirs_to_delete.each { |d| Common.log_warn("  - #{d}/") }

          print '続行しますか？ [y/N]: '
          return false unless $stdin.tty?

          ans = $stdin.gets
          return false unless ans && ans.strip.downcase == 'y'

          true
        end

        # 既存ディレクトリの削除
        def cleanup_existing_directories!
          Common.log_action('[Step 1] 既存ディレクトリを削除します')

          %w[contents images codes].each do |dir|
            next unless Dir.exist?(dir)

            FileUtils.rm_rf(dir)
            Common.log_info("  削除: #{dir}/")
          end

          # ディレクトリを再作成
          %w[contents images codes].each do |dir|
            FileUtils.mkdir_p(dir)
          end
        end

        # .re → .md 変換
        def convert_re_to_md!
          Common.log_action('[Step 2] .re → .md 変換を実行します')

          # temp ディレクトリを準備
          temp_dir = 'temp'
          FileUtils.mkdir_p(temp_dir)

          # Starter ディレクトリで rake markdown を実行
          Dir.chdir(@starter_dir) do
            config_file = File.join(@starter_dir, 'config.yml')
            unless File.exist?(config_file)
              raise "config.yml が見つかりません: #{config_file}"
            end

            # bookname を取得して出力ディレクトリを特定
            config = YAML.safe_load(File.read(config_file), permitted_classes: [Symbol])
            bookname = config['bookname'] || 'book'
            md_output_dir = "#{bookname}-md"

            # 既存の md 出力ディレクトリがあればそれを使用、なければ rake markdown を実行
            if Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
              Common.log_info("  既存の #{md_output_dir}/ を使用します")
            else
              # rake markdown を実行
              Common.log_info('  rake markdown を実行中...')
              # RUBYOPT をクリアして環境の競合を回避
              env = { 'RUBYOPT' => nil, 'BUNDLE_GEMFILE' => nil }
              result = system(env, 'rake', 'markdown')
              
              # 生成された md ファイルを確認
              unless Dir.exist?(md_output_dir) && !Dir.glob(File.join(md_output_dir, '*.md')).empty?
                raise "Markdown 出力ディレクトリが見つからないか空です: #{md_output_dir}\n" \
                      "手動で `cd #{@starter_dir} && rake markdown` を実行してから再度インポートしてください。"
              end
            end
            Common.log_info("  #{Dir.glob(File.join(md_output_dir, '*.md')).size} 個の Markdown ファイルを検出しました")

            @md_output_dir = md_output_dir
          end

          # vivlio-starter の temp にコピー
          starter_md_dir = File.join(@starter_dir, @md_output_dir)
          vivlio_root = Dir.pwd
          Dir.chdir(vivlio_root) do
            Dir.glob(File.join(starter_md_dir, '*.md')).each do |md_file|
              FileUtils.cp(md_file, temp_dir)
              Common.log_info("  コピー: #{File.basename(md_file)} → temp/")
            end

            # 追従変換を実行
            post_process_markdown!(temp_dir)

            # contents/ に移動
            Dir.glob(File.join(temp_dir, '*.md')).each do |md_file|
              dest = File.join('contents', File.basename(md_file))
              FileUtils.mv(md_file, dest)
              Common.log_info("  移動: #{File.basename(md_file)} → contents/")
            end

            # temp を削除
            FileUtils.rm_rf(temp_dir)
            Common.log_info('  temp/ を削除しました')
          end

          cleanup_starter_markdown_dir!
        end

        # Markdown の追従変換処理
        def post_process_markdown!(temp_dir)
          Common.log_info('  追従変換を実行中...')

          Dir.glob(File.join(temp_dir, '*.md')).each do |md_path|
            markdown = File.read(md_path)
            fixed = markdown.dup

            # <img> タグを Markdown 画像記法に変換
            # HTML の img タグを検出し、ファイル名部分だけを抽出して webp に書き換える
            fixed.gsub!(/<img src=".*\/([^\/]+)\.(?:png|jpg|jpeg|gif)">/i) do
              file_name_no_ext = Regexp.last_match(1)
              "![](#{file_name_no_ext}.webp)"
            end

            # フェンス記法
            {
              'abstract'   => 'chapter-lead',
              'tip'        => 'tip',
              'note'       => 'note',
              'notice'     => 'notice',
              'centering'  => 'centering',
              'flushright' => 'text-right',
            }.each do |tag, klass|
              fixed.gsub!(/^\[#{tag}\][ \t]*\n(.*?)\n\[\/#{tag}\][ \t]*$/m) do
                inner = Regexp.last_match(1).strip # 前後の空白や余計な改行を一括除去
                ":::{.#{klass}}\n#{inner}\n:::\n"
              end
            end

            # [column] ブロックはタイトルを許容する
            fixed.gsub!(/^\[column\](?:[ \t]+(.+?))?\s*\n(.*?)\n\[\/column\][ \t]*$/m) do
              title = Regexp.last_match(1)
              body  = Regexp.last_match(2).strip
              inner = []
              inner << title.to_s.strip unless title.to_s.strip.empty?
              inner << body unless body.empty?
              "::: {.column}\n#{inner.join("\n")}\n:::\n"
            end

            # [quote] → 引用ブロック
            fixed.gsub!(/^\[quote\][^\n]*\n(.*?)^\[\/quote\]\s*$/m) do
              # strip ではなく、前後の「空行のみ」を削る
              inner = Regexp.last_match(1).gsub(/\A\n+|\n+\z/, '')
              
              # 全ての行（空行含む）の先頭に "> " を付与
              # 空行でも "> " (スペースあり) にすることで、引用の継続を確実にする
              inner.lines.map { |l| "> #{l.rstrip}".strip }.join("\n") + "\n\n"
            end

            # <br> → .aki
            fixed.gsub!(/^\s*<br>\s*$/, '{.aki}')

            # コードブロックのキャプション変換
            # <span class="caption">▼janken.css</span>\n```  →  ```css:janken.css
            fixed.gsub!(/<span class="caption">▼([^<]+)<\/span>\s*\n```/i) do
              caption = Regexp.last_match(1).strip
              ext = File.extname(caption).delete('.').downcase
              ext = 'text' if ext.empty?
              "```#{ext}:#{caption}"
            end

            # Markdown 画像パスの正規化
            # ![alt](./images/chapter/file.png) → ![alt](file.webp)
            # alt テキストに [] が含まれる場合も対応
            fixed.gsub!(/!\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\.\/images\/[^)]+\/([^\/]+)\.(?:png|jpg|jpeg|gif)\)/i) do
              alt = Regexp.last_match(1)
              filename = Regexp.last_match(2)
              "![#{alt}](#{filename}.webp)"
            end

            # dl/dt/dd タグの Markdown 箇条書き変換
            fixed.gsub!(/<dl>\s*(.*?)\s*<\/dl>/m) do
              dl_content = Regexp.last_match(1)
              items = []
              # dt/dd ペアを抽出
              dl_content.scan(/<dt>([^<]*)<\/dt>\s*<dd>\s*(.*?)\s*<\/dd>/m) do |dt, dd|
                term = dt.strip
                desc = dd.strip.gsub(/\n\s*/, "\n    ") # 継続行をインデント
                # 複数行の場合、最初の改行の前に半角スペース2つを挿入
                if desc.include?("\n")
                  lines = desc.split("\n")
                  desc = lines.map.with_index { |l, i| i == lines.size - 1 ? l : "#{l}  " }.join("\n")
                end
                items << "- **#{term}**\n    #{desc}"
              end
              items.join("\n\n") + "\n"
            end

            # HTML テーブルの Markdown 表への変換
            fixed.gsub!(/<div class="table[^"]*">\s*(?:<p class="caption">([^<]*)<\/p>)?\s*<table>(.*?)<\/table>\s*<\/div>/m) do
              caption = Regexp.last_match(1)
              table_html = Regexp.last_match(2)
              
              rows = []
              table_html.scan(/<tr[^>]*>(.*?)<\/tr>/m) do |row_content|
                row = row_content[0]
                cells = row.scan(/<t[hd][^>]*>(.*?)<\/t[hd]>/m).map { |c| c[0].strip }
                rows << cells
              end
              
              next '' if rows.empty?
              
              # Markdown テーブル生成
              md_table = []
              md_table << "**#{caption}**\n" if caption && !caption.strip.empty?
              
              # ヘッダー行
              md_table << "| #{rows[0].join(' | ')} |"
              md_table << "| #{rows[0].map { '---' }.join(' | ')} |"
              
              # データ行
              rows[1..].each do |row|
                md_table << "| #{row.join(' | ')} |"
              end
              
              md_table.join("\n") + "\n"
            end

            # ルビ記法の変換: 漢字（よみ）→ {漢字|よみ}
            # ひらがな・カタカナ両対応、漢字の範囲を直前の連続漢字に限定
            fixed.gsub!(/([一-龯々]+)（([ぁ-んァ-ヶー]+)）/) do
              kanji = Regexp.last_match(1)
              reading = Regexp.last_match(2)
              "{#{kanji}|#{reading}}"
            end

            # HTML 文字実体参照をデコード
            require 'cgi'
            fixed = CGI.unescapeHTML(fixed)

            File.write(md_path, fixed) if fixed != markdown
          end
        end

        # 画像の WebP 変換
        def convert_images_to_webp!
          Common.log_action('[Step 3] 画像を WebP に変換します')

          starter_images = File.join(@starter_dir, 'images')
          unless Dir.exist?(starter_images)
            Common.log_warn("  images/ ディレクトリが見つかりません: #{starter_images}")
            return
          end

          # 画像をコピー
          patterns = %w[png jpg jpeg gif PNG JPG JPEG GIF]
          files = patterns.flat_map { |ext| Dir.glob(File.join(starter_images, "**/*.#{ext}")) }

          if files.empty?
            Common.log_info('  変換対象の画像がありません')
            return
          end

          files.each do |src|
            # ディレクトリ構造を維持してコピー
            relative = src.sub("#{starter_images}/", '')
            dest_dir = File.join('images', File.dirname(relative))
            FileUtils.mkdir_p(dest_dir)
            FileUtils.cp(src, File.join(dest_dir, File.basename(src)))
          end

          Common.log_info("  #{files.size} 個の画像をコピーしました")

          # ResizeCommands で WebP 変換
          ResizeCommands.execute_resize_medium('images')
          remove_original_image_files!
        end

        # source/ → codes/ コピー
        def copy_source_to_codes!
          Common.log_action('[Step 4] source/ → codes/ をコピーします')

          starter_source = File.join(@starter_dir, 'source')
          unless Dir.exist?(starter_source)
            Common.log_info("  source/ ディレクトリが見つかりません（スキップ）")
            return
          end

          FileUtils.cp_r(Dir.glob(File.join(starter_source, '*')), 'codes/')
          Common.log_info("  source/ の内容を codes/ にコピーしました")
        end

        # catalog.yml の変換
        def convert_catalog!
          Common.log_action('[Step 5] catalog.yml を変換します')

          starter_catalog = File.join(@starter_dir, 'catalog.yml')
          unless File.exist?(starter_catalog)
            Common.log_warn("  catalog.yml が見つかりません: #{starter_catalog}")
            return
          end

          catalog = YAML.safe_load(File.read(starter_catalog), permitted_classes: [Symbol])

          # キー名の変換
          new_catalog = {}
          key_map = {
            'PREDEF' => 'PREFACE',
            'CHAPS' => 'CHAPTERS',
            'APPENDIX' => 'APPENDICES',
            'POSTDEF' => 'POSTFACE'
          }

          catalog.each do |key, value|
            new_key = key_map[key] || key
            # .re 拡張子を除去
            new_catalog[new_key] = strip_re_extension(value)
          end

          Build::CatalogUpdater.save_catalog(new_catalog)
          Common.log_info('  config/catalog.yml を更新しました（コメント保持）')
        end

        # .re 拡張子を再帰的に除去
        def strip_re_extension(value)
          case value
          when Array
            value.map { |v| strip_re_extension(v) }
          when Hash
            value.transform_keys { |k| k.to_s.sub(/\.re$/, '') }
                 .transform_values { |v| strip_re_extension(v) }
          when String
            value.sub(/\.re$/, '')
          else
            value
          end
        end

        # config.yml / config-starter.yml の変換
        def convert_config!
          Common.log_action('[Step 6] config.yml を変換します')

          starter_config = File.join(@starter_dir, 'config.yml')
          starter_config_starter = File.join(@starter_dir, 'config-starter.yml')

          unless File.exist?(starter_config)
            Common.log_warn("  config.yml が見つかりません: #{starter_config}")
            return
          end

          config = YAML.safe_load(File.read(starter_config), permitted_classes: [Symbol])
          config_starter = if File.exist?(starter_config_starter)
                             YAML.safe_load(File.read(starter_config_starter), permitted_classes: [Symbol])
                           else
                             {}
                           end

          updates = []
          main_title = extract_text(config['booktitle']) if config['booktitle']
          updates << [%w[book main_title], main_title] if main_title && !main_title.empty?

          subtitle = extract_text(config['subtitle']) if config['subtitle']
          updates << [%w[book subtitle], subtitle] if subtitle && !subtitle.empty?

          updates << [%w[book language], config['language']] if config['language']

          if config['bookname']
            updates << [%w[project name], config['bookname']]
            updates << [%w[project version], '0.1.0']
          end

          if config['aut']
            authors = Array(config['aut'])
            author_names = authors.map { |a| a.is_a?(Hash) ? a['name'] : a.to_s }.reject { |name| name.to_s.strip.empty? }
            updates << [%w[book author], author_names.first] if author_names.any?
          end

          if config['additional']
            config['additional'].each do |item|
              next unless item.is_a?(Hash)

              case item['key']
              when '発行者'
                value = extract_text(item['value'])
                updates << [%w[book publisher], value] if value && !value.empty?
              when '連絡先'
                contacts = Array(item['value'])
                email = contacts.find { |c| c.to_s.include?('@') }
                updates << [%w[book contact], email] if email
              end
            end
          end

          if config['history']
            history = Array(config['history']).flatten
            release = history.find { |entry| !extract_text(entry).to_s.empty? }
            release_text = extract_text(release) if release
            updates << [%w[book release], release_text] if release_text && !release_text.empty?
          end

          if config['pubevent_name']
            updates << [%w[book series], config['pubevent_name']]
          end

          if config_starter.dig('starter', 'pagesize')
            pagesize = config_starter.dig('starter', 'pagesize')
            page_use = case pagesize.to_s.upcase
                       when 'B5' then 'b5_airy'
                       when 'A5' then 'a5_compact'
                       else 'a4_standard'
                       end
            updates << [%w[page use], page_use]
          end

          if update_book_yaml_with_values(updates)
            Common.log_info('  config/book.yml を更新しました（コメント保持）')
          else
            Common.log_info('  config/book.yml に反映すべき値がありませんでした')
          end
        end

        # 複数行テキストやハッシュから文字列を抽出
        def extract_text(value)
          case value
          when Hash
            value['name'] || value.values.first
          when String
            value.gsub(/\n/, ' ').strip
          else
            value.to_s
          end
        end

        def update_book_yaml_with_values(updates)
          book_yml_path = 'config/book.yml'
          unless File.exist?(book_yml_path)
            Common.log_warn("  #{book_yml_path} が見つからなかったため、更新をスキップします")
            return false
          end

          lines = File.readlines(book_yml_path, encoding: 'utf-8')
          updated = false

          updates.each do |path, value|
            next if value.nil?

            replaced = replace_yaml_value_in_lines!(lines, path, value)
            unless replaced
              Common.log_warn("  #{book_yml_path} 内で #{path.join('.')} を更新できませんでした")
            end
            updated ||= replaced
          end

          if updated
            File.write(book_yml_path, lines.join, encoding: 'utf-8')
          end

          updated
        end

        def replace_yaml_value_in_lines!(lines, path, value)
          stack = []

          lines.each_with_index do |line, idx|
            next if line.lstrip.start_with?('#')
            match = line.match(/^(\s*)([A-Za-z0-9_]+):(.*)$/)
            next unless match

            indent = match[1].length
            key = match[2]

            while stack.any? && stack.last[:indent] >= indent
              stack.pop
            end
            stack << { key: key, indent: indent }

            next unless stack.map { |item| item[:key] } == path

            comment = match[3]&.match(/(\s+#.*)$/)&.[](1)
            scalar = format_yaml_scalar(value)
            new_line = "#{match[1]}#{key}: #{scalar}"
            new_line += comment.to_s
            new_line << "\n"
            lines[idx] = new_line
            return true
          end

          false
        end

        def format_yaml_scalar(value)
          case value
          when Numeric
            value.to_s
          when TrueClass, FalseClass
            value.to_s
          else
            str = value.to_s
            return "''" if str.empty?
            escaped = str.gsub(/["\\]/) { |m| "\\#{m}" }
            "\"#{escaped}\""
          end
        end

        def cleanup_starter_markdown_dir!
          return unless @starter_dir && @md_output_dir

          md_dir = File.join(@starter_dir, @md_output_dir)
          return unless Dir.exist?(md_dir)

          FileUtils.rm_rf(md_dir)
          Common.log_info("  #{@md_output_dir}/ を削除しました（Starter 側）")
        rescue StandardError => e
          Common.log_warn("  #{@md_output_dir}/ の削除に失敗しました: #{e.message}")
        end

        def remove_original_image_files!
          removed = 0
          Dir.glob(File.join('images', '**', '*')).each do |path|
            next unless File.file?(path)
            next unless path.match?(/\.(png|jpe?g|gif)$/i)

            FileUtils.rm_f(path)
            removed += 1
          end

          if removed.positive?
            Common.log_info("  旧画像 (png/jpg/gif) を #{removed} 個削除しました")
          else
            Common.log_info('  削除対象の旧画像はありませんでした')
          end
        end
      end
    end
  end
end
