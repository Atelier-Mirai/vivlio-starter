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
#       → InversionCheck（--log=debug のときだけ）
#       → Flattener.render
#
# 三つの形（§4.2）:
#   layered       pdf・print_pdf。入口をそのまま読み、ここでは何も作らない
#   flat          epub。下の write_epub! が消費者 dir の styles/ へ書く
#   flat_literal  kindle。S3-3 でリテラル化の段を足す（今は flat と同じ処理に Kindle のフィルタ）
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

module VivlioStarter
  module CLI
    module Css
      # 平らな CSS の生成と書き出し
      module Bundle
        # 確かめのために PDF の CSS の形を選ぶ環境変数
        FORM_ENV = 'VS_CSS_FORM'

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
        #   （--log=debug のとき、InversionCheck の組をこの HTML で絞る）
        # @param target [Symbol] :epub / :kindle
        # @param styles_dir [String] 平らな CSS の置き場（消費者 dir の styles/）
        # @param embed_fonts [Boolean] EPUB に書体の実体を入れるか
        # @return [Hash{String => String}] 入口の名前 → 書いたパス
        def write_epub!(html_by_kind, target:, styles_dir:, embed_fonts:)
          reported = {}
          html_by_kind.to_h do |kind, html_files|
            dest = File.join(styles_dir, "#{kind}.css")
            pieces = flat_pieces(kind, target:, dest:, package_root: File.dirname(styles_dir), embed_fonts:,
                                       reported:)
            report_inversions(kind, target, pieces, html_files)
            FileUtils.mkdir_p(styles_dir)
            File.write(dest, Flattener.render(pieces), encoding: 'utf-8')
            [kind, dest]
          end
        end

        # frontmatter の `stylesheet:` で章が足した CSS（入口の後に層の外で読む）を、
        # 同じフィルタを掛けて styles/ の下へ書く。
        # @param source [String] 作業ディレクトリからの相対（stylesheets/…）
        # @return [String] 書いたパス
        def write_epub_extra!(source, target:, styles_dir:, embed_fonts:)
          dest = File.join(styles_dir, source)
          rebase = package_rebase(dest, File.dirname(styles_dir))
          pieces = Flattener.pieces(source, rebase:)
          report_nested(pieces, {})
          pieces = TargetFilter.apply(pieces, target:, embed_fonts:)
          FileUtils.mkdir_p(File.dirname(dest))
          File.write(dest, Flattener.render(pieces), encoding: 'utf-8')
          dest
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

        # url() が指す作業ディレクトリの中のファイルを、パッケージの中の位置へ置き換えて、
        # dest から見た相対にする。パッケージには stylesheets/ がそのままの階層で写り
        # （EpubBuilder.localize_assets!）、生成キャッシュ .cache/vs/ の中のもの（theme-images/）は
        # パッケージのルート直下に写る（EpubBuilder.localize_theme_variant_images!）。
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

        # 層を外すと勝ち負けが変わる組と、層の中の !important を --log=debug で一覧にする。
        # vs とテーマの CSS は css_layer_test.rb がテストで確かめるので、ビルドでは開発者向けの
        # 情報にとどめる（§4.5）。組み上がった HTML を読むので、debug でなければ何もしない
        def report_inversions(kind, target, pieces, html_files)
          return unless Common.current_log_level >= Common::LEVELS['debug']

          require 'nokogiri'
          decls, = Cascade.collect(pieces.reject(&:nested))
          decls.select { it.important && it.rank != Cascade::UNLAYERED }.each do |decl|
            Common.log_debug("[css] #{kind}（#{target}）: 層の中の !important: #{decl.selector} { #{decl.property} } — #{relative(decl.source)}")
          end

          documents = html_files.map { Nokogiri::HTML5(File.read(it, encoding: 'utf-8'), max_errors: 0) }
          pairs = InversionCheck.present(InversionCheck.pairs(pieces.reject(&:nested)), documents)
          Common.log_debug("[css] #{kind}（#{target}）: 層を外すと勝ち負けが変わる組 #{pairs.size}")
          pairs.each { Common.log_debug("[css]   #{InversionCheck.describe(it)}") }
        end

        def relative(path) = path.delete_prefix("#{Dir.pwd}/")
      end
    end
  end
end
