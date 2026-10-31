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
#   - 削除の前の確認（省けない。スクリプトからは答えを標準入力から渡す）
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
require_relative 'index/unified_terms_manager'

module VivlioStarter
  module CLI
    # 章削除コマンドの実装モジュール
    module DeleteCommands
      # 削除実績。表示は呼び出し側（DeleteCommand）の責務とし、ここでは件数を返すだけにする
      # catalog_entries は原稿の無い章の項目だけを数える（原稿のある章の項目は原稿と一緒に外れる）
      DeleteSummary = Data.define(:documents, :image_dirs, :catalog_entries) do
        def self.none = new(documents: 0, image_dirs: 0, catalog_entries: 0)
        def +(other) = DeleteSummary.new(documents: documents + other.documents,
                                         image_dirs: image_dirs + other.image_dirs,
                                         catalog_entries: catalog_entries + other.catalog_entries)
        def none? = documents.zero? && image_dirs.zero? && catalog_entries.zero?
      end

      # delete コマンドの制御フローを担う実行クラス
      #
      # オプション解釈・対象解決・削除処理の各責務を分離し、
      # テスト容易性と保守性を確保している。
      class DeleteCommandExecutor
        # @param options_source [Hash, Object] オプション情報
        #   - Hash: { verbose: false }
        #   - Object: #options メソッドで Hash を返すオブジェクト
        # @param tokens [Array<String>] 削除対象の指定
        #   - 章番号: "11" → 11-*.md にマッチ
        #   - 範囲: "11-13" → 11〜13 番の章すべて
        #   - ファイル名: "11-install" → 11-install.md
        def initialize(options_source, tokens)
          @options = DeleteOptions.new(options_source)
          @resolver = TargetResolver.new(tokens)
          @deletion = ChapterDeletion.new
        end

        # 削除処理を実行する
        #
        # @return [DeleteSummary] 削除した対象の内訳（表示は呼び出し側の責務）
        # @raise [SystemExit] 対象が見つからない場合 exit(1)
        def call
          options.apply_verbose!
          ensure_targets!

          targets.sum(DeleteSummary.none) { |basename| deletion.remove(basename) }
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
        #   - Hash: { verbose: false }
        #   - Object: #options で Hash を返すオブジェクト
        def initialize(source)
          @option_values = extract_option_values(source)
        end

        # verbose オプションが有効な場合、環境変数を設定してログを詳細化する
        def apply_verbose!
          ENV['VERBOSE'] = '1' if verbose?
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
      #   - 索引辞書の main: と scanned_chapters のうち、その章を指すもの
      class ChapterDeletion
        # 章ファイルと関連リソースを削除する
        #
        # @param basename [String] 章ファイル名（例: "11-install.md"）
        # @return [DeleteSummary] 削除した対象の内訳
        #
        # 副作用:
        #   - contents/XX-slug.md を削除
        #   - images/XX-slug/ ディレクトリを削除
        #   - config/catalog.yml から該当エントリを削除（原稿を消したときと、原稿が無い章で許可されたとき）
        #   - 索引辞書からその章を指す主要参照を外す（原稿を消したときだけ）
        def remove(basename)
          base = basename.sub(/\.md\z/, '')
          no_document = !File.exist?(File.join(Common::CONTENTS_DIR, basename))
          documents = delete_markdown_file(basename) ? 1 : 0
          image_dirs = delete_image_directory(basename) ? 1 : 0
          catalog_entries = no_document && delete_catalog_entry(base) ? 1 : 0

          # 目次と辞書は原稿に従う。原稿を残すと答えた章まで目次から外すと、その章は本から黙って消える
          if documents.positive?
            Build::CatalogUpdater.remove_chapter(base)
            # 辞書の main: が消えた章を指したまま残ると、索引の主要参照が黙って消える
            # （改善案.md #108）。vs rename の追随と対になる
            UnifiedTermsManager.new.forget_chapter!(base)
          end

          DeleteSummary.new(documents:, image_dirs:, catalog_entries:)
        end

        private

        # 原稿の無い章の目次の項目を削除する（確認プロンプト付き）
        #
        # これから書く章を目次に先に載せておくこともあるので、原稿が無くても確認なしには外さない
        # @param base [String] 章の basename（拡張子なし）
        # @return [Boolean] 実際に削除したか
        def delete_catalog_entry(base)
          return false unless confirm_deletion?("目次の項目: #{Build::CatalogUpdater::CATALOG_FILE} の #{base}")

          Build::CatalogUpdater.remove_chapter(base)
          true
        end

        # Markdown ファイルを削除する（確認プロンプト付き）
        #
        # @param filename [String] ファイル名
        # @return [Boolean] 実際に削除したか
        def delete_markdown_file(filename)
          md_file = File.join(Common::CONTENTS_DIR, filename)
          return false unless File.exist?(md_file)
          return false unless confirm_deletion?("文書ファイル: #{md_file}")

          File.delete(md_file)
          true
        end

        # 画像ディレクトリを削除する（確認プロンプト付き）
        #
        # @param filename [String] 章ファイル名（拡張子付き）
        # @return [Boolean] 実際に削除したか
        def delete_image_directory(filename)
          base_filename = filename.sub(/\.md\z/, '')
          image_dir = File.join(Common::IMAGES_DIR, base_filename)
          return false unless Dir.exist?(image_dir)
          return false unless confirm_deletion?("画像ディレクトリ: #{image_dir}")

          FileUtils.remove_dir(image_dir, true)
          true
        end

        # ユーザーに削除確認を求める
        #
        # @param label [String] 削除対象の説明（表示用）
        # @return [Boolean] 削除を許可する場合 true
        def confirm_deletion?(label)
          Common.confirm?("本当に #{label} を削除しますか？")
        end
      end
    end
  end
end
