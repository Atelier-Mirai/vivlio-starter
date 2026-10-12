# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/create.rb
# ================================================================
# 責務:
#   書籍プロジェクトにおける章ファイル・特殊ページの生成を担当する。
#
# 提供機能:
#   - execute_create: 章 Markdown と画像ディレクトリを生成
#   - execute_titlepage: タイトルページを config/book.yml から生成
#   - execute_colophon: 奥付を config/book.yml から生成
#   - execute_legalpage: 免責・商標ページを config/book.yml から生成
#   表紙は CoverCommands（cover.rb）が作る。
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
require_relative 'build/catalog_updater'
require_relative 'chapter_names'
require_relative 'token_resolver'

module VivlioStarter
  module CLI
    # 章ファイル・特殊ページ生成ロジック
    #
    # Samovar CLI コマンドから呼び出される実行メソッド群。
    # 各メソッドは純粋な Hash オプションを受け取る。
    module CreateCommands
      module_function

      MAX_AUTO_CHAPTER = 98

      # ================================================================
      # 章ファイル生成
      # ================================================================

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
        normalized_names = enforce_name_rule!(normalize_name_inputs(names, resolver))
        entries = resolver.resolve(normalized_names)

        # 1. 不正な形式をチェック
        invalid_entries = entries.reject(&:valid?)
        if invalid_entries.any?
          Common.log_error("エラー: 不正な形式が含まれています: #{invalid_entries.map(&:slug).join(', ')}")
          exit 1
        end

        # 2. カタログとの重複をチェック
        duplicate_entries = entries.select(&:in_catalog?)
        if duplicate_entries.any?
          Common.log_error('エラー: 以下の章は既にカタログに存在します:')
          duplicate_entries.each { |e| Common.log_error("  - #{e.basename} (#{e.label})") }
          exit 1
        end

        # 3. 番号と名前の重なりをチェック。同じ番号・同じ名前の別の章があると、
        #    vs build 97・vs build sample・章のラベル ID（@ch-sample）がどちらを指すか決められない
        conflicts = name_conflicts(entries)
        if conflicts.any?
          Common.log_error('エラー: 以下の章は、番号かスラッグが既に使われています:')
          conflicts.each { Common.log_error("  - #{it}") }
          exit 1
        end

        # 4. すべてクリアしたら、一括で作成
        errors = false
        created = []
        entries.each do |entry|
          fname = ensure_filename(entry.basename)
          unless fname
            Common.log_error("エラー: 無効なファイル名です: #{entry.basename}")
            errors = true
            next
          end

          create_single_chapter(fname, entry)
          created << entry.basename
        rescue StandardError => e
          errors = true
          Common.log_error("作成に失敗しました: #{fname} (#{e.class}: #{e.message})")
        end

        exit 1 if errors

        # 作成した章名を返す（表示は呼び出し側の責務）
        created
      end

      # ================================================================
      # タイトルページ生成
      # ================================================================

      # タイトルページ（扉）を config/book.yml から生成する
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      #   - :force [Boolean] 既存ファイルを強制上書き
      # @return [void]
      #
      # 生成ファイル: .cache/vs/_titlepage.md
      def execute_titlepage(options)
        apply_verbose(options)
        title, subtitle = extract_title_and_subtitle
        author  = fetch_config_value(:book, :author)
        series  = fetch_config_value(:book, :series)
        release = fetch_config_value(:book, :release)
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

        # 常に上書き再生成する（book.yml 変更を確実に反映するため）
        path = File.join(Common::CACHE_DIR, '_titlepage.md')
        safe_write(path, content)
      end

      # ================================================================
      # 奥付生成
      # ================================================================

      # 奥付ページを config/book.yml から生成する
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      #   - :force [Boolean] 既存ファイルを強制上書き
      # @return [void]
      #
      # 生成ファイル: .cache/vs/_colophon.md
      def execute_colophon(options)
        apply_verbose(options)
        title, subtitle = extract_title_and_subtitle
        author    = fetch_config_value(:book, :author)
        publisher = fetch_config_value(:book, :publisher)
        publisher = fetch_config_value(:book, :publisher_name) if publisher.empty?
        contact   = fetch_config_value(:book, :contact)
        release   = fetch_config_value(:book, :release)
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
                  (Powered by Vivlio Starter)
              </small>
          </p>
        MD

        # 常に上書き再生成する（book.yml 変更を確実に反映するため）
        path = File.join(Common::CACHE_DIR, '_colophon.md')
        safe_write(path, content)
      end

      # ================================================================
      # リーガルページ生成
      # ================================================================

      # 免責事項・商標情報を含むリーガルページを生成する
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      #   - :force [Boolean] 既存ファイルを強制上書き
      # @return [void]
      #
      # 生成ファイル: .cache/vs/_legalpage.md
      def execute_legalpage(options)
        apply_verbose(options)
        FileUtils.mkdir_p(Common::CACHE_DIR)
        # 常に上書き再生成する（book.yml 変更を確実に反映するため）
        target = File.join(Common::CACHE_DIR, '_legalpage.md')

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

        # Twemoji クレジット（legal.twemoji が設定されている場合のみ）
        twemoji_credit = Common::CONFIG.legal.twemoji
        if twemoji_credit && !twemoji_credit.to_s.strip.empty?
          body += <<~MD

            <div class="twemoji-credit">
              <h2>■絵文字クレジット</h2>
              #{twemoji_credit.to_s.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>
          MD
        end

        safe_write(target, body)
        Common.log_success("生成しました: #{target}")
      end

      # ================================================================
      # 章ファイル生成ヘルパー
      # ================================================================

      # 単一の章ファイルと関連リソースを生成する
      #
      # @param fname [String] ファイル名（XX-slug.md 形式）
      # @param entry [TokenResolver::Entry] 章エントリ
      # @return [void]
      def create_single_chapter(fname, entry)
        title   = generate_title(fname)
        content = generate_content_from_template(entry, title)
        path    = create_markdown_file(fname, content)
        create_image_directory(fname, {})

        basename = File.basename(fname, '.md')
        Build::CatalogUpdater.add_chapter(basename)

        Common.log_success("#{path} を作成しました")
      end

      # 章名を正規化し、ファイル名形式（XX-slug.md）に変換する
      #
      # @param name [String, nil] 入力された章名
      # @return [String, nil] 正規化されたファイル名、無効な場合は nil
      def ensure_filename(name)
        return nil if name.nil?

        n = name.to_s.strip
        n = File.basename(n)
        n = File.basename(n, '.md')
        return nil unless n =~ /\A\d+(?:-[\w.-]+)?\z/

        "#{n}.md"
      rescue StandardError
        nil
      end

      # ファイル名から章タイトルを抽出する
      def generate_title(fname)
        basename = File.basename(fname.to_s, '.md')
        basename.sub(/\A\d+-/, '')
      end

      # slug を chapter 名として利用できる形式へ正規化する
      def normalize_slug(value)
        slug = value.to_s.downcase
                    .tr(' ', '-')
                    .gsub(/[^a-z0-9-]+/, '-')
                    .gsub(/-+/, '-')
                    .gsub(/\A-+|-+\z/, '')
        slug = 'chapter' if slug.empty?
        slug
      end

      # テンプレートから章コンテンツを生成する
      def generate_content_from_template(entry, title)
        tpl = template_path_for(entry)
        if tpl && File.exist?(tpl)
          File.read(tpl, encoding: 'utf-8').gsub('{{TITLE}}', title.to_s)
        else
          <<~MD
            # #{title}

            <!-- 章テンプレートが見つからなかったため、デフォルトの骨子を生成しました -->

            ここに#{title}の内容を記述してください。
          MD
        end
      end

      def template_path_for(entry)
        case entry&.kind
        when :preface  then Common.preface_template_path
        when :appendix then Common.appendix_template_path
        when :postface then Common.postface_template_path
        else                Common.chapter_template_path
        end
      end

      # Markdown ファイルを contents/ に作成する
      def create_markdown_file(fname, content)
        path = File.join(Common::CONTENTS_DIR, fname)
        raise "既に存在します: #{path}" if File.exist?(path)

        safe_write(path, content)
        path
      end

      # 章に対応する画像ディレクトリを生成する
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
      def safe_write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content, encoding: 'utf-8')
      end

      # ================================================================
      # book.yml アクセスヘルパー
      # ================================================================

      # config/book.yml からタイトルとサブタイトルを取得する
      def extract_title_and_subtitle
        book = Common::CONFIG.book
        title    = (book.main_title || '').to_s
        subtitle = (book.subtitle || '').to_s
        [title, subtitle]
      end

      # サブタイトルの装飾スタイルを取得する
      def subtitle_style
        style = fetch_config_value(:book, :subtitle_style).downcase
        %w[wave bar none].include?(style) ? style : 'wave'
      end

      # config/book.yml から指定キーの値を取得する
      def fetch_config_value(section, key)
        value = Common::CONFIG.dig(section, key)
        value ? value.to_s : ''
      end

      # 西暦から和暦の漢数字表記を生成する
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
      def legal_texts
        legal = Common::CONFIG.legal
        disclaimer = (legal.disclaimer || '').strip
        trademark  = (legal.trademark  || '').strip

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

      # ================================================================
      # 章番号管理ヘルパー
      # ================================================================

      def apply_verbose(options)
        ENV['VERBOSE'] = '1' if options[:verbose]
      end

      def ensure_names_present?(names)
        !names.nil? && !names.empty?
      end

      def normalize_name_inputs(names, resolver)
        used_numbers = used_numbers_pool(resolver)

        Array(names).map do |raw|
          token    = raw.to_s.strip
          basename = strip_token_basename(token)

          if numbered_basename?(basename)
            number = extract_number(basename)
            used_numbers << number if number && !used_numbers.include?(number)
            token
          else
            slug      = normalize_slug(basename)
            number    = next_available_number!(used_numbers)
            generated = "#{number}-#{slug}"
            Common.log_info("[create] #{basename} -> #{generated}")
            generated
          end
        end
      end

      def strip_token_basename(token)
        base = File.basename(token.to_s.strip)
        base.sub(/\.(md|markdown)\z/i, '')
      rescue StandardError
        token.to_s
      end

      def numbered_basename?(basename)
        basename.match?(/\A\d+/)
      end

      def extract_number(basename)
        return unless basename =~ /\A(\d+)/

        format('%02d', Regexp.last_match(1).to_i)
      end

      def ensure_names_present!(names)
        return if ensure_names_present?(names)

        Common.log_error('使い方: vs create NAME [NAME ...]')
        exit 1
      end

      def used_numbers_pool(resolver)
        catalog_numbers  = resolver.resolve([]).map(&:number).compact
        markdown_numbers = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).filter_map do |path|
          File.basename(path, '.md')[/\A(\d{2})/, 1]
        end
        (catalog_numbers + markdown_numbers).uniq
      end

      # 章の名前を決まりの形（ChapterNames::VALID_BASENAME）に整える。大文字と `_` は整えて知らせ、
      # 点・空白・日本語を含む名前は作らずに止める。点を含む名前は章の解決が別の章を指し、ビルドを壊していた
      # @return [Array<String>] 整えた名前
      def enforce_name_rule!(names)
        taken = ChapterNames.existing_basenames
        rejected = []
        fixed = names.map do |name|
          base = strip_token_basename(name)
          normalized = ChapterNames.normalize(base)
          rejected << base unless normalized
          Common.log_info("[create] #{base} -> #{normalized}") if normalized && normalized != base
          normalized || base
        end
        return fixed if rejected.empty?

        Common.log_error('エラー: 以下の名前は章の名前に使えません（2 桁の番号と、英小文字・数字・ハイフンのスラッグで付けます）:')
        rejected.each do |base|
          suggested = ChapterNames.suggestion(base, taken)
          Common.log_error("  - #{base}#{" → vs create #{suggested}" if suggested}")
        end
        exit 1
      end

      # 作ろうとする章のうち、番号か名前を別の章（contents/ の原稿か catalog.yml の章）が使っているもの。
      # 一度に作る章どうしの重なりも数える。重ならない番号・名前で打ち直すコマンドを添える
      # （勧めた名前どうしも重ならないよう、reserved に溜める）
      # @return [Array<String>] 知らせる行
      def name_conflicts(entries)
        taken = ChapterNames.existing_basenames
        reserved = []

        entries.filter_map do |entry|
          problems = ChapterNames.conflicts(entry.basename, taken)
          taken << entry.basename
          next if problems.empty?

          suggested = ChapterNames.suggestion(entry.basename, taken + reserved)
          reserved << suggested if suggested
          hint = suggested ? " → vs create #{suggested}" : ''
          "#{entry.basename}（#{problems.join('、')}）#{hint}"
        end
      end

      def next_available_number!(used_numbers)
        (1..MAX_AUTO_CHAPTER).each do |candidate|
          number = format('%02d', candidate)
          next if used_numbers.include?(number)

          used_numbers << number
          return number
        end

        raise '01-98 までの章番号がすべて使用済みです'
      end
    end
  end
end
