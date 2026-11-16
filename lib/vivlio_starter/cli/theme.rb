# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme.rb
# ================================================================
# 責務:
#   book.yml の theme.name から、本の themes/<名前>/ のテーマを選ぶ（theme-contract-spec.md §3・§7.1）。
#
# 探す場所:
#   本の themes/ だけを探す。gem や npm の中のテーマは直接は読まない（同 §7.1）。同梱のテーマ
#   （BUNDLED_ROOT）を見るのは、対応するテーマの名前を著者に示すときだけである。
#
# 誤りの扱い:
#   Theme.resolve は誤りを Theme::Error で上げる。著者に 🔴 で示すのは
#   Guards::TraitCombinationCheck（vs build と vs preflight の入口）。入口の CSS を書く
#   Css::EntryWriter は Theme.selected を読み、テーマが読めなければテーマ無しで書く
#   （ビルドは入口の検査で止まっている。直接ビルドとテストは、テーマ無しで組める）。
# ================================================================

require_relative 'config_keys'
require_relative 'theme/manifest'
require_relative 'theme/contract'

module VivlioStarter
  module CLI
    # テーマの選択
    module Theme
      # 本のルートからの、テーマを置くディレクトリ
      DIR = 'themes'

      # 同梱のテーマ（雛形の写し）。正典はリポジトリの直下の themes/
      BUNDLED_ROOT = File.expand_path('../../project_scaffold', __dir__)

      # 書いていない supports: の軸の値（土台のテーマも書いていないとき）。
      # 出力先は省略すると四つ全部（theme-contract-spec.md §3.1）。組方向とレイアウトは、
      # 1.x からある横書き・リフローの本だけを組めるとみなす
      DEFAULT_SUPPORTS = { writing_mode: %i[horizontal], layout: %i[reflowable],
                           targets: %i[pdf print_pdf epub kindle] }.freeze

      # テーマを読めない・使えないときの誤り。detail は Guards の Violation へそのまま渡す
      class Error < StandardError
        attr_reader :detail

        def initialize(message, detail: nil)
          super(message)
          @detail = detail
        end
      end

      # 選ばれたテーマと、その土台（extends: の先。無ければ nil）
      Resolved = Data.define(:manifest, :base) do
        # 読む順（土台 → 自分。theme-contract-spec.md §3.2）
        def chain = [base, manifest].compact

        def name = manifest.name

        # theme 層に入る CSS（本のルートからの相対パス）
        def styles = chain.flat_map { |theme| theme.styles.map { File.join(theme.dir, it) } }

        # tokens 層に入る値（`--book-` を除いた名前 → 値）。自分の値が土台の値に勝つ
        def tokens = chain.map(&:tokens).reduce({}, :merge)

        # target 層に入る出力先の CSS（css-layer-restructure-spec.md §5 の 4・5）
        def target_files(kind, target) = chain.flat_map { it.target_files(kind, target) }

        # 対応する組方向・レイアウト・出力先。書いていない軸は土台から、土台も書いていなければ既定
        def supports
          DEFAULT_SUPPORTS.to_h { |axis, default| [axis, manifest.supports[axis] || base&.supports&.[](axis) || default] }
        end

        # 知らないキーの 🟡（土台の分も）
        def warnings = chain.flat_map(&:warnings)
      end

      module_function

      # 名前からテーマを読む。土台（extends:）は 1 段だけ読む
      # @param name [String] theme.name
      # @param root [String] 本のルート
      # @return [Resolved]
      # @raise [Error]
      def resolve(name, root: Dir.pwd)
        manifest = load_named(name, root:)
        base = manifest.extends && load_base(manifest, root:)
        Resolved.new(manifest:, base:)
      end

      # 設定で選ばれたテーマ。読めなければ nil（誤りは入口の検査が示す）。
      # 入口の CSS は種類と出力先ごとに何度も書くので、設定と作業ディレクトリが同じ間は読み直さない
      # @return [Resolved, nil]
      def selected(config = Common::CONFIG)
        cached = @selected
        return cached[:theme] if cached && cached[:config].equal?(config) && cached[:pwd] == Dir.pwd
      
        theme = config && begin
          resolve(selected_name(config))
        rescue Error
          nil
        end
        @selected = { config:, pwd: Dir.pwd, theme: }
        theme
      end

      # theme.name（書いていなければ既定の standard）
      def selected_name(config)
        name = config&.dig(:theme, :name).to_s.strip
        name.empty? ? ConfigKeys::KEYS.fetch(%i[theme name]).default : name
      end

      # 本の themes/ と同梱のテーマのうち、読めるものの名前と宣言。同じ名前は本のものを採る。
      # 対応するテーマを著者に示すために使う
      # @return [Hash{String => Resolved}]
      def available(root: Dir.pwd, bundled_root: BUNDLED_ROOT)
        [root, bundled_root].each_with_object({}) do |base_root, found|
          Dir.glob('*/theme.yml', base: File.join(base_root, DIR)).each do |file|
            name = File.dirname(file)
            next if found.key?(name)

            found[name] = resolve(name, root: base_root)
          rescue Error
            next
          end
        end
      end

      # テーマの名前の誤り（形・置き場）を、本の themes/ にあるテーマの名前と一緒に示す
      # @param wanted_by [String] 名前を書いた場所（著者に示し、直す場所として案内する）
      def load_named(name, root:, wanted_by: 'config/book.yml の theme.name')
        dir = File.join(DIR, name.to_s)
        unless name.to_s.match?(Manifest::NAME_PATTERN) && File.file?(File.join(root, dir, Manifest::FILE))
          names = Dir.glob('*/theme.yml', base: File.join(root, DIR)).map { File.dirname(it) }.sort
          detail = if names.empty? then "#{dir}/#{Manifest::FILE} を置いてください"
                   else "本にあるテーマ: #{names.join('・')}（#{wanted_by} に書きます）"
                   end
          raise Error.new("#{wanted_by} のテーマ #{name} が、本の #{DIR}/ にありません", detail:)
        end

        Manifest.load(dir, root:).tap { Contract.check!(it) }
      end

      def load_base(manifest, root:)
        base = load_named(manifest.extends, root:, wanted_by: "#{File.join(manifest.dir, Manifest::FILE)} の extends:")
        return base unless base.extends

        raise Error.new("テーマ #{manifest.name} の土台 #{base.name} が、さらに extends: #{base.extends} を持っています",
                        detail: "extends: は 1 段だけです。#{manifest.name} の extends: を #{base.extends} にするか、" \
                                "#{base.name} の extends: を消してください")
      end
    end
  end
end
