# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module Vivlio
  module Starter
    module Commands
      module New
        module_function

        def run(name)
          name = (name || '').strip
          abort 'Error: プロジェクト名を指定してください。例: vs new mybook' if name.empty?

          dest = File.expand_path(name)
          abort "Error: '#{name}' は既に存在します。別名を指定してください。" if File.exist?(dest)

          gem_root = File.expand_path('../../../..', __dir__)
          scaffold_root       = File.join(gem_root, 'lib', 'project_scaffold')
          source_contents_dir = File.join(scaffold_root, 'contents')
          source_styles_dir   = File.join(scaffold_root, 'stylesheets')
          source_images_dir   = File.join(scaffold_root, 'images')
          source_codes_dir    = File.join(scaffold_root, 'codes')
          source_chapter_tpl  = File.join(scaffold_root, 'chapter_templates')
          source_config_book  = File.join(gem_root, 'config', 'book.yml')
          source_post_replace = File.join(gem_root, '_post_replace_list.yml')
          source_viv_config   = File.join(scaffold_root, 'vivliostyle.config.js')
          source_gemfile      = File.join(scaffold_root, 'Gemfile')

          puts "[vivlio-starter] Creating new project: #{name}"

          dirs = %w[config contents images stylesheets codes chapter_templates].map { |d| File.join(dest, d) }
          FileUtils.mkdir_p(dirs)

          # 章テンプレートをプロジェクトへコピー（執筆者用の雛形）
          if Dir.exist?(source_chapter_tpl)
            target_chapter_dir = File.join(dest, 'chapter_templates')
            FileUtils.mkdir_p(target_chapter_dir)
            Dir.children(source_chapter_tpl).each do |entry|
              src = File.join(source_chapter_tpl, entry)
              dst = File.join(target_chapter_dir, entry)
              FileUtils.cp_r(src, dst)
            end
          end

          # config/book.yml をコピー
          target_book = File.join(dest, 'config', 'book.yml')
          if File.file?(source_config_book)
            FileUtils.cp(source_config_book, target_book)
          else
            File.write(target_book,
                       "# book.yml\nbook:\n  main_title: ''\n  subtitle: ''\n  subtitle_style: wave\n  author: ''\n  language: 'ja'\n")
          end

          # _post_replace_list.yml をプロジェクト直下にコピー（置換ルール定義）
          if File.file?(source_post_replace)
            FileUtils.cp(source_post_replace, File.join(dest, '_post_replace_list.yml'))
          end

          # codes ディレクトリをコピー（存在する場合のみ）
          if Dir.exist?(source_codes_dir)
            target_codes_dir = File.join(dest, 'codes')
            FileUtils.mkdir_p(target_codes_dir)
            Dir.children(source_codes_dir).each do |entry|
              src = File.join(source_codes_dir, entry)
              dst = File.join(target_codes_dir, entry)
              FileUtils.cp_r(src, dst)
            end
          end

          # 対話形式で book.yml の主要3項目を入力（TTY の場合のみ）
          if $stdin.tty?
            begin
              cfg = begin
                YAML.load_file(target_book)
              rescue StandardError
                {}
              end
              cfg = {} unless cfg.is_a?(Hash)
              book_cfg = cfg['book'] || {}

              def self.prompt_with_default(label, current)
                print "#{label} [#{current}]: "
                input = $stdin.gets&.strip
                input.nil? || input.empty? ? current : input
              end

              puts "\n[vivlio-starter] 書籍情報を入力してください（未入力は現状の値を維持）"
              current_title = book_cfg['main_title'].to_s
              current_sub   = book_cfg['subtitle'].to_s
              current_auth  = book_cfg['author'].to_s

              new_title = prompt_with_default('書籍名（main_title）', current_title)
              new_sub   = prompt_with_default('副題（subtitle）', current_sub)
              new_auth  = prompt_with_default('著者名（author）', current_auth)

              # コメントを保持したまま、book: セクション内の対象キーだけ書き換える
              text = File.read(target_book, encoding: 'utf-8')
              lines = text.lines
              book_idx = lines.index { |l| l =~ /^\s*book:\s*$/ }
              if book_idx
                # book: 範囲の終端を探索（先頭無インデントの次キー、またはEOF）
                end_idx = lines.length
                ((book_idx + 1)...lines.length).each do |i|
                  # トップレベルキーの開始で終了（非空行かつ行頭が非スペース）
                  if lines[i] =~ /^\S/ && lines[i] !~ /^\s/ && lines[i] !~ /^\s{2}/
                    end_idx = i
                    break
                  end
                end

                keys = {
                  'main_title' => new_title,
                  'subtitle' => new_sub,
                  'author' => new_auth
                }

                present = { 'main_title' => false, 'subtitle' => false, 'author' => false }

                # 既存行の置換（末尾コメント保持）
                ((book_idx + 1)...end_idx).each do |i|
                  line = lines[i]
                  next unless line =~ /^(\s{2})(main_title|subtitle|author):\s*([^#\n]*)(\s*#.*)?$/

                  indent = ::Regexp.last_match(1)
                  key    = ::Regexp.last_match(2)
                  comment = ::Regexp.last_match(4).to_s
                  value = keys[key]
                  lines[i] = "#{indent}#{key}: '#{value}'#{comment}\n"
                  present[key] = true
                end

                # 足りないキーを、book: 直後に追記（main_title, subtitle, author 順）
                insert_pos = book_idx + 1
                %w[main_title subtitle author].each do |key|
                  next if present[key]

                  value = keys[key]
                  lines.insert(insert_pos, "  #{key}: '#{value}'\n")
                  insert_pos += 1
                end

                File.write(target_book, lines.join, encoding: 'utf-8')
                puts "[vivlio-starter] book.yml を更新しました。\n"
              else
                # フォールバック: book: が見つからない場合は追記
                File.open(target_book, 'a:utf-8') do |f|
                  f.puts
                  f.puts 'book:'
                  f.puts "  main_title: '#{new_title}'"
                  f.puts "  subtitle: '#{new_sub}'"
                  f.puts "  author: '#{new_auth}'"
                end
                puts "[vivlio-starter] book.yml に book セクションを追記しました。\n"
              end
            rescue StandardError => e
              warn "[vivlio-starter] book.yml の対話入力に失敗しました: #{e}"
            end
          end

          # 既存コンテンツのコピー
          copy_list = %w[
            02-preface.md
            11-install.md
            12-tutorial.md
            21-customize.md
            31-advance.md
            91-appendix-a.md
            92-appendix-b.md
            93-appendix-c.md
            98-postface.md
          ]
          copy_list.each do |fname|
            src = File.join(source_contents_dir, fname)
            dst = File.join(dest, 'contents', fname)
            if File.file?(src)
              FileUtils.cp(src, dst)
            else
              File.write(dst, "# #{File.basename(fname, '.md')}\n\nコンテンツをここに記述してください。\n")
            end
          end

          # README はテンプレートを使わず、普通の日本語READMEを作成（ハードコーディング）
          readme_out = File.join(dest, 'README.md')
          readme_md = <<~MD
            # #{name}

            このリポジトリは Vivlio Starter で作成された書籍プロジェクトです。執筆・プレビュー・ビルドに関する基本情報をまとめています。

            ## 概要
            - 原稿: `contents/`
            - 画像: `images/`
            - スタイル: `stylesheets/`
            - 設定: `config/`

            ## 必要条件
            - Node.js / npm（Vivliostyle CLI を使用）
            - Ruby（rakeタスク等を使用する場合）

            ## セットアップ
            ```bash
            npm install
            ```

            ## プレビュー
            ```bash
            vivliostyle preview
            ```
            ブラウザで原稿を確認できます。

            ## ビルド（PDFなどの生成）
            ```bash
            vivlio-starter build
            ```
            執筆した書籍をビルドして成果物を生成します。出力先は設定に従います。

            ## ディレクトリ構成（抜粋）
            ```
            #{name}/
              contents/      # Markdown原稿
              images/        # 画像ファイル
              stylesheets/   # 章別・共通CSS
              config/        # 書籍設定 (book.yml など)
              README.md
            ```

            ## ライセンス / 著作権
            各ファイルの先頭や `LICENSE` を参照してください。
          MD
          File.write(readme_out, readme_md, encoding: 'utf-8')

          gi = File.join(dest, '.gitignore')
          File.write(gi, <<~GITIGNORE)
            .DS_Store
            node_modules/
            *.log
            *.tmp
            *.pdf
            entries.js
          GITIGNORE

          # スタイルコピー: 共通資産 + 必要な章別CSSのみ
          if Dir.exist?(source_styles_dir)
            target_styles_dir = File.join(dest, 'stylesheets')
            # 1) ディレクトリはそのままコピー（fonts, images など）
            Dir[File.join(source_styles_dir, '*/')].each do |src_dir|
              FileUtils.cp_r(src_dir, target_styles_dir)
            end

            # 2) 非番号CSSはすべてコピー（base.css, chapter.css など）
            Dir[File.join(source_styles_dir, '*')]
              .select { |p| File.file?(p) }
              .reject { |p| File.basename(p) =~ /^\d+\.css$/ }
              .each do |css|
                FileUtils.cp(css, File.join(target_styles_dir, File.basename(css)))
              end

            # 3) 章別CSSは、生成したMDに対応するものだけコピー
            needed_chapter_css = %w[11 12 21 31]
            needed_chapter_css.each do |num|
              src = File.join(source_styles_dir, "#{num}.css")
              FileUtils.cp(src, File.join(target_styles_dir, "#{num}.css")) if File.file?(src)
            end
          end

          # 画像の初期資産があればコピーし、なければ章ごとの空ディレクトリを作成
          if Dir.exist?(source_images_dir)
            FileUtils.cp_r(Dir[File.join(source_images_dir, '*')], File.join(dest, 'images'))
          else
            image_slugs = copy_list.map { |f| File.basename(f, '.md') }
            image_slugs.each do |slug|
              dir = File.join(dest, 'images', slug)
              FileUtils.mkdir_p(dir)
            end
          end

          # ----- 自動生成: 00 / 01 / 99 -----
          cfg = begin
            YAML.load_file(target_book)
          rescue StandardError
            {}
          end

          book = cfg['book'] || {}
          full  = (book['title'] || '').to_s
          main  = (book['main_title'] || '').to_s
          sub   = (book['subtitle'] || '').to_s

          title = main.empty? ? full : main
          subtitle = sub
          if subtitle.empty? && !full.empty? && (full =~ /(.*?)[ \u3000]*[～〜](.+?)[～〜]\s*$/)
            title = ::Regexp.last_match(1).to_s.strip
            subtitle = ::Regexp.last_match(2).to_s.strip
          end
          title = title.to_s.gsub(/[ \u3000]*[～〜].*$/, '').strip

          author   = (book['author'] || '').to_s
          series   = (book['series'] || '').to_s
          release  = (book['release'] || '').to_s
          style    = (book['subtitle_style'] || 'wave').to_s.downcase
          style    = 'wave' unless %w[wave bar none].include?(style)
          subtitle_class = "subtitle subtitle--#{style}"

          # 00-titlepage.md
          titlepage = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="author"><span>[著]</span> #{author}</p>) unless author.empty?}

            #{%(<div class="publication-info">) unless series.empty? && release.empty?}
            #{%(    <p class="series">#{series}</p>) unless series.empty?}
            #{%(    <p class="release-info">#{release}</p>) unless release.empty?}
            #{%(</div>) unless series.empty? && release.empty?}
          MD
          File.write(File.join(dest, 'contents', '00-titlepage.md'), titlepage, encoding: 'utf-8')

          # 01-legalpage.md
          legal = cfg['legal'] || {}
          disclaimer = (legal['disclaimer'] || '').to_s.strip
          trademark  = (legal['trademark']  || '').to_s.strip
          if disclaimer.empty? && trademark.empty?
            disclaimer = <<~TXT.strip
              本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
              本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
            TXT
            trademark = <<~TXT.strip
              本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
              本書では ™、®、© などのマークは省略しています。
            TXT
          end
          legal_md = <<~MD
            <div class="disclaimer">
              <h2>■免責</h2>
              #{disclaimer.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
            </div>

            <div class="trademark">
              <h2>■商標</h2>
              #{trademark.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
            </div>
          MD
          File.write(File.join(dest, 'contents', '01-legalpage.md'), legal_md, encoding: 'utf-8')

          # 99-colophon.md
          publisher = (book['publisher'] || book['publisher_name'] || '').to_s
          contact   = (book['contact'] || '').to_s
          current_year = Time.now.year
          start_year = nil
          if release =~ /令和([一二三四五六七八九十百]+)年/
            kan = ::Regexp.last_match(1)
            kan_map = { '零' => 0, '一' => 1, '二' => 2, '三' => 3, '四' => 4, '五' => 5, '六' => 6, '七' => 7, '八' => 8,
                        '九' => 9 }
            to_int = lambda do |s|
              total = 0
              if s.include?('百')
                s = s.sub('百', '')
                total += 100
              end
              if s.include?('十')
                parts = s.split('十', 2)
                tens = parts[0].empty? ? 1 : kan_map[parts[0]]
                ones = parts[1].to_s.empty? ? 0 : kan_map[parts[1]]
                total += (tens.to_i * 10) + ones.to_i
              else
                total += kan_map[s].to_i
              end
              total
            end
            n = to_int.call(kan)
            start_year = 2018 + n
          elsif release =~ /(\d{4})/
            start_year = ::Regexp.last_match(1).to_i
          end
          to_kan = lambda do |n|
            km = %w[零 一 二 三 四 五 六 七 八 九]
            return '零' if n.zero?
            return km[n] if n < 10
            return '十' if n == 10

            tens = n / 10
            ones = n % 10
            s = ''
            s += "#{km[tens] unless tens == 1}十"
            s += (ones.zero? ? '' : km[ones])
            s
          end
          current_wareki = "令和#{to_kan.call(current_year - 2018)}年"
          copyright_years = if start_year && start_year != current_year && start_year >= 2019
                              start_wareki = "令和#{to_kan.call(start_year - 2018)}年"
                              "#{start_wareki} #{current_wareki}"
                            else
                              current_wareki
                            end
          colophon_md = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="publication-info">#{release}</p>) unless release.empty?}

            <dl class="info-list">
                #{%(<dt>著者</dt>\n                <dd>#{author}</dd>) unless author.empty?}
                #{%(<dt>発行者</dt>\n                <dd>#{publisher}</dd>) unless publisher.empty?}
                #{%(<dt>連絡先</dt>\n                <dd>#{contact}</dd>) unless contact.empty?}
            </dl>

            <p class="copyright">
                <small>
                    &copy; #{copyright_years} #{author.empty? ? '著者' : author} All rights reserved.
                </small>
            </p>

            <p class="powered-by">
                <small>
                    (powered by Vivlio Starter)
                </small>
            </p>
          MD
          File.write(File.join(dest, 'contents', '99-colophon.md'), colophon_md, encoding: 'utf-8')

          # Vivliostyle の設定ファイルを生成（rake vivliostyle:generate_config のショートカット: vs config）
          begin
            # `vs` は gem 同梱のコマンド。プロジェクト直下で実行して設定を生成する。
            system({ 'VIVLIO_QUIET' => '1' }, 'vs', 'config', chdir: dest)
          rescue StandardError => e
            warn "[vivlio-starter] vivliostyle 設定生成に失敗しました（スキップ）: #{e}"
          end

          # 生成に失敗した／何らかの理由で作成されなかった場合のフォールバック
          target_viv_config = File.join(dest, 'vivliostyle.config.js')
          unless File.exist?(target_viv_config)
            if File.file?(source_viv_config)
              FileUtils.cp(source_viv_config, target_viv_config)
            else
              # 最小構成の設定ファイルを書き出す
              minimal = <<~JS
                import entries from './entries.js';

                // @ts-check
                /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                const vivliostyleConfig = {
                  title: 'My Book',
                  author: '',
                  language: 'ja',
                  readingProgression: 'ltr',
                  entry: entries,
                  output: [
                    './output.pdf'
                  ]
                };

                export default vivliostyleConfig;
              JS
              File.write(target_viv_config, minimal, encoding: 'utf-8')
            end
          end

          # プロジェクト用 Gemfile が用意されている場合はコピー（任意）
          begin
            FileUtils.cp(source_gemfile, File.join(dest, 'Gemfile')) if File.file?(source_gemfile)
          rescue StandardError => e
            warn "[vivlio-starter] Gemfile のコピーに失敗しました（継続）: #{e}"
          end

          # vivliostyle.config.js の内容を book.yml にあわせて同期
          begin
            lang = (book['language'] || 'ja').to_s
            rp   = (cfg.dig('vivliostyle', 'reading_progression') || 'ltr').to_s
            outf = (cfg.dig('pdf', 'output_file') || 'output.pdf').to_s

            js = File.read(target_viv_config, encoding: 'utf-8')
            # title, author, language, readingProgression, output[0]
            js.gsub!(/(^\s*title:\s*)['"][^'"]*['"]/,        "\\1'#{title}'")
            js.gsub!(/(^\s*author:\s*)['"][^'"]*['"]/,       "\\1'#{author}'")
            js.gsub!(/(^\s*language:\s*)['"][^'"]*['"]/,     "\\1'#{lang}'")
            js.gsub!(/(^\s*readingProgression:\s*)['"][^'"]*['"]/, "\\1'#{rp}'")
            js.gsub!(%r{(^\s*['"]\./output\.pdf['"])|(^\s*['"][^'"]*\.pdf['"])}, "'./#{outf}'")

            # output: [ './file.pdf' ] の形式に限定して安全に置換
            js.gsub!(/(^\s*output:\s*\[\s*)['"][^'"]*\.pdf['"](\s*\])/m, "\\1'./#{outf}'\\2")

            File.write(target_viv_config, js, encoding: 'utf-8')
          rescue StandardError => e
            warn "[vivlio-starter] vivliostyle.config.js の同期に失敗しました（継続）: #{e}"
          end

          puts "[vivlio-starter] 完了しました。cd #{name} で移動し、執筆を開始できます。"
          puts '例: vivlio-starter build で執筆した書籍をPDFで作成できます。'
          0
        end
      end
    end
  end
end