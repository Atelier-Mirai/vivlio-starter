# frozen_string_literal: true

# ================================================================
# robustness: macOS 日本語ファイル名の Unicode 正規化（NFD/NFC）
# ================================================================
# docs/specs/test-suite-expansion-spec.md §9
#
# 検証内容:
#   NF-01: NFD 名の章ファイルを NFC トークンで指定 → 同一章として解決できる
#   NF-02: NFD 名の章ファイル + NFC 記載の catalog → 孤立ファイル扱いしない
#   NF-03: 逆方向（NFC ファイル + NFD 記載）でも同様
#
# 背景:
#   macOS（HFS+ / 旧来の保存）では濁点・半濁点付きファイル名が NFD で
#   保持されることがあり、原稿・catalog 中の NFC 表記と「文字列としては」
#   一致しなくなる。File.exist? は macOS が正規化を吸収するため通るが、
#   Dir.glob の結果と文字列比較する経路（孤立判定・カタログ照合）は
#   正規化差で誤判定し得る。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class NfdFilenameTest < Minitest::Test
      NFC_BASENAME = "11-ガイド".unicode_normalize(:nfc).freeze
      NFD_BASENAME = "11-ガイド".unicode_normalize(:nfd).freeze

      # NF-01: NFD 名で保存された章ファイルを NFC トークンで解決できる
      def test_should_resolve_nfc_token_to_nfd_named_file
        with_temp_project(file_basename: NFD_BASENAME, catalog_basename: NFC_BASENAME) do
          entries = TokenResolver::Resolver.new.resolve([NFC_BASENAME])

          assert_equal 1, entries.size
          assert entries.first.exists?,
                 'NFC トークンから NFD 名の実ファイルへ解決できるべき（正規化差を吸収する）'
        end
      end

      # NF-02: NFD 名のファイルが NFC 記載の catalog にあるなら、孤立扱いしない
      def test_should_not_flag_nfd_file_as_orphan_when_cataloged_in_nfc
        with_temp_project(file_basename: NFD_BASENAME, catalog_basename: NFC_BASENAME) do
          violations = Guards::OrphanFileCheck.new.validate

          assert_empty violations,
                       '正規化差しかないファイルを孤立ファイルとして警告すべきではない'
        end
      end

      # NF-03: 逆方向（NFC ファイル + NFD 記載の catalog）でも欠落扱いしない
      def test_should_not_flag_nfc_file_as_missing_when_cataloged_in_nfd
        with_temp_project(file_basename: NFC_BASENAME, catalog_basename: NFD_BASENAME) do
          violations = Guards::CatalogEntriesCheck.new.validate

          assert_empty violations,
                       '正規化差しかないファイルを欠落として扱うべきではない'
        end
      end

      private

      def with_temp_project(file_basename:, catalog_basename:, &)
        Dir.mktmpdir('vs-nfd') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write("contents/#{file_basename}.md", "# guide\n")
            File.write('config/catalog.yml',
                       "PREFACE:\nCHAPTERS:\n  - #{catalog_basename}\nAPPENDICES:\nPOSTFACE:\n")
            yield
          end
        end
      end
    end
  end
end
