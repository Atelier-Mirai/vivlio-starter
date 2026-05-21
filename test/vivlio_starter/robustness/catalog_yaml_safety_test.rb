# frozen_string_literal: true

# ================================================================
# robustness: catalog.yml の YAML anchors/aliases / 不許可クラス悪用
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 9-7 (L287): catalog.yml の YAML 文字列に
#                 YAML anchors/aliases を悪用
#                 → safe_load + aliases: true のため DoS は起きにくいが、
#                   permitted_classes が限定的かを再確認
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 検証観点:
#   A. !ruby/object:Object を含む catalog は Psych::DisallowedClass を捕捉して
#      ユーザー向けメッセージ付き StandardError を raise する
#   B. !ruby/symbol :foo も同様に拒否される（permitted_classes: [] のため）
#   C. 正常な anchor/alias (&ref / *ref) は問題なく展開される
#   D. ネストされた anchor/alias も正常に展開される（DoS 耐性の確認）
#   E. safe_load で読み込んだオブジェクトに Ruby インスタンスが一切含まれない
#      （全て Hash / Array / String / Integer / Float / Boolean / nil のいずれか）
#   F. Psych::SyntaxError（無効な YAML 構文）は引き続き明示的なメッセージになる
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/catalog_loader'

module VivlioStarter
  module CLI
    module Build
      class CatalogYamlSafetyTest < Minitest::Test
        Loader = CatalogLoader

        # プリミティブ以外が混入していないか再帰的に検査する
        SAFE_PRIMITIVES = [Hash, Array, String, Integer, Float, TrueClass, FalseClass, NilClass].freeze

        def setup
          @original_pwd = Dir.pwd
          @tmpdir = Dir.mktmpdir('catalog-yaml-safety-')
          Dir.chdir(@tmpdir)
          FileUtils.mkdir_p('config')
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
        end

        # ----------------------------------------------------------------
        # A. !ruby/object を含む catalog.yml は拒否される
        # ----------------------------------------------------------------
        def test_rejects_ruby_object_tags
          File.write('config/catalog.yml', <<~YAML)
            CHAPTERS:
              - !ruby/object:Object {}
          YAML

          error = assert_raises(StandardError) { Loader.load_catalog }
          msg = error.message
          assert_includes msg, '許可されていないクラス/タグ',
                          'ユーザー向けの説明メッセージを含むこと'
          assert_includes msg, '!ruby/object',
                          '具体的な禁止例が示されていること'
        end

        # ----------------------------------------------------------------
        # B. !ruby/symbol も拒否される（permitted_classes: [] のため）
        # ----------------------------------------------------------------
        def test_rejects_ruby_symbol_tags
          File.write('config/catalog.yml', <<~YAML)
            CHAPTERS:
              - !ruby/symbol foo
          YAML

          error = assert_raises(StandardError) { Loader.load_catalog }
          assert_includes error.message, '許可されていないクラス/タグ'
        end

        # ----------------------------------------------------------------
        # C. 正常な anchor/alias は展開される
        # ----------------------------------------------------------------
        def test_allows_normal_anchor_alias
          File.write('config/catalog.yml', <<~YAML)
            defaults: &base
              - 11-install
              - 12-quickstart
            CHAPTERS: *base
          YAML

          catalog = Loader.load_catalog
          assert_equal %w[11-install 12-quickstart], catalog['CHAPTERS'],
                       'alias が正常に展開されていること'
        end

        # ----------------------------------------------------------------
        # D. 深いネストの anchor/alias でも展開される（DoS 耐性）
        # ----------------------------------------------------------------
        def test_resolves_nested_aliases_without_dos
          yaml = <<~YAML
            a: &a [1]
            b: &b [*a, *a]
            c: &c [*b, *b]
            d: &d [*c, *c]
            CHAPTERS:
              - 11-install
            extra: *d
          YAML
          File.write('config/catalog.yml', yaml)

          # タイムアウト相当のガード（合理的時間内に完了すべき）
          started = Time.now
          catalog = Loader.load_catalog
          elapsed = Time.now - started

          assert_operator elapsed, :<, 1.0, '深いネストでも合理的時間で完了すること'
          assert_equal ['11-install'], catalog['CHAPTERS']
          # Psych は alias を参照共有するため、extra の展開サイズは指数的ではない
          assert_kind_of Array, catalog['extra']
        end

        # ----------------------------------------------------------------
        # E. 読み込まれたオブジェクトはプリミティブ型のみ
        # ----------------------------------------------------------------
        def test_loaded_values_contain_only_primitives
          File.write('config/catalog.yml', <<~YAML)
            PREFACE:
              - 00-preface
            CHAPTERS:
              - 11-install
              - 21-customize
            APPENDICES:
              - 91-appendix
            POSTFACE:
              - 99-postface
            extra:
              flag: true
              count: 42
              ratio: 3.14
              nothing: ~
          YAML

          catalog = Loader.load_catalog
          assert_all_primitives!(catalog)
        end

        # ----------------------------------------------------------------
        # F. Psych::SyntaxError も引き続き明示的メッセージに変換される
        # ----------------------------------------------------------------
        def test_syntax_error_is_reported_friendly
          File.write('config/catalog.yml', "CHAPTERS:\n  - 11-install\n  :bad: syntax:\n")

          error = assert_raises(StandardError) { Loader.load_catalog }
          assert_includes error.message, 'catalog.yml のパースに失敗しました'
        end

        # ----------------------------------------------------------------
        # G. ファイルが存在しない場合のメッセージ
        # ----------------------------------------------------------------
        def test_missing_file_error
          FileUtils.rm_f('config/catalog.yml')

          error = assert_raises(StandardError) { Loader.load_catalog }
          assert_includes error.message, 'catalog.yml が見つかりません'
        end

        # ----------------------------------------------------------------
        # H. トップレベルが Hash でないと拒否される
        # ----------------------------------------------------------------
        def test_rejects_non_hash_top_level
          File.write('config/catalog.yml', "- just\n- a\n- list\n")

          error = assert_raises(StandardError) { Loader.load_catalog }
          assert_includes error.message, 'Hash ではありません'
        end

        private

        # 再帰的にプリミティブ型しか含まないことを検証する
        def assert_all_primitives!(obj, path = 'root')
          case obj
          when Hash
            obj.each do |k, v|
              assert_all_primitives!(k, "#{path}.key")
              assert_all_primitives!(v, "#{path}.#{k}")
            end
          when Array
            obj.each_with_index do |v, i|
              assert_all_primitives!(v, "#{path}[#{i}]")
            end
          else
            unless SAFE_PRIMITIVES.any? { |klass| obj.is_a?(klass) }
              flunk "#{path} に非プリミティブ型が含まれています: #{obj.class}"
            end
          end
        end
      end
    end
  end
end
