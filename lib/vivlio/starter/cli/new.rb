# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: NewCommands
      # ------------------------------------------------------------------------------
      # 新規書籍プロジェクトの雛形を作成するコマンド群。
      # ディレクトリ構成の作成、テンプレートのコピー、初期 Markdown 生成、
      # README/Gemfile/.gitignore の配置を行う。
      # ==============================================================================
      module NewCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'new NAME', '新しい書籍プロジェクトを作成します'
            long_desc <<~DESC
              新しい書籍プロジェクトを作成します。

              引数:
                NAME    プロジェクト名（必須）

              作成内容:
              - プロジェクトディレクトリの作成
              - 設定ファイル(config/book.yml)のコピー
              - コンテンツファイルのテンプレートコピー
              - スタイルシート・画像・コードのコピー
              - タイトルページ・リーガルページ・奥付の自動生成
              - README・Gemfile・.gitignoreの作成

              使用例:
                vs new mybook
            DESC

            # ================================================================
            # Command: new（新規プロジェクト作成）
            # ------------------------------------------------
            # 概要:
            #   NAME で指定したディレクトリ配下に、Vivlio Starter の標準構成を生成。
            #   設定・テンプレート・初期コンテンツ・スタイル・画像・コードを展開し、
            #   タイトル/リーガル/奥付ページの Markdown を自動生成する。
            #
            # 引数:
            #   name    プロジェクト名（必須）
            # ================================================================
            method_option :auto_install, type: :boolean, default: true, desc: '必要ツールを自動インストール (macOS Homebrew)'
            method_option :interactive, type: :boolean, default: false, desc: '対話的に確認しながら実行'
            method_option :manual_install, type: :boolean, default: false, desc: 'doctor の自動実行を無効化'
            def new(name)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              name = name&.strip
              if name.nil? || name.empty?
                Common.log_error("Error: プロジェクト名を指定してください。例: vs new mybook")
                exit(1)
              end

              dest = File.expand_path(name)
              if File.exist?(dest)
                Common.log_error("Error: '#{name}' は既に存在します。別名を指定してください。")
                exit(1)
              end

              # gem ルートとテンプレートの場所
              gem_root = File.expand_path('..', __dir__) # rakelib/ の一つ上が gem ルート
              scaffold_root       = File.join(gem_root, 'lib', 'project_scaffold')
              source_contents_dir = File.join(scaffold_root, 'contents')
              source_styles_dir   = File.join(scaffold_root, 'stylesheets')
              source_images_dir   = File.join(scaffold_root, 'images')
              source_codes_dir    = File.join(scaffold_root, 'codes')
              source_chapter_tpl  = File.join(scaffold_root, 'chapter_templates')
              source_readme_tpl   = File.join(scaffold_root, 'README.md')
              source_config_book  = File.join(gem_root, 'config', 'book.yml')
              source_gemfile      = File.join(scaffold_root, 'Gemfile')
              source_ci_workflow  = File.join(scaffold_root, '.github', 'workflows', 'build.yml')

              Common.log_action("[vivlio-starter] Creating new project: #{name}")

              # ディレクトリ構成
              dirs = %w[
                config
                contents
                images
                stylesheets
                codes
                chapter_templates
              ].map { |d| File.join(dest, d) }
              FileUtils.mkdir_p(dirs)

              # 設定ファイル: config/book.yml を複製（ユーザー記述の元になる）
              target_book = File.join(dest, 'config', 'book.yml')
              if File.file?(source_config_book)
                FileUtils.cp(source_config_book, target_book)
              else
                File.write(target_book, "# book.yml\nbook:\n  main_title: ''\n  subtitle: ''\n  subtitle_style: wave\n  author: ''\n  language: 'ja'\n")
              end

              # 既存コンテンツのコピー: 指定されたファイル群
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

              # README テンプレート（任意）
              readme_out = File.join(dest, 'README.md')
              if File.file?(source_readme_tpl)
                content = File.read(source_readme_tpl)
                content = content.gsub(/\{\{\s*PROJECT_NAME\s*\}\}/, name)
                File.write(readme_out, content)
              else
                File.write(readme_out, "# #{name}\n\nThis book was bootstrapped by vivlio-starter.\n")
              end

              # Gemfile（任意）
              if File.file?(source_gemfile)
                FileUtils.cp(source_gemfile, File.join(dest, 'Gemfile'))
              end

              # 最小の .gitignore（生成物は追跡しない推奨）
              gi = File.join(dest, '.gitignore')
              File.write(gi, <<~GITIGNORE)
              .DS_Store
              node_modules/
              *.log
              *.tmp
              *.pdf
              entries.js
              GITIGNORE

              # GitHub Actions ワークフロー（任意だが有用）
              if File.file?(source_ci_workflow)
                ci_dir = File.join(dest, '.github', 'workflows')
                FileUtils.mkdir_p(ci_dir)
                FileUtils.cp(source_ci_workflow, File.join(ci_dir, 'build.yml'))
              end

              # スタイル一式コピー（章個別CSSは後で自動生成されることがあります）
              if Dir.exist?(source_styles_dir)
                FileUtils.cp_r(Dir[File.join(source_styles_dir, '*')], File.join(dest, 'stylesheets'))
              end

              # 章テンプレートのコピー
              if Dir.exist?(source_chapter_tpl)
                FileUtils.cp_r(Dir[File.join(source_chapter_tpl, '*')], File.join(dest, 'chapter_templates'))
              end

              # codes ディレクトリのコピー
              if Dir.exist?(source_codes_dir)
                FileUtils.cp_r(Dir[File.join(source_codes_dir, '*')], File.join(dest, 'codes'))
              end

              # 画像ディレクトリの自動生成（02-preface 〜 98-postface 相当の各ファイルに対応）
              if Dir.exist?(source_images_dir)
                FileUtils.cp_r(Dir[File.join(source_images_dir, '*')], File.join(dest, 'images'))
              else
                image_slugs = copy_list.map { |f| File.basename(f, '.md') }
                image_slugs.each do |slug|
                  dir = File.join(dest, 'images', slug)
                  FileUtils.mkdir_p(dir)
                end
              end

              # ----- 自動生成系: titlepage / legalpage / colophon -----
              # newプロジェクトの book.yml を読み込み、同等ロジックで生成
              cfg = begin
                YAML.load_file(target_book)
              rescue
                {}
              end

              book = (cfg['book'] || {})
              full  = (book['title'] || '').to_s
              main  = (book['main_title'] || '').to_s
              sub   = (book['subtitle'] || '').to_s

              title = main.empty? ? full : main
              subtitle = sub
              if subtitle.empty? && !full.empty?
                if full =~ /(.*?)[ \u3000]*[～〜](.+?)[～〜]\s*$/
                  title = $1.to_s.strip
                  subtitle = $2.to_s.strip
                end
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
              #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

              #{author.empty? ? '' : %Q(<p class="author"><span>[著]</span> #{author}</p>)}

              #{(series.empty? && release.empty?) ? '' : %Q(<div class="publication-info">)}
              #{series.empty? ? '' : %Q(    <p class="series">#{series}</p>)}
              #{release.empty? ? '' : %Q(    <p class="release-info">#{release}</p>)}
              #{(series.empty? && release.empty?) ? '' : %Q(</div>)}
              MD
              File.write(File.join(dest, 'contents', '00-titlepage.md'), titlepage, encoding: 'utf-8')

              # 01-legalpage.md
              legal = (cfg['legal'] || {})
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
                kan = $1
                kan_map = { '零'=>0, '一'=>1, '二'=>2, '三'=>3, '四'=>4, '五'=>5, '六'=>6, '七'=>7, '八'=>8, '九'=>9 }
                to_int = lambda do |s|
                  total = 0
                  if s.include?('百')
                    s = s.sub('百','')
                    total += 100
                  end
                  if s.include?('十')
                    parts = s.split('十', 2)
                    tens = parts[0].empty? ? 1 : kan_map[parts[0]]
                    ones = parts[1].to_s.empty? ? 0 : kan_map[parts[1]]
                    total += tens.to_i * 10 + ones.to_i
                  else
                    total += kan_map[s].to_i
                  end
                  total
                end
                n = to_int.call(kan)
                start_year = 2018 + n
              elsif release =~ /(\d{4})/
                start_year = $1.to_i
              end
              to_kan = lambda do |n|
                km = %w(零 一 二 三 四 五 六 七 八 九)
                return '零' if n == 0
                return km[n] if n < 10
                return '十' if n == 10
                tens = n / 10
                ones = n % 10
                s = ''
                s += (tens == 1 ? '' : km[tens]) + '十'
                s += (ones == 0 ? '' : km[ones])
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
              #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

              #{release.empty? ? '' : %Q(<p class="publication-info">#{release}</p>)}

              <dl class="info-list">
                  #{author.empty? ? '' : %Q(<dt>著者</dt>\n        <dd>#{author}</dd>)}
                  #{publisher.empty? ? '' : %Q(<dt>発行者</dt>\n        <dd>#{publisher}</dd>)}
                  #{contact.empty? ? '' : %Q(<dt>連絡先</dt>\n        <dd>#{contact}</dd>)}
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

              Common.log_success("[vivlio-starter] Done. cd #{name} で移動し、執筆を開始できます。")
              Common.log_info("例: vivliostyle preview などのコマンドを実行")

              # ---- 仕上げ: 依存診断の案内/実行（A+B 同時対応）
              begin
                Dir.chdir(dest) do
                  if options[:manual_install]
                    Common.echo_always('doctor の自動実行をスキップします (--manual-install)')
                  elsif options[:auto_install]
                    Common.echo_always('必要ツールの自動インストールを有効にして doctor を実行します (--auto-install)')
                    args = ['doctor', '--fix']
                    args << '--yes' unless options[:interactive]
                    Vivlio::Starter::ThorCLI.start(args)
                  else
                    proceed = false
                    if $stdin.tty?
                      $stdout.print("qpdf / pdfinfo の診断を実行しますか？ [y/N]: ")
                      ans = $stdin.gets
                      proceed = ans && ans.strip.downcase == 'y'
                    end
                    if proceed
                      Vivlio::Starter::ThorCLI.start(['doctor'])
                    else
                      Common.echo_always('後で実行する場合: vs doctor もしくは vs doctor --fix (macOS)')
                    end
                  end
                end
              rescue => e
                Common.log_warn("doctor 実行フローでエラーが発生しました: #{e}")
              end
            end
          end
        end
      end
    end
  end
end
