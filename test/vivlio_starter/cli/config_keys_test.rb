# frozen_string_literal: true

# ================================================================
# Test: config_keys_test.rb
# ================================================================
# テスト対象:
#   ConfigKeys::KEYS（lib/vivlio_starter/cli/config_keys.rb）
#
# 背景:
#   既定値の宣言を 1 表へ寄せる前は、同じ値が book.yml・既定値スキーマ・
#   ドメイン定数・読み出し地点のリテラルに散っていた。結果として book.yml と
#   コードで値が食い違い、著者がキーを消した瞬間だけ誰も宣言していない値で動く、
#   という状態が 7 件あった（heading_chars 10 対 8 など）。
#   仕様: config-defaults-design-spec.md
#
# **このテストが本体である。** 宣言を 1 箇所にしただけでは食い違いは再発する——
# 著者が見る book.yml と表の default: がずれていないことを機械が見張って初めて、
# 「book.yml が正典」が成立する。
#
# 検証方法:
#   配布物（lib/project_scaffold/config/book.yml）を正とする。著者が vs new で
#   受け取り、実際に目にするのはこちらだから。リポジトリ直下の config/book.yml は
#   この本自身の編集判断なので比較しない。
# ================================================================

require 'test_helper'
require 'yaml'
require 'vivlio_starter/cli/config_keys'

module VivlioStarter
  module CLI
    class ConfigKeysTest < Minitest::Test
      SCAFFOLD_BOOK_YML = File.expand_path('../../../lib/project_scaffold/config/book.yml', __dir__)

      # vs new が {{ }} を著者の回答で置き換えるキー。値の比較対象にしない。
      PLACEHOLDER = /\A\{\{.+\}\}\z/

      def setup
        skip "scaffold の book.yml が見つかりません: #{SCAFFOLD_BOOK_YML}" unless File.exist?(SCAFFOLD_BOOK_YML)
      end

      # 表に宣言が無いキーが book.yml にあると、著者が設定しても既定値が無い状態になる
      def test_every_scaffold_key_is_declared
        missing = scaffold_leaves.keys - ConfigKeys::KEYS.keys

        assert_empty missing.map { it.join('.') },
                     'scaffold の book.yml にあるが ConfigKeys::KEYS に宣言が無いキー'
      end

      # 表にあって book.yml に無いキーは、著者から見えない設定になる
      # （見せたくないなら設定にせず定数にする——config-key-criteria-guidelines.md）
      def test_every_declared_key_is_in_scaffold
        extra = ConfigKeys::KEYS.keys - scaffold_leaves.keys

        assert_empty extra.map { it.join('.') },
                     'ConfigKeys::KEYS にあるが scaffold の book.yml に無いキー'
      end

      # 既定値が book.yml の値と一致すること。**これが再発防止の本体。**
      def test_defaults_match_scaffold_values
        mismatches = ConfigKeys::KEYS.filter_map do |path, spec|
          next if spec.authored?

          actual = scaffold_leaves[path]
          next if actual.to_s.match?(PLACEHOLDER)
          next if spec.default == actual

          "#{path.join('.')}: 表 #{spec.default.inspect} / book.yml #{actual.inspect}"
        end

        assert_empty mismatches, "既定値が config/book.yml と食い違っています\n  #{mismatches.join("\n  ")}"
      end

      # 廃止キーは book.yml から消えていること（残っていると案内と実物が矛盾する）
      def test_retired_keys_are_absent_from_scaffold
        still_present = ConfigKeys::RETIRED.keys.select { scaffold_leaves.key?(it) }

        assert_empty still_present.map { it.join('.') },
                     '廃止したのに scaffold の book.yml に残っているキー'
      end

      # authored: と retired: は排他。両方与えると、どちらとして扱うかが読む側で分かれる。
      #
      # default: は数に入れない——`nil` が正当な既定値だから
      # （spellcheck.extra_dictionaries は「追加辞書なし」を nil で表す）。
      # Spec[] と Spec[default: nil] は同一オブジェクトなので、そもそも区別できない。
      # したがって「authored でも retired でもないキー」＝既定値キー、と読む。
      def test_authored_and_retired_are_exclusive
        ambiguous = ConfigKeys::ALL.select { |_, spec| spec.authored? && spec.retired? }

        assert_empty ambiguous.keys.map { it.join('.') },
                     'authored: と retired: は同時に与えられない'
      end

      # 廃止キーに既定値を与えると「読まないのに値がある」という矛盾になる
      def test_retired_keys_have_no_default
        with_default = ConfigKeys::RETIRED.select { |_, spec| !spec.default.nil? }

        assert_empty with_default.keys.map { it.join('.') },
                     '廃止キーは読まないので default: を持たない'
      end

      # 打ち間違いは Data が即座に落とす（ハッシュリテラルだと静かに通ってしまう）
      def test_spec_rejects_unknown_keyword
        assert_raises(ArgumentError) { ConfigKeys::Spec[defualt: 500] }
      end

      private

      # scaffold の book.yml を { [:a, :b] => 値 } に平坦化する
      def scaffold_leaves
        @scaffold_leaves ||= begin
          raw = YAML.safe_load_file(SCAFFOLD_BOOK_YML, aliases: true, permitted_classes: [Date])
          flatten_leaves(raw)
        end
      end

      def flatten_leaves(node, prefix = [], into = {})
        node.each do |key, value|
          path = prefix + [key.to_sym]
          value.is_a?(Hash) ? flatten_leaves(value, path, into) : into[path] = value
        end
        into
      end
    end
  end
end
