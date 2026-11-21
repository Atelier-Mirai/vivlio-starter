# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/check.rb
# ================================================================
# 責務:
#   本の themes/<名前>/ のテーマを検査し、指摘の一覧を返す（vs theme:check。theme-contract-spec.md §7.2）。
#   表示はしない（ThemeCommands が表示する。vs theme:add・vs theme:new も同じ検査を通す）。
#
# 検査すること:
#   🔴 theme.yml の誤り・契約の版・requires_vs:・extends: の先が無い（Theme.resolve の誤り）
#   🟡 theme.yml の知らないキー
#   🟡 契約 HTML に無いクラス・vs の内部のクラスを選んでいる規則（ContainerClassCheck の逆向き）
#   🟡 層の中の !important（css-layer-restructure-spec.md §2.4・§3.5 の表）
#   🟡 外部の URL（url(http…)・@import）。組むたびにネットワークへ取りにいく
#   🟡 章見出し（h1）・節見出し（h2）の改ページを、公開する変数でなく値で書いた規則。
#      page.chapter_pagebreak・page.section_pagebreak が効かない（theme-contract-spec.md §3.5・§7.2）
#   Kindle に対応するテーマ（supports.targets に kindle）だけ（§3.5）:
#     💡 紙の寸法（clamp()・min()・max()）で Kindle に届かない宣言の数。意図した書き方で、直す対象ではない
#     🟡 それ以外で Kindle に届かない宣言（深い要素の変数・:has()・単位の混ざる calc() など）
#     🟡 kindle_tokens: と kindle*.css の body.vs-kindle の、総称の名前でない書体・--book-font-size・
#        --book-line-height（Kindle では読者が選ぶ値）
#   💡 層を外すと勝ち負けが変わりうる規則の組（静的な判定。確定は vs build --log=debug の要素ごとの判定。
#      css-layer-restructure-spec.md §4.3）
#
# 見る範囲:
#   検査するテーマ自身のファイルだけ。extends: の先のテーマと vs の部品は含めない（§7.2）。
#   Kindle に届くかと層の勝ち負けは、本の stylesheets/ とテーマを入口の CSS に組んで判定する
#   （一時ディレクトリに本の写しを作る。custom.css は空にする）。組方向は、テーマが本の組方向に
#   対応していなければ、テーマの対応する組方向で組む。設定から作る book-settings.css は、
#   本の今の設定のものを使う。
# ================================================================

require 'crass'
require 'fileutils'
require 'tmpdir'
require_relative '../common'
require_relative '../html_contract'
require_relative '../css/bundle'
require_relative '../pre_process/book_settings_css'

module VivlioStarter
  module CLI
    module Theme
      # テーマの検査
      module Check
        # 指摘 1 件。level は :error（🔴）・:warning（🟡）・:hint（💡）
        Finding = Data.define(:level, :message, :detail) do
          def initialize(level:, message:, detail: nil) = super
        end

        # 検査の結果。theme は読めたテーマ（読めなければ nil）
        Report = Data.define(:name, :theme, :findings) do
          def errors = findings.select { it.level == :error }
          def warnings = findings.select { it.level == :warning }
        end

        # Kindle の書体の変数に書ける総称の名前（§3.5）
        GENERIC_FONTS = %w[serif sans-serif monospace].freeze

        # Kindle では読者が選ぶ値の変数（--book- を除いた名前。§3.5）
        READER_TOKENS = %w[font-size line-height].freeze

        # ページの種類の body のクラスのうち、入口の名前と違うもの（HtmlContract の page_kind）
        PAGE_BODY_CLASSES = { 'index' => 'index-page', 'glossary' => 'glossary-page' }.freeze

        # 外部の URL（url(http…)・url(//…)・@import "http…"）
        EXTERNAL_URL = %r{(?:url\(\s*['"]?|@import\s+['"])(?:https?:)?//}i

        # 見出しの改ページを読む設定と、テーマが使う公開する変数（--book- を除いた名前）
        PAGEBREAK_TOKENS = {
          'h1' => ['page.chapter_pagebreak', 'chapter-break-before'],
          'h2' => ['page.section_pagebreak', 'section-break-before']
        }.freeze

        # 改ページを起こさない値。これらは設定と取り合わないので、値で書いてよい
        NON_BREAKING_VALUES = /\A(?:auto|avoid)/

        module_function

        # @param name [String] テーマの名前（本の themes/<名前>/）
        # @param root [String] 本のルート
        # @param config [Data] 本の設定（book-settings.css と body のクラスに使う）
        # @return [Report]
        def run(name, root: Dir.pwd, config: Common::CONFIG)
          theme = Theme.resolve(name, root:)
          manifest = theme.manifest
          own = Dir.glob('**/*.css', base: manifest.path).sort.map { File.join(manifest.dir, it) }
          findings = manifest.warnings.map { Finding.new(level: :warning, message: it) }

          # --- Phase: ファイルごとの字面の検査 ---
          own.each { findings.concat(file_findings(theme, it, root)) }

          # --- Phase: 入口に組んだ CSS の検査（Kindle に届くか・層の勝ち負け） ---
          findings.concat(bundle_findings(theme, own, root, config))
          findings.concat(kindle_token_findings(theme, own, root)) if kindle?(theme)

          Report.new(name:, theme:, findings:)
        rescue Error => e
          Report.new(name:, theme: nil, findings: [Finding.new(level: :error, message: e.message, detail: e.detail)])
        end

        def kindle?(theme) = theme.supports.fetch(:targets).include?(:kindle)

        # ================================================================
        # ファイルごとの字面
        # ================================================================

        # クラス・!important・外部の URL
        def file_findings(theme, file, root)
          css = File.read(File.join(root, file), encoding: 'utf-8')
          lines = uncommented_lines(css)
          own_classes = theme.options.flat_map(&:body_classes)
          findings = HtmlContract.css_classes(css).filter_map do |name|
            next if own_classes.include?(name) || HtmlContract.selectable?(name)

            place = place(file, line_index(lines, ".#{name}"))
            if HtmlContract.lookup(name)
              Finding.new(level: :warning, message: "#{place} の .#{name} は、vs の内部のクラスです",
                          detail: '→ 内部のクラスは、vs の版が変わると予告なく変わります。ほかの保証されたクラスで選んでください')
            else
              Finding.new(level: :warning, message: "#{place} の .#{name} は、契約 HTML に無いクラスです",
                          detail: ['→ どの要素にも当たりません。クラスの名前を確かめてください',
                                   '  テーマが付けるクラスなら、theme.yml の options: の body_class: に書きます'])
            end
          end
          lines.each.with_index(1) do |line, number|
            if line.match?(/!\s*important/i)
              findings << Finding.new(level: :warning, message: "#{place(file, number)} に !important があります",
                                      detail: '→ 層の中の !important は層の順を逆にします。外して、選択子で優先を決めてください')
            end
            next unless line.match?(EXTERNAL_URL)

            findings << Finding.new(level: :warning, message: "#{place(file, number)} は、組むたびにネットワークからファイルを読みます",
                                    detail: '→ ファイルをテーマのディレクトリに置き、相対パスで指してください')
          end
          findings.concat(pagebreak_findings(file, css, lines))
        end

        # 章見出し・節見出しの改ページを値で書いた規則。設定（book-settings.css）は公開する変数の値だけを
        # 書くので、値で書いた改ページには効かない（theme-contract-spec.md §3.5）。
        # 出力先の CSS（epub*.css・kindle*.css）では h2 だけを見る——章の改丁は PDF だけの設定で、
        # Kindle の章見出しは値で固定してよい
        def pagebreak_findings(file, css, lines)
          headings = File.basename(file).start_with?('epub', 'kindle') ? %w[h2] : %w[h1 h2]
          Crass.parse(css).filter_map do |node|
            next unless node[:node] == :style_rule

            selector = node[:selector][:value]
            heading = selector.split(',').filter_map { heading_of(it) }.find { headings.include?(it) }
            declaration = Array(node[:children]).find { it[:node] == :property && it[:name] == 'break-before' }
            next unless heading && declaration

            value = declaration[:value].to_s.strip
            next if value.include?('var(') || value.match?(NON_BREAKING_VALUES)

            setting, token = PAGEBREAK_TOKENS.fetch(heading)
            start = line_index(lines, selector.split(',').first.strip) || 1
            number = lines.drop(start - 1).index { it.include?('break-before') }&.then { start + it }
            Finding.new(level: :warning,
                        message: "#{place(file, number)} の break-before: #{value} では、config/book.yml の #{setting} が効きません",
                        detail: "→ break-before: var(--book-#{token}); と書いてください")
          end
        end

        # 選択子が選ぶ要素が h1・h2 なら、その名前（最後の複合選択子の要素名）
        def heading_of(selector) = selector.strip.split(/[\s>+~]+/).last.to_s[/\Ah[12](?![\w-])/]

        # ================================================================
        # 入口に組んだ CSS
        # ================================================================

        # 本の写し（stylesheets/ と themes/ への参照・空の custom.css・今の設定の book-settings.css）で、
        # ページの種類ごとに EPUB と Kindle の入口を組んで判定する
        def bundle_findings(theme, own, root, config)
          targets = %i[epub kindle] & theme.supports.fetch(:targets)
          return [] if targets.empty?

          settings = PreProcessCommands::BookSettingsCss.render(config)
          drops = {}
          pairs = {}
          Dir.mktmpdir('vs-theme-check') do |tmp|
            dir = File.realpath(tmp)
            prepare_workspace(dir, root, settings, theme)
            Dir.chdir(dir) do
              Css::EntryWriter::IMPORTS.each_key do |kind|
                targets.each do |target|
                  pieces = bundle_pieces(kind, target, theme)
                  if target == :kindle
                    result = Css::LiteralResolver.resolve(pieces, scope: kindle_scope(kind, theme, config))
                    result.dropped.each { drops[[it.reason, relative(it.source, dir), it.selector, it.declaration]] = true if own?(it.source, dir, own) }
                    pieces = result.pieces
                  end
                  Css::InversionCheck.pairs(pieces).each do |pair|
                    sides = [pair.upper, pair.lower]
                    next unless sides.any? { own?(it.source, dir, own) }
                    next if sides.any? { it.source.end_with?(Css::EntryWriter::BOOK_SETTINGS, 'custom.css') }

                    pairs[[pair.longhand, *sides.map { [relative(it.source, dir), it.selector] }]] = true
                  end
                end
              end
            end
          end
          [*drop_findings(drops.keys, root), *inversion_findings(pairs.keys, own, root)]
        end

        def prepare_workspace(dir, root, settings, theme)
          stylesheets = File.join(dir, 'stylesheets')
          FileUtils.mkdir_p([stylesheets, File.join(dir, Common::CACHE_DIR)])
          source = File.join(root, 'stylesheets')
          Dir.children(source).each { File.symlink(File.join(source, it), File.join(stylesheets, it)) unless it == 'custom.css' } if File.directory?(source)
          File.write(File.join(stylesheets, 'custom.css'), '')
          File.symlink(File.join(root, DIR), File.join(dir, DIR))
          File.write(File.join(dir, Common::CACHE_DIR, Css::EntryWriter::BOOK_SETTINGS), settings)
          File.write(File.join(dir, Common::CACHE_DIR, Css::EntryWriter::BOOK_FONTS), '')
          Dir.chdir(dir) { Css::EntryWriter.write_theme_tokens!(theme) }
        end

        def bundle_pieces(kind, target, theme)
          css = Css::EntryWriter.render(kind, target:, theme:, traits: traits_for(theme))
          pieces = Css::Flattener.pieces(Css::EntryWriter.path_for(kind), rebase: ->(path) { path }, css:)
          Css::TargetFilter.apply(pieces, target:, embed_fonts: false)
        end

        # 束を組む本の軸。組方向は、テーマが対応していれば本のもの、対応していなければテーマの対応する
        # ものにする（縦書きだけの novel を技術書の本で検査しても、縦に組むページとして判定する）
        def traits_for(theme)
          traits = Common.traits
          modes = theme.supports.fetch(:writing_mode)
          modes.include?(traits.writing_mode) ? traits : traits.with(writing_mode: modes.first)
        end

        # Kindle の束の変数の表を作る範囲。body のクラスは、ページの種類とテーマのオプションが付けるもの
        def kindle_scope(kind, theme, config)
          classes = [PAGE_BODY_CLASSES.fetch(kind, kind), *theme.body_classes(kind, config)]
          Css::LiteralResolver.scope_for([classes], target_classes: Css::Bundle::KINDLE_BODY_CLASSES,
                                                    language: Common.book_language)
        end

        # 紙の寸法は数だけ（💡）、ほかは場所ごとに 🟡
        def drop_findings(drops, root)
          paper, others = drops.partition { |reason, *| reason == :paper_dimension }
          findings = others.map do |reason, file, selector, declaration|
            what = declaration ? "#{selector} { #{declaration} }" : selector
            line = line_in(root, file, declaration&.sub(/;\s*\z/, ''), selector)
            Finding.new(level: :warning, message: "#{place(file, line)} の「#{what}」は Kindle では効きません",
                        detail: Css::Bundle::UNRESOLVED_ADVICE.fetch(reason))
          end
          return findings if paper.empty?

          findings << Finding.new(level: :hint,
                                  message: "紙の寸法（clamp()・min()・max()）の宣言 #{paper.size} 個は、Kindle には届きません",
                                  detail: '判型に対する大きさなので、意図した書き方です。Kindle での大きさは kindle.css に em で書きます')
        end

        # 層を外すと勝ち負けが変わりうる組を、テーマの規則ごとにまとめる（💡）
        # @param pairs [Array<Array>] [プロパティ, [上のファイル, 選択子], [下のファイル, 選択子]]
        def inversion_findings(pairs, own, root)
          return [] if pairs.empty?

          groups = Hash.new { |hash, key| hash[key] = { longhands: [], rivals: [] } }
          pairs.each do |longhand, upper, lower|
            [[upper, lower], [lower, upper]].each do |mine, rival|
              next unless own.include?(mine.first)

              group = groups[mine]
              group[:longhands] |= [longhand]
              group[:rivals] |= [rival.last]
            end
          end
          detail = groups.map do |(file, selector), group|
            rivals = group[:rivals].first + (group[:rivals].size > 1 ? " ほか #{group[:rivals].size - 1} 個" : '')
            "#{place(file, line_in(root, file, selector))} #{selector}（#{group[:longhands].join('・')}）↔ #{rivals}"
          end
          [Finding.new(level: :hint,
                       message: "EPUB と Kindle の CSS（層を外した CSS）で、勝ち負けが変わりうる規則の組が #{pairs.size} 組あります",
                       detail: ['同じ要素を取り合うかは、vs build --log=debug が組み上がった HTML で確かめます', *detail])]
        end

        # ================================================================
        # Kindle で読者が選ぶ値
        # ================================================================

        # kindle_tokens: と、テーマの kindle*.css の body.vs-kindle の変数（§3.5）
        def kindle_token_findings(theme, own, root)
          label = File.join(theme.manifest.dir, Manifest::FILE)
          findings = theme.manifest.kindle_tokens.filter_map do |name, value|
            reader_value_finding("#{label} の kindle_tokens.#{name}", name.to_s, value.to_s)
          end
          own.select { File.basename(it).start_with?('kindle') }.each do |file|
            css = File.read(File.join(root, file), encoding: 'utf-8')
            body_kindle_declarations(css).each do |name, value|
              finding = reader_value_finding("#{place(file, line_index(uncommented_lines(css), "--book-#{name}"))} の --book-#{name}",
                                             name, value)
              findings << finding if finding
            end
          end
          findings
        end

        # body.vs-kindle（body に付くほかのクラスとの組を含む）の規則で定義した --book-* の名前と値
        def body_kindle_declarations(css)
          Crass.parse(css).flat_map do |node|
            next [] unless node[:node] == :style_rule

            selectors = node[:selector][:value].split(',').map(&:strip)
            next [] unless selectors.all? { it.match?(/\Abody(?:\.[\w-]+)+\z/) && it.include?('.vs-kindle') }

            Array(node[:children]).filter_map do |child|
              [child[:name].delete_prefix('--book-'), child[:value].to_s.strip] if child[:node] == :property && child[:name].start_with?('--book-')
            end
          end
        end

        def reader_value_finding(where, name, value)
          if READER_TOKENS.include?(name)
            return Finding.new(level: :warning, message: "#{where} は、Kindle では読者が選ぶ値です",
                               detail: '→ 削除してください。Kindle の本文の字の大きさと行送りは、端末の設定で決まります')
          end
          return nil unless name.start_with?('font-')

          families = value.split(',').map { it.strip.delete('"\'') }
          return nil if families.all? { GENERIC_FONTS.include?(it) }

          Finding.new(level: :warning, message: "#{where}: #{value} は、Kindle では使えない書体の名前です",
                      detail: "→ 総称の名前（#{GENERIC_FONTS.join('・')}）だけを書いてください。書体は読者が端末で選びます")
        end

        # ================================================================
        # 場所
        # ================================================================

        # 注釈を同じ行数の空白に置き換えた行の並び（行番号を保つ）
        def uncommented_lines(css) = css.gsub(%r{/\*.*?\*/}m) { it.gsub(/[^\n]/, ' ') }.lines

        # 最初に needle を含む行の番号（1 始まり）。無ければ nil
        def line_index(lines, needle)
          return nil if needle.nil? || needle.empty?

          lines.index { it.include?(needle) }&.then { it + 1 }
        end

        # ファイルの中で、needles を順に探して最初に見つかった行の番号
        def line_in(root, file, *needles)
          lines = uncommented_lines(File.read(File.join(root, file), encoding: 'utf-8'))
          needles.compact.each do |needle|
            number = line_index(lines, needle)
            return number if number
          end
          nil
        rescue SystemCallError
          nil
        end

        def place(file, line) = line ? "#{file}:#{line}" : file

        # 写しの中のパスを、本のルートからの相対に戻す
        def relative(path, dir) = path.delete_prefix("#{dir}/")

        def own?(path, dir, own) = own.include?(relative(path, dir))
      end
    end
  end
end
