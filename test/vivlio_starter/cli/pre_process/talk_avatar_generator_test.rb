# frozen_string_literal: true

# ================================================================
# Test: talk_avatar_generator_test.rb
# ================================================================
# 検証内容（talk-auto-avatar-spec.md §3）:
#   簡易アバター（話者色を地に、表示名の頭 1 文字）の自動生成。
#   - 文字の切り出し（CJK / ラテン / 絵文字を割らない）
#   - 地色の明るさによる文字色の自動選択
#   - 内容アドレスのキャッシュキー
#   - magick 不在時の縮退（DI でツールを差し替え）
#   - 参照パスに asset_prefix を付けない（生成物の規約）
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class TalkAvatarGeneratorTest < Minitest::Test
        Gen = TalkAvatarGenerator
        LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

        # 呼び出し引数を記録するだけの偽ツール（外部コマンドを起動しない）。
        # measure は字の寸法を返す。既定は 200pt の漢字 2 字の実測値（佐藤 = 396 × 184）
        class FakeTools
          attr_reader :calls, :measured

          def initialize(available: true, size: [396, 184])
            @available = available
            @size = size
            @calls = []
            @measured = []
          end

          def available? = @available

          def render(path, glyph:, background:, foreground:, pointsize:, font:)
            @calls << { path:, glyph:, background:, foreground:, pointsize:, font: }
            File.write(path, 'fake')
            true
          end

          def measure(glyph, pointsize:, font:)
            @measured << { glyph:, pointsize:, font: }
            @size
          end
        end

        def setup
          @saved = LOG_METHODS.to_h { [it, Common.method(it)] }
          LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        end

        def teardown
          @saved&.each { |name, m| Common.define_singleton_method(name, m) }
        end

        def character(name:, color: 'purple', initial: nil)
          TalkRegistry::Character.new(key: 'k', name:, color:, avatar: 'auto', side: 'left', initial:)
        end

        # 表示名の 1 文字目を書記素クラスタで取る（CJK・ラテン・絵文字を割らない）。
        def test_should_take_first_grapheme_cluster
          assert_equal '遙', Gen.avatar_glyph(character(name: '遙香'))
          assert_equal 'A', Gen.avatar_glyph(character(name: 'Alice'))
          assert_equal '👩‍🎓', Gen.avatar_glyph(character(name: '👩‍🎓さん')), '結合絵文字を割らない'
        end

        # initial: があれば、表示名ではなくその字を使う（talk-avatar-initial-spec.md §2.2）。
        def test_should_prefer_initial_over_name
          assert_equal '佐藤', Gen.avatar_glyph(character(name: '佐藤', initial: '佐藤'))
          assert_equal 'AE', Gen.avatar_glyph(character(name: 'アインシュタイン', initial: 'AE'))
        end

        # 1 文字は測らずに今までの大きさで描く。2 文字は測って円の中の箱に収まるよう縮め、
        # 収まるなら上限のまま。漢字 2 字（佐藤 396 × 184）は 136pt、欧字 2 字（AE 239 × 141）は 200pt。
        def test_should_fit_two_graphemes_into_the_circle
          one = FakeTools.new
          assert_equal Gen::POINTSIZE, Gen.fit_pointsize('遙', one)
          assert_empty one.measured, '1 文字は測らない'

          kanji = FakeTools.new(size: [396, 184])
          assert_equal 136, Gen.fit_pointsize('佐藤', kanji)
          assert_equal [{ glyph: '佐藤', pointsize: Gen::POINTSIZE, font: Gen.font_path }], kanji.measured

          assert_equal Gen::POINTSIZE, Gen.fit_pointsize('AE', FakeTools.new(size: [239, 141]))
          assert_equal Gen::POINTSIZE, Gen.fit_pointsize('AE', FakeTools.new(size: nil)), '測れなければ上限で描く'
        end

        # 測った大きさで描き、大きさが違えば別のキャッシュになる。
        def test_should_render_two_graphemes_with_fitted_pointsize
          tools = FakeTools.new(size: [396, 184])
          src = in_tmp_workspace do
            Gen.generate(character(name: '佐藤', initial: '佐藤'), source_filename: 'x.md', tools:)
          end

          assert_equal 136, tools.calls.first[:pointsize]
          assert_equal '佐藤', tools.calls.first[:glyph]
          assert_includes src, Gen.cache_key('佐藤', ThemeColor.to_hex6('purple'), '#ffffff', 136)
        end

        # 1 文字のキーは、字を指定できるようになる前と同じ式（既存のキャッシュを使い続ける）。
        def test_should_keep_single_glyph_cache_key
          assert_equal Gen.cache_key('遙', '#7c3aed', '#ffffff'), Gen.cache_key('遙', '#7c3aed', '#ffffff', 200)
          refute_equal Gen.cache_key('佐藤', '#7c3aed', '#ffffff', 136), Gen.cache_key('佐藤', '#7c3aed', '#ffffff', 200)
        end

        # ImageMagick が解釈する頭の @（ファイルの読み込み）・%（書式）・\（逃がし）を逃がす。
        def test_should_escape_text_for_imagemagick
          assert_equal '\\@a', Gen.magick_text('@a')
          assert_equal 'a@', Gen.magick_text('a@'), '頭以外の @ はそのまま'
          assert_equal '%%w', Gen.magick_text('%w')
          assert_equal 'a\\\\b', Gen.magick_text('a\\b')
          assert_equal '佐藤', Gen.magick_text('佐藤')
        end

        # 暗い地色には白、明るい地色には濃色を載せる。
        def test_should_pick_readable_foreground
          assert_equal Gen::LIGHT_TEXT, Gen.foreground_hex('#7c3aed'), 'purple は暗いので白'
          assert_equal Gen::DARK_TEXT, Gen.foreground_hex('#f0e68c'), '淡い色は濃色'
        end

        # 話者色が未指定ならテーマ色を地色に使う。
        def test_should_fall_back_to_theme_color
          assert_equal ThemeColor.to_hex6('purple'), Gen.background_hex(character(name: 'あ', color: 'purple'))
          assert_equal Gen.theme_hex, Gen.background_hex(character(name: 'あ', color: nil))
        end

        # 同じ入力は同じキー、色や文字が変われば別キー（内容アドレス）。
        def test_should_be_content_addressed
          a = Gen.cache_key('遙', '#7c3aed', '#ffffff')
          assert_equal a, Gen.cache_key('遙', '#7c3aed', '#ffffff')
          refute_equal a, Gen.cache_key('未', '#7c3aed', '#ffffff')
          refute_equal a, Gen.cache_key('遙', '#0ea5e9', '#ffffff')
        end

        # 生成に成功すると参照パスを返し、asset_prefix は付けない（生成物の規約）。
        def test_should_return_workspace_relative_path_without_asset_prefix
          tools = FakeTools.new
          src = in_tmp_workspace { Gen.generate(character(name: '遙香'), source_filename: 'x.md', tools:) }

          assert_match %r{\Aimages/talk-avatars/\h{16}\.webp\z}, src
          refute_includes src, Common.asset_prefix
          assert_equal '遙', tools.calls.first[:glyph]
          assert_equal ThemeColor.to_hex6('purple'), tools.calls.first[:background]
        end

        # magick 不在なら 🟡 を出して nil（アバターなしへ縮退）。
        def test_should_degrade_when_tool_missing
          src = in_tmp_workspace do
            Gen.generate(character(name: '遙香'), source_filename: 'x.md', tools: FakeTools.new(available: false))
          end

          assert_nil src
        end

        # 表示名が空なら生成しない。
        def test_should_skip_when_name_empty
          char = TalkRegistry::Character.new(key: 'k', name: '', color: 'purple', avatar: 'auto', side: 'left')
          assert_nil Gen.generate(char, source_filename: 'x.md', tools: FakeTools.new)
        end

        # 生成物とキャッシュを一時ディレクトリへ隔離して実行する。
        def in_tmp_workspace
          Dir.mktmpdir('vs-avatar') do |dir|
            saved_cache = Common.method(:cache_dir)
            saved_html = Common.const_get(:BUILD_HTML_DIR)
            Common.define_singleton_method(:cache_dir) { File.join(dir, 'cache') }
            Common.send(:remove_const, :BUILD_HTML_DIR)
            Common.const_set(:BUILD_HTML_DIR, File.join(dir, 'html'))
            begin
              return yield
            ensure
              Common.define_singleton_method(:cache_dir, saved_cache)
              Common.send(:remove_const, :BUILD_HTML_DIR)
              Common.const_set(:BUILD_HTML_DIR, saved_html)
            end
          end
        end
      end
    end
  end
end
