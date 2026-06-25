# frozen_string_literal: true

# 新規書籍プロジェクトの雛形作成（`vs new` のドメイン層）。
# Samovar の `NewCommand` は本モジュールのみを参照する。

require 'shellwords'
require 'yaml'
require 'fileutils'

module VivlioStarter
  module CLI
    module NewCommands
      extend self

      # `lib/project_scaffold/` への絶対パス（`cli/new.rb` 基準）
      SCAFFOLD_SOURCE = File.expand_path('../../project_scaffold', __dir__).freeze

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
        return if cmd.options[:add_missing]

        Common.log_error("エラー: ディレクトリ \"#{project_name}\" はすでに存在します。")
        Common.log_error('既存ディレクトリに不足ファイルだけを追加する場合は --add-missing オプションを指定してください（既存ファイルは保持されます）。')
        Common.log_error("  vs new #{project_name} --add-missing")
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
          main_title: prompt('書籍名を入力してください（例: はじめての技術書づくり）', DEFAULT_ANSWERS[:main_title]),
          subtitle: prompt('副題を入力してください（任意。Enter でスキップ）', DEFAULT_ANSWERS[:subtitle]),
          author: prompt('著者名を入力してください（原稿を書いた人。例: 早乙女 遙香）', DEFAULT_ANSWERS[:author]),
          publisher: prompt('発行者・サークル名を入力してください（本を世に出す主体。お一人なら著者と同じでも可。例: アトリヱ未來）', DEFAULT_ANSWERS[:publisher])
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
        # `--add-missing` で既存ディレクトリに重ねる場合は、部分破壊を避けるため保持する。
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
    end
  end
end
