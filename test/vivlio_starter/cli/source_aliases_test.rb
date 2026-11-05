# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    # 設定ファイルなしのビルドの報告で、作業用の原稿の名前と行を、著者の原稿の名前と行へ読み替える
    class SourceAliasesTest < Minitest::Test
      ALIASES = [
        SourceAliases::Alias.new(workspace: '10-handout.md', source: 'handout.md', offset: 0),
        SourceAliases::Alias.new(workspace: '11-handout-2.md', source: 'handout.md', offset: 20)
      ].freeze

      def test_should_rename_and_shift_lines_only_inside_the_block
        SourceAliases.with(ALIASES) do
          assert_equal '🔴 handout.md:5 - リンク切れを検出しました',
                       SourceAliases.localize('🔴 10-handout.md:5 - リンク切れを検出しました')
          assert_equal '🟡 handout.md:23 - 本の書体にない字があります',
                       SourceAliases.localize('🟡 11-handout-2.md:3 - 本の書体にない字があります')
          assert_equal '[qr] handout.md:4 - QR コードを生成できませんでした',
                       SourceAliases.localize('[qr] contents/10-handout.md:4 - QR コードを生成できませんでした')
          assert_equal 'handout.md: 会話文の不明な指定です', SourceAliases.localize('10-handout.md: 会話文の不明な指定です')
          # 作業用の画像の置き場は外す（直接ビルドの画像は原稿と同じ場所から探す）
          assert_equal '画像の場所: figs/nothere.png', SourceAliases.localize('画像の場所: images/10-handout/figs/nothere.png')
        end

        assert_equal '10-handout.md:5', SourceAliases.localize('10-handout.md:5'), 'ブロックの外では読み替えない'
      end

      # 名前の一部が重なるほかのファイル（110-handout.md など）は読み替えない
      def test_should_not_touch_other_names
        SourceAliases.with(ALIASES) do
          assert_equal '110-handout.md:5', SourceAliases.localize('110-handout.md:5')
        end
      end

      # 出力の出口（Common.emit）で読み替わる
      def test_should_localize_lines_emitted_by_common
        out, = capture_io do
          SourceAliases.with(ALIASES) { Common.log_always('🔴 11-handout-2.md:1 - 例') }
        end

        assert_equal "🔴 handout.md:21 - 例\n", out
      end
    end
  end
end
