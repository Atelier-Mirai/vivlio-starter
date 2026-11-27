# frozen_string_literal: true

# ================================================================
# Test: index/furigana_test.rb
# ================================================================
# テスト対象:
#   IndexCommands::Furigana（lib/vivlio_starter/cli/index/furigana.rb）
#
# 検証内容（改善案 #175）:
#   - 漢字の部分だけに読みを振り、かなには振らない
#   - 英字の部分には、著者が確かめた読みだけを振る
#   - 全体の形（{明日|あした}の{予定|よてい}）が自動より優先する
#   - 割り出しが一通りに決まらない語・読みが分からない語の扱い
#   - 英字の読みの候補（手で補う表 → SudachiDict → 一字ずつ）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/index/furigana'

module VivlioStarter
  module CLI
    module IndexCommands
      class FuriganaTest < Minitest::Test
        # 区切りを `{親|かな}` の形の文字列で見る
        def marked(term, yomi, furigana = nil)
          segments, how = Furigana.segments(term, yomi, furigana)
          [segments.map { it.reading ? "{#{it.base}|#{it.reading}}" : it.base }.join, how]
        end

        # 漢字の続きごとに読みを割り出す。かな・送り仮名には振らない
        def test_should_ruby_only_the_kanji_parts
          assert_equal ['{三平方|さんへいほう}の{定理|ていり}', :parts], marked('三平方の定理', 'さんへいほうのていり')
          assert_equal ['インスタンス{変数|へんすう}', :parts], marked('インスタンス変数', 'いんすたんすへんすう')
          assert_equal ['{浅|あさ}いコピー', :parts], marked('浅いコピー', 'あさいこぴー')
          assert_equal ['カプセル{化|か}', :parts], marked('カプセル化', 'かぷせるか')
        end

        # かなだけの語・英字だけで確かめた読みの無い語には振らない
        def test_should_not_ruby_kana_or_unconfirmed_latin
          assert_equal ['ローカルストレージ', :none], marked('ローカルストレージ', 'ろーかるすとれーじ')
          assert_equal ['YAML', :none], marked('YAML', 'YAML')
        end

        # 英字の部分には、著者が確かめた読みをカタカナで振る。漢字と混じる語は両方に振る
        def test_should_ruby_latin_parts_with_the_confirmed_reading
          assert_equal ['{YAML|ヤムル}', :parts], marked('YAML', 'YAML', 'ヤムル')
          assert_equal ['{JIS|ジス} {配列|はいれつ}', :parts], marked('JIS 配列', 'JIS はいれつ', 'ジス')
          assert_equal ['{ASCII|アスキー}{文字|もじ}', :parts], marked('ASCII文字', 'ASCIIもじ', 'アスキー')
        end

        # 全体の形は自動より優先する（熟字訓・当て字）。親文字が見出し語と合わなければ使わない
        def test_full_form_should_take_precedence
          assert_equal ['{明日|あした}の{予定|よてい}', :full], marked('明日の予定', 'あすのよてい', '{明日|あした}の{予定|よてい}')
          assert_equal ['{明日|あす}の{予定|よてい}', :parts], marked('明日の予定', 'あすのよてい', '{昨日|きのう}の{予定|よてい}')
        end

        # 割り出しが一通りに決まらないときは、今のとおり語の全体に振る
        def test_should_fall_back_to_the_whole_word_when_alignment_is_ambiguous
          assert_equal ['{東京大阪|とうきょうおおさか}', :parts], marked('東京大阪', 'とうきょうおおさか')
          assert_equal ['{和の和|わのわのわ}', :whole], marked('和の和', 'わのわのわ')
          assert_equal ['{雰囲気|ふいんき}', :parts], marked('雰囲気', 'ふいんき')
        end

        # 読みに漢字が残る語（MeCab が読めなかった語）は振らない。漢字の上に漢字を重ねない
        def test_should_not_ruby_when_the_reading_is_unknown
          assert_equal ['遙香姫', :unreadable], marked('遙香姫', '遙香ひめ')
        end

        # 子行の値の誤り。英字の部分が 2 つある語に読みだけ・親文字が見出し語と合わない全体の形
        def test_should_report_values_that_cannot_be_placed
          assert_nil Furigana.problem('JIS 配列', 'ジス')
          assert_match(/英字の部分が 2 つ/, Furigana.problem('HTML と CSS', 'エイチ'))
          assert_match(/見出し語「明日の予定」と合いません/, Furigana.problem('明日の予定', '{明後日|あさって}'))
          assert_equal '{HTML|エイチティーエムエル} と {CSS|シーエスエス}', Furigana.full_form_example('HTML と CSS')
        end

        # 候補は、手で補う表 → SudachiDict → 大文字の略語を一字ずつ、の順。数字を含む語には作らない
        def test_candidates_should_follow_the_lookup_order
          assert_equal ['ジャバ'], Furigana.candidates('Java'), '手で補う表が SudachiDict（ジャワ）に勝つ'
          assert_equal ['ユーティーエフエイト'], Furigana.candidates('UTF-8')
          assert_equal ['ヤムル'], Furigana.candidates('YAML'), 'SudachiDict'
          assert_equal ['サファリ'], Furigana.candidates('Safari'), '小文字の綴りでも引ける'
          assert_equal ['エイチティーエムエル'], Furigana.candidates('HTML'), '一字ずつ読む'
          assert_empty Furigana.candidates('Windows11'), '数字の読み方は語ごとに違う'
        end
      end
    end
  end
end
