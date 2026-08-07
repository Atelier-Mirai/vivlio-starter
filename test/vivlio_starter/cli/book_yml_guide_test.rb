# frozen_string_literal: true

# ================================================================
# Test: book_yml_guide_test.rb
# ================================================================
# テスト対象:
#   config/book.yml — 冒頭ガイドの目次と本文セクションの対応
#
# 背景:
#   book.yml は著者が設定を知る唯一の窓口なので、冒頭の【主なセクション】は
#   「何が設定できるか」の目次として働く。ところが本文とは別々に手で書くため、
#   セクションを足したり並べ替えたりすると静かにずれる。実際 2026-08-07 に
#   index_glossary が legal の上に置かれ、ガイドの分類
#   （legal =「著者が設定する」／index_glossary =「機能ごと」）と食い違っていた。
#   目次が現物と違うのは、書いていないより悪い。
#
# 検証方法:
#   ガイドの「• <キー> :」の並びと、YAML のトップレベルキーの並びを突き合わせる。
#   順序まで見るのは、ガイドが読む順の案内でもあるため。
#   本文の「# ======= 見出し =======」の数とも突き合わせ、見出しの付け忘れを拾う。
#
#   見るのは **root の config/book.yml**（`book_yml_consumption_test.rb` が scaffold を
#   見るのとは対象が違う）。ガイドは開発者が root で書くものであり、scaffold は
#   `copy_to_scaffold.rb` による機械的な複製なので、root が整っていれば同期後の
#   scaffold も整う。scaffold を直接見ると「同期し忘れ」で落ち、直す場所も
#   root なので、失敗の指す先がぶれる。
# ================================================================

require 'test_helper'
require 'yaml'

module VivlioStarter
  module CLI
    # book.yml の冒頭ガイドと本文の対応保証テスト
    class BookYmlGuideTest < Minitest::Test
      PROJECT_ROOT = File.expand_path('../../..', __dir__)
      BOOK_YML = File.join(PROJECT_ROOT, 'config/book.yml')

      # 冒頭ガイドの目次行（`#  • index_glossary : 索引・用語集の共通設定`）
      GUIDE_ENTRY = /\A#\s+•\s+([a-z_]+)\s*:/
      # 本文のセクション見出し（`# ======= 索引設定 =======`）
      SECTION_HEADING = /\A# ={3,} .+ ={3,}\z/

      def setup
        skip "#{BOOK_YML} が見つかりません" unless File.exist?(BOOK_YML)

        @lines = File.readlines(BOOK_YML, chomp: true)
        @config = YAML.safe_load_file(BOOK_YML, aliases: true)
      end

      # ガイドの目次と本文のキーが、順序まで含めて一致すること
      def test_should_list_every_top_level_section_in_the_guide_in_order
        listed = @lines.filter_map { it[GUIDE_ENTRY, 1] }
        actual = @config.keys

        assert_equal actual, listed, <<~MSG
          冒頭ガイドの【主なセクション】と本文のセクションがずれています。
            ガイド: #{listed.join(', ')}
            本文  : #{actual.join(', ')}
          不足 #{(actual - listed).inspect} / 余分 #{(listed - actual).inspect}
          セクションを足したり並べ替えたら、ガイドの目次も同じ順に直してください。
        MSG
      end

      # すべてのトップレベルキーに見出しが付いていること
      def test_should_give_every_section_a_heading
        headings = @lines.count { it.match?(SECTION_HEADING) }

        assert_equal @config.keys.size, headings,
                     "セクション見出し（# ======= … =======）が #{headings} 本、" \
                     "トップレベルキーが #{@config.keys.size} 個で数が合いません。" \
                     '見出しの付け忘れか、キーの無い見出しが残っています。'
      end

      # ガイドの説明文が空になっていないこと（キー名だけ足して説明を忘れる事故を防ぐ）
      def test_should_describe_every_guide_entry
        blank = @lines.filter_map do |line|
          next unless (key = line[GUIDE_ENTRY, 1])

          key if line.sub(GUIDE_ENTRY, '').strip.empty?
        end

        assert_empty blank, "冒頭ガイドに説明の無い項目があります: #{blank.join(', ')}"
      end
    end
  end
end
