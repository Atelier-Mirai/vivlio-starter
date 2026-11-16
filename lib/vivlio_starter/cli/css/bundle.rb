# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/bundle.rb
# ================================================================
# 責務:
#   出力先とページの種類を受けて、平らな CSS を作って書き出す
#   （css-layer-restructure-spec.md §4.1 の bundle.rb・§4.2）。
#     入口（EntryWriter.render・出力先の target 層つき）
#       → Flattener.pieces（読み込み・並べ替え）
#       → 入れ子の規則を知らせる
#       → TargetFilter（出力先が扱えない規則を落とす）
#       → LiteralResolver（Kindle だけ。var()・calc()・color-mix()・:is() を解く）
#       → Flattener.render
#   書いた規則の列は Sheet として返す。HTML の書き換えが終わった後に、同じ列で次の二つを行う。
#     prioritize_author_css!   custom.css などの層の外の宣言を、平らな CSS でも勝たせる（AuthorPriority・§7.1）
#     report_epub_inversions!  層を外すと勝ち負けが変わる組の一覧（InversionCheck・--log=debug のときだけ）
#   どちらも要素ごとの判定なので、vs-kindle の印・合成画像・コードの行ブロックなどが入った後の
#   HTML でないと、Kindle の規則が当たらない。
#
# 三つの形（§4.2）:
#   layered       pdf・print_pdf。入口をそのまま読み、ここでは何も作らない
#   flat          epub。下の write_epub! が消費者 dir の styles/ へ書く
#   flat_literal  kindle。flat に Kindle のフィルタと、リテラル化（LiteralResolver）を足す
#
# VS_CSS_FORM=flat（開発用・文書には載せない）:
#   PDF にも平らな CSS を読ませる。層を外しても PDF の結果が変わらないことを、全ページの
#   画素で確かめるため（§4.3 の (1)）。余白の箱を落とすフィルタは掛けない。
# ================================================================

require 'fileutils'
require 'pathname'
require_relative '../common'
require_relative 'entry_writer'
require_relative 'flattener'
require_relative 'target_filter'
require_relative 'cascade'
require_relative 'inversion_check'
require_relative 'literal_resolver'
require_relative 'author_priority'

module VivlioStarter
  module CLI
    module Css
      # 平らな CSS の生成と書き出し
      module Bundle
        # 書き出した平らな CSS 1 枚。pieces は書いた規則の列（HTML の書き換えの後の判定に使う）
        Sheet = Data.define(:dest, :pieces)

        # 著者に見せる出力先の名前
        TARGET_LABELS = { epub: 'EPUB', kindle: 'Kindle' }.freeze

        # 確かめのために PDF の CSS の形を選ぶ環境変数
        FORM_ENV = 'VS_CSS_FORM'

        # Kindle の出力先の変換（L4）が body に足すクラス。変数の表を作る範囲に入れる
        KINDLE_BODY_CLASSES = %w[vs-epub vs-kindle].freeze

        # 著者に知らせる、Kindle で解けなかった宣言の直し方（LiteralResolver::Dropped#reason ごと）
        UNRESOLVED_ADVICE = {
          variable: '→ 値を 4mm や #1a73e8 のように直接書くか、変数を :root で定義してください',
          calc: '→ 単位をそろえるか、計算した値を直接書いてください（例: calc(100% - 2mm) → 95%）',
          color_mix: '→ 混ぜた後の色を #1a73e8 のように直接書いてください',
          has: '→ :has() を使わない選択子で書いてください'
        }.freeze

        module_function

        # VS_CSS_FORM=flat のとき、PDF が読む入口のファイル（.cache/vs/entry-*.css）を、
        # 平らにした CSS で上書きする。book-settings.css を生成した後に呼ぶ。
        # 入口の中身は EntryWriter.render から作るので、上書きしても EPUB の束には響かない。
        # @return [Array<String>] 書いたパス（flat でなければ空）
        def write_pdf_entries!
          return [] unless ENV[FORM_ENV] == 'flat'

          Common.log_info("[css] #{FORM_ENV}=flat: PDF に平らにした CSS を読ませます")
          reported = {}
          EntryWriter::IMPORTS.each_key.map do |kind|
            dest = EntryWriter.path_for(kind)
            pieces = flat_pieces(kind, target: :pdf, dest:, reported:)
            File.write(dest, Flattener.render(pieces), encoding: 'utf-8')
            dest
          end
        end

        # EPUB・Kindle の消費者 dir の styles/ へ、ページの種類ごとに平らな CSS を書く。
        # @param html_by_kind [Hash{String => Array<String>}] 入口の名前 → その入口を読む HTML
        # @param target [Symbol] :epub / :kindle
        # @param styles_dir [String] 平らな CSS の置き場（消費者 dir の styles/）
        # @param embed_fonts [Boolean] EPUB に書体の実体を入れるか
        # @return [Hash{String => Sheet}] 入口の名前 → 書いた CSS
        def write_epub!(html_by_kind, target:, styles_dir:, embed_fonts:)
          reported = {}
          html_by_kind.to_h do |kind, html_files|
            dest = File.join(styles_dir, "#{kind}.css")
            pieces = flat_pieces(kind, target:, dest:, package_root: File.dirname(styles_dir), embed_fonts:,
                                       reported:)
            pieces = literalize(pieces, target:, scope: kindle_scope(html_files), reported:) if target == :kindle
            FileUtils.mkdir_p(styles_dir)
            File.write(dest, Flattener.render(pieces), encoding: 'utf-8')
            [kind, Sheet.new(dest:, pieces:)]
          end
        end

        # 層の外の宣言（custom.css・章が足した CSS）のうち、平らな CSS で vs の規則に負けるものに
        # !important を付けて、その CSS を書き直す（css-layer-restructure-spec.md §7.1）。
        # 付けられなかった宣言は、場所を示して 🟡 で知らせる（vs の選択子は見せない・§4.5）。
        # HTML の書き換えが全部終わった後に呼ぶ（Kindle の規則は vs-kindle の印が付いてから当たる）。
        # @param sheets [Hash{String => Sheet}] HTML の link の href → 書いた CSS
        # @param html_sheets [Hash{String => Array<String>}] HTML のパス → 読む CSS の href（link の順）
        # @return [Hash{String => Sheet}] 付けた後の CSS（付けなかったものはそのまま）
        def prioritize_author_css!(sheets, html_sheets, target:)
          pieces = sheets.transform_values(&:pieces)
          return sheets unless pieces.each_value.any? { |list| list.any? { AuthorPriority.author_piece?(it) } }

          require 'nokogiri'
          documents = html_sheets.map do |path, keys|
            AuthorPriority::Document.new(doc: Nokogiri::HTML5(File.read(path, encoding: 'utf-8'), max_errors: 0),
                                         path:, sheets: keys)
          end
          result = AuthorPriority.apply(pieces, documents)
          result.promoted.each do |key, count|
            File.write(sheets.fetch(key).dest, Flattener.render(result.sheets.fetch(key)), encoding: 'utf-8')
            Common.log_debug("[css] #{target}: #{key} の層の外の宣言 #{count} に !important を付けました（§7.1）")
          end
          # 付けた宣言に当たる要素の style 属性にも !important を付けた HTML（style 属性が勝つのを保つ）
          result.restyled.each do |document|
            File.write(document.path, document.doc.to_html(encoding: 'UTF-8'), encoding: 'utf-8')
            Common.log_debug("[css] #{target}: #{File.basename(document.path)} の style 属性に !important を付けました（§7.1）")
          end
          warn_unresolved_author_css(result.unresolved, target)
          sheets.to_h { |key, sheet| [key, sheet.with(pieces: result.sheets.fetch(key))] }
        end

        # --log=debug のとき、EPUB・Kindle の HTML で要素ごとの判定（InversionCheck.inversions）を行い、
        # 層を外すと勝ち負けが変わる組と、層の中の !important を一覧にする。
        # HTML の書き換え（vs-kindle の印・合成画像・コードの行ブロックなど）が全部終わった後に、
        # 書いた CSS の規則の列（prioritize_author_css! の後のもの）で判定する
        # @param sheets [Hash{String => Sheet}] HTML の link の href → 書いた CSS
        # @param html_sheets [Hash{String => Array<String>}] HTML のパス → 読む CSS の href
        def report_epub_inversions!(sheets, html_sheets, target:)
          return unless Common.current_log_level >= Common::LEVELS['debug']

          sheets.each do |key, sheet|
            html_files = html_sheets.select { |_, keys| keys.include?(key) }.keys
            report_inversions(File.basename(key, '.css'), target, sheet.pieces, html_files) unless html_files.empty?
          end
        end

        # frontmatter の `stylesheet:` で章が足した CSS（入口の後に層の外で読む）を、
        # 同じフィルタを掛けて styles/ の下へ書く。
        # @param source [String] 作業ディレクトリからの相対（stylesheets/…）
        # @return [Sheet] 書いた CSS
        def write_epub_extra!(source, target:, styles_dir:, embed_fonts:)
          dest = File.join(styles_dir, source)
          rebase = package_rebase(dest, File.dirname(styles_dir))
          pieces = Flattener.pieces(source, rebase:)
          report_nested(pieces, {})
          pieces = TargetFilter.apply(pieces, target:, embed_fonts:)
          if target == :kindle
            # 章が足した CSS は単独では変数をほとんど定義しないので、本文の束の変数も表に入れて解く
            base = flat_pieces('chapter', target:, dest:, embed_fonts:)
            pieces = literalize(pieces, target:, scope: kindle_scope([]), reported: {}, base:, author: true)
          end
          FileUtils.mkdir_p(File.dirname(dest))
          File.write(dest, Flattener.render(pieces), encoding: 'utf-8')
          Sheet.new(dest:, pieces:)
        end

        # 入口を平らにし、出力先のフィルタを掛けた規則の列。
        # @param dest [String] 書き出す先（url() をここから見た位置へ引き直す）
        # @param package_root [String, nil] EPUB のパッケージのルート（消費者 dir）。nil なら
        #   作業ディレクトリのファイルをそのまま指す（PDF）
        def flat_pieces(kind, target:, dest:, package_root: nil, embed_fonts: true, reported: {})
          entry = EntryWriter.path_for(kind)
          rebase = package_root ? package_rebase(dest, package_root) : workspace_rebase(dest)
          pieces = Flattener.pieces(entry, rebase:, css: EntryWriter.render(kind, target: target == :pdf ? nil : target))
          report_nested(pieces, reported)
          TargetFilter.apply(pieces, target:, embed_fonts:)
        end

        # Kindle 用に var()・calc()・color-mix()・:is() を解く（css-layer-restructure-spec.md §4.4）。
        # 解けずに落とした宣言は --log=debug で一覧にし、著者の CSS（custom.css・章が足した CSS）の
        # ものだけを 🟡 で知らせる（§4.5）。同じものを種類ごとに何度も知らせない。
        # 紙の寸法（clamp()・min()・max()）で落とした宣言は、著者の CSS でも知らせない。PDF の紙面のために
        # 書いた意図した書き方で、直すものではない（Kindle に届かないのは、ここで落とす前も同じだった）
        # @param base [Array<Flattener::Piece>] 変数の表にだけ使う規則
        # @param author [Boolean] pieces が全部著者の CSS か（章が足した CSS）
        def literalize(pieces, target:, scope:, reported:, base: [], author: false)
          result = LiteralResolver.resolve(pieces.reject(&:nested), scope:, base: base.reject(&:nested))
          result.dropped.each do |dropped|
            key = [:literal, dropped.source, dropped.selector, dropped.declaration]
            next if reported[key]

            reported[key] = true
            what = dropped.declaration ? "#{dropped.selector} { #{dropped.declaration} }" : dropped.selector
            Common.log_debug("[css] #{target}: 解けないので落とした（#{dropped.reason}）: #{what} — #{relative(dropped.source)}")
            next if dropped.reason == :paper_dimension
            next unless author || File.basename(dropped.source) == 'custom.css'

            Common.log_warn("#{relative(dropped.source)} の「#{what}」は Kindle では効きません",
                            detail: [UNRESOLVED_ADVICE.fetch(dropped.reason)])
          end
          result.pieces
        end

        # Kindle の束の変数の表を作る範囲。body のクラスは、その種類を読む HTML に共通のもの
        # （出力先の変換が後で足す vs-epub・vs-kindle を含める）。HTML の style 属性で定義された
        # 変数（写真の列の数など）は要素ごとに値が違うので、解かない
        def kindle_scope(html_files)
          sources = html_files.map { File.read(it, encoding: 'utf-8') }
          body_classes = sources.map { it[/<body\b[^>]*\bclass="([^"]*)"/, 1].to_s.split }
          scoped = sources.flat_map { it.scan(/\sstyle="([^"]*)"/).flatten.flat_map { it.scan(/(--[\w-]+)\s*:/).flatten } }
          LiteralResolver.scope_for(body_classes, target_classes: KINDLE_BODY_CLASSES, language: Common.book_language,
                                                  scoped:)
        end

        # url() が指す作業ディレクトリの中のファイルを、パッケージの中の位置へ置き換えて、
        # dest から見た相対にする。パッケージには stylesheets/ がそのままの階層で写り
        # （Epub::Workspace.localize_assets!）、生成キャッシュ .cache/vs/ の中のもの（theme-images/）は
        # パッケージのルート直下に写る（Epub::Workspace.localize_theme_variant_images!）。
        def package_rebase(dest, package_root)
          from = Pathname(dest).dirname.relative_path_from(Pathname(package_root))
          lambda do |absolute|
            relative = absolute.delete_prefix("#{Dir.pwd}/")
            next absolute if relative == absolute

            Pathname(relative.delete_prefix("#{Common::CACHE_DIR}/")).relative_path_from(from).to_s
          end
        end

        # 作業ディレクトリのファイルを、dest から見た相対にする（PDF の入口の置き場 .cache/vs/ から）
        def workspace_rebase(dest)
          from = Pathname(File.expand_path(File.dirname(dest)))
          ->(absolute) { Pathname(absolute).relative_path_from(from).to_s }
        end

        # 入れ子の規則は平らな CSS から外れる。同じ規則を種類ごとに何度も知らせない
        def report_nested(pieces, reported)
          pieces.select(&:nested).each do |piece|
            key = [piece.source, piece.text]
            next if reported[key]

            reported[key] = true
            selector = piece.text[/\A[^{]*/].strip
            Common.log_warn("#{relative(piece.source)} の「#{selector}」は入れ子の書き方のため、EPUB と Kindle の CSS から外しました",
                            detail: ["→ 入れ子を開いて書いてください（例: .box { & p { … } } → .box p { … }）"])
          end
        end

        # 層を外すと勝ち負けが変わる組と、層の中の !important を一覧にする。
        # vs とテーマの CSS は css_layer_test.rb がテストで確かめるので、ビルドでは開発者向けの
        # 情報にとどめる（§4.5）
        def report_inversions(kind, target, pieces, html_files)
          require 'nokogiri'
          decls, = Cascade.collect(pieces.reject(&:nested))
          decls.select { it.important && it.rank != Cascade::UNLAYERED }.each do |decl|
            Common.log_debug("[css] #{kind}（#{target}）: 層の中の !important: #{decl.selector} { #{decl.property} } — #{relative(decl.source)}")
          end

          documents = html_files.map { Nokogiri::HTML5(File.read(it, encoding: 'utf-8'), max_errors: 0) }
          pairs, unreadable = InversionCheck.inversions(pieces.reject(&:nested), documents)
          Common.log_debug("[css] #{kind}（#{target}）: 層を外すと勝ち負けが変わる組 #{pairs.size}")
          pairs.each { Common.log_debug("[css]   #{InversionCheck.describe(it)}") }
          unreadable.each { Common.log_debug("[css]   判定できない選択子（当たらないものとして扱った）: #{it}") }
        end

        # !important を付けられなかった層の外の宣言を、場所と直し方を添えて知らせる。
        # 同じ宣言は、ページの種類をまたいで一度だけ知らせる
        def warn_unresolved_author_css(unresolved, target)
          label = TARGET_LABELS.fetch(target, target.to_s)
          reported = {}
          unresolved.each do |item|
            decl = item.decl
            rule = "#{decl.selector} { #{decl.property}: #{decl.value} }"
            next if reported[[decl.source, rule]]

            reported[[decl.source, rule]] = true
            place = "#{page_name(item.path)} の <#{item.element.name}#{%( class="#{item.element['class']}") if item.element['class']}>"
            detail = case item
                     in { rival: { rank: Cascade::UNLAYERED } => rival }
                       ["📍 #{place} には、#{relative(rival.source)} の「#{rival.selector} { #{rival.property}: " \
                        "#{rival.value} !important }」も当たります",
                        '→ 二つの選択子が同じ要素に当たらないよう、どちらかを絞ってください']
                     else
                       ["📍 #{place}",
                        "→ この要素の #{decl.property} は #{label} では変えられません。PDF だけの指定として残すか、削除してください"]
                     end
            Common.log_warn("#{relative(decl.source)}#{line_label(decl)}の「#{rule}」は #{label} では効きません", detail:)
          end
        end

        # 規則の書かれた行（「（12 行目）」）。注記の中の書き方の例には当てない。見つからなければ空
        def line_label(decl)
          return '' unless File.file?(decl.source)

          text = File.read(decl.source, encoding: 'utf-8').gsub(%r{/\*.*?\*/}m) { it.gsub(/[^\n]/, ' ') }
          pattern = /(?:\A|[\s,}])#{Regexp.escape(decl.selector).gsub('\\ ', '\\s+')}\s*[,{]/
          index = text =~ pattern
          index ? "（#{text[0..index].count("\n") + 1} 行目）" : ''
        end

        # HTML の名前を、著者が書いた原稿の名前にする（原稿の無いページは HTML の名前のまま）
        def page_name(path)
          source = File.join(Common::CONTENTS_DIR, "#{File.basename(path, '.html')}.md")
          File.file?(source) ? source : File.basename(path)
        end

        def relative(path) = path.delete_prefix("#{Dir.pwd}/")
      end
    end
  end
end
