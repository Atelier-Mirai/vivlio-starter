# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/strip_webp_inline_styles.rb
# ================================================================
# 責務:
#   インラインの <style> の中の、WebP の url() の宣言を外す
# ================================================================

require_relative '../context'
require_relative '../../../css/target_filter'

module VivlioStarter
  module CLI
    module Build
      # インラインの <style> の中の、WebP の url() の宣言を外す
      module Transforms::Kindle::StripWebpInlineStyles
        module_function

        # インライン <style> 内の `--xxx: url(...webp)...;` 宣言を 1 つ検出する正規表現
        # （Transforms::Kindle::StripWebpInlineStyles で使用）。平らな CSS から落とす宣言と同じ形
        INLINE_WEBP_DECL_PATTERN = Css::TargetFilter::WEBP_URL_PATTERN

        # Kindle 専用: 章 HTML のインライン <style> 内の webp url() 宣言を除去する（RSC-007 回避）。
        # Techbook が PDF の Type3 対策で head に注入する :root{ --h3-marker: url(...webp) } 等は、
        # Kindle では WebP を同梱しない（localize_assets! が除外）ため参照切れになる。
        # Kindle は var() も解さずこのマーカーを描画しないので、宣言ごと除去して無害化する。
        # Css::TargetFilter は平らな CSS のファイルだけを扱い、インライン <style> は拾わないため、
        # ここで章 HTML の <style> ブロックを処理する。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            updated = html.gsub(%r{<style\b[^>]*>.*?</style>}m) { it.gsub(INLINE_WEBP_DECL_PATTERN, '') }
            next if updated == html

            File.write(path, updated, encoding: 'utf-8')
            Common.log_info("[EPUB] #{File.basename(path)} のインライン style から webp 参照を除去しました")
          end
          html_files
        end
      end
    end
  end
end
