# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/runner.rb
# ================================================================
# 責務:
#   変換の並びを HTML に当てる
# ================================================================

require_relative 'context'
require_relative '../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 変換の並びを HTML に当てる
      module Transforms::Runner
        module_function

        # 全部のページを一度だけ読み、出力先の宣言の順に段を当て、一度だけ書く。
        #
        # 段の順が外側、ページの順が内側である。索引・用語集の段（PostProcessIndexGlossary）は
        # ほかのページの id を照合するので、その段に来たときには、前の段が全部のページに
        # 当たり終えていなければならない。
        #
        # 段は二種類ある。
        #   - `call(doc, ctx)`: 1 ページの DOM を書き換える（ほとんどの段）
        #   - `rewrite(html, ctx)`: 1 ページの HTML の文字列を書き換えて返す。HTML として不正な
        #     途中の形を通る書き換え（閉じタグを足して要素を分ける、など）のための種別で、
        #     文字列が変わったページだけ DOM を作り直す
        #
        # @param transforms [Array<Module>] 変換の段の並び
        # @param html_files [Array<String>] 出力先のワークスペースの HTML のパス（本の順）
        # @param ctx [Transforms::Context]
        # @return [Array<String>] そのままの配列
        def apply!(transforms, html_files, ctx)
          parser = PostProcessCommands::HtmlParser
          pages = html_files.to_h { [it, parser.parse_html_document(File.read(it, encoding: 'utf-8'))] }
          book = ctx.with(pages:, memo: {})

          transforms.each do |transform|
            html_files.each { |path| pages[path] = apply_step(transform, pages[path], book.with(path:)) }
          end

          pages.each { |path, doc| parser.save_html_document(path, doc) }
          html_files
        end

        # 段を 1 ページに当て、当てた後の DOM を返す
        def apply_step(transform, doc, ctx)
          unless transform.respond_to?(:rewrite)
            transform.call(doc, ctx)
            return doc
          end

          parser = PostProcessCommands::HtmlParser
          html = parser.render_html_document(doc)
          rewritten = transform.rewrite(html, ctx)
          rewritten == html ? doc : parser.parse_html_document(rewritten)
        end
      end
    end
  end
end
