# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme_commands.rb
# ================================================================
# 責務:
#   vs theme・vs theme:add・vs theme:check・vs theme:new の処理と表示（theme-contract-spec.md §7.2）。
#   検査は Theme::Check、取得と複製は Theme::Install が行い、ここは確認と案内を受け持つ。
#
# book.yml は書き換えない（§7.2）。使うときに書く行を示す。
# ================================================================

require 'tmpdir'
require 'yaml'
require_relative 'common'
require_relative 'theme'
require_relative 'theme/check'
require_relative 'theme/install'

module VivlioStarter
  module CLI
    module ThemeCommands
      BOOK_YML = File.join('config', 'book.yml')

      module_function

      # ================================================================
      # vs theme
      # ================================================================

      # 本の themes/ のテーマと、選ばれているテーマ、本に無い同梱のテーマ
      def list(root: Dir.pwd, config: Common::CONFIG, bundled_root: Theme::BUNDLED_ROOT)
        selected = Theme.selected_name(config)
        names = theme_names(root)
        Common.log_always("本のテーマ（#{Theme::DIR}/）:")
        Common.log_always('  （ありません）') if names.empty?
        names.each { Common.log_always("  #{theme_line(it, root, selected)}") }
        unless names.include?(selected)
          Common.log_warn("#{BOOK_YML} の theme.name の #{selected} が、本の #{Theme::DIR}/ にありません",
                          detail: add_hint(selected, bundled_root))
        end

        others = theme_names(bundled_root) - names
        unless others.empty?
          Common.log_always('')
          Common.log_always('同梱のテーマ（vs theme:add <名前> で本に入れます）:')
          others.each { Common.log_always("  #{theme_line(it, bundled_root, nil)}") }
        end
        0
      end

      def theme_names(root) = Dir.glob("*/#{Theme::Manifest::FILE}", base: File.join(root, Theme::DIR)).map { File.dirname(it) }.sort

      # 1 行: 印・名前・題・版・土台
      def theme_line(name, root, selected)
        mark = name == selected ? '▶' : ' '
        manifest = Theme::Manifest.load(File.join(Theme::DIR, name), root:)
        # 書いていないキーは空文字列で読まれる（Manifest.optional_string）
        facts = [manifest.title.to_s, manifest.version.to_s.empty? ? '' : "版 #{manifest.version}",
                 manifest.extends ? "土台: #{manifest.extends}" : ''].reject(&:empty?)
        suffix = name == selected ? "  ← #{BOOK_YML} の theme.name" : ''
        "#{mark} #{name}  #{facts.join('・')}#{suffix}"
      rescue Theme::Error => e
        "#{mark} #{name}  （読めません: #{e.message}）"
      end

      def add_hint(name, bundled_root)
        bundled = File.file?(File.join(bundled_root, Theme::DIR, name, Theme::Manifest::FILE))
        bundled ? "同梱のテーマなので、vs theme:add #{name} で本に入れられます" : "#{Theme::DIR}/#{name}/ を置くか、theme.name を直してください"
      end

      # ================================================================
      # vs theme:check
      # ================================================================

      # @param name [String, nil] テーマの名前（省略すると book.yml の theme.name）
      # @return [Integer] 終了コード（🔴 があれば 1）
      def check(name = nil, root: Dir.pwd, config: Common::CONFIG)
        name = name.to_s.strip.empty? ? Theme.selected_name(config) : name.to_s.strip
        report = Theme::Check.run(name, root:, config:)
        print_report(report)
        report.errors.empty? ? 0 : 1
      end

      def print_report(report)
        report.findings.each do |finding|
          case finding.level
          in :error then Common.log_error(finding.message, detail: finding.detail)
          in :warning then Common.log_warn(finding.message, detail: finding.detail)
          in :hint
            Common.log_always("💡 #{finding.message}")
            Array(finding.detail).each { Common.log_always("#{Common::DETAIL_INDENT}#{it}") }
          end
        end
        if !report.errors.empty?
          Common.log_result("テーマ #{report.name} は使えません（🔴 #{report.errors.size} 件）", status: :failure)
        elsif !report.warnings.empty?
          Common.log_result("テーマ #{report.name} に 🟡 が #{report.warnings.size} 件あります", status: :warning)
        else
          Common.log_result("テーマ #{report.name} に、直すところは見つかりませんでした", status: :success)
        end
      end

      # ================================================================
      # vs theme:add
      # ================================================================

      # テーマを本の themes/ へ複製し、検査して、book.yml に書く行を示す
      # @param source [String] 同梱のテーマの名前・ディレクトリ・zip のパス
      # @param input [IO] 置き換えの確認の答えを読む先
      # @return [Integer] 終了コード
      def add(source, root: Dir.pwd, config: Common::CONFIG, input: $stdin, bundled_root: Theme::BUNDLED_ROOT)
        Dir.mktmpdir('vs-theme-add') do |work|
          # --- Phase: 取得と、許可の表のファイルだけの複製（一時ディレクトリへ） ---
          from = Theme::Install.fetch(source, work, root:, bundled_root:)
          stage_root = File.join(work, 'book')
          staged = [Theme::Install.stage(from, stage_root)]
          base_note = stage_base(staged, stage_root, root, bundled_root)
          report_skipped(staged.first)

          # --- Phase: 本のテーマとの違いと、置き換えの確認 ---
          changes = staged.to_h { [it, Theme::Install.changes(it, root)] }
          if changes.values.all?(&:none?)
            Common.log_result("テーマ #{staged.first.name} は、本の #{Theme::DIR}/#{staged.first.name}/ と同じです（変えるものはありません）",
                              status: :success)
          else
            return 0 unless confirm_replacement(changes, input)

            changes.each { |item, change| Theme::Install.apply!(item, root) unless change.none? }
            changes.each { |item, change| report_added(item, change) }
          end
          Common.log_warn(base_note[:message], detail: base_note[:detail]) if base_note

          # --- Phase: 検査と、book.yml に書く行（土台が無ければテーマを読めないので省く） ---
          next 0 if base_note

          status = check(staged.first.name, root:, config:)
          print_usage_lines(staged.first.name, root, config)
          status
        end
      rescue Theme::Error => e
        Common.log_error(e.message, detail: e.detail)
        1
      end

      # extends: の先が本に無ければ、同梱のテーマなら一緒に写す（§7.2 の 5）。
      # 同梱に無ければ、無いことを知らせる文面を返す
      def stage_base(staged, stage_root, root, bundled_root)
        base = staged.first.manifest.extends
        return nil if base.nil? || File.file?(File.join(root, Theme::DIR, base, Theme::Manifest::FILE))

        bundled = File.join(bundled_root, Theme::DIR, base)
        if File.file?(File.join(bundled, Theme::Manifest::FILE))
          staged << Theme::Install.stage(bundled, stage_root)
          return nil
        end

        { message: "テーマ #{staged.first.name} の土台 #{base} が、本の #{Theme::DIR}/ にありません",
          detail: "→ #{base} を vs theme:add で入れてから、theme.name に #{staged.first.name} を書いてください" }
      end

      def report_skipped(staged)
        return if staged.skipped.empty?

        Common.log_always('💡 次のファイルは写しませんでした（テーマに入れられるのは CSS・YAML・画像・書体・README.md・LICENSE だけです）:')
        staged.skipped.each { Common.log_always("#{Common::DETAIL_INDENT}#{it}") }
      end

      # 置き換わるもの・削除するものがあれば、全部を見せてから確認する（いいえなら何も変えない）
      def confirm_replacement(changes, input)
        replacing = changes.select { |_, change| change.replacing? }
        return true if replacing.empty?

        replacing.each do |item, change|
          Common.log_always("#{Theme::DIR}/#{item.name}/ は本にあります。次のファイルが変わります:")
          { '置き換え' => change.replaced, '追加' => change.added, '削除' => change.removed }.each do |label, files|
            files.each { Common.log_always("#{Common::DETAIL_INDENT}#{label}: #{it}") }
          end
        end
        names = replacing.keys.map { "#{Theme::DIR}/#{it.name}/" }.join('・')
        return true if Common.confirm?("#{names} を置き換えますか？", input:)

        Common.log_always("#{names} は変えていません")
        false
      end

      def report_added(staged, change)
        return if change.none?

        count = Theme::Install.files_in(staged.dir).size
        Common.log_result("テーマ #{staged.name} を #{Theme::DIR}/#{staged.name}/ に入れました（ファイル #{count} 個）", status: :success)
      end

      # 使うときに book.yml に書く行と、テーマの値を覆っている theme: の行（§3.2・§7.2）
      def print_usage_lines(name, root, config)
        if Theme.selected_name(config) == name
          Common.log_always("💡 #{BOOK_YML} の theme.name は #{name} です。次のビルドから使われます")
        else
          Common.log_always("💡 使うときは、#{BOOK_YML} の theme: に次のように書きます（book.yml は書き換えていません）")
          Common.log_always("#{Common::DETAIL_INDENT}theme:")
          Common.log_always("#{Common::DETAIL_INDENT}  name: #{name}")
        end
        overriding_lines(name, root).each do |message, advice|
          Common.log_always("💡 #{message}")
          Common.log_always("#{Common::DETAIL_INDENT}#{advice}")
        end
      end

      # テーマの tokens: の値を、book.yml に書いた theme: の値が覆っている行（[文面, 直し方] の並び）
      def overriding_lines(name, root)
        theme = Theme.resolve(name, root:)
        written = book_theme_section(root)
        tokens = theme.tokens
        theme.all_options.filter_map do |option|
          next unless option.token && tokens.key?(option.token)

          value = written.dig(*option.path.map(&:to_s))
          next if value.nil? || value.to_s.strip.empty?

          ["#{BOOK_YML} の #{option.label}: #{value} が、テーマ #{name} の値（#{tokens[option.token]}）を覆っています",
           "→ テーマの値で組むには、#{option.key}: の値を消して空欄にします"]
        end
      rescue Theme::Error
        []
      end

      # book.yml の theme: 節（書いたとおりの値）
      def book_theme_section(root)
        raw = YAML.safe_load_file(File.join(root, BOOK_YML))
        section = raw.is_a?(Hash) ? raw['theme'] : nil
        section.is_a?(Hash) ? section : {}
      rescue SystemCallError, Psych::Exception
        {}
      end

      # ================================================================
      # vs theme:new
      # ================================================================

      # 配色のテーマ（--extends あり）か組版のテーマ（なし）の雛形を themes/<名前>/ に作る
      # @return [Integer] 終了コード
      def new_theme(name, extends: nil, root: Dir.pwd, config: Common::CONFIG, bundled_root: Theme::BUNDLED_ROOT)
        name = name.to_s.strip
        unless name.match?(Theme::Manifest::NAME_PATTERN)
          raise Theme::Error.new("テーマの名前 #{name} は使えません", detail: '半角の英小文字・数字・ハイフンで書きます（例: mono）')
        end

        dir = File.join(root, Theme::DIR, name)
        raise Theme::Error.new("#{Theme::DIR}/#{name}/ は、もうあります", detail: '別の名前にしてください') if File.exist?(dir)
        if extends && !File.file?(File.join(root, Theme::DIR, extends, Theme::Manifest::FILE))
          raise Theme::Error.new("土台にするテーマ #{extends} が、本の #{Theme::DIR}/ にありません", detail: add_hint(extends, bundled_root))
        end

        FileUtils.mkdir_p(dir)
        Theme::Template.files(name, extends:).each { |file, body| File.write(File.join(dir, file), body, encoding: 'utf-8') }
        kind = extends ? "配色のテーマ（土台: #{extends}）" : '組版のテーマ'
        Common.log_result("#{kind} #{name} の雛形を #{Theme::DIR}/#{name}/ に作りました", status: :success)
        status = check(name, root:, config:)
        print_usage_lines(name, root, config)
        status
      rescue Theme::Error => e
        Common.log_error(e.message, detail: e.detail)
        1
      end
    end

    module Theme
      # vs theme:new が作るファイル（theme-contract-spec.md §3.1・§3.2）
      module Template
        module_function

        # @return [Hash{String => String}] ファイル名 → 中身
        def files(name, extends: nil)
          return { Manifest::FILE => color_theme(name, extends) } if extends

          { Manifest::FILE => typesetting_theme(name), 'theme.css' => stylesheet(name) }
        end

        def color_theme(name, extends)
          <<~YAML
            name: #{name}
            title: #{name}
            version: 0.1.0
            contract: #{Contract::CURRENT}
            extends: #{extends}

            # 配色のテーマ: 土台（#{extends}）の CSS をそのまま使い、公開する変数（--book-*）の値だけを差し替えます。
            # 名前は --book- を除いて書きます。変数の一覧と既定の値は stylesheets/tokens.css にあります。
            # config/book.yml の theme: に同じ値（color など）を書いていると、そちらが勝ちます。
            tokens:
            #  color-accent: "#3b6ea5"
            #  color-link: "#2a5590"
            #  font-heading: '"Noto Serif JP", serif'
          YAML
        end

        def typesetting_theme(name)
          <<~YAML
            name: #{name}
            title: #{name}
            version: 0.1.0
            contract: #{Contract::CURRENT}

            supports:
              writing_mode: [horizontal]
              layout: [reflowable]
              targets: [pdf, print_pdf, epub, kindle]

            # 組版のテーマの CSS（theme 層に、書いた順に読みます）。
            # EPUB と Kindle だけの規則は、このディレクトリの epub.css・kindle.css に書きます。
            styles:
              - theme.css
          YAML
        end

        def stylesheet(name)
          <<~CSS
            @charset "utf-8";

            /* テーマ #{name} の CSS（theme 層）。
               値を変えるときは stylesheets/tokens.css の公開する変数（--book-*）を使います。
               Kindle に届かない書き方は vs theme:check #{name} が示します。 */
          CSS
        end
      end
    end
  end
end
