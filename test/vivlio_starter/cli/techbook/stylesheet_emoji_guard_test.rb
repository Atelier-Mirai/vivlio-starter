# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/techbook/stylesheet_emoji_guard_test.rb
#
# CSS の content: に生の絵文字を置かせないためのラチェット
#
# 【背景】
#   絵文字を Type 3 から守っているのは Techbook::EmojiReplacer だが、これは
#   **HTML のテキストしか走査しない**。CSS の `content: "📚 "` で描かれた絵文字は
#   その射程外に落ち、Chromium が OS の絵文字フォント（AppleColorEmoji 等）を
#   Type 3 で埋め込む。入稿用 PDF に Type 3 は不可。
#
#   2026-08-11 に preface.css の `h3::before { content: "📚 " }` で実際に踏んだ。
#   本書の前書きに h3 が 1 つも無かったため、全章ビルドの Type 3 チェック
#   （test/vivlio_starter/type3/）を 0 件のまますり抜けていた。**著者が前書きに
#   `###` を 1 行書いた瞬間に混入する**という、テストで守れていない経路だった。
#
# 【この検査の考え方】
#   CSS 側の絵文字は「気づけないこと」が本質なので、件数を固定して増加を止める。
#   新たに足したくなったら、Techbook::Processor#inject_css に打ち消し規則
#   （content: "" + background-image で Twemoji 画像化）を書いたうえで
#   KNOWN_EMOJI_IN_CSS に登録すること。
# =============================================================================

require_relative '../../../test_helper'

module VivlioStarter
  module CLI
    module Techbook
      class StylesheetEmojiGuardTest < Minitest::Test
        STYLESHEETS_DIR = File.expand_path('../../../../stylesheets', __dir__)

        # コメントは検査対象外（解説文に絵文字を書くのは自由）。
        CSS_COMMENT = %r{/\*.*?\*/}m

        # 絵文字だけを拾う。`\p{Emoji}` は ASCII 数字や `#` にも当たるため使わない
        # （`content: "1"` のような正当な指定を誤検出する）。
        EMOJI = /[\p{Emoji_Presentation}\u{FE0F}]/

        # 打ち消し済みの既知の在処。ファイル名 => 絵文字の配列。
        KNOWN_EMOJI_IN_CSS = {
          # Techbook::Processor#inject_css の body.preface/postface h3::before が画像化する
          'preface.css' => ['📚']
        }.freeze

        def test_should_not_introduce_unguarded_emoji_in_css_content
          found = {}

          Dir.glob(File.join(STYLESHEETS_DIR, '**', '*.css')).sort.each do |path|
            declarations = File.read(path, encoding: 'utf-8').gsub(CSS_COMMENT, '')
            emoji = declarations.scan(EMOJI).uniq
            next if emoji.empty?

            found[path.delete_prefix("#{STYLESHEETS_DIR}/")] = emoji
          end

          actual = found.transform_values { it.uniq.sort }
          expected = KNOWN_EMOJI_IN_CSS.transform_values { it.uniq.sort }

          assert_equal expected, actual,
                       "CSS の content: にある絵文字が既知の一覧と一致しません。\n" \
                       '増えた場合は Techbook::Processor#inject_css に打ち消し規則を書いてから ' \
                       "KNOWN_EMOJI_IN_CSS に登録してください（書かないと入稿用 PDF に Type 3 が混入します）。\n" \
                       "減った場合は一覧から消してください。"
        end

        # 一覧に載っている絵文字は、必ず Twemoji のマスター SVG が同梱されていること。
        # 無ければ fallback の丸印に化け、意図した字形が出ない。
        def test_should_ship_twemoji_master_for_known_css_emoji
          KNOWN_EMOJI_IN_CSS.each_value do |emoji_list|
            emoji_list.each do |emoji|
              codepoint = emoji.codepoints.reject { it == 0xFE0F }.map { it.to_s(16).downcase }.join('-')
              path = File.join(STYLESHEETS_DIR, 'twemoji', "#{codepoint}.svg")

              assert_path_exists path, "#{emoji}（#{codepoint}）の Twemoji SVG が同梱されていません"
            end
          end
        end
      end
    end
  end
end
