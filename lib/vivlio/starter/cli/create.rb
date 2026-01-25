# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/create.rb
# ================================================================
# 責務:
#   書籍プロジェクトにおける章ファイル・特殊ページの生成を担当する。
#
# 提供機能:
#   - execute_create: 章 Markdown と画像ディレクトリを生成
#   - execute_titlepage: タイトルページを config/book.yml から生成
#   - execute_colophon: 奥付を config/book.yml から生成
#   - execute_legalpage: 免責・商標ページを config/book.yml から生成
#
# 生成規約:
#   - 章ファイル名は「数字-スラッグ.md」形式（例: 11-install.md）
#   - 画像は章ごとのサブディレクトリに配置（Vivliostyle の相対パス解決のため）
#   - 生成した章は config/catalog.yml に自動追記される
#
# 依存:
#   - Common: 設定読み込み・ログ出力・パス定数
#   - Build::CatalogUpdater: catalog.yml への章追記
#   - config/book.yml: タイトル・著者情報などのメタデータ
# ================================================================

require 'fileutils'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'token_resolver'

module Vivlio
  module Starter
    module CLI
      # 章ファイル・特殊ページ生成ロジック
      #
      # Samovar CLI コマンドから呼び出される実行メソッド群。
      # 各メソッドは純粋な Hash オプションを受け取る。
      module CreateCommands
        module_function

        # --- 章ファイル生成 ---

        # 章ファイルと画像ディレクトリを一括生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        # @param names [Array<String>] 生成する章名のリスト
        #   - 形式: "XX-slug" または "XX-slug.md"（XX は並び順を示す数字）
        #   - 例: ['11-install', '12-tutorial']
        # @return [void]
        # @raise [SystemExit] 1つ以上の章生成に失敗した場合
        def execute_create(options, names)
          apply_verbose(options)
          ensure_names_present!(names)

          resolver = TokenResolver::Resolver.new
          entries = resolver.resolve(names)

          # 1. 不正な形式をチェック
          invalid_entries = entries.reject(&:valid?)
          if invalid_entries.any?
            Common.log_error("エラー: 不正な形式が含まれています: #{invalid_entries.map(&:slug).join(', ')}")
            exit 1
          end

          # 2. カタログとの重複をチェック
          duplicate_entries = entries.select(&:in_catalog?)
          if duplicate_entries.any?
            Common.log_error("エラー: 以下の章は既にカタログに存在します:")
            duplicate_entries.each { |e| Common.log_error("  - #{e.basename} (#{e.label})") }
            exit 1
          end

          # 3. すべてクリアしたら、一括で作成
          errors = false
          entries.each do |entry|
            fname = ensure_filename(entry.basename)
            unless fname
              Common.log_error("エラー: 無効なファイル名です: #{entry.basename}")
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

        # --- タイトルページ生成 ---

        # タイトルページ（扉）を config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: contents/_titlepage.md
        def execute_titlepage(options)
          apply_verbose(options)
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
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # --- 奥付生成 ---

        # 奥付ページを config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: contents/_colophon.md
        def execute_colophon(options)
          apply_verbose(options)
          title, subtitle = extract_title_and_subtitle
          author    = fetch_config_value('book', 'author')
          publisher = fetch_config_value('book', 'publisher')
          # publisher が未設定の場合は publisher_name をフォールバック
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
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # --- リーガルページ生成 ---

        # 免責事項・商標情報を含むリーガルページを生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: contents/_legalpage.md
        def execute_legalpage(options)
          apply_verbose(options)
          FileUtils.mkdir_p(Common::CONTENTS_DIR)
          target = File.join(Common::CONTENTS_DIR, '_legalpage.md')
          return if File.exist?(target) && !options[:force]

          disclaimer, trademark = legal_texts
          # 各行を <p> タグで囲んで HTML 化（Vivliostyle での表示用）
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

        # --- ヘルパー ---

        # verbose オプションが有効な場合、環境変数を設定してログ出力を詳細化する
        #
        # @param options [Hash] オプション Hash
        # @return [void]
        def apply_verbose(options)
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # 章名リストが空でないかを判定する
        #
        # @param names [Array, nil] 章名リスト
        # @return [Boolean] 有効な章名が1つ以上あれば true
        def ensure_names_present?(names)
          !names.nil? && !names.empty?
        end

        # 章名リストが空の場合、使い方を表示して終了する
        #
        # @param names [Array, nil] 章名リスト
        # @return [void]
        # @raise [SystemExit] names が空の場合 exit(1)
        def ensure_names_present!(names)
          return if ensure_names_present?(names)

          warn '使い方: vs create NAME [NAME ...]'
          exit 1
        end

        # 単一の章ファイルと関連リソースを生成する
        #
        # @param fname [String] ファイル名（XX-slug.md 形式）
        # @return [void]
        #
        # 処理フロー:
        #   1. テンプレートから Markdown コンテンツを生成
        #   2. contents/ に Markdown ファイルを作成
        #   3. images/ に章専用の画像ディレクトリを作成
        #   4. config/catalog.yml の CHAPTERS に章を追記
        def create_single_chapter(fname)
          title   = generate_title(fname)
          content = generate_content_from_template(title)
          path    = create_markdown_file(fname, content)
          # Vivliostyle は章ごとに画像を images/XX-slug/ に配置する規約
          create_image_directory(fname, {})

          # catalog.yml に追記することで build 時に自動的に含まれる
          basename = File.basename(fname, '.md')
          Build::CatalogUpdater.add_chapter(basename)

          Common.log_success("#{path} を作成しました")
        end

        # 章名を正規化し、ファイル名形式（XX-slug.md）に変換する
        #
        # @param name [String, nil] 入力された章名
        # @return [String, nil] 正規化されたファイル名、無効な場合は nil
        #
        # ファイル名規約:
        #   - 先頭は1桁以上の数字（並び順を示す。例: 11, 21, A1）
        #   - ハイフンで区切る
        #   - 英数字・ハイフン・ドット・アンダースコアのみ許可
        #   - 例: "11-install" → "11-install.md"
        def ensure_filename(name)
          return nil if name.nil?

          n = name.to_s.strip
          n = File.basename(n)
          n = File.basename(n, '.md')
          # 規約: 数字-スラッグ 形式のみ許可（目次や並べ替えで数字を使用するため）
          return nil unless n =~ /\A\d+-[\w.-]+\z/

          "#{n}.md"
        rescue StandardError
          nil
        end

        # ファイル名から章タイトルを抽出する
        #
        # @param fname [String] ファイル名（例: "11-sample.md"）
        # @return [String] タイトル部分（例: "sample"）
        #
        # 章番号プレフィックス（数字-）を除去し、タイトルとして使用する
        def generate_title(fname)
          basename = File.basename(fname.to_s, '.md')
          basename.sub(/\A\d+-/, '')
        end

        # テンプレートから章コンテンツを生成する
        #
        # @param title [String] 章タイトル
        # @return [String] Markdown コンテンツ
        #
        # templates/chapter_template.md が存在すればそれを使用し、
        # {{TITLE}} プレースホルダをタイトルで置換する。
        # テンプレートが無い場合はデフォルトの骨子を生成する。
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

        # Markdown ファイルを contents/ に作成する
        #
        # @param fname [String] ファイル名
        # @param content [String] ファイル内容
        # @return [String] 作成したファイルのパス
        # @raise [RuntimeError] 同名ファイルが既に存在する場合
        def create_markdown_file(fname, content)
          path = File.join(Common::CONTENTS_DIR, fname)
          raise "既に存在します: #{path}" if File.exist?(path)

          safe_write(path, content)
          path
        end

        # 章に対応する画像ディレクトリを生成する
        #
        # @param fname [String] 章ファイル名（XX-slug.md）
        # @param _options [Hash] 予約（将来拡張用）
        # @return [String] 作成したディレクトリのパス
        #
        # Vivliostyle では章ごとに images/XX-slug/ に画像を配置する規約があり、
        # Markdown 内の相対パス参照が正しく解決されるために必要
        def create_image_directory(fname, _options = {})
          basename = File.basename(fname, '.md')
          dir = File.join(Common::IMAGES_DIR, basename)

          if Dir.exist?(dir)
            Common.log_info("画像ディレクトリは既に存在します: #{dir}")
            return dir
          end

          FileUtils.mkdir_p(dir)
          Common.log_success("画像ディレクトリを作成しました: #{dir}")
          dir
        end

        # ファイルを安全に書き込む（親ディレクトリを自動作成）
        #
        # @param path [String] 書き込み先パス
        # @param content [String] ファイル内容
        # @return [void]
        def safe_write(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: 'utf-8')
        end

        # config/book.yml からタイトルとサブタイトルを取得する
        #
        # @return [Array<String, String>] [タイトル, サブタイトル]
        #
        # 設定キー:
        #   - book.main_title または book.title: メインタイトル
        #   - book.subtitle: サブタイトル（任意）
        def extract_title_and_subtitle
          book = Common::CONFIG.fetch('book', {})
          title = (book['main_title'] || book['title'] || '').to_s
          subtitle = (book['subtitle'] || '').to_s
          [title, subtitle]
        end

        # サブタイトルの装飾スタイルを取得する
        #
        # @return [String] "wave", "bar", "none" のいずれか（デフォルト: "wave"）
        #
        # CSS クラス subtitle--wave, subtitle--bar, subtitle--none に対応
        def subtitle_style
          style = fetch_config_value('book', 'subtitle_style').downcase
          %w[wave bar none].include?(style) ? style : 'wave'
        end

        # config/book.yml から指定キーの値を取得する
        #
        # @param section [String] セクション名（例: 'book', 'legal'）
        # @param key [String] キー名
        # @return [String] 値（nil の場合は空文字列）
        #
        # 使用例: fetch_config_value('book', 'author') → "著者名"
        def fetch_config_value(section, key)
          value = Common::CONFIG.dig(section, key)
          value ? value.to_s : ''
        end

        # 西暦から和暦の漢数字表記を生成する
        #
        # @param num [Integer] 元号からの年数（例: 令和7年なら 7）
        # @return [String] 漢数字表記（例: "七"）
        #
        # 奥付の著作権表示で使用（例: "令和七年"）
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

        # config/book.yml から免責・商標文面を取得する
        #
        # @return [Array<String, String>] [免責文面, 商標文面]
        #
        # 設定キー:
        #   - legal.disclaimer: 免責事項
        #   - legal.trademark: 商標情報
        #
        # 両方とも未設定の場合は DEFAULT_DISCLAIMER / DEFAULT_TRADEMARK を使用
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

        # デフォルトの免責事項テンプレート
        DEFAULT_DISCLAIMER = <<~TXT.strip
          本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
          本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
        TXT

        # デフォルトの商標情報テンプレート
        DEFAULT_TRADEMARK = <<~TXT.strip
          本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
          本書では ™、®、© などのマークは省略しています。
        TXT
      end
    end
  end
end
