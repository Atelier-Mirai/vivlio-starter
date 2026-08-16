# frozen_string_literal: true

# ================================================================
# Test: cli/convert_test.rb
# ================================================================
# テスト対象:
#   ConvertCommands.convert_markdown!（lib/vivlio_starter/cli/convert.rb）
#
# 検証内容:
#   CV-01: 正常な Markdown → HTML が生成され true
#   CV-02: VFM が失敗したとき → false かつ .html を残さない
#          （VFM は読み込み失敗でも exit 0 でスタックトレースを stdout へ吐く。
#            それを .html として残すと章の本文がエラーダンプに化ける）
#
# VFM は外部コマンドのため、未導入の環境ではスキップする
# （導入は `vs doctor` が検査する。Guards::VfmCheck がビルド前に止める）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/convert'

module VivlioStarter
  module CLI
    class ConvertTest < Minitest::Test
      def setup
        return if system(Common::VFM_COMMAND, '--version', out: File::NULL, err: File::NULL)

        skip "#{Common::VFM_COMMAND} が未導入のためスキップ"
      end

      # CV-01: 変換に成功したら HTML 文書が残る
      def test_should_convert_markdown_into_html_document
        Dir.mktmpdir do |dir|
          md = File.join(dir, '11-intro.md')
          File.write(md, "# 見出し\n\n本文です。\n")

          assert ConvertCommands.convert_markdown!(md)

          html = File.join(dir, '11-intro.html')
          assert_path_exists html
          assert File.read(html).lstrip.start_with?('<'), 'HTML 文書として始まるべき'
        end
      end

      # CV-02: 失敗したら .html を残さない。
      # VFM は入力を読めなくても exit 0 を返すため、終了コードだけを見ていた頃は
      # Node のスタックトレースが章の HTML として本に組み込まれていた
      def test_should_not_leave_html_when_conversion_fails
        Dir.mktmpdir do |dir|
          md = File.join(dir, 'missing.md') # ファイルを作らない

          refute ConvertCommands.convert_markdown!(md)
          refute_path_exists File.join(dir, 'missing.html'),
                             '壊れた HTML を後続のステップへ渡してはならない'
        end
      end
    end
  end
end
