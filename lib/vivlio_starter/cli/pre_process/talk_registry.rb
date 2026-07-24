# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/talk_registry.rb
# ================================================================
# 責務:
#   config/talk.yml を読み、会話文（:::{.talk}）記法が使う
#   「表示設定（display:）」と「話者定義」を正規化して提供する
#   （talk-display-options-spec.md §2.1）。
#
# ファイル構成（talk.yml）:
#   display:              ← 表示設定（予約キー。本文の :::{.talk ...} が優先）
#     style: chat
#     name: true
#     avatar: on
#     separator: "："
#   haruka:               ← 以降のトップレベルキーはすべて話者
#     name: 遙香
#     color: purple
#     avatar: haruka.webp
#     side: left
#
# なぜ話者をネストせず平置きするのか:
#   display: を別セクションへ切り出した時点で「表示の name（真偽値）」と
#   「話者の name（表示名）」の衝突は解消する。話者を characters: 配下へ
#   さらに寄せると旧 characters.yml からの移行で全行の字下げが必要になるため、
#   予約キーを display: ひとつに絞って平置きのままとする。
#
# 正規化の要点:
#   - 簡易形（値が文字列＝色）と詳細形（値がマップ）を Character へ吸収する
#   - side 省略時は出現順に left, right, … と交互自動割当（明示指定は値のみ上書き）
#   - color は ThemeValidator の色検証を流用。無効値は 🟡＋テーマ色フォールバック（nil）
#   - 真偽値は Common.truthy?（true/yes/on/1）。キーの有無で「未指定」と「明示 false」を区別する
#   - 壊れた YAML は 🔴＋行番号。ビルドは止めない
# ================================================================

require 'yaml'
require_relative '../common'
# theme_validator / frontmatter_generator は色検証に使うが、これらを top で require すると
# frontmatter_generator → book_settings_css → talk_registry → theme_validator の
# ロード循環に入り、theme_validator の load 時 FrontmatterGenerator::ALLOWED_COLORS 参照が
# 未定義で落ちる。実際に使うのはビルド時（全ファイル load 済み）なので遅延 require する。

module VivlioStarter
  module CLI
    module PreProcessCommands
      # config/talk.yml の読み込みと正規化
      module TalkRegistry
        # 正規化済みのキャラクター 1 人分。color/avatar は省略時 nil。
        Character = Data.define(:key, :name, :color, :avatar, :side)

        # 会話文の表示設定。ブロック指定はこの Data の #with で上書きする。
        TalkDisplay = Data.define(:style, :name, :avatar, :separator)

        # 表示設定を置くトップレベルの予約キー（これ以外はすべて話者とみなす）。
        DISPLAY_KEY = 'display'

        # 受理する表示形式。
        STYLES = %i[chat inline].freeze

        # アバターの表示モード（talk-auto-avatar-spec.md §1.1）。
        #   :on   … avatar: に画像を指定した話者だけ表示
        #   :auto … 画像があればそれ、無ければ簡易アバターを自動生成
        #   :off  … 表示しない
        AVATAR_MODES = %i[on auto off].freeze

        # 話者の avatar: にファイル名の代わりに書くと自動生成になる値。
        AVATAR_AUTO = 'auto'

        # 組み込み既定（talk.yml に display: が無い／キーが欠けているときの値）。
        DEFAULT_DISPLAY = TalkDisplay.new(style: :chat, name: true, avatar: :on, separator: '：').freeze

        # 正規化結果の集合。present はファイルの実在（.talk 使用時のエラー分岐に使う）。
        class Registry
          attr_reader :characters, :display

          # @param characters [Array<Character>] 正規化済みキャラクター（出現順）
          # @param display [TalkDisplay] 表示設定
          # @param present [Boolean] config/talk.yml が実在したか
          def initialize(characters, display:, present:)
            @characters = characters.freeze
            @by_key = characters.to_h { [it.key, it] }.freeze
            @display = display
            @present = present
          end

          def [](key) = @by_key[key.to_s]
          def key?(key) = @by_key.key?(key.to_s)
          def present? = @present
          def empty? = @characters.empty?

          # 色を明示指定した（有効な）キャラクターのみ（生成 CSS の対象）。
          def with_color = @characters.select(&:color)
        end

        module_function

        # config/talk.yml の既定パス（config ディレクトリ直下）。
        def default_path = File.join(Common.config_dir, 'talk.yml')

        # 旧仕様のファイル。存在したら移行を促す（§1.7）。
        def legacy_path = File.join(Common.config_dir, 'characters.yml')

        # ファイルを読んで Registry を返す。存在しなければ空（present: false）。
        # @param path [String] 読み込み対象（既定は default_path）
        # @return [Registry]
        def load(path = default_path)
          unless File.exist?(path)
            warn_legacy_characters_yml if File.exist?(legacy_path)
            return Registry.new([], display: DEFAULT_DISPLAY, present: false)
          end

          from_hash(read_yaml(path))
        end

        # ビルド 1 回につき 1 度だけ読む共有インスタンス（前処理は章ごとに走るため）。
        # 無効色などの警告もここで一度きりに集約される。テストは reset! で破棄する。
        def shared = (@shared ||= load)

        def reset! = (@shared = nil)

        # Hash（YAML 相当）から Registry を組む。テストと load から共用する。
        def from_hash(raw)
          hash = raw.is_a?(Hash) ? raw : {}
          Registry.new(build_characters(hash), display: build_display(hash[DISPLAY_KEY]), present: true)
        end

        # display: セクションを TalkDisplay へ正規化する。キーが無ければ組み込み既定を使う。
        def build_display(raw)
          return DEFAULT_DISPLAY unless raw.is_a?(Hash)

          DEFAULT_DISPLAY.with(
            style: parse_style(raw['style']),
            name: parse_flag(raw, 'name', DEFAULT_DISPLAY.name),
            avatar: raw.key?('avatar') ? parse_avatar_mode(raw['avatar']) : DEFAULT_DISPLAY.avatar,
            separator: raw.key?('separator') ? raw['separator'].to_s : DEFAULT_DISPLAY.separator
          )
        end

        # アバターの表示モードを解決する。`auto` を先に見てから真偽解釈する
        # （Common.truthy? は 'auto' を偽と判定するため）。
        def parse_avatar_mode(raw)
          value = raw.to_s.strip.downcase
          return :auto if value == AVATAR_AUTO

          Common.truthy?(value) ? :on : :off
        end

        # style 値を Symbol へ。未指定は既定、未知値は 🟡 で既定へフォールバック。
        def parse_style(raw)
          value = raw.to_s.strip.downcase
          return DEFAULT_DISPLAY.style if value.empty?
          return value.to_sym if STYLES.include?(value.to_sym)

          Common.log_warn(
            "config/talk.yml: display.style '#{raw}' は不明な表示形式です。#{DEFAULT_DISPLAY.style} で続行します。",
            detail: "指定できるのは #{STYLES.join(' / ')} です"
          )
          DEFAULT_DISPLAY.style
        end

        # 真偽キーを解決する。**キーが無ければ既定を引き継ぐ**（明示 false と区別する）。
        def parse_flag(raw, key, fallback)
          raw.key?(key) ? Common.truthy?(raw[key]) : fallback
        end

        # display: を除くトップレベルのキーをすべて話者として正規化する。
        # @return [Array<Character>]
        def build_characters(raw)
          # side 省略時は「出現順」で left, right, left, … と交互に割当てる（位置ベース）。
          # 明示指定は値のみ上書きし、位置カウンタ自体は全話者で進める——そうすれば
          # 一部だけ side を明示しても、残りの自動割当が出現順の交互ストライプを保つ。
          position = 0
          raw.filter_map do |key, spec|
            key = key.to_s.strip
            next if key.empty? || key == DISPLAY_KEY

            name, color, avatar, side = extract(spec, key)
            side = position.even? ? 'left' : 'right' unless %w[left right].include?(side)
            position += 1
            Character.new(key:, name:, color:, avatar:, side:)
          end
        end

        # 1 エントリの値（簡易形＝色文字列 / 詳細形＝マップ）から属性 4 つを取り出す。
        # @return [Array(String, String, String, String)] name, color, avatar, side（未指定は nil/空）
        def extract(spec, key)
          if spec.is_a?(Hash)
            name = blank_to_nil(spec['name'] || spec[:name]) || key
            [name, validate_color(spec['color'] || spec[:color], key),
             blank_to_nil(spec['avatar'] || spec[:avatar]), (spec['side'] || spec[:side]).to_s.strip.downcase]
          else
            # 簡易形: 値が色（テーマ色名 or HEX）。表示名はキー、アバターなし、side 自動。
            [key, validate_color(spec, key), nil, '']
          end
        end

        # 色の妥当性を検証する。無効値は 🟡 で警告してテーマ色へフォールバック（nil を返す）。
        # 未指定（空）は警告せず nil（＝テーマアクセント色を使う）。
        def validate_color(raw, key)
          value = raw.to_s.strip
          return nil if value.empty?
          return value if color_valid?(value)

          Common.log_warn(
            "config/talk.yml: キャラクター '#{key}' の色 '#{raw}' は無効です。テーマ色でビルドを続行します。",
            detail: "指定できる色: #{allowed_colors.join(' / ')}、" \
                    "または '#4f46e5' のような HEX（#rrggbb / #rrggbbaa）"
          )
          nil
        end

        # ThemeValidator の色検証を流用する（遅延 require でロード循環を回避）。
        def color_valid?(value)
          require_relative 'theme_validator'
          ThemeValidator.valid_color?(value)
        end

        def allowed_colors
          require_relative 'frontmatter_generator'
          FrontmatterGenerator::ALLOWED_COLORS
        end

        def blank_to_nil(value)
          s = value.to_s.strip
          s.empty? ? nil : s
        end

        # 旧 config/characters.yml が残っている場合の移行案内（§1.7）。
        def warn_legacy_characters_yml
          Common.log_error(
            'config/characters.yml は config/talk.yml へ移行してください（旧ファイルは読み込まれません）',
            detail: "→ 1. config/characters.yml を config/talk.yml へリネーム\n" \
                    "→ 2. 各話者の `icon:` を `avatar:` へ書き換え\n" \
                    '→ 3. 表示設定を変えたい場合はファイル先頭に display: セクションを追加'
          )
        end

        # 壊れた YAML は 🔴＋行番号で報告し、空（{}）として扱う（ビルドは止めない）。
        def read_yaml(path)
          YAML.safe_load(File.read(path, encoding: 'utf-8'), aliases: true)
        rescue Psych::SyntaxError => e
          Common.log_error(
            "config/talk.yml の解析に失敗しました（#{e.line}行目付近）",
            detail: e.problem.to_s
          )
          nil
        end
      end
    end
  end
end
