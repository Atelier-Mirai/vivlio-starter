# frozen_string_literal: true

# 新規書籍プロジェクトの雛形作成（`vs new` のドメイン層および Scaffolder ベースの API）。
# Samovar の `NewCommand` は本モジュールのみを参照する。

require 'shellwords'
require 'yaml'
require 'fileutils'
require_relative '../scaffolder'

module Vivlio
  module Starter
    module CLI
      module NewCommands
        extend self

        # `lib/project_scaffold/` への絶対パス（`cli/new.rb` 基準）
        SCAFFOLD_SOURCE = File.expand_path('../../../project_scaffold', __dir__).freeze

        GEM_ROOT = File.expand_path('../../../..', __dir__).freeze

        VALID_NAME_PATTERN = /\A[a-zA-Z0-9_-]+\z/

        DEFAULT_ANSWERS = {
          main_title: '新しい本',
          subtitle: '',
          author: '',
          publisher: ''
        }.freeze

        # Samovar `NewCommand` から呼び出すメイン処理（終了コードを返す）
        def run_from_command(cmd)
          return cmd.print_usage if cmd.options[:help]

          project_name = validated_project_name!(cmd)
          check_existing_directory!(cmd, project_name)

          answers = collect_answers(cmd, project_name)
          expand_scaffold(cmd, project_name, answers)
          run_doctor(cmd, project_name)
          print_success(project_name)
          0
        end

        # 旧来のオプション付き新規作成（内部・テスト用）
        def execute_new(name, options = {})
          ENV['VERBOSE'] = '1' if options[:verbose]

          name = name&.strip
          if name.nil? || name.empty?
            Common.log_error('Error: プロジェクト名を指定してください。例: vs new mybook')
            exit(1)
          end

          dest = File.expand_path(name)
          if File.exist?(dest)
            Common.log_error("Error: '#{name}' は既に存在します。別名を指定してください。")
            exit(1)
          end

          Common.log_action("[vivlio-starter] Creating new project: #{name}")

          result = Vivlio::Starter::Scaffolder.scaffold_project(
            name: name,
            dest: dest,
            gem_root: GEM_ROOT,
            copy_styles_mode: :all,
            include_ci_workflow: true,
            include_viv_config_update: true
          )

          Common.log_success("[vivlio-starter] Done. cd #{name} で移動し、執筆を開始できます。")
          Common.log_info('例: vivliostyle preview などのコマンドを実行')

          begin
            Dir.chdir(result.dest) do
              if options[:manual_install]
                Common.log_always('doctor の自動実行をスキップします (--manual-install)')
              elsif options[:auto_install]
                Common.log_always('必要ツールの自動インストールを有効にして doctor を実行します (--auto-install)')
                opts = { fix: true }
                opts[:yes] = true unless options[:interactive]
                DoctorCommands.execute_doctor({ options: opts })
              else
                proceed = false
                if $stdin.tty?
                  $stdout.print('qpdf / pdfinfo の診断を実行しますか？ [y/N]: ')
                  ans = $stdin.gets
                  proceed = ans && ans.strip.downcase == 'y'
                end
                if proceed
                  DoctorCommands.execute_doctor({})
                else
                  Common.log_always('後で実行する場合: vs doctor もしくは vs doctor --fix (macOS)')
                end
              end
            end
          rescue StandardError => e
            Common.log_warn("doctor 実行フローでエラーが発生しました: #{e}")
          end
        end

        # Scaffolder ベースのプロジェクト作成（README 同梱・book.yml 対話更新・vivliostyle 同期）
        def run(name)
          name = (name || '').strip
          abort 'Error: プロジェクト名を指定してください。例: vs new mybook' if name.empty?

          dest = File.expand_path(name)
          abort "Error: '#{name}' は既に存在します。別名を指定してください。" if File.exist?(dest)

          puts "[vivlio-starter] Creating new project: #{name}"

          result = Vivlio::Starter::Scaffolder.scaffold_project(
            name: name,
            dest: dest,
            gem_root: GEM_ROOT,
            include_post_replace: true,
            include_readme: true,
            readme_content: default_readme_content(name),
            include_viv_config_update: true
          ) do |event, ctx|
            update_book_config_interactively(ctx[:config_path]) if event == :after_config
          end

          run_vs_config(result.dest)
          synchronize_viv_config(result.vivliostyle_config_path, result.config_path)

          Common.log_always "[vivlio-starter] 完了しました。cd #{name} で移動し、執筆を開始できます。"
          Common.log_always '例: vivlio-starter build で執筆した書籍をPDFで作成できます。'
          0
        end

        def update_book_config_interactively(config_path)
          return unless $stdin.tty?

          cfg = YAML.load_file(config_path)
          cfg = {} unless cfg.is_a?(Hash)
          book_cfg = cfg['book'] || {}

          puts "\n[vivlio-starter] 書籍情報を入力してください（未入力は現状の値を維持）"
          current_title = book_cfg['main_title'].to_s
          current_sub   = book_cfg['subtitle'].to_s
          current_auth  = book_cfg['author'].to_s

          new_title = prompt_with_default('書籍名（main_title）', current_title)
          new_sub   = prompt_with_default('副題（subtitle）', current_sub)
          new_auth  = prompt_with_default('著者名（author）', current_auth)

          text = File.read(config_path, encoding: 'utf-8')
          lines = text.lines
          book_idx = lines.index { |l| l =~ /^\s*book:\s*$/ }

          keys = {
            'main_title' => new_title,
            'subtitle' => new_sub,
            'author' => new_auth
          }

          if book_idx
            end_idx = lines.length
            ((book_idx + 1)...lines.length).each do |i|
              if lines[i] =~ /^\S/ && lines[i] !~ /^\s{2}/
                end_idx = i
                break
              end
            end

            present = { 'main_title' => false, 'subtitle' => false, 'author' => false }

            ((book_idx + 1)...end_idx).each do |i|
              line = lines[i]
              next unless line =~ /^(\s{2})(main_title|subtitle|author):\s*([^#\n]*)(\s*#.*)?$/

              indent  = ::Regexp.last_match(1)
              key     = ::Regexp.last_match(2)
              comment = ::Regexp.last_match(4).to_s
              value   = keys[key]
              lines[i] = "#{indent}#{key}: '#{value}'#{comment}\n"
              present[key] = true
            end

            insert_pos = book_idx + 1
            %w[main_title subtitle author].each do |key|
              next if present[key]

              lines.insert(insert_pos, "  #{key}: '#{keys[key]}'\n")
              insert_pos += 1
            end

            File.write(config_path, lines.join, encoding: 'utf-8')
            Common.log_success("[vivlio-starter] book.yml を更新しました。")
          else
            File.open(config_path, 'a:utf-8') do |f|
              f.puts
              f.puts 'book:'
              f.puts "  main_title: '#{new_title}'"
              f.puts "  subtitle: '#{new_sub}'"
              f.puts "  author: '#{new_auth}'"
            end
            Common.log_success("[vivlio-starter] book.yml に book セクションを追記しました。")
          end
        rescue StandardError => e
          Common.log_warn("[vivlio-starter] book.yml の対話入力に失敗しました: #{e}")
        end

        private

        def validated_project_name!(cmd)
          raw = cmd.names.first.to_s.strip
          if raw.empty?
            Common.log_error('エラー: プロジェクト名を指定してください。')
            Common.log_error('  vs new <project_name>')
            exit 1
          end
          unless raw.match?(VALID_NAME_PATTERN)
            Common.log_error('エラー: プロジェクト名に使用できる文字は英数字・ハイフン・アンダースコアのみです。')
            exit 1
          end
          raw
        end

        def check_existing_directory!(cmd, project_name)
          return unless Dir.exist?(project_name)
          return if cmd.options[:force]

          Common.log_error("エラー: ディレクトリ \"#{project_name}\" はすでに存在します。")
          Common.log_error('上書き展開する場合は --force オプションを指定してください。')
          Common.log_error("  vs new #{project_name} --force")
          exit 1
        end

        def collect_answers(cmd, project_name)
          if cmd.options[:yes]
            Common.log_action("Vivlio Starter: プロジェクト \"#{project_name}\" を作成しています...（デフォルト設定）")
            return DEFAULT_ANSWERS.dup
          end

          Common.log_always 'Vivlio Starter へようこそ！新しい書籍プロジェクトを作成します。'
          Common.log_always ''

          answers = {
            main_title: prompt('書籍名を入力してください（例: はじめての Ruby）', DEFAULT_ANSWERS[:main_title]),
            subtitle: prompt('副題を入力してください（任意。Enter でスキップ）', DEFAULT_ANSWERS[:subtitle]),
            author: prompt('著者名を入力してください（例: 山田 太郎）', DEFAULT_ANSWERS[:author]),
            publisher: prompt('発行者・サークル名を入力してください（例: アトリヱ未來）', DEFAULT_ANSWERS[:publisher])
          }

          confirm_answers!(project_name, answers)
          answers
        end

        def prompt(message, default)
          $stdout.print("#{message}: ")
          $stdout.flush
          input = $stdin.gets&.strip || ''
          input.empty? ? default : input
        end

        def confirm_answers!(project_name, answers)
          subtitle_display = answers[:subtitle].empty? ? '（なし）' : answers[:subtitle]
          author_display   = answers[:author].empty? ? '（なし）' : answers[:author]
          publisher_display = answers[:publisher].empty? ? '（なし）' : answers[:publisher]

          Common.log_always ''
          Common.log_always '以下の設定でプロジェクトを作成します。'
          Common.log_always ''
          Common.log_always "  プロジェクト名: #{project_name}"
          Common.log_always "  書籍名:         #{answers[:main_title]}"
          Common.log_always "  副題:           #{subtitle_display}"
          Common.log_always "  著者:           #{author_display}"
          Common.log_always "  発行者:         #{publisher_display}"
          Common.log_always ''
          $stdout.print('よろしいですか？ [Y/n]: ')
          $stdout.flush
          input = $stdin.gets&.strip || ''

          return unless input.downcase == 'n'

          Common.log_always "中断しました。もう一度 vs new #{project_name} を実行してください。"
          exit 0
        end

        def expand_scaffold(cmd, project_name, answers)
          # クリーンアップ対象にするのは「今回作成した」ディレクトリのみ。
          # `--force` で既存ディレクトリに重ねる場合は、部分破壊を避けるため保持する。
          created_root = !File.exist?(project_name)
          FileUtils.mkdir_p(project_name)

          begin
            Dir.glob('**/*', File::FNM_DOTMATCH, base: SCAFFOLD_SOURCE).each do |relative|
              src = File.join(SCAFFOLD_SOURCE, relative)
              dst = File.join(project_name, relative)

              next if File.basename(relative) == '.DS_Store'

              if File.directory?(src)
                FileUtils.mkdir_p(dst)
                log_debug(cmd, "ディレクトリ作成: #{dst}")
                next
              end

              if File.exist?(dst)
                Common.log_info("スキップ: #{dst}（既存ファイルを保持）")
                next
              end

              FileUtils.mkdir_p(File.dirname(dst))

              if relative == File.join('config', 'book.yml')
                rewrite_book_yml(cmd, src, dst, answers, project_name)
              else
                FileUtils.cp(src, dst)
              end

              log_debug(cmd, "コピー: #{relative}")
            end
          rescue Interrupt, SignalException
            # Ctrl+C / SIGTERM: 中途半端なディレクトリを残さない
            cleanup_partial_scaffold(project_name, created_root)
            raise
          rescue StandardError
            # 展開中のその他例外も同様にロールバック
            cleanup_partial_scaffold(project_name, created_root)
            raise
          end

          Common.log_action("プロジェクトファイルを展開しました: #{project_name}/")
        end

        # expand_scaffold の中断時に、今回新規作成した project ディレクトリを削除する
        # @param project_name [String]
        # @param created_root [Boolean] 今回 mkdir_p で新規作成したか
        def cleanup_partial_scaffold(project_name, created_root)
          return unless created_root
          return unless File.directory?(project_name)

          FileUtils.rm_rf(project_name)
          Common.log_warn("中断されたため、部分展開されたディレクトリを削除しました: #{project_name}/")
        rescue StandardError => e
          # クリーンアップ自体が失敗しても元例外は握り潰さない
          Common.log_warn("クリーンアップ中にエラー: #{e.class}: #{e.message}")
        end

        def rewrite_book_yml(cmd, src_path, dest_path, answers, project_name)
          # `{{KEY}}` → 値 の一覧。ブロック形式の gsub を使うことで、
          # 置換値に含まれる `\\` が後方参照（例: `\1`）として解釈されて
          # バックスラッシュが潰れる Ruby gsub の落とし穴を回避する。
          substitutions = {
            '{{MAIN_TITLE}}'   => yaml_escape_double_quoted(answers[:main_title]),
            '{{SUBTITLE}}'     => yaml_escape_double_quoted(answers[:subtitle]),
            '{{AUTHOR}}'       => yaml_escape_double_quoted(answers[:author]),
            '{{PUBLISHER}}'    => yaml_escape_double_quoted(answers[:publisher]),
            '{{PROJECT_NAME}}' => yaml_escape_double_quoted(project_name)
          }
          # 単一パスで全プレースホルダを置換することで、値に別のプレースホルダ文字列が
          # 含まれていても二重展開が起きないようにする（例: author に `{{MAIN_TITLE}}`
          # をペーストしても、書籍名には展開されない）。
          pattern = Regexp.union(substitutions.keys)
          content = File.read(src_path, encoding: 'utf-8').gsub(pattern) { substitutions[it] }

          File.write(dest_path, content, encoding: 'utf-8')
          log_debug(cmd, "book.yml を置換して書き込みました: #{dest_path}")
        end

        # YAML の double-quoted string リテラル内で安全になるよう値をエスケープする。
        # scaffold の book.yml は `"{{PLACEHOLDER}}"` 形式のため、ユーザー入力に
        # `\` `"` `\n` `\r` `\t` が混じっても book.yml を壊さないよう置換する。
        # @param value [String, nil] ユーザー入力
        # @return [String] YAML double-quoted string で安全に埋め込める文字列
        def yaml_escape_double_quoted(value)
          value.to_s.gsub(/[\\"\n\r\t]/) do |c|
            case c
            in "\\" then '\\\\'
            in '"'  then '\\"'
            in "\n" then '\\n'
            in "\r" then '\\r'
            in "\t" then '\\t'
            end
          end
        end

        def run_doctor(cmd, project_name)
          shell_cmd = "cd #{Shellwords.escape(project_name)} && vs doctor --fix"
          log_debug(cmd, "実行: #{shell_cmd}")

          # system の呼び出しを cmd 経由にすることでテスト時のスタブが有効になる
          return if cmd.system(shell_cmd)

          Common.log_warn('vs doctor --fix が失敗しました。')
          Common.log_warn('  手動で以下を実行してください:')
          Common.log_warn("  cd #{project_name} && vs doctor --fix")
        end

        def print_success(project_name)
          Common.log_success("プロジェクト \"#{project_name}\" を作成しました。")
          Common.log_always <<~MSG

            book.yml で書籍の設定を変更できます。
            書き方の参考は contents/ 内のサンプルファイルをご覧ください。

            次のコマンドで執筆を始めましょう！

              cd #{project_name}
              vs build
          MSG
        end
        
        def log_debug(cmd, msg)
          puts "[debug] #{msg}" if cmd&.options&.[](:log) == 'debug'
        end

        def prompt_with_default(label, current)
          print "#{label} [#{current}]: "
          input = $stdin.gets&.strip
          input.nil? || input.empty? ? current : input
        end

        def default_readme_content(name)
          <<~MD
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
        end

        def run_vs_config(dest)
          system({ 'VIVLIO_QUIET' => '1' }, 'vs', 'config', chdir: dest)
        rescue StandardError => e
          warn "[vivlio-starter] vivliostyle 設定生成に失敗しました（継続）: #{e}"
        end

        def synchronize_viv_config(viv_config_path, config_path)
          return unless viv_config_path && File.exist?(viv_config_path)

          cfg = YAML.load_file(config_path)
          cfg = {} unless cfg.is_a?(Hash)
          book_cfg = cfg['book'] || {}

          Vivlio::Starter::Scaffolder.update_vivliostyle_config(
            viv_config_path: viv_config_path,
            book: book_cfg,
            config: cfg
          )
        rescue StandardError => e
          warn "[vivlio-starter] vivliostyle.config.js の同期に失敗しました（継続）: #{e}"
        end
      end
    end
  end
end
