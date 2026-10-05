# frozen_string_literal: true

require "open3"
require "set"
require "tmpdir"

require "test_helper"
require "vivlio_starter/cli/pdf/ocr_postprocess"

module VivlioStarter
  module PDF
    # OCR で読んだ原稿の後処理（pdf-read-ocr-postprocess-spec.md §3）
    class OcrPostprocessTest < Minitest::Test
      # 数字と和文のあいだの空白は詰め、英字の語と和文のあいだ・数字どうしの空白は残す（§3.1・論点 2）
      def test_should_collapse_spaces_between_digits_and_japanese_only
        text = "1879 年 3 月、Ruby の 2 × 10 を使う\n"

        assert_equal("1879年3月、Ruby の2 × 10を使う\n", OcrPostprocess.collapse_digit_spacing(text))
      end

      # 和文を含む半角括弧は全角にし、外側の空白も詰める
      def test_should_normalize_brackets_around_japanese
        assert_equal("塊（量子）として (x + y)", OcrPostprocess.normalize_brackets("塊 (量子 ) として (x + y)"))
      end

      # 形の似た字は、入れ替えた形の MeCab のコストが十分に低いときだけ直す。
      # 正しい「ニュートン力学」「イタリアへ」「父ヘルマン」は壊さない（§3.2）
      def test_should_fix_confusable_characters_checked_by_mecab
        skip "MeCab is not available" unless mecab_available?

        text = "向けて6、針は動く。協カして作る。ブ口グを書く。ニュートン力学を学ぶ。イタリアへ移る。父ヘルマンが来た。"

        assert_equal("向けても、針は動く。協力して作る。ブログを書く。ニュートン力学を学ぶ。イタリアへ移る。父ヘルマンが来た。",
                     OcrPostprocess.fix_confusables(text, 'mecab'))
      end

      # MeCab が無いときは、形の似た字の補正だけを飛ばす
      def test_should_skip_confusables_without_mecab
        assert_equal("向けて6、針は", OcrPostprocess.fix_confusables("向けて6、針は", 'no-such-mecab-command'))
      end

      # 後処理はコードの囲みの外にだけかけ、補正表は最後に当てる
      def test_should_postprocess_outside_code_and_apply_corrections_last
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'ocr_corrections.yml')
          File.write(path, { 'rules' => [{ 'expected' => '人工知能', 'patterns' => ['入工知能'] }] }.to_yaml)
          markdown = "入工知能は 2026 年に。\n\n```\nputs 2026 年\n```\n"

          result = OcrPostprocess.apply(markdown, corrections_path: path, mecab: 'no-such-mecab-command', vocabulary: Set[])

          assert_equal("人工知能は2026年に。\n\n```\nputs 2026 年\n```\n", result)
        end
      end

      # 補正表は、コードの囲みの外にだけかける
      def test_should_apply_corrections_outside_code_fences
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'ocr_corrections.yml')
          File.write(path, { 'rules' => [{ 'expected' => '人工知能', 'patterns' => ['入工知能'] }] }.to_yaml)
          markdown = "入工知能の話。\n\n```\nputs '入工知能'\n```\n\n入工知能で終わる。\n"

          corrected = OcrCorrections.apply(markdown, path:)

          assert_equal("人工知能の話。\n\n```\nputs '入工知能'\n```\n\n人工知能で終わる。\n", corrected)
        end
      end

      # 英字の語は、部品ごとに辞書に無ければ取り違えやすい字を入れ替え、辞書に当たる形が 1 つだけのときに
      # 直す。t を l・i に戻す入れ替えは複数か所まで許す（`vetoctty` → `velocity`）
      def test_should_fix_misread_latin_words_with_dictionary
        vocabulary = Set['float', 'threshold', 'frequency', 'velocity', 'ratio', 'delta']

        fixed = OcrLatinWords.fix('Ftoat threshotd_frequency vetoctty_ratto detta', vocabulary)

        assert_equal('Float threshold_frequency velocity_ratio delta', fixed)
      end

      # 3 字以下の部品・数字を含む部品・辞書に当たる形が 2 つ以上ある部品は直さない
      def test_should_keep_latin_words_that_cannot_be_decided
        vocabulary = Set['sip', 'lilt', 'lift'] # litt は lilt にも lift にも戻せる

        assert_equal('stp x2tt litt', OcrLatinWords.fix('stp x2tt litt', vocabulary))
      end

      # 英字の語はコードの囲みの中にもかける。画像の参照と HTML のコメントは書き換えない
      def test_should_fix_latin_words_inside_code_but_not_in_image_references
        markdown = "![](ptctures.webp) <!-- ptctures -->\n\n```ruby\nx = Ftoat(1)\n```\n"

        result = OcrPostprocess.apply(markdown, corrections_path: '/no/such/file', mecab: 'no-such-mecab-command',
                                                vocabulary: Set['float', 'pictures'])

        assert_equal("![](ptctures.webp) <!-- ptctures -->\n\n```ruby\nx = Float(1)\n```\n", result)
      end

      private

      def mecab_available?
        _out, status = Open3.capture2('mecab', stdin_data: "テスト\n")
        status.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
