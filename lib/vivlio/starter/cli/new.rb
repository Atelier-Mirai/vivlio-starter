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
        SCAFFOLD_SOURCE = File.expand_path('../../../../project_scaffold', __FILE__).freeze

        GEM_ROOT = File.expand_path('../../../..', __dir__).freeze

        VALID_NAME_PATTERN = /\A[a-zA-Z0-9_\-]+\z/

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
                Common.echo_always('doctor の自動実行をスキップします (--manual-install)')
              elsif options[:auto_install]
                Common.echo_always('必要ツールの自動インストールを有効にして doctor を実行します (--auto-install)')
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
                  Common.echo_always('後で実行する場合: vs doctor もしくは vs doctor --fix (macOS)')
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

          puts "[vivlio-starter] 完了しました。cd #{name} で移動し、執筆を開始できます。"
          puts '例: vivlio-starter build で執筆した書籍をPDFで作成できます。'
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
            puts "[vivlio-starter] book.yml を更新しました。\n"
          else
            File.open(config_path, 'a:utf-8') do |f|
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

        private

        def validated_project_name!(cmd)
          raw = cmd.name.to_s.strip
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

          puts 'Vivlio Starter へようこそ！新しい書籍プロジェクトを作成します。'
          puts

          answers = {
            main_title: prompt('書籍名を入力してください（例: はじめての Ruby）', DEFAULT_ANSWERS[:main_title]),
            subtitle:   prompt('副題を入力してください（任意。Enter でスキップ）', DEFAULT_ANSWERS[:subtitle]),
            author:     prompt('著者名を入力してください（例: 山田 太郎）', DEFAULT_ANSWERS[:author]),
            publisher:  prompt('発行者・サークル名を入力してください（例: アトリヱ未來）', DEFAULT_ANSWERS[:publisher])
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

          puts
          puts '以下の設定でプロジェクトを作成します。'
          puts
          puts "  プロジェクト名: #{project_name}"
          puts "  書籍名:         #{answers[:main_title]}"
          puts "  副題:           #{subtitle_display}"
          puts "  著者:           #{author_display}"
          puts "  発行者:         #{publisher_display}"
          puts
          $stdout.print('よろしいですか？ [Y/n]: ')
          $stdout.flush
          input = $stdin.gets&.strip || ''

          return unless input.downcase == 'n'

          puts "中断しました。もう一度 vs new #{project_name} を実行してください。"
          exit 0
        end

        def expand_scaffold(cmd, project_name, answers)
          FileUtils.mkdir_p(project_name)

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

          Common.log_action("プロジェクトファイルを展開しました: #{project_name}/")
        end

        def rewrite_book_yml(cmd, src_path, dest_path, answers, project_name)
          content = File.read(src_path, encoding: 'utf-8')
            .gsub('{{MAIN_TITLE}}',   answers[:main_title])
            .gsub('{{SUBTITLE}}',     answers[:subtitle])
            .gsub('{{AUTHOR}}',       answers[:author])
            .gsub('{{PUBLISHER}}',    answers[:publisher])
            .gsub('{{PROJECT_NAME}}', project_name)
          File.write(dest_path, content, encoding: 'utf-8')
          log_debug(cmd, "book.yml を置換して書き込みました: #{dest_path}")
        end

        def run_doctor(cmd, project_name)
          shell_cmd = "cd #{Shellwords.escape(project_name)} && vs doctor --fix"
          log_debug(cmd, "実行: #{shell_cmd}")

          # system の呼び出しを cmd 経由にすることでテスト時のスタブが有効になる
          return if cmd.system(shell_cmd)

          warn '⚠️ 警告: vs doctor --fix が失敗しました。'
          warn '  手動で以下を実行してください:'
          warn "  cd #{project_name} && vs doctor --fix"
        end

        def print_success(project_name)
          puts
          Common.log_success("プロジェクト \"#{project_name}\" を作成しました。")
          puts
          puts 'book.yml で書籍の設定を変更できます。'
          puts '書き方の参考は contents/ 内のサンプルファイルをご覧ください。'
          puts
          puts '次のコマンドで執筆を始めましょう！'
          puts
          puts "  cd #{project_name}"
          puts '  vs build'
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
