# frozen_string_literal: true

# ================================================================
# Test: book_type_usage_test.rb
# ================================================================
# テスト対象:
#   lib/ の中で book.type を読む箇所（v2-architecture-spec.md §2.3）
#
# 種類での分岐を許すと、種類を一つ足すたびに全体を調べ直すことになり、「横書きの小説」の
# ような、種類の既定値から一つだけ軸を変えた本が組めなくなる。book.type を読んでよいのは
# 次の箇所だけとし、それ以外のコードは軸（BookTraits）か機能のキーを読む。
#   - config_keys.rb   … キーの宣言
#   - book_profile.rb  … 種類の既定値の表と、book.type の読み方
#   - common.rb        … load_config（種類の既定値を重ねる）
#   - guards/trait_combination_check.rb … 著者向けの表示（知らない種類の名前を 🔴 で示す文面。
#     値は BookProfile.unknown_type から受け取り、種類では分岐しない）
#   - vs new は、作った段階でここに足す
# ================================================================

require 'test_helper'

module VivlioStarter
  module CLI
    class BookTypeUsageTest < Minitest::Test
      LIB_DIR = File.expand_path('../../../lib/vivlio_starter', __dir__)

      ALLOWED = %w[cli/config_keys.rb cli/book_profile.rb cli/common.rb cli/guards/trait_combination_check.rb].freeze

      # book.type の読み方。ドット・安全参照・dig・添字・キーの宣言の形
      PATTERN = /
        \bbook&?\.type\b
        | dig\(\s*:book\s*,\s*:type\b
        | \[:book\]\s*\[:type\]
        | %i\[book\s+type\]
        | BookProfile\.type_of
      /x

      def test_should_read_book_type_only_in_the_allowed_files
        offenders = Dir[File.join(LIB_DIR, '**/*.rb')].flat_map do |path|
          rel = path.delete_prefix("#{LIB_DIR}/")
          next [] if ALLOWED.include?(rel)

          File.readlines(path).each_with_index.filter_map do |line, index|
            "#{rel}:#{index + 1}: #{line.strip}" if !line.lstrip.start_with?('#') && line.match?(PATTERN)
          end
        end

        assert_empty offenders, 'book.type を読む箇所は ALLOWED だけ。分岐の理由になっている性質を軸か機能のキーにする'
      end

      # 検査の正規表現が、実際の読み方に当たることを確かめる（当たらない正規表現では検査にならない）
      def test_pattern_should_match_the_ways_of_reading_book_type
        ['Common::CONFIG.book.type', 'config.book&.type', 'cfg.dig(:book, :type)', 'raw[:book][:type]',
         'KEYS[%i[book type]]', 'BookProfile.type_of(raw)'].each do |code|
          assert_match PATTERN, code
        end
        refute_match PATTERN, 'CONFIG.book.title'
        refute_match PATTERN, 'output.pdf.type_label'
      end
    end
  end
end
