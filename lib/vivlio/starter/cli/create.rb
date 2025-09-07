# frozen_string_literal: true
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: create（章の作成ユーティリティ）
      # ------------------------------------------------
      # - 目的: 新規章ファイルの作成、画像ディレクトリ生成、章別CSSの生成
      # - 提供コマンド: create, create:titlepage, create:colophon
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module CreateCommands
        extend self
        def included(base)
          base.class_eval do
            # create（章の作成）
            desc 'create NAME [NAME ...]', '新しい章を作成します (Thor)'
            long_desc <<~DESC
              新しい章ファイルを作成し、画像ディレクトリを用意し、章別 CSS（該当時）を生成します。

              例:
                vs create 11-install
                vs create 11-install 12-tutorial

              備考:
                ・拡張子 .md は省略可能です（自動付与）
                ・既存ファイルがある場合は作成を中止します
            DESC
            # ================================================================
            # Command: create（章の作成）
            # ------------------------------------------------
            # - 概要: 指定した章スラッグから Markdown を生成し、関連ディレクトリ/ファイルを準備
            # - 入力: NAME（拡張子 .md は省略可）を1つ以上
            # - 出力: contents/<NAME>.md, images/<NAME>/, stylesheets/<NN>.css（章番号時）
            # ================================================================

            def create(*names)
              ENV['VERBOSE'] = '1' if options[:verbose]
              if names.nil? || names.empty?
                warn '使い方: vs create NAME [NAME ...]'
                exit 1
              end

              # 共通正規化（contents/ と .md を剥がす）+ 重複排除
              names = Common.normalize_tokens(names).uniq

              had_error = false
              names.each do |name|
                fname = ensure_filename(name)
                unless fname
                  Common.log_error("エラー: 無効なファイル名です: #{name}")
                  had_error = true
                  next
                end

                begin
                  title   = generate_title(fname)
                  content = generate_content_from_template(title)
                  path    = create_markdown_file(fname, content)
                  create_image_directory(fname, {})
                  create_css_file_if_chapter(fname)
                  Common.log_success("#{path} を作成しました")
                rescue => e
                  had_error = true
                  Common.log_error("作成に失敗しました: #{fname} (#{e.class}: #{e.message})")
                end
              end

              exit 1 if had_error
            end

            # create:titlepage
            desc 'create:titlepage', 'タイトルページを config/book.yml から生成 (Thor)'
            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'
            # ================================================================
            # Command: create:titlepage（タイトルページ生成）
            # ------------------------------------------------
            # - 概要: config から 00-titlepage.md を生成
            # - 入力: config.yml / book.yml（book.main_title, subtitle, author 等）
            # - 出力: contents/00-titlepage.md
            # ================================================================
            def create_titlepage
              ENV['VERBOSE'] = '1' if options[:verbose]
              cfg = Common::CONFIG
              title, subtitle = extract_title_and_subtitle(cfg)
              author   = (cfg.dig('book', 'author') || '').to_s
              series   = (cfg.dig('book', 'series') || '').to_s
              contact  = (cfg.dig('book', 'contact') || '').to_s
              release  = (cfg.dig('book', 'release') || '').to_s
              style = (cfg.dig('book', 'subtitle_style') || 'wave').to_s.downcase
              style = 'wave' unless %w[wave bar none].include?(style)
              subtitle_class = "subtitle subtitle--#{style}"

              content = <<~MD
                <h1 class="book-title">#{title}</h1>
                #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

                #{author.empty? ? '' : %Q(<p class="author"><span>[著]</span> #{author}</p>)}

                #{(series.empty? && release.empty?) ? '' : %Q(<div class="publication-info">)}
                #{series.empty? ? '' : %Q(    <p class="series">#{series}</p>)}
                #{release.empty? ? '' : %Q(    <p class="release-info">#{release}</p>)}
                #{(series.empty? && release.empty?) ? '' : %Q(</div>)}
              MD

              out = File.join(Common::CONTENTS_DIR, '00-titlepage.md')
              if File.exist?(out) && !options[:force]
                Common.log_warn("既に存在するためスキップします: #{out} (--force で上書き)")
                return
              end
              safe_write(out, content)
            end

            # create:colophon
            desc 'create:colophon', '奥付を config/book.yml から生成 (Thor)'
            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'
            # ================================================================
            # Command: create:colophon（奥付生成）
            # ------------------------------------------------
            # - 概要: config から 99-colophon.md を生成
            # - 入力: config.yml / book.yml（author, publisher, contact, release 等）
            # - 出力: contents/99-colophon.md
            # ================================================================
            def create_colophon
              ENV['VERBOSE'] = '1' if options[:verbose]
              cfg = Common::CONFIG
              title, subtitle = extract_title_and_subtitle(cfg)
              author    = (cfg.dig('book', 'author') || '').to_s
              publisher = (cfg.dig('book', 'publisher') || cfg.dig('book', 'publisher_name') || '').to_s
              contact   = (cfg.dig('book', 'contact') || '').to_s
              release   = (cfg.dig('book', 'release') || '').to_s
              style = (cfg.dig('book', 'subtitle_style') || 'wave').to_s.downcase
              style = 'wave' unless %w[wave bar none].include?(style)
              subtitle_class = "subtitle subtitle--#{style}"

              to_kan = lambda do |n|
                km = %w(〇 一 二 三 四 五 六 七 八 九)
                return '〇' if n == 0
                return km[n] if n < 10
                return '十' if n == 10
                tens = n / 10
                ones = n % 10
                s = ''
                s += (tens == 1 ? '' : km[tens]) + '十'
                s += (ones == 0 ? '' : km[ones])
                s
              end

              current_year = Time.now.year
              current_wareki = "令和#{to_kan.call(current_year - 2018)}年"

              content = <<~MD
                <h1 class="book-title">#{title}</h1>
                #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

                #{release.empty? ? '' : %Q(<p class="publication-info">#{release}</p>)}

                <dl class="info-list">
                    #{author.empty? ? '' : %Q(<dt>著者</dt>\n                    <dd>#{author}</dd>)}
                    #{publisher.empty? ? '' : %Q(<dt>発行者</dt>\n                    <dd>#{publisher}</dd>)}
                    #{contact.empty? ? '' : %Q(<dt>連絡先</dt>\n                    <dd>#{contact}</dd>)}
                </dl>

                <p class="copyright">
                    <small>
                        &copy; #{current_wareki} #{author.empty? ? '著者' : author} All rights reserved.
                    </small>
                </p>

                <p class="powered-by">
                    <small>
                        (powered by Vivlio Starter)
                    </small>
                </p>
              MD

              out = File.join(Common::CONTENTS_DIR, '99-colophon.md')
              if File.exist?(out) && !options[:force]
                Common.log_warn("既に存在するためスキップします: #{out} (--force で上書き)")
                return
              end
              safe_write(out, content)
            end

            # create.rb 専用ヘルパー（no_commands）
            no_commands do
              # '11-install' / '11-install.md' を検証し '11-install.md' を返す
              def ensure_filename(name)
                return nil if name.nil?
                n = name.to_s.strip
                n = File.basename(n)
                n = File.basename(n, '.md')
                return nil unless n =~ /\A\d+-[\w\.-]+\z/
                n + '.md'
              rescue
                nil
              end

              # 章タイトル生成（"11-install.md" -> "Install"）
              def generate_title(filename)
                base = File.basename(filename.to_s, '.md')
                slug = base.sub(/^-?\d+-/, '')
                slug.split(/[-_]/).map { |w| w.strip.empty? ? w : w[0].upcase + w[1..] }.join(' ')
              end

              # テンプレート読み込み（なければデフォルト骨子）
              def generate_content_from_template(title)
                tpl = File.join(Common::CHAPTER_TEMPLATES_DIR, 'chapter_template.md')
                if File.exist?(tpl)
                  File.read(tpl, encoding: 'utf-8').gsub('{{TITLE}}', title.to_s)
                else
                  <<~MD
                    # #{title}

                    <!-- 章テンプレートが見つからなかったため、デフォルトの骨子を生成しました -->
                    
                    ここに#{title}の内容を記述してください。
                  MD
                end
              end

              # Markdown ファイル作成（既存なら例外）
              def create_markdown_file(fname, content)
                path = File.join(Common::CONTENTS_DIR, fname)
                raise "既に存在します: #{path}" if File.exist?(path)
                safe_write(path, content)
                path
              end

              # 画像ディレクトリ作成（images/<basename>）
              def create_image_directory(fname, _options = {})
                base = File.basename(fname.to_s, '.md')
                dir  = File.join(Common::IMAGES_DIR, base)
                FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
                dir
              end

              # 章番号(11..89)のみ CSS を stylesheets/<NN>.css に生成
              def create_css_file_if_chapter(fname)
                num = Common.get_chapter_number(File.basename(fname.to_s))
                return nil unless num && num.to_i.between?(11, 89)
                css = File.join(Common::STYLESHEETS_DIR, format('%02d.css', num.to_i))
                return css if File.exist?(css)
                content = <<~CSS
                  /* 第#{num.to_i - 10}章用スタイル */
                  @page {
                    /* 章開始ページ番号（必要に応じて変更） */
                    counter-reset: chapter-counter #{num.to_i - 10};
                  }
                CSS
                safe_write(css, content)
                css
              end

              # 安全書き込み
              def safe_write(path, content)
                FileUtils.mkdir_p(File.dirname(path))
                File.write(path, content, encoding: 'utf-8')
                true
              end

              # config/book.yml から title/subtitle を抽出
              # title は main_title を優先し、無ければ title をフォールバック
              def extract_title_and_subtitle(cfg)
                book = cfg['book'] || {}
                title = (book['main_title'] || book['title'] || '').to_s
                subtitle = (book['subtitle'] || '').to_s
                [title, subtitle]
              end
            end

            # create:legalpage
            desc 'create:legalpage', 'リーガルページを config/book.yml から生成 (Thor)'
            long_desc <<~DESC
              著作権ページや免責事項を含むリーガルページを生成します。

              config/book.yml の legal セクションから設定を読み取り、
              contents/01-legalpage.md を生成します。

              設定項目:
              - legal.disclaimer: 免責事項
              - legal.trademark: 商標情報

              未設定の場合はテンプレート文面を使用します。

              オプション:
                -f, --force    既存ファイルを強制上書き
                -v, --verbose  詳細な処理情報を表示
            DESC

            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'

            # ================================================================
            # Command: create:legalpage（リーガルページ生成）
            # ------------------------------------------------
            # 概要:
            #   config/book.yml の legal セクションから免責・商標情報を読み取り、
            #   `contents/01-legalpage.md` を生成する。
            #
            # オプション:
            #   -f, --force     既存ファイルがある場合でも上書き
            #   -v, --verbose   詳細ログ（ENV['VERBOSE']=1）
            #
            # 備考:
            #   - 設定未記入時はテンプレート文面で生成。
            # ================================================================
            def create_legalpage
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              contents_dir = Common::CONTENTS_DIR
              FileUtils.mkdir_p(contents_dir)

              target = File.join(contents_dir, '01-legalpage.md')
              if File.exist?(target) && !options[:force]
                Common.log_warn("既に存在するためスキップします: #{target} (--force で上書き)")
                return
              end

              cfg = Common::CONFIG || {}
              legal = (cfg['legal'] || {})
              disclaimer = (legal['disclaimer'] || '').strip
              trademark  = (legal['trademark'] || '').strip

              if disclaimer.empty? && trademark.empty?
                Common.log_warn('config/book.yml の legal.disclaimer / legal.trademark が未設定です。テンプレート文面で生成します。')
                disclaimer = <<~TXT.strip
                  本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
                  本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
                TXT
                trademark = <<~TXT.strip
                  本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
                  本書では ™、®、© などのマークは省略しています。
                TXT
              end

              # Markdown 本文（見出しは本文側で与える。フロントマターは pre_process で自動付与）
              body = <<~MD
                <div class="disclaimer">
                  <h2>■免責</h2>
                  #{disclaimer.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
                </div>

                <div class="trademark">
                  <h2>■商標</h2>
                  #{trademark.split(/\r?\n/).map { |l| "  <p>#{l}</p>" }.join("\n")}
                </div>
              MD

              safe_write(target, body)
              Common.log_success("生成しました: #{target}")
            end

            # コロン区切りをメソッドへマップ
            map 'create:titlepage' => :create_titlepage
            map 'create:colophon'  => :create_colophon
            map 'create:legalpage' => :create_legalpage
          end
        end
      end
    end
  end
end
