# frozen_string_literal: true

# ================================================================
# robustness: catalog.yml に登録されているが contents/ にファイルがない
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 1-2-1 (L68): catalog.yml に登録されているが contents/ にファイルがない
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動:
#   該当章は Entry.exists=false → build で警告し成果物から除外、**全体は成功**。
#
# 検証レイヤー:
#   1. TokenResolver::Resolver — Entry.exists=false かつ in_catalog=true で返る
#   2. Build::CatalogLoader#load_existing_basenames — missing を warn で通知し除外
#   3. Lint::TargetResolver — missing を warn で通知し existing のみ返す
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/build/catalog_loader'

module VivlioStarter
  module CLI
    class CatalogMissingFileTest < Minitest::Test
      # ----------------------------------------------------------------
      # Layer 1: TokenResolver::Resolver
      # ----------------------------------------------------------------

      # 存在しないファイルでも catalog に登録されていれば Entry として返る。
      # exists=false, in_catalog=true というフラグの組合せが仕様の要。
      def test_resolver_returns_entry_with_exists_false_for_missing_content
        within_fixture(catalog_entries: %w[11-chapter_a 12-missing_chapter],
                       existing_files: %w[11-chapter_a.md]) do |paths|
          resolver = TokenResolver::Resolver.new(
            catalog_path: paths[:catalog],
            contents_dir: paths[:contents]
          )
          entries = resolver.resolve([])

          assert_equal 2, entries.size, '欠落ファイルも Entry として返る'

          existing = entries.find { it.basename == '11-chapter_a' }
          refute_nil existing
          assert_predicate existing, :in_catalog?
          assert_predicate existing, :exists?, '存在する章は exists? が true'

          missing = entries.find { it.basename == '12-missing_chapter' }
          refute_nil missing
          assert_predicate missing, :in_catalog?, 'catalog 由来の章は in_catalog? が true'
          refute_predicate missing, :exists?,      '欠落ファイルの章は exists? が false'
          assert_predicate missing, :valid?,        '形式は valid'
        end
      end

      # 単章指定（token あり）でも catalog にあって contents/ にないケースで
      # 同じ Entry が返る
      def test_resolver_returns_same_entry_when_token_targets_missing_file
        within_fixture(catalog_entries: %w[12-missing_chapter], existing_files: []) do |paths|
          resolver = TokenResolver::Resolver.new(
            catalog_path: paths[:catalog],
            contents_dir: paths[:contents]
          )
          entries = resolver.resolve(['12'])

          assert_equal 1, entries.size
          assert_equal '12-missing_chapter', entries.first.basename
          assert_predicate entries.first, :in_catalog?
          refute_predicate entries.first, :exists?
        end
      end

      # ----------------------------------------------------------------
      # Layer 2: Build::CatalogLoader
      # ----------------------------------------------------------------

      # load_existing_basenames は missing を警告出力して除外する
      def test_catalog_loader_warns_and_filters_missing_files
        within_fixture(catalog_entries: %w[11-chapter_a 12-missing_chapter 13-chapter_c],
                       existing_files: %w[11-chapter_a.md 13-chapter_c.md]) do |paths|
          Dir.chdir(paths[:root]) do
            captured_warnings = capture_stdout do
              existing = Build::CatalogLoader.load_existing_basenames
              assert_equal %w[11-chapter_a 13-chapter_c], existing.sort,
                           '欠落章は basename 配列から除外されるべき'
            end

            assert(captured_warnings.any? { it.include?('12-missing_chapter') },
                   '欠落章名を含む警告が出るべき')
            assert(captured_warnings.any? { it.include?('存在しません') },
                   '警告メッセージに missing file への言及があるべき')
            refute(captured_warnings.any? { it.include?('11-chapter_a') && it.include?('存在しません') },
                   '存在する章を missing 警告に含めてはならない')
          end
        end
      end

      # 空 catalog は StandardError を送出する（仕様どおり）
      def test_catalog_loader_raises_when_catalog_is_empty
        within_fixture(catalog_entries: [], existing_files: []) do |paths|
          Dir.chdir(paths[:root]) do
            err = assert_raises(StandardError) { Build::CatalogLoader.load_existing_basenames }
            assert_match(/ビルド対象の章がありません/, err.message)
          end
        end
      end

      private

      # 一時プロジェクトを作って catalog.yml と contents/*.md を配置する。
      # @param catalog_entries [Array<String>] catalog に書き込む章 basename（拡張子なし）
      # @param existing_files  [Array<String>] contents/ に実際に作るファイル名
      # @yieldparam paths [Hash] { root:, catalog:, contents: } 絶対パス
      def within_fixture(catalog_entries:, existing_files:)
        Dir.mktmpdir('vs-robustness-catalog-') do |root|
          contents = File.join(root, 'contents')
          config   = File.join(root, 'config')
          FileUtils.mkdir_p([contents, config])

          catalog_path = File.join(config, 'catalog.yml')
          File.write(catalog_path, build_catalog_yaml(catalog_entries), encoding: 'utf-8')

          existing_files.each do |name|
            File.write(File.join(contents, name),
                       "---\ntitle: test\n---\n\n# dummy\n", encoding: 'utf-8')
          end

          yield(root: root, catalog: catalog_path, contents: contents)
        end
      end

      def build_catalog_yaml(entries)
        return "CHAPTERS: []\n" if entries.empty?

        lines = ['CHAPTERS:']
        entries.each { |e| lines << "  - #{e}" }
        "#{lines.join("\n")}\n"
      end

      # Common.log_warn は stdout に puts するため stdout を捕捉する。
      def capture_stdout
        original_stdout = $stdout
        captured = StringIO.new
        $stdout = captured
        yield
        captured.string.lines.map(&:chomp)
      ensure
        $stdout = original_stdout
      end
    end
  end
end
