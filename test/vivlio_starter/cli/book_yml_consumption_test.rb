# frozen_string_literal: true

# ================================================================
# Test: book_yml_consumption_test.rb
# ================================================================
# テスト対象:
#   scaffold の config/book.yml（著者に配布される設定ファイル）と
#   lib/vivlio_starter/ 実装コードの突き合わせ
#
# 背景:
#   「新機能の追加時に book.yml へ設定キーを書いたが、実装側は
#   ハードコーディングのままで設定値が消費されていない」という漏れが
#   時折発生していた（例: metrics.labels、vfm.hard_line_breaks、
#   book.isbn、output.epub.layout、index_glossary.use_mecab）。
#   book.yml に載せるキーは必ずコードが消費する、を回帰として固定する。
#
# 検証方法:
#   book.yml の全キーパスを列挙し、各キー名が lib コード中に
#   シンボル（:key）・文字列（'key'/"key"）・ドット記法（.key）の
#   いずれかで出現することを確認する。
#   注意: title や name のような汎用キー名は別文脈でも一致し得るため
#   完全な証明ではないが、固有名のキー（use_mecab 等）の消費漏れは
#   確実に検出できる。動的参照されるキーは ALLOWED_UNREFERENCED に
#   理由つきで登録する。
# ================================================================

require 'test_helper'
require 'yaml'

module VivlioStarter
  module CLI
    # book.yml 設定キーの消費保証テスト
    class BookYmlConsumptionTest < Minitest::Test
      PROJECT_ROOT = File.expand_path('../../..', __dir__)
      SCAFFOLD_BOOK_YML = File.join(PROJECT_ROOT, 'lib/project_scaffold/config/book.yml')
      LIB_GLOB = File.join(PROJECT_ROOT, 'lib/vivlio_starter/**/*.rb')

      # コードから名前で直接参照されない正当な理由があるキー（理由を必ず添える）
      ALLOWED_UNREFERENCED = {
        'metrics.author_custom' => 'metrics.use の値として動的参照される著者定義プリセット名'
      }.freeze

      def test_should_reference_every_book_yml_key_in_lib_code
        # Arrange
        book = YAML.load_file(SCAFFOLD_BOOK_YML, aliases: true)
        sources = Dir.glob(LIB_GLOB).map { File.read(it) }.join("\n")

        # Act
        unconsumed = key_paths(book).reject do |path|
          ALLOWED_UNREFERENCED.key?(path.join('.')) || referenced?(sources, path.last)
        end

        # Assert
        message = <<~MSG
          book.yml に定義されているのにコードから参照されていないキーがあります:
            #{unconsumed.map { it.join('.') }.join("\n  ")}
          設定値は必ず実装が消費してください（ハードコーディングの残留を確認）。
          動的参照など正当な理由がある場合は ALLOWED_UNREFERENCED に理由つきで登録します。
        MSG
        assert_empty unconsumed, message
      end

      # 許可リストの陳腐化防止: 登録キーが参照されるようになったら削除を促す
      def test_should_keep_allowlist_entries_actually_unreferenced
        sources = Dir.glob(LIB_GLOB).map { File.read(it) }.join("\n")

        stale = ALLOWED_UNREFERENCED.keys.select { referenced?(sources, it.split('.').last) }

        assert_empty stale,
                     "ALLOWED_UNREFERENCED のキーがコードから参照されるようになっています。" \
                     "許可リストから削除してください: #{stale.join(', ')}"
      end

      private

      # book.yml のネスト構造を ['section', 'key', ...] のパス配列に展開する
      def key_paths(node, prefix = [])
        return [] unless node.is_a?(Hash)

        node.flat_map do |key, value|
          path = prefix + [key.to_s]
          [path] + key_paths(value, path)
        end
      end

      # キー名がシンボル（:key / key: 省略記法）・文字列リテラル・ドット記法の
      # いずれかで出現するか
      def referenced?(sources, key)
        escaped = Regexp.escape(key)
        sources.match?(/:#{escaped}\b|\b#{escaped}:|['"]#{escaped}['"]|\.#{escaped}\b/)
      end
    end
  end
end
