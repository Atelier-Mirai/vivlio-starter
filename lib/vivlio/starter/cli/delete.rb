# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: delete（章の削除ユーティリティ）
      # ------------------------------------------------
      # - 目的: 指定章の Markdown・画像ディレクトリを削除
      # - 提供コマンド: delete
      # - 補足: 確認プロンプト、dry-run対応、force指定に対応
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module DeleteCommands
        module_function

        DELETE_DESC = {
          short: '指定した章を削除します (Thor)',
          long: <<~DESC
            指定した章（単体/複数/範囲）に対して、Markdown と画像ディレクトリを削除します。

            例:
              vs delete 11-install
              vs delete 11-install.md 12-tutorial
              vs delete 11-21
              vs delete 11 21-31

            オプション:
              --dry-run, -n   実行せずに削除予定のみを表示します（削除の試行）
              --force, -f, -y 確認プロンプト無しで削除を実行します
              --verbose, -v   冗長ログを表示します

            備考:
              ・ユーザー利便性のため、オプションは引数の前後どちらに置いても構いません
                例: vs delete --force 31-33 / vs delete 31-33 --force
              ・--dry-run と --force を同時指定した場合、--dry-run を優先し --force は無視されます
          DESC
        }.freeze

        # Thor 基底クラスに delete コマンドを登録する
        def included(base)
          # class_option はベース側に定義済み（verbose）
          base.class_eval do
            # delete 本体
            desc 'delete TOKENS...', DELETE_DESC[:short]
            long_desc DELETE_DESC[:long]

            method_option :dry_run, type: :boolean, aliases: '-n', desc: '変更せずに削除予定を表示'
            method_option :force,   type: :boolean, aliases: %w[-f -y], desc: '確認なしで削除'
            # ================================================================
            # Command: delete（章の削除）
            # ------------------------------------------------
            # - 概要: 指定章の文書/画像/CSS を削除
            # - 入力: TOKENS（単体/複数/範囲指定に対応: 11-install, 11-21, 11 21-31 など）
            # - オプション: --dry-run (-n), --force (-f, -y), --verbose (-v)
            # ================================================================
            # delete コマンドのエントリポイント
            def delete(*tokens)
              DeleteCommandExecutor.new(self, tokens).call
            end
          end
        end

        # 実行時のオプション解釈・対象解決・削除処理をまとめる実行クラス
        class DeleteCommandExecutor
          # コマンドとトークンから削除処理に必要な依存を構築する
          def initialize(command, tokens)
            @options = DeleteOptions.new(command)
            @resolver = TargetResolver.new(tokens)
            @deletion = ChapterDeletion.new(@options)
          end

          # delete コマンドの実際の制御フローを実行する
          def call
            options.apply_verbose!
            options.warn_conflict!
            ensure_targets!
            return perform_dry_run if options.dry_run?

            targets.each { |basename| deletion.remove(basename) }
          end

          private

          attr_reader :options, :resolver, :deletion

          # 削除対象が存在しない場合は警告して終了する
          def ensure_targets!
            return unless targets.empty?

            Common.log_warn("指定に一致する章ファイルが見つかりませんでした: #{resolver.tokens_for_message}")
            exit 1
          end

          # dry-run 時に削除予定をダンプ表示する
          def perform_dry_run
            Common.echo_always "\n== Dry Run: 削除予定一覧 =="
            targets.each { |basename| deletion.preview(basename) }
            Common.echo_always "\n合計 #{targets.size} 章が対象（dry-run、実ファイルは変更されません）。"
            exit 0
          end

          # 解決済みの削除対象リストを返す
          def targets
            resolver.targets
          end
        end

        # Thor オプションを CLI 用オプションに正規化
        class DeleteOptions
          # Thor のオプションハッシュを保持する
          def initialize(command)
            @thor_options = command.respond_to?(:options) ? command.options || {} : {}
          end

          # verbose オプションがある場合に冗長ログを有効にする
          def apply_verbose!
            ENV['VERBOSE'] = '1' if verbose?
          end

          # dry-run と force の同時指定時に警告を出力する
          def warn_conflict!
            return unless dry_run? && force?

            Common.log_warn('--dry-run が指定されているため、--force は無視されます。実ファイルは変更されません。')
          end

          # dry-run オプションの有無を返す
          def dry_run?
            !!thor_options[:dry_run]
          end

          # force オプションの有無を返す
          def force?
            !!thor_options[:force]
          end

          # verbose オプションの有無を返す
          def verbose?
            !!thor_options[:verbose]
          end

          private

          attr_reader :thor_options
        end

        # トークンから削除対象章ファイルを決定
        class TargetResolver
          # ユーザー入力されたトークン情報を受け取る
          def initialize(tokens)
            @tokens = tokens
          end

          # ログ出力用に正規化済みトークンを結合して返す
          def tokens_for_message
            normalized_tokens.join(' ')
          end

          # 削除対象となる章ファイル名の一覧を返す
          def targets
            @targets ||= expand_tokens_to_targets(normalized_tokens)
          end

          private

          attr_reader :tokens

          # トークンを正規化（拡張子付与など）する
          def normalized_tokens
            @normalized_tokens ||= Common.normalize_tokens(tokens)
          end

          # トークン列から削除対象のファイル名配列を生成する
          def expand_tokens_to_targets(values)
            Array(values).compact.flat_map { |token| expand_token_to_basenames(token) }.uniq
          end

          # 単一トークンから対応する章ファイル名リストを求める
          def expand_token_to_basenames(token)
            stripped = token.to_s.strip
            return [] if stripped.empty?

            if stripped =~ /(\A\d+)-(\d+\z)/
              return find_basenames_in_range(::Regexp.last_match(1), ::Regexp.last_match(2))
            end

            if stripped =~ /\A\d+\z/
              return list_contents_basenames.select { |basename| basename.start_with?("#{stripped}-") }
            end

            name = "#{stripped}.md"
            path = File.join(Common::CONTENTS_DIR, name)
            File.exist?(path) ? [name] : []
          end

          # contents ディレクトリ内の章ファイル名一覧を取得する
          def list_contents_basenames
            Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |path| File.basename(path) }
          end

          # 数値範囲指定トークンから該当する章ファイル名を抽出する
          def find_basenames_in_range(from_num, to_num)
            lower, upper = [from_num.to_i, to_num.to_i].minmax
            list_contents_basenames.select do |basename|
              basename[/^(\d+)-/, 1]&.to_i&.between?(lower, upper)
            end
          end
        end

        # 章ファイルと関連ディレクトリの削除処理
        class ChapterDeletion
          # 削除時に参照するオプションを受け取る
          def initialize(options)
            @options = options
          end

          # dry-run 時に対象ファイル・ディレクトリを表示する
          def preview(basename)
            base = basename.sub(/\.md\z/, '')
            md_file = File.join(Common::CONTENTS_DIR, basename)
            img_dir = File.join(Common::IMAGES_DIR, base)
            Common.echo_always "[DRY-RUN] #{base} の削除予定:"
            Common.echo_always "  - 文書:       #{md_file} #{File.exist?(md_file) ? '(exists)' : '(not found)'}"
            Common.echo_always "  - 画像Dir:    #{img_dir} #{Dir.exist?(img_dir) ? '(exists)' : '(not found)'}"
          end

          # 指定された章ファイルと画像ディレクトリを削除する
          def remove(basename)
            delete_markdown_file(basename)
            delete_image_directory(basename)
          end

          private

          attr_reader :options

          # Markdown ファイル削除とログ出力を行う
          def delete_markdown_file(filename)
            md_file = File.join(Common::CONTENTS_DIR, filename)
            unless File.exist?(md_file)
              Common.log_info("文書ファイルは存在しません: #{md_file}")
              return
            end

            if confirm_deletion?("文書ファイル: #{md_file}")
              File.delete(md_file)
              Common.log_success("文書ファイルを削除しました: #{md_file}")
            else
              Common.log_info("文書ファイルの削除をスキップしました: #{md_file}")
            end
          end

          # 対応する画像ディレクトリの削除とログ出力を行う
          def delete_image_directory(filename)
            base_filename = filename.sub(/\.md\z/, '')
            image_dir = File.join(Common::IMAGES_DIR, base_filename)
            unless Dir.exist?(image_dir)
              Common.log_info("画像ディレクトリは存在しません: #{image_dir}")
              return
            end

            if confirm_deletion?("画像ディレクトリ: #{image_dir}")
              FileUtils.remove_dir(image_dir, true)
              Common.log_success("画像ディレクトリを削除しました: #{image_dir}")
            else
              Common.log_info("画像ディレクトリの削除をスキップしました: #{image_dir}")
            end
          end

          # ユーザーに削除確認を求め、許可された場合のみ実行する
          def confirm_deletion?(label)
            return true if options.force?

            print "⚠️ 本当に #{label} を削除しますか？ (y/N): "
            response = $stdin.gets&.chomp&.downcase
            %w[y yes].include?(response)
          end
        end
      end
    end
  end
end
