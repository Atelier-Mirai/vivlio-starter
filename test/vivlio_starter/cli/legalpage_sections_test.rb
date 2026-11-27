# frozen_string_literal: true

# ================================================================
# Test: legalpage_sections_test.rb
# ================================================================
# テスト対象:
#   CreateCommands#execute_legalpage（権利ページの「免責」「商標」の節）
#
# 検証内容:
#   - 文の空いた節は載せない（小説の既定は商標の文が空。BookProfile::NOVEL_DISCLAIMER）
#   - 小説の本の権利ページに、技術書の免責の文が載らない
#   - 両方が書いてある本（技術書）は、2 つの節を載せる
#   - 小説の本には絵文字のクレジットを載せない（技術書は載せる）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    class LegalpageSectionsTest < Minitest::Test
      PAGE_PRESETS = File.expand_path('../../../config/page_presets.yml', __dir__)

      # load_config は読んだ本のテーマの宣言を Common に覚えさせる（小説は novel）。
      # 戻さないと、後で走る既定値のテストが standard の宣言（theme.markers）を見失う
      def legalpage(book_yml)
        original = Common::CONFIG
        original_specs = Common.instance_variable_get(:@theme_specs)
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.cp(PAGE_PRESETS, 'config')
            File.write(Common::CONFIG_FILE, book_yml.to_yaml)
            Common.install_configuration!(Common.wrap_config(Common.load_config).freeze)
            CreateCommands.send(:execute_legalpage)
            File.read(File.join(Common::CACHE_DIR, '_legalpage.md'), encoding: 'utf-8')
          end
        end
      ensure
        Common.install_configuration!(original)
        Common.instance_variable_set(:@theme_specs, original_specs)
      end

      def test_should_show_only_the_fiction_note_in_a_novel
        page = legalpage('book' => { 'type' => 'novel' })

        assert_includes page, '■免責'
        assert_includes page, 'この物語はフィクションです。'
        refute_includes page, '■商標', '文の空いた節は載せない'
        refute_includes page, '教育目的', '技術書の免責の文は載せない'
        refute_includes page, '■絵文字クレジット', '小説は Twemoji を使わないので、クレジットを載せない'
      end

      def test_should_show_both_sections_in_a_techbook
        page = legalpage('book' => { 'type' => 'techbook' })

        assert_includes page, '■免責'
        assert_includes page, '■商標'
        assert_includes page, '教育目的'
        assert_includes page, '■絵文字クレジット'
      end
    end
  end
end
