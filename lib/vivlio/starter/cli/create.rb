# frozen_string_literal: true

require 'fileutils'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: create（章の作成ユーティリティ）
      # ------------------------------------------------
      # - 目的: 新規章ファイルの作成と画像ディレクトリ生成
      # - 提供コマンド: create, create:titlepage, create:colophon
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module CreateCommands
        module_function

        CREATE_DESC = {
          create: {
            short: '新しい章を作成します (Thor)',
            long: <<~DESC
              新しい章ファイルを作成し、画像ディレクトリを用意します。

              例:
                vs create 11-install
                vs create 11-install 12-tutorial

              備考:
                ・拡張子 .md は省略可能です（自動付与）
                ・既存ファイルがある場合は作成を中止します
            DESC
          },
          titlepage: {
            short: 'タイトルページを config/book.yml から生成 (Thor)'
          },
          colophon: {
            short: '奥付を config/book.yml から生成 (Thor)'
          },
          legalpage: {
            short: 'リーガルページを config/book.yml から生成 (Thor)',
            long: <<~DESC
              著作権ページや免責事項を含むリーガルページを生成します。

              config/book.yml の legal セクションから設定を読み取り、
              contents/_legalpage.md を生成します。

              設定項目:
              - legal.disclaimer: 免責事項
              - legal.trademark: 商標情報

              未設定の場合はテンプレート文面を使用します。

              オプション:
                -f, --force    既存ファイルを強制上書き
                -v, --verbose  詳細な処理情報を表示
            DESC
          }
        }.freeze

        # Thor CLI に create 系コマンドをまとめて登録する
        def included(base)
          base.class_eval do
            desc 'create NAME [NAME ...]', CREATE_DESC[:create][:short]
            long_desc CREATE_DESC[:create][:long]
            # ================================================================
            # Command: create（章の作成）
            # ------------------------------------------------
            # - 概要: 指定した章スラッグから Markdown を生成し、画像ディレクトリを準備
            # - 入力: NAME（拡張子 .md は省略可）を1つ以上
            # - 出力: contents/<NAME>.md, images/<NAME>/
            # ================================================================
            def create(*names)
              CreateCommands.execute_create(self, names)
            end

            desc 'create:titlepage', CREATE_DESC[:titlepage][:short]
            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'
            # Command: create:titlepage（タイトルページ生成）
            def create_titlepage
              CreateCommands.execute_titlepage(self)
            end

            desc 'create:colophon', CREATE_DESC[:colophon][:short]
            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'
            # Command: create:colophon（奥付生成）
            def create_colophon
              CreateCommands.execute_colophon(self)
            end

            desc 'create:legalpage', CREATE_DESC[:legalpage][:short]
            long_desc CREATE_DESC[:legalpage][:long]
            method_option :force, type: :boolean, aliases: '-f', desc: '既存ファイルを強制上書き'
            # Command: create:legalpage（リーガルページ生成）
            def create_legalpage
              CreateCommands.execute_legalpage(self)
            end

            map 'create:titlepage' => :create_titlepage
            map 'create:colophon'  => :create_colophon
            map 'create:legalpage' => :create_legalpage
          end
        end

        # ==================== Command Implementations ====================

        # create コマンドの実処理エントリーポイント
        def execute_create(command, names)
          enable_verbose(command)
          ensure_names_present!(names)

          errors = false
          Common.normalize_tokens(names).uniq.each do |name|
            unless (fname = ensure_filename(name))
              Common.log_error("エラー: 無効なファイル名です: #{name}")
              errors = true
              next
            end

            create_single_chapter(fname)
          rescue StandardError => e
            errors = true
            Common.log_error("作成に失敗しました: #{fname} (#{e.class}: #{e.message})")
          end

          exit 1 if errors
        end
        module_function :execute_create

        # create:titlepage コマンドの実処理を担う
        def execute_titlepage(command)
          enable_verbose(command)
          title, subtitle = extract_title_and_subtitle
          author  = fetch_config_value('book', 'author')
          series  = fetch_config_value('book', 'series')
          release = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"

          content = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="author"><span>[著]</span> #{author}</p>) unless author.empty?}

            #{%(<div class="publication-info">) unless series.empty? && release.empty?}
            #{%(    <p class="series">#{series}</p>) unless series.empty?}
            #{%(    <p class="release-info">#{release}</p>) unless release.empty?}
            #{%(</div>) unless series.empty? && release.empty?}
          MD

          path = File.join(Common::CONTENTS_DIR, '_titlepage.md')
          return skip_existing(path) if File.exist?(path) && !forced?(command)

          safe_write(path, content)
        end
        module_function :execute_titlepage

        # create:colophon コマンドの実処理を担う
        def execute_colophon(command)
          enable_verbose(command)
          title, subtitle = extract_title_and_subtitle
          author    = fetch_config_value('book', 'author')
          publisher = fetch_config_value('book', 'publisher')
          publisher = fetch_config_value('book', 'publisher_name') if publisher.empty?
          contact   = fetch_config_value('book', 'contact')
          release   = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"
          current_wareki = "令和#{kanji_year(Time.now.year - 2018)}年"

          content = <<~MD
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
                    &copy; #{current_wareki} #{author.empty? ? '著者' : author} All rights reserved.
                </small>
            </p>

            <p class="powered-by">
                <small>
                    (powered by Vivlio Starter)
                </small>
            </p>
          MD

          path = File.join(Common::CONTENTS_DIR, '_colophon.md')
          return skip_existing(path) if File.exist?(path) && !forced?(command)

          safe_write(path, content)
        end
        module_function :execute_colophon

        # create:legalpage コマンドの実処理を担う
        def execute_legalpage(command)
          enable_verbose(command)
          FileUtils.mkdir_p(Common::CONTENTS_DIR)
          target = File.join(Common::CONTENTS_DIR, '_legalpage.md')
          return skip_existing(target) if File.exist?(target) && !forced?(command)

          disclaimer, trademark = legal_texts
          body = <<~MD
            <h1 style="display: none;">本書について</h1>
            <div class="disclaimer">
              <h2>■免責</h2>
              #{disclaimer.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>

            <div class="trademark">
              <h2>■商標</h2>
              #{trademark.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>
          MD

          safe_write(target, body)
          Common.log_success("生成しました: #{target}")
        end
        module_function :execute_legalpage

        # =========================== Helpers =============================

        # --verbose 指定時に詳細ログを有効化する
        def enable_verbose(command)
          ENV['VERBOSE'] = '1' if options_of(command)[:verbose]
        end

        # create コマンド引数の存在を確認する
        def ensure_names_present?(names)
          !names.nil? && !names.empty?
        end

        # 引数未指定時にエラー終了させる
        def ensure_names_present!(names)
          return if ensure_names_present?(names)

          warn '使い方: vs create NAME [NAME ...]'
          exit 1
        end

        # 単一章の Markdown と画像ディレクトリを生成する
        def create_single_chapter(fname)
          title   = generate_title(fname)
          content = generate_content_from_template(title)
          path    = create_markdown_file(fname, content)
          create_image_directory(fname, {})

          # catalog.yml に追加
          basename = File.basename(fname, '.md')
          Build::CatalogUpdater.add_chapter(basename)

          Common.log_success("#{path} を作成しました")
        end

        # 入力値を正規化し、有効な章ファイル名を返す
        def ensure_filename(name)
          return nil if name.nil?

          n = name.to_s.strip
          n = File.basename(n)
          n = File.basename(n, '.md')
          return nil unless n =~ /\A\d+-[\w.-]+\z/

          "#{n}.md"
        rescue StandardError
          nil
        end

        # ファイル名から章タイトル文字列を生成する
        def generate_title(filename)
          base = File.basename(filename.to_s, '.md')
          slug = base.sub(/^-?\d+-/, '')
          slug.split(/[-_]/).map { |word| titleize_word(word) }.join(' ')
        end

        # 単語の先頭を大文字化する
        def titleize_word(word)
          return word if word.strip.empty?

          word[0].upcase + word[1..]
        end

        # 章テンプレートを読み込み、既定文面を生成する
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

        # Markdown ファイルを生成し、パスを返す
        def create_markdown_file(fname, content)
          path = File.join(Common::CONTENTS_DIR, fname)
          raise "既に存在します: #{path}" if File.exist?(path)

          safe_write(path, content)
          path
        end

        # 章ごとの画像ディレクトリを生成する
        def create_image_directory(fname, _options = {})
          base = File.basename(fname.to_s, '.md')
          dir  = File.join(Common::IMAGES_DIR, base)
          FileUtils.mkdir_p(dir)
          dir
        end

        # ディレクトリを作成してからファイルに書き込む
        def safe_write(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: 'utf-8')
        end

        # 設定からタイトルとサブタイトルを取得する
        def extract_title_and_subtitle
          book = Common::CONFIG.fetch('book', {})
          title = (book['main_title'] || book['title'] || '').to_s
          subtitle = (book['subtitle'] || '').to_s
          [title, subtitle]
        end

        # サブタイトル装飾スタイルを取得する
        def subtitle_style
          style = fetch_config_value('book', 'subtitle_style').downcase
          %w[wave bar none].include?(style) ? style : 'wave'
        end

        # CONFIG から値を取り出し文字列化する
        def fetch_config_value(section, key)
          value = Common::CONFIG.dig(section, key)
          value ? value.to_s : ''
        end

        # 既存ファイルを検知した場合にスキップログを出す
        def skip_existing(path)
          Common.log_warn("既に存在するためスキップします: #{path} (--force で上書き)")
        end

        # --force 指定の有無を返す
        def forced?(command)
          options_of(command)[:force]
        end

        # Thor コマンドから options を取り出す
        def options_of(command)
          command.respond_to?(:options) ? (command.options || {}) : {}
        end

        # 西暦から簡易的な漢数字表記の年を生成する
        def kanji_year(num)
          km = %w[〇 一 二 三 四 五 六 七 八 九]
          return '〇' if num <= 0
          return km[num] if num < 10
          return '十' if num == 10

          tens = num / 10
          ones = num % 10
          result = ''
          result += "#{km[tens] unless tens == 1}十"
          result += km[ones] unless ones.zero?
          result
        end

        # config から免責・商標文面を取得し、未設定ならテンプレートを返す
        def legal_texts
          legal = Common::CONFIG.fetch('legal', {})
          disclaimer = (legal['disclaimer'] || '').strip
          trademark  = (legal['trademark']  || '').strip

          if disclaimer.empty? && trademark.empty?
            Common.log_warn('config/book.yml の legal.disclaimer / legal.trademark が未設定です。テンプレート文面で生成します。')
            disclaimer = DEFAULT_DISCLAIMER
            trademark  = DEFAULT_TRADEMARK
          end

          [disclaimer, trademark]
        end

        DEFAULT_DISCLAIMER = <<~TXT.strip
          本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
          本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
        TXT

        DEFAULT_TRADEMARK = <<~TXT.strip
          本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
          本書では ™、®、© などのマークは省略しています。
        TXT
      end
    end
  end
end
