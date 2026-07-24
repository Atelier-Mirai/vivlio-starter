# frozen_string_literal: true

# ================================================================
# Test: talk_registry_test.rb
# ================================================================
# 検証内容（characters-dialogue-spec.md §3-1）:
#   TalkRegistry が config/talk.yml を正規化する。
#   - 簡易形（値＝色）／詳細形（値＝マップ）の吸収
#   - side 自動割当（left→right 交互）と明示指定の尊重
#   - 色検証（無効値はテーマ色フォールバック＝nil）
#   - ファイル不在（present: false）／YAML 破損時のエラー
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'
require 'tmpdir'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class TalkRegistryTest < Minitest::Test
        Registry = TalkRegistry
        LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

        # 色検証・YAML エラーはログ副作用を伴うため、出力を黙らせて DI で隔離する。
        def setup
          @saved = LOG_METHODS.to_h { [it, Common.method(it)] }
          LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        end

        def teardown
          @saved&.each { |name, m| Common.define_singleton_method(name, m) }
        end

        # display: が無ければ組み込み既定（chat / name on / avatar on / 全角コロン）。
        def test_should_use_builtin_display_defaults
          d = Registry.from_hash({ 'a' => 'teal' }).display

          assert_equal :chat, d.style
          assert d.name
          assert_equal :on, d.avatar
          assert_equal '：', d.separator
        end

        # display: の各キーを正規化する。真偽値は on/true/yes/1 を真とする。
        def test_should_normalize_display_section
          d = Registry.from_hash({
            'display' => { 'style' => 'inline', 'name' => 'off', 'avatar' => 'on', 'separator' => '— ' }
          }).display

          assert_equal :inline, d.style
          refute d.name
          assert_equal :on, d.avatar
          assert_equal '— ', d.separator
        end

        # キーを書かなければ「未指定」として既定を引き継ぐ（明示 false とは区別する）。
        def test_should_keep_defaults_for_absent_display_keys
          d = Registry.from_hash({ 'display' => { 'style' => 'inline' } }).display

          assert_equal :inline, d.style
          assert d.name, 'name 未指定は既定の true'
          assert_equal :on, d.avatar, 'avatar 未指定は既定の :on'
        end

        # avatar は on / off / auto の 3 値（auto は truthy? より先に判定する）。
        def test_should_parse_avatar_as_tri_state
          assert_equal :auto, Registry.from_hash({ 'display' => { 'avatar' => 'auto' } }).display.avatar
          assert_equal :on, Registry.from_hash({ 'display' => { 'avatar' => 'on' } }).display.avatar
          assert_equal :on, Registry.from_hash({ 'display' => { 'avatar' => true } }).display.avatar
          assert_equal :off, Registry.from_hash({ 'display' => { 'avatar' => 'off' } }).display.avatar
          assert_equal :on, Registry.from_hash({}).display.avatar, '未指定は既定の :on'
        end

        # 未知の style は 🟡 で既定（chat）へフォールバックする。
        def test_should_fall_back_on_unknown_style
          d = Registry.from_hash({ 'display' => { 'style' => 'balloon' } }).display

          assert_equal :chat, d.style
        end

        # display は予約キー。話者としては扱わない。
        def test_should_not_treat_display_as_character
          reg = Registry.from_hash({ 'display' => { 'style' => 'chat' }, 'a' => 'teal' })

          refute reg.key?('display')
          assert_equal %w[a], reg.characters.map(&:key)
        end

        # 簡易形: 値が色。表示名はキー、アイコンなし、side は自動で left。
        def test_should_absorb_simple_form_as_color
          reg = Registry.from_hash({ 'hanako' => 'teal' })
          char = reg['hanako']

          assert_equal 'hanako', char.key
          assert_equal 'hanako', char.name
          assert_equal 'teal', char.color
          assert_nil char.avatar
          assert_equal 'left', char.side
        end

        # 詳細形: 表示名・色・アイコン・side を取り出す。
        def test_should_absorb_detailed_form
          reg = Registry.from_hash({
            'sensei' => { 'name' => '山田先生', 'color' => 'indigo', 'avatar' => 'sensei.webp', 'side' => 'right' }
          })
          char = reg['sensei']

          assert_equal '山田先生', char.name
          assert_equal 'indigo', char.color
          assert_equal 'sensei.webp', char.avatar
          assert_equal 'right', char.side
        end

        # 表示名省略時はキーをそのまま表示名にする。
        def test_should_default_name_to_key_when_omitted
          reg = Registry.from_hash({ 'yamada' => { 'color' => '#1565c0' } })
          assert_equal 'yamada', reg['yamada'].name
          assert_equal '#1565c0', reg['yamada'].color
        end

        # side 省略時は出現順に left, right, left … と交互自動割当。
        def test_should_auto_assign_side_alternating
          reg = Registry.from_hash({ 'a' => 'teal', 'b' => 'indigo', 'c' => 'red' })

          assert_equal 'left', reg['a'].side
          assert_equal 'right', reg['b'].side
          assert_equal 'left', reg['c'].side
        end

        # 明示 side は値のみ上書きし、位置カウンタは全話者で進む（残りの自動割当は出現順を保つ）。
        def test_should_respect_explicit_side_over_auto_position
          reg = Registry.from_hash({
            'a' => { 'side' => 'right' }, # pos0 明示 right（値のみ上書き）
            'b' => 'teal',                # pos1 省略 → right
            'c' => 'indigo'               # pos2 省略 → left
          })

          assert_equal 'right', reg['a'].side
          assert_equal 'right', reg['b'].side
          assert_equal 'left', reg['c'].side
        end

        # 無効な色はテーマ色フォールバック（color=nil）。キャラクター自体は残る。
        def test_should_nil_out_invalid_color
          reg = Registry.from_hash({ 'x' => 'not-a-color' })

          assert reg.key?('x')
          assert_nil reg['x'].color
        end

        # with_color は色を明示した（有効な）キャラクターのみ返す（生成 CSS の対象）。
        def test_should_filter_with_color
          reg = Registry.from_hash({
            'a' => 'teal', 'b' => { 'name' => '名前だけ' }, 'c' => 'bad-color'
          })

          keys = reg.with_color.map(&:key)
          assert_equal %w[a], keys
        end

        # ファイル不在なら空・present: false（.talk 使用時の作成促しに使う）。
        def test_should_be_absent_when_file_missing
          reg = Registry.load(File.join(Dir.tmpdir, 'no-such-talk-#{object_id}.yml'))

          assert reg.empty?
          refute reg.present?
        end

        # 実在ファイルは present: true。空ファイル（定義ゼロ）でも present: true。
        def test_should_load_from_file_and_normalize
          Dir.mktmpdir('vs-talk') do |dir|
            path = File.join(dir, 'talk.yml')
            File.write(path, "hanako: teal\nsensei:\n  name: 山田先生\n  color: indigo\n")
            reg = Registry.load(path)

            assert reg.present?
            assert_equal 'teal', reg['hanako'].color
            assert_equal '山田先生', reg['sensei'].name
            assert_equal 'right', reg['sensei'].side, '2 人目は自動で right'
          end
        end

        # YAML 破損時は空だが present: true（エラーは 🔴 で報告済み・ビルドは止めない）。
        def test_should_return_present_but_empty_on_broken_yaml
          Dir.mktmpdir('vs-talk') do |dir|
            path = File.join(dir, 'talk.yml')
            File.write(path, "hanako: teal\n  : broken\n:::\n")
            reg = Registry.load(path)

            assert reg.present?
            assert reg.empty?
          end
        end
      end
    end
  end
end
