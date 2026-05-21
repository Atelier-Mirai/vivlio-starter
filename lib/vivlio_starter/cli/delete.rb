# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/delete.rb
# ================================================================
# 責務:
#   指定された章ファイル（Markdown）と関連リソース（画像ディレクトリ）を
#   削除するコマンドを提供する。
#
# 機能:
#   - 章番号・範囲・ファイル名による削除対象の指定
#   - --force による確認プロンプトのスキップ
#   - config/catalog.yml からの章エントリ自動削除
#
# 削除対象:
#   - contents/XX-slug.md（章 Markdown ファイル）
#   - images/XX-slug/（章に対応する画像ディレクトリ）
#   - config/catalog.yml 内の該当エントリ
#
# 依存:
#   - Common: ログ出力・パス定数
#   - Build::CatalogUpdater: catalog.yml からの章削除
# ================================================================

require 'fileutils'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'token_resolver'

module VivlioStarter
  module CLI
    # 章削除コマンドの実装モジュール
    module DeleteCommands
      # delete コマンドの制御フローを担う実行クラス
      #
      # オプション解釈・対象解決・削除処理の各責務を分離し、
      # テスト容易性と保守性を確保している。
      class DeleteCommandExecutor
        # @param options_source [Hash, Object] オプション情報
        #   - Hash: { force: true, verbose: false }
        #   - Object: #options メソッドで Hash を返すオブジェクト
        # @param tokens [Array<String>] 削除対象の指定
        #   - 章番号: "11" → 11-*.md にマッチ
        #   - 範囲: "11-13" → 11〜13 番の章すべて
        #   - ファイル名: "11-install" → 11-install.md
        def initialize(options_source, tokens)
          @options = DeleteOptions.new(options_source)
          @resolver = TargetResolver.new(tokens)
          @deletion = ChapterDeletion.new(@options)
        end

        # 削除処理を実行する
        #
        # @return [void]
        # @raise [SystemExit] 対象が見つからない場合 exit(1)
        def call
          options.apply_verbose!
          ensure_targets!

          targets.each { |basename| deletion.remove(basename) }
        end

        private

        attr_reader :options, :resolver, :deletion

        # 削除対象が空の場合、警告を出力して終了する
        # CI/CD での検知を可能にするため exit(1) で異常終了
        def ensure_targets!
          return unless targets.empty?

          Common.log_warn("指定に一致する章ファイルが見つかりませんでした: #{resolver.tokens_for_message}")
          exit 1
        end

        # dry-run モード: 削除予定を表示して正常終了
        # 実ファイルは変更されないことを明示
        def perform_dry_run
          Common.log_always "\n== Dry Run: 削除予定一覧 =="
          targets.each { |basename| deletion.preview(basename) }
          Common.log_always "\n合計 #{targets.size} 章が対象（dry-run、実ファイルは変更されません）。"
          exit 0
        end

        # @return [Array<String>] 削除対象のファイル名リスト
        def targets
          resolver.targets
        end
      end

      # CLI オプションを正規化し、各種フラグへのアクセスを提供する
      #
      # 異なる形式のオプション入力（Hash / Samovar コマンド）を
      # 統一的なインターフェースで扱えるようにする
      class DeleteOptions
        # @param source [Hash, Object] オプションソース
        #   - Hash: { force: true, dry_run: false }
        #   - Object: #options で Hash を返すオブジェクト
        def initialize(source)
          @option_values = extract_option_values(source)
        end

        # verbose オプションが有効な場合、環境変数を設定してログを詳細化する
        def apply_verbose!
          ENV['VERBOSE'] = '1' if verbose?
        end

        # dry-run と force の同時指定は矛盾するため警告を出力する
        # dry-run が優先され、force は無視される
        def warn_conflict!
          return unless dry_run? && force?

          Common.log_warn('--dry-run が指定されているため、--force は無視されます。実ファイルは変更されません。')
        end

        # @return [Boolean] dry-run モードが有効か
        def dry_run?
          !!option_values[:dry_run]
        end

        # @return [Boolean] force モードが有効か（--yes も同義）
        def force?
          !!(option_values[:force] || option_values[:yes])
        end

        # @return [Boolean] verbose モードが有効か
        def verbose?
          !!option_values[:verbose]
        end

        private

        attr_reader :option_values

        # オプションソースから Hash を抽出する
        # @param source [Hash, Object] オプションソース
        # @return [Hash] オプション Hash
        def extract_option_values(source)
          if source.respond_to?(:options)
            source.options || {}
          elsif source.is_a?(Hash)
            source
          else
            {}
          end
        end
      end

      # ユーザー入力トークンから削除対象の章ファイルを解決する
      #
      # TokenResolver を使用してトークンを Entry に変換し、
      # カタログまたはファイルシステム上に存在する章を対象とする。
      class TargetResolver
        # @param tokens [Array<String>] ユーザー入力のトークンリスト
        def initialize(tokens)
          @tokens = tokens
          @resolver = TokenResolver::Resolver.new
        end

        # ログ出力用にトークンを空白区切りで結合する
        # @return [String] 表示用トークン文字列
        def tokens_for_message
          resolved_entries.map(&:basename).join(' ')
        end

        # 削除対象として解決された章ファイル名の一覧を返す
        # @return [Array<String>] ファイル名リスト（例: ["11-install.md", "12-setup.md"]）
        def targets
          @targets ||= resolved_entries
                       .select { |e| e.in_catalog? || e.exists? }
                       .map { |e| "#{e.basename}.md" }
                       .uniq
        end

        private

        attr_reader :tokens, :resolver

        # TokenResolver で解決された Entry 配列を返す
        def resolved_entries
          @resolved_entries ||= resolver.resolve(tokens)
        end
      end

      # 章ファイルと関連リソースの削除処理を担う
      #
      # 削除対象:
      #   - contents/XX-slug.md（章 Markdown）
      #   - images/XX-slug/（章画像ディレクトリ）
      #   - config/catalog.yml 内の該当エントリ
      class ChapterDeletion
        # @param options [DeleteOptions] 削除オプション（force 判定などに使用）
        def initialize(options)
          @options = options
        end

        # dry-run モード用: 削除予定を表示する（実際の削除は行わない）
        #
        # @param basename [String] 章ファイル名（例: "11-install.md"）
        # @return [void]
        def preview(basename)
          base = basename.sub(/\.md\z/, '')
          md_file = File.join(Common::CONTENTS_DIR, basename)
          img_dir = File.join(Common::IMAGES_DIR, base)
          Common.log_always "[DRY-RUN] #{base} の削除予定:"
          Common.log_always "  - 文書:       #{md_file} #{File.exist?(md_file) ? '(exists)' : '(not found)'}"
          Common.log_always "  - 画像Dir:    #{img_dir} #{Dir.exist?(img_dir) ? '(exists)' : '(not found)'}"
        end

        # 章ファイルと関連リソースを削除する
        #
        # @param basename [String] 章ファイル名（例: "11-install.md"）
        # @return [void]
        #
        # 副作用:
        #   - contents/XX-slug.md を削除
        #   - images/XX-slug/ ディレクトリを削除
        #   - config/catalog.yml から該当エントリを削除
        def remove(basename)
          delete_markdown_file(basename)
          delete_image_directory(basename)

          # catalog.yml からも削除することで build 時に含まれなくなる
          base = basename.sub(/\.md\z/, '')
          Build::CatalogUpdater.remove_chapter(base)
        end

        private

        attr_reader :options

        # Markdown ファイルを削除する（確認プロンプト付き）
        #
        # @param filename [String] ファイル名
        # @return [void]
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

        # 画像ディレクトリを削除する（確認プロンプト付き）
        #
        # @param filename [String] 章ファイル名（拡張子付き）
        # @return [void]
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

        # ユーザーに削除確認を求める
        #
        # @param label [String] 削除対象の説明（表示用）
        # @return [Boolean] 削除を許可する場合 true
        #
        # --force オプションが有効な場合は確認をスキップして true を返す
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
