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
#     avatar_size: 12     ← アバターの直径（mm）。全話者の既定
#   haruka:               ← 以降のトップレベルキーはすべて話者
#     name: 遙香
#     color: purple
#     avatar: haruka.webp
#     avatar_size: 15     ← この話者だけの直径（display の値より優先）
#     side: left
#
# なぜ話者をネストせず平置きするのか:
#   display: を別セクションへ切り出した時点で「表示の name（真偽値）」と
#   「話者の name（表示名）」の衝突は解消する。さらに話者用の親キーを設けても
#   曖昧さは減らず著者の字下げが 1 段深くなるだけなので、予約キーを display:
#   ひとつに絞って平置きのままとする。
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
require_relative '../units'
# theme_validator / frontmatter_generator は色検証に使うが、これらを top で require すると
# frontmatter_generator → book_settings_css → talk_registry → theme_validator の
# ロード循環に入り、theme_validator の load 時 FrontmatterGenerator::ALLOWED_COLORS 参照が
# 未定義で落ちる。実際に使うのはビルド時（全ファイル load 済み）なので遅延 require する。

module VivlioStarter
  module CLI
    module PreProcessCommands
      # config/talk.yml の読み込みと正規化
      module TalkRegistry
        # 正規化済みのキャラクター 1 人分。color/avatar/initial/avatar_size は省略時 nil。
        # initial は簡易アバターに入れる字、avatar_size はこの話者のアバターの直径（mm の Float）
        # （talk-avatar-initial-spec.md）。既定を nil にして、これらを指定しない呼び出し
        # （テストの組み立てなど）は今までどおり書けるようにする。
        Character = Data.define(:key, :name, :color, :avatar, :side, :initial, :avatar_size) do
          def initialize(initial: nil, avatar_size: nil, **) = super
        end

        # 会話文の表示設定。ブロック指定はこの Data の #with で上書きする。
        # avatar_size は全話者のアバターの直径の既定（mm の Float）。未指定は nil で、CSS の既定
        # （12mm）を使う。話者の avatar_size が優先する。大きさは話者の絵に合わせて決めるもので、
        # 会話のまとまりごとに変える理由がないため、ブロック指定（:::{.talk ...}）では上書きしない
        # （talk-avatar-initial-spec.md §7.2）。
        TalkDisplay = Data.define(:style, :name, :avatar, :separator, :avatar_size)

        # 表示設定を置くトップレベルの予約キー（これ以外はすべて話者とみなす）。
        DISPLAY_KEY = 'display'

        # 受理する表示形式。
        STYLES = %i[chat inline].freeze

        # アバターの表示モード（talk-auto-avatar-spec.md §1.1）。
        #   :on   … avatar: に画像を指定した話者だけ表示
        #   :auto … 画像があればそれ、無ければ簡易アバターを自動生成
        #   :off  … 表示しない
        AVATAR_MODES = %i[on auto off].freeze

        # 各モードとして受理する綴り。YAML は `avatar: on` / `off` を真偽値へ解決する
        # （Psych の YAML 1.1）ため、"true" / "false" も同じモードの綴りとして受ける。
        AVATAR_MODE_SPELLINGS = {
          on: %w[on true yes 1],
          auto: %w[auto],
          off: %w[off false no 0]
        }.freeze

        # 話者の avatar: にファイル名の代わりに書くと自動生成になる値。
        AVATAR_AUTO = 'auto'

        # 組み込み既定（talk.yml に display: が無い／キーが欠けているときの値）。
        DEFAULT_DISPLAY = TalkDisplay.new(style: :chat, name: true, avatar: :on, separator: '：',
                                          avatar_size: nil).freeze

        # avatar_size を省略したときの直径。CSS（components.css の var() の既定）と同じ値で、
        # 警告文で「既定の 12mm」と示すためだけに持つ。
        DEFAULT_AVATAR_SIZE_MM = 12

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

          # アバターの直径を指定した話者のみ（生成 CSS の対象）。
          def with_avatar_size = @characters.select(&:avatar_size)
        end

        module_function

        # config/talk.yml の既定パス（config ディレクトリ直下）。
        def default_path = File.join(Common.config_dir, 'talk.yml')

        # ファイルを読んで Registry を返す。存在しなければ空（present: false）。
        # @param path [String] 読み込み対象（既定は default_path）
        # @return [Registry]
        def load(path = default_path)
          return Registry.new([], display: DEFAULT_DISPLAY, present: false) unless File.exist?(path)

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
            avatar: raw.key?('avatar') ? parse_config_avatar_mode(raw['avatar']) : DEFAULT_DISPLAY.avatar,
            separator: raw.key?('separator') ? raw['separator'].to_s : DEFAULT_DISPLAY.separator,
            avatar_size: raw.key?('avatar_size') ? parse_avatar_size(raw['avatar_size']) : nil
          )
        end

        # アバターの直径を mm で読む。単位なしの数は mm とし、15mm・1.5cm・42pt も
        # book.yml と同じく Units.length_to_mm で mm に直す（`15` を見て単位に迷った著者が
        # `15mm` と書いても通るように）。em・%・px・数でない値・0 以下は 🟡 で既定へ戻す。
        # display と話者の両方から呼ぶので、警告には書いた場所と戻り先を添える。
        # @param where [String] 警告に出す書いた場所（"display.avatar_size" など）
        # @param fallback [String] 読めなかったときに使う大きさの説明
        # @return [Float, nil] 直径（mm）。読めなければ nil
        def parse_avatar_size(raw, where: 'display.avatar_size', fallback: "既定の #{DEFAULT_AVATAR_SIZE_MM}mm")
          mm = Units.length_to_mm(raw)
          return mm if mm&.positive?

          Common.log_warn(
            "config/talk.yml: #{where} '#{raw}' は読めない大きさです。#{fallback} で続行します。",
            detail: '→ 直径を mm で書いてください（例: avatar_size: 15 / avatar_size: 15mm）'
          )
          nil
        end

        # アバターの表示モードを解決する。未知の綴りは nil を返し、呼び出し側が
        # 出現位置つきで警告する（style と同じ流儀）。ここで黙って :off へ倒すと、
        # `avatar: onn` のような綴り間違い 1 つで全話者のアバターが理由も示されず消える。
        # @param raw [Object] talk.yml の値（YAML が真偽値へ解決済みのこともある）
        # @return [Symbol, nil] :on / :auto / :off。未知の綴りは nil
        def parse_avatar_mode(raw)
          value = raw.to_s.strip.downcase
          AVATAR_MODES.find { AVATAR_MODE_SPELLINGS[it].include?(value) }
        end

        # talk.yml の display.avatar を解決する。未知の綴りは 🟡 で既定へ落とす。
        def parse_config_avatar_mode(raw)
          parse_avatar_mode(raw) || begin
            Common.log_warn(
              "config/talk.yml: display.avatar '#{raw}' は不明な表示モードです。" \
              "#{DEFAULT_DISPLAY.avatar} で続行します。",
              detail: "指定できるのは #{AVATAR_MODES.join(' / ')} です" \
                      '（on=画像のある話者だけ表示 / auto=無ければ自動生成 / off=表示しない）'
            )
            DEFAULT_DISPLAY.avatar
          end
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

            name, color, avatar, side, initial, avatar_size = extract(spec, key)
            side = position.even? ? 'left' : 'right' unless %w[left right].include?(side)
            position += 1
            Character.new(key:, name:, color:, avatar:, side:, initial:, avatar_size:)
          end
        end

        # 1 エントリの値（簡易形＝色文字列 / 詳細形＝マップ）から属性 6 つを取り出す。
        # @return [Array(String, String, String, String, String, Float)]
        #   name, color, avatar, side, initial, avatar_size（未指定は nil/空）
        def extract(spec, key)
          if spec.is_a?(Hash)
            name = blank_to_nil(spec['name'] || spec[:name]) || key
            [name, validate_color(spec['color'] || spec[:color], key),
             blank_to_nil(spec['avatar'] || spec[:avatar]), (spec['side'] || spec[:side]).to_s.strip.downcase,
             validate_initial(spec, key), character_avatar_size(spec, key)]
          else
            # 簡易形: 値が色（テーマ色名 or HEX）。表示名はキー、アバターなし、side 自動。
            [key, validate_color(spec, key), nil, '', nil, nil]
          end
        end

        # 話者の avatar_size。キーが無ければ nil（display.avatar_size か CSS の既定に任せる）。
        # 似顔絵の話者と 1 文字の簡易アバターの話者が同じ本にいると、合う大きさが違う
        # （似顔絵は 12mm では表情が読めず、1 文字は 15mm では大きすぎる）ため話者ごとに持つ。
        def character_avatar_size(spec, key)
          return nil unless spec.key?('avatar_size') || spec.key?(:avatar_size)

          parse_avatar_size(spec['avatar_size'] || spec[:avatar_size],
                            where: "話者 '#{key}' の avatar_size",
                            fallback: 'display.avatar_size（無ければ既定の 12mm）')
        end

        # 簡易アバターに入れる字の上限（talk-avatar-initial-spec.md §5）。
        # 3 文字にすると円の中で 90pt 前後まで縮み、12mm の紙面では読みにくくなる。
        INITIAL_MAX_GRAPHEMES = 2

        # initial: を確かめる。書記素クラスタで数え（絵文字・結合文字を 1 文字とする）、
        # 1〜2 文字なら返す。キーが無ければ nil（表示名の頭 1 文字を使う）。
        # 空や 3 文字以上は 🟡 を出して nil に戻す——アバターは作り続け、ビルドは止めない。
        def validate_initial(spec, key)
          return nil unless spec.key?('initial') || spec.key?(:initial)

          raw = (spec['initial'] || spec[:initial]).to_s.strip
          count = raw.grapheme_clusters.size
          return raw if count.between?(1, INITIAL_MAX_GRAPHEMES)

          shown = count.zero? ? ' が空' :" '#{raw}' は #{count} 文字"
          Common.log_warn(
            "config/talk.yml: 話者 '#{key}' の initial#{shown}です。表示名の頭 1 文字で続行します。",
            detail: "→ initial: には 1〜#{INITIAL_MAX_GRAPHEMES} 文字を書いてください（例: initial: AE）"
          )
          nil
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
