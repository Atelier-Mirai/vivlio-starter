# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/data_image_resolver.rb
# ================================================================
# 責務:
#   QueryStream 展開結果内の「素ファイル名」画像参照を data/ 配下から解決する。
#
# なぜ必要か（querystream-data-images-spec.md §0）:
#   QueryStream 記法は data/*.yml の cover: 値等を素のファイル名（例 relativity.webp）
#   として展開する。従来はこれを ImagePathNormalizer が images/<章>/ へ正規化するため、
#   データが参照する画像は「記法を書いた章の画像ディレクトリ」に置くしかなかった。
#   本モジュールは QueryStream 展開直後（post_render フック）に働き、data/ 配下に
#   置かれたデータ画像を解決してデータ一式を自己完結にする。
#
# 探索順（spec §2）:
#   1. images/<章スラッグ>/<名前>   ── 章ローカル優先（後方互換・章別差し替え）。
#      ヒットしたら書き換えず従来経路（normalizer が正規化）に委ねる
#   2. data/<データファイル basename>/<名前>  ── データ単位フォルダ
#   3. data/images/<名前>                       ── データ横断の共有プール
#
# 出力（spec §2・§3.4）:
#   2/3 でヒットした実体をワークスペース html/images/data/<data 相対パス> へコピーし、
#   参照を images/data/<相対パス>（asset_prefix なし・数式 SVG と同型のビルド生成物参照）
#   へ書き換える。PDF ミラー・EPUB/Kindle 同梱は既存機構が自動で拾う。
# ================================================================

require 'fileutils'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # QueryStream 展開結果内の素ファイル名画像を data/ 配下から解決するモジュール
      module DataImageResolver
        module_function

        # 変種解決の優先順（ImagePathNormalizer.image_exists_for? と同ポリシー）。
        VARIANT_EXTS = %w[.webp .png .jpg .jpeg].freeze

        # ビルド生成物参照の共通プレフィックス（ImagePathNormalizer の carve-out と対応）。
        DATA_REL_ROOT = 'images/data'

        # QueryStream 1 記法の展開結果内の画像参照を data/ 配下から解決して書き換える。
        # Markdown 画像（![alt](src){attrs}）と HTML <img src="src"> の両方を対象とする。
        #
        # @param text [String] QueryStream 1 記法の展開結果
        # @param context [Hash] QueryStream post_render コンテキスト（:data_file :query :location を使う）
        # @param chapter_slug [String] 章スラッグ（例: "22-extentions"）
        # @return [String] 画像参照を書き換えた展開結果
        def rewrite(text, context, chapter_slug:)
          data_base = File.basename(context[:data_file].to_s, '.*')

          # --- Phase: Markdown 画像 ![alt](src){attrs} ---
          result = text.gsub(/!\[(?<alt>[^\]]*)\]\((?<src>[^)\s]+)\)(?<attr>\{[^}]*\})?/) do
            md = ::Regexp.last_match
            resolved = resolve_src(md[:src], data_base, chapter_slug, context)
            resolved ? "![#{md[:alt]}](#{resolved})#{md[:attr]}" : md[0]
          end

          # --- Phase: HTML <img src="src"> ---
          result.gsub(/<img\b[^>]*?\ssrc="(?<src>[^"]+)"[^>]*>/i) do
            tag = ::Regexp.last_match[0]
            src = ::Regexp.last_match[:src]
            resolved = resolve_src(src, data_base, chapter_slug, context)
            resolved ? tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{resolved}\\2") : tag
          end
        end

        # 単一の src を解決する。書き換えるべき新 src を返し、対象外・章ローカル該当・
        # ミス時は nil を返す（呼び出し元は nil のとき元の記法を保つ）。
        # @return [String, nil]
        def resolve_src(src, data_base, chapter_slug, context)
          return nil unless plain_filename?(src)

          # 章ローカルが最優先。実在すれば従来経路に委ねるため書き換えない。
          return nil if variant_exists?(File.join(Common.images_dir, chapter_slug, src))

          data_dir = Common.data_dir
          hit = variant_path(File.join(data_dir, data_base, src)) ||
                variant_path(File.join(data_dir, 'images', src))

          unless hit
            warn_missing(src, data_base, chapter_slug, context)
            return nil
          end

          rel = hit.delete_prefix("#{data_dir}/")     # 例: "physics_books/relativity.webp"
          stage_into_workspace!(hit, rel)
          "#{DATA_REL_ROOT}/#{rel}"
        end

        # 素のファイル名か（"/" を含まず・スキーム付きでも絶対パスでもなく・images/ 始まりでもない）。
        def plain_filename?(src)
          return false if src.nil? || src.empty?
          return false if src.include?('/')                       # パス・URL・images/… を一括除外
          return false if src.match?(%r{\A[a-zA-Z][a-zA-Z0-9+.-]*:}) # スキーム付き（data: 等）

          true
        end

        # 変種込みで実在パスを返す（無ければ nil）。.svg は完全一致、他は VARIANT_EXTS 優先順。
        # @return [String, nil]
        def variant_path(base_path)
          return (File.exist?(base_path) ? base_path : nil) if base_path.end_with?('.svg')

          base_without_ext = base_path.sub(/\.(webp|png|jpe?g)\z/i, '')
          VARIANT_EXTS.map { "#{base_without_ext}#{it}" }.find { File.exist?(it) }
        end

        # 変種込みで実在するか（真偽のみ）。
        def variant_exists?(base_path) = !variant_path(base_path).nil?

        # data/ 配下の実体をワークスペース html/images/data/<rel> へコピーする。
        # 既存の宛先が同一 size・同 mtime 以降なら再コピーしない（冪等・再ビルド高速化）。
        def stage_into_workspace!(source, rel)
          dest = File.join(Common::BUILD_HTML_DIR, 'images', 'data', rel)
          return if File.exist?(dest) && File.size(dest) == File.size(source) &&
                    File.mtime(dest) >= File.mtime(source)

          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(source, dest)
        end

        # 探索 3 箇所を列挙した親切な警告を出す（最終的な 🔴＋プレースホルダーは normalizer が担う）。
        def warn_missing(src, data_base, chapter_slug, context)
          searched = [
            "#{File.join(Common.images_dir, chapter_slug, src)}（章ローカル）",
            "#{File.join(Common.data_dir, data_base, src)}（データ単位フォルダ）",
            "#{File.join(Common.data_dir, 'images', src)}（共有プール）"
          ]
          Common.log_warn(
            "#{context[:location]} - データ画像 '#{src}' が見つかりません（記法: #{context[:query]}）",
            detail: "探索した場所:\n  - #{searched.join("\n  - ")}\n" \
                    "ヒント: #{File.join(Common.data_dir, data_base, src)} に置くとデータ一式が自己完結します"
          )
        end
      end
    end
  end
end
