# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/generated_asset_cache.rb
# ================================================================
# 責務:
#   前処理が焼く生成資産（mermaid 図・showcase 合成画像・数式 SVG）の
#   **クリーンビルドを跨ぐ永続キャッシュ**。generated-assets 移設仕様 §2
#   （covers / theme-images を BUILD_DIR の外に置く方針）の延長として、
#   「fetch-or-generate → ワークスペースへ materialize」を一元化する。
#
# なぜ BUILD_DIR の外なのか:
#   生成物をワークスペース（BUILD_HTML_DIR 配下）にだけ置くと、final clean
#   （rm_rf BUILD_DIR）で毎ビルド消え、内容が変わっていなくても再生成される。
#   mmdc（Chromium 起動）・magick+rsvg・Node+MathJax はいずれも図/式 1 件あたり
#   数百 ms〜1s 級で、書籍全体では毎ビルド数秒〜十数秒の無駄になる。
#   キーはすべて内容アドレス（ソース＋設定のハッシュ）なので、`.cache/vs/<種別>/`
#   に置けば「変わらない限り再生成しない・変われば別キーで自動再生成」が成り立つ。
#
# 掃除:
#   `vs clean --cache` の .cache/vs 一括削除がそのまま面倒を見る（個別処理は不要）。
#
# 使い方（2 形）:
#   - fetch:       1 件ずつ生成する変換（mermaid / showcase）。キャッシュミス時だけ
#                  ブロックが呼ばれ、ブロックはキャッシュ dir へ生成物を書いて true を返す。
#   - materialize: 生成を自前バッチで済ませる変換（math は Node 起動を 1 回に束ねる）。
#                  キャッシュに揃っている生成物をワークスペースへ写すだけを行う。
# ================================================================

require 'fileutils'
require_relative '../common'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 生成資産の永続キャッシュ（fetch-or-generate ＋ materialize）
      module GeneratedAssetCache
        module_function

        # 種別のキャッシュディレクトリ（.cache/vs/<kind>/）。
        # @param kind [String] 資産種別（'mermaid' / 'showcase' / 'math'）
        def dir(kind) = File.join(Common.cache_dir, kind)

        # キャッシュから生成物一式をワークスペースへ写す。無ければブロックで生成する。
        #
        # @param kind [String] 資産種別
        # @param files [Array<String>] 期待する生成物のファイル名（例: ["#{key}.svg", "#{key}.png"]）
        # @param out_dir [String] ワークスペース側の配置先
        # @yieldparam cache_dir [String] 生成物の書き込み先（キャッシュ dir・作成済み）
        # @yieldreturn [Boolean] 生成に成功したか（false なら縮退）
        # @return [Boolean] 生成物一式が out_dir に揃ったか
        def fetch(kind, files, out_dir:)
          return true if files.all? { File.exist?(File.join(out_dir, it)) }

          cache = dir(kind)
          unless files.all? { File.exist?(File.join(cache, it)) }
            FileUtils.mkdir_p(cache)
            return false unless yield(cache)
            # 生成側の書き忘れ（成功を返したのにファイルが無い）は縮退として扱う
            return false unless files.all? { File.exist?(File.join(cache, it)) }
          end

          copy_to_workspace(cache, files, out_dir)
        end

        # キャッシュに揃っている生成物一式をワークスペースへ写す（生成はしない）。
        # 呼び出し元が dir(kind) へ自前バッチ生成した後の配布に使う。
        #
        # @return [Boolean] 生成物一式が out_dir に揃ったか（キャッシュ不足は false）
        def materialize(kind, files, out_dir:)
          return true if files.all? { File.exist?(File.join(out_dir, it)) }

          cache = dir(kind)
          return false unless files.all? { File.exist?(File.join(cache, it)) }

          copy_to_workspace(cache, files, out_dir)
        end

        def copy_to_workspace(cache, files, out_dir)
          FileUtils.mkdir_p(out_dir)
          files.each { FileUtils.cp(File.join(cache, it), File.join(out_dir, it)) }
          true
        end
      end
    end
  end
end
