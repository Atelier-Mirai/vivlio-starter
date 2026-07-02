# frozen_string_literal: true

# ================================================================
# Test: common_config_loading_test.rb
# ================================================================
# テスト対象:
#   Common の設定読み込み層（lib/vivlio_starter/cli/common.rb）
#   - wrap_config（再帰的 Data ラッパー）の各記法
#   - merge_hardcoded_defaults（既定値スキーマ・deep merge）
#   - reload_configuration!（book.yml 編集後の再読込）
#
# 仕様: docs/specs/config-access-unification-spec.md
#   正規記法は「静的キーはドット・動的キーはシンボル dig」。
#   [] のメソッド漏れ（旧実装では CONFIG[:to_h] が設定全体を返した）と
#   セクション欠落時の NoMethodError が再発しないことを回帰として固定する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    # wrap_config の記法（ドット / [] / dig / fetch / パターンマッチ）検証
    class CommonConfigNotationTest < Minitest::Test
      # 記法テスト共通のサンプル設定（book.yml 相当の入れ子構造）
      def sample_config
        Common.wrap_config(
          book: { main_title: 'タイトル', author: '著者' },
          output: { pdf: { combined: true, compress: false } },
          chapters: [{ number: 1, slug: 'intro' }]
        )
      end

      def test_should_read_static_keys_with_dot_notation
        cfg = sample_config

        assert_equal 'タイトル', cfg.book.main_title
        assert_equal true, cfg.output.pdf.combined
      end

      def test_should_read_dynamic_keys_with_symbol_bracket_and_dig
        cfg = sample_config
        section = :book

        assert_equal '著者', cfg[section][:author]
        assert_equal false, cfg.dig(:output, :pdf, :compress)
      end

      # 移行期間の互換: String キーは Symbol へ正規化される（Phase 3 で廃止予定）
      def test_should_normalize_string_keys_to_symbols
        cfg = sample_config

        assert_equal 'タイトル', cfg['book']['main_title']
        assert_equal true, cfg.dig('output', 'pdf', 'combined')
      end

      def test_should_return_nil_for_missing_keys_via_bracket_and_dig
        cfg = sample_config

        assert_nil cfg[:missing]
        assert_nil cfg.dig(:output, :epub, :embed)
      end

      # 回帰: 旧実装（respond_to? ベースの []）では cfg[:to_h] が設定全体を、
      # cfg['inspect'] が inspect 文字列を返していた（メソッド漏れ）
      def test_should_not_leak_methods_through_bracket_access
        cfg = sample_config

        assert_nil cfg[:to_h]
        assert_nil cfg['inspect']
        assert_nil cfg[:members]
        assert_nil cfg.dig(:book, :class)
      end

      def test_should_support_pattern_matching_with_symbol_keys
        case sample_config
        in { book: { main_title: String => title }, output: { pdf: { combined: true } } }
          assert_equal 'タイトル', title
        else
          flunk 'ネストしたハッシュパターンにマッチするべきです'
        end
      end

      # Ruby の規約: deconstruct_keys(nil) は全体を返す（`in { **rest }` で全キーを束縛）
      def test_should_return_full_hash_when_deconstruct_keys_receives_nil
        sample_config => { **rest }

        assert_equal %i[book output chapters], rest.keys
      end

      def test_should_wrap_array_elements_recursively
        cfg = sample_config

        assert_equal 'intro', cfg.chapters.first.slug
      end

      # 廃止予定（仕様書 Phase 3）の fetch の現行互換: nil 値も default 扱い
      def test_should_treat_nil_value_as_default_in_fetch
        cfg = Common.wrap_config(page: { size: nil })

        assert_equal 'B5', cfg.page.fetch(:size, 'B5')
      end

      # Data の予約メソッド名と衝突するキーはロード時に警告される
      def test_should_warn_when_key_collides_with_reserved_method_names
        assert_output(/予約名/) { Common.wrap_config(hash: 1) }
      end
    end

    # 既定値スキーマ（全セクションの存在保証）と deep merge の検証
    class CommonConfigDefaultsTest < Minitest::Test
      # 空の book.yml でも全セクション・既知キーがドット記法で安全に参照できる
      def test_should_provide_all_sections_for_minimal_book_yml
        cfg = Common.wrap_config(Common.merge_hardcoded_defaults({}))

        assert_nil cfg.book.main_title
        assert_nil cfg.project.name
        assert_nil cfg.theme.markers.h3
        assert_nil cfg.legal.twemoji
        assert_nil cfg.output.cover
        assert_nil cfg.output.pdf.combined
        assert_nil cfg.index_glossary.enabled
        assert_nil cfg.lint.config
        assert_nil cfg.spellcheck.extra_words
        assert_nil cfg.pdf_read.ocr.mode
        assert_equal 'contents', cfg.directories.contents
        assert_equal true, cfg.vfm.hard_line_breaks
      end

      # deep merge: 入れ子の部分指定でも兄弟キーが既定値スキーマから残る
      def test_should_preserve_sibling_keys_on_partial_override
        merged = Common.merge_hardcoded_defaults(output: { pdf: { compress: true } })

        assert_equal true, merged[:output][:pdf][:compress]
        assert merged[:output][:pdf].key?(:combined)
        assert merged[:output].key?(:cover)
      end

      # 空欄キー（nil）は既定値を採用し、false は明示設定として尊重する
      def test_should_keep_default_for_nil_and_respect_explicit_false
        nil_merged = Common.merge_hardcoded_defaults(vfm: { hard_line_breaks: nil })
        false_merged = Common.merge_hardcoded_defaults(vfm: { hard_line_breaks: false })

        assert_equal true, nil_merged[:vfm][:hard_line_breaks]
        assert_equal false, false_merged[:vfm][:hard_line_breaks]
      end

      # スキーマ外のセクション・キーは従来どおり素通しする（自由拡張の維持）
      def test_should_pass_through_unknown_sections_and_keys
        merged = Common.merge_hardcoded_defaults(
          my_section: { foo: 1 },
          book: { custom_note: '独自キー' }
        )

        assert_equal 1, merged[:my_section][:foo]
        assert_equal '独自キー', merged[:book][:custom_note]
        assert merged[:book].key?(:main_title)
      end
    end

    # 実ファイルからの reload_configuration! 検証
    # （cover_test.rb と同じ chdir + teardown で canonical CONFIG を復旧するパターン）
    class CommonConfigReloadTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @original_dir = Dir.pwd
        Dir.chdir(@temp_dir)
        FileUtils.mkdir_p('config')
        %w[catalog page_presets post_replace_list].each { File.write("config/#{it}.yml", '{}') }
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@temp_dir)
        # CONFIG 定数がテスト用 book.yml で汚染されるため、
        # プロジェクトルートの canonical な book.yml で復旧する
        Common.reload_configuration!(silent: true) if File.file?('config/book.yml')
      end

      def test_should_reload_configuration_after_book_yml_edit
        File.write('config/book.yml', { 'book' => { 'main_title' => '初版' } }.to_yaml)
        Common.reload_configuration!(silent: true)

        assert_equal '初版', Common::CONFIG.book.main_title

        File.write('config/book.yml', { 'book' => { 'main_title' => '改訂版' } }.to_yaml)
        Common.reload_configuration!(silent: true)

        assert_equal '改訂版', Common::CONFIG.book.main_title
      end

      # 回帰: セクションを削った最小 book.yml で CONFIG.lint 等が NoMethodError にならない
      def test_should_expose_all_sections_from_minimal_real_book_yml
        File.write('config/book.yml', "book:\n  main_title: 最小構成\n")
        Common.reload_configuration!(silent: true)

        assert_equal '最小構成', Common::CONFIG.book.main_title
        assert_nil Common::CONFIG.lint.config
        assert_nil Common::CONFIG.project.name
        assert_equal true, Common::CONFIG.vfm.hard_line_breaks
      end
    end
  end
end
