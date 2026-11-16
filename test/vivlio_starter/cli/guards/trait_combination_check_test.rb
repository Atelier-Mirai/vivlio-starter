# frozen_string_literal: true

# ================================================================
# Test: guards/trait_combination_check_test.rb
# ================================================================
# テスト対象:
#   Guards::TraitCombinationCheck（lib/vivlio_starter/cli/guards/trait_combination_check.rb）
#
# 検証内容（v2-architecture-spec.md §2.5・§8 の S5 の決め 2・3・6）:
#   - 既定の本（横書き・リフロー）は違反 0 件
#   - 知らない book.type・page.writing_mode・page.layout は 🔴（書ける値を示す）
#   - page.layout: fixed は S9 まで 🔴（その間は、索引と用語集の 🟡 を重ねない）
#   - 設定が無い（プロジェクトの外）ときは何も出さない（ProjectRootCheck が示す）
#   - テーマ（theme-contract-spec.md §9 の S6 の完了の条件 6）: 本の themes/ に無い名前・合わない契約の版・
#     テーマの supports: に無い組方向と出力先は 🔴 で、次にすることを示す。縦書きの本は、standard が
#     横書きだけなので S8 まで 🔴（§9 の S6 の決め 11）。縦書きに対応する材料のテーマなら通る
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'
require 'tmpdir'
require 'fileutils'
require 'yaml'

module VivlioStarter
  module CLI
    class GuardsTraitCombinationCheckTest < Minitest::Test
      def test_should_pass_for_the_default_book
        assert_empty validate
      end

      # 縦書きの本は、standard が横書きだけに対応するので止める。縦書きに対応するテーマはまだ同梱されていない
      def test_should_stop_a_vertical_book_because_standard_is_horizontal_only
        violations = validate(page: { writing_mode: 'vertical', layout: 'reflowable' })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_equal 'テーマ standard は縦書き（page.writing_mode: vertical）に対応していません', violations.first.message
        assert_equal ['縦書きに対応するテーマは、まだ同梱されていません'], violations.first.detail
      end

      def test_should_stop_a_novel_with_the_resolved_defaults_until_a_vertical_theme_exists
        violations = validate(book: { type: 'novel' }, page: { writing_mode: 'vertical', layout: 'reflowable' },
                              index_glossary: { enabled: false })

        assert_equal %i[error], violations.map(&:severity)
        assert_includes violations.first.message, '縦書き'
      end

      # S5 の完了の条件の 4 の本（縦書きの最小の本）は、縦書きに対応する材料のテーマで組む
      def test_should_pass_a_vertical_book_with_a_theme_that_supports_vertical_writing
        with_themes('tate' => { 'supports' => { 'writing_mode' => %w[horizontal vertical] } }) do |root|
          assert_empty validate({ theme: { name: 'tate' }, page: { writing_mode: 'vertical', layout: 'reflowable' } }, root)
        end
      end

      # 対応するテーマは、本の themes/ と同梱のテーマから探して示す
      def test_should_name_the_themes_that_support_the_requested_writing_mode
        with_themes('tate' => { 'supports' => { 'writing_mode' => %w[vertical] } }) do |root|
          violations = validate({ page: { writing_mode: 'vertical', layout: 'reflowable' } }, root)

          assert_equal ['縦書きに対応するテーマ: tate（config/book.yml の theme.name に書きます）'], violations.first.detail
        end
      end

      def test_should_stop_when_the_named_theme_is_not_in_the_book
        violations = validate(theme: { name: 'standart' })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_equal 'config/book.yml の theme.name のテーマ standart が、本の themes/ にありません', violations.first.message
        assert_equal '本にあるテーマ: standard（config/book.yml の theme.name に書きます）', violations.first.detail
      end

      def test_should_stop_a_theme_written_for_a_newer_contract
        with_themes('future' => { 'contract' => 2 }) do |root|
          violations = validate({ theme: { name: 'future' } }, root)

          assert_equal %i[error], violations.map(&:severity)
          assert_equal 'テーマ future の契約の版（contract: 2）に、この vs は対応していません', violations.first.message
          assert_equal ['この vs が読める契約の版: 1', 'vs upgrade で vs を新しくしてください'], violations.first.detail
        end
      end

      def test_should_stop_an_output_target_that_the_theme_does_not_support
        with_themes('print-only' => { 'supports' => { 'targets' => %w[pdf print_pdf] } }) do |root|
          violations = validate({ theme: { name: 'print-only' }, output: { targets: %w[pdf kindle] } }, root)

          assert_equal 1, violations.size
          assert_equal 'テーマ print-only はKindle（output.targets: kindle）に対応していません', violations.first.message
          assert_includes violations.first.detail, 'output.targets から kindle を外すと組めます'
        end
      end

      # 知らないキーは止めずに読み飛ばし、🟡 で示す（後の版のテーマを前の版の vs で開いた場合）
      def test_should_warn_about_unknown_keys_in_the_theme_manifest
        with_themes('later' => { 'layout_grid' => '8px' }) do |root|
          violations = validate({ theme: { name: 'later' } }, root)

          assert_equal %i[warn], violations.map(&:severity)
          assert_equal 'themes/later/theme.yml の知らないキー layout_grid: を読み飛ばしました', violations.first.message
        end
      end

      # theme: の、選ばれたテーマにも機能にも無いキーは 🟡。綴りの近いキーと、同じ段に書けるキーを示す。
      # 廃止キーは廃止の案内に任せ、ここでは出さない（theme-contract-spec.md §3.3）
      def test_should_warn_about_theme_keys_that_the_theme_does_not_declare
        violations = validate(theme: { name: 'standard', colour: 'red', color: 'green',
                                       frontispiece: { imag: 'x', image: 'sakura' }, markers: { h3: '♣' } })

        assert_equal %i[warn warn], violations.map(&:severity)
        colour = violations.find { it.message.include?('theme.colour') }
        assert_equal 'config/book.yml の theme.colour は、テーマ standard には無い設定です', colour.message
        assert_equal '直すなら: colour → color', colour.detail.first
        assert_match(/テーマ standard の theme: に書けるキー: name・color・.*・ornament\z/, colour.detail.last)
        imag = violations.find { it.message.include?('theme.frontispiece.imag') }
        assert_match(/theme\.frontispiece: に書けるキー: image・edge_inset/, imag.detail.last)
      end

      # 機能を使わないテーマでは、その機能のオプションも「無い設定」になる（前のテーマのものが残った場合）
      def test_should_warn_about_feature_options_of_a_theme_without_the_feature
        with_themes('plain' => {}) do |root|
          violations = validate({ theme: { name: 'plain', frontispiece: { image: 'sakura' }, ornament: 'sakura' } }, root)

          assert_equal ['config/book.yml の theme.frontispiece は、テーマ plain には無い設定です',
                        'config/book.yml の theme.ornament は、テーマ plain には無い設定です'], violations.map(&:message)
        end
      end

      def test_should_report_an_unknown_book_type_with_the_valid_names
        violations = validate(book: { type: 'novle' })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'book.type'
        assert_includes violations.first.message, 'novle'
        assert_equal '書ける値: techbook・novel・picture_book', violations.first.detail
      end

      def test_should_report_unknown_axis_values_with_the_valid_values
        violations = validate(page: { writing_mode: 'tategaki', layout: 'fix' })

        assert_equal 2, violations.size
        assert(violations.all?(&:error?))
        assert_includes violations[0].message, 'page.writing_mode'
        assert_equal '書ける値: horizontal・vertical', violations[0].detail
        assert_includes violations[1].message, 'page.layout'
        assert_equal '書ける値: reflowable・fixed', violations[1].detail
      end

      def test_should_stop_a_fixed_layout_book_until_the_fixed_pipeline_exists
        violations = validate(page: { writing_mode: 'horizontal', layout: 'fixed' }, index_glossary: { enabled: false })

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'page.layout: fixed'
        assert_includes violations.first.detail, 'reflowable'
      end

      # 固定レイアウトを 🔴 で止めている間は、索引の 🟡 を重ねない。S9 で 🔴 を外したら、
      # このテストを「🟡 が 1 件」に書き換える
      def test_should_not_add_the_index_warning_while_fixed_layout_is_stopped
        violations = validate(page: { writing_mode: 'horizontal', layout: 'fixed' }, index_glossary: { enabled: true })

        assert_equal %i[error], violations.map(&:severity)
      end

      def test_should_pass_without_a_configuration
        assert_empty Guards::TraitCombinationCheck.new(config: nil).validate
      end

      private

      BASE = { book: { type: 'techbook' }, page: { writing_mode: 'horizontal', layout: 'reflowable' },
               index_glossary: { enabled: true } }.freeze

      REPO_ROOT = File.expand_path('../../../..', __dir__)

      # 既定では、リポジトリの themes/（standard）を本の themes/ とみなす。同梱のテーマは空の置き場にし、
      # 対応するテーマの探索に雛形の写しを混ぜない
      def validate(overrides = {}, root = REPO_ROOT)
        Dir.mktmpdir('vs-bundled') do |bundled_root|
          Guards::TraitCombinationCheck.new(config: Common.wrap_config(BASE.merge(overrides)), root:, bundled_root:)
                                       .validate
        end
      end

      # リポジトリの standard と、材料のテーマを置いた本のルートを作る
      # @param themes [Hash{String => Hash}] 名前 → theme.yml に足すキー
      def with_themes(themes)
        Dir.mktmpdir('vs-themes') do |root|
          FileUtils.cp_r(File.join(REPO_ROOT, 'themes'), root)
          themes.each do |name, extra|
            FileUtils.mkdir_p(File.join(root, 'themes', name))
            File.write(File.join(root, 'themes', name, 'theme.yml'), { 'name' => name, 'contract' => 1 }.merge(extra).to_yaml)
          end
          yield root
        end
      end
    end
  end
end
