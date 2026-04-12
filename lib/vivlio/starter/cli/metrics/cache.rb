# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/metrics/cache.rb
# ================================================================
# 責務:
#   章ごとのメトリクス解析結果をキャッシュする。
#
# 機能:
#   - .cache/metrics/{basename}.yml への読み書き
#   - 章 Markdown とキャッシュファイルの mtime 比較による鮮度判定
#   - キャッシュフォーマットのバージョン管理
#   - 環境変数 VIVLIO_METRICS_CACHE=0 でキャッシュ無効化
#
# Ruby 4.0+ 構文:
#   - it パラメータ
#   - エンドレスメソッド
#   - Data.define
# ================================================================

require 'yaml'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Metrics
        # キャッシュエントリを保持するイミュータブルデータ
        CacheEntry = Data.define(:basename, :mtime, :data)

        # メトリクスキャッシュを管理する
        class Cache
          CACHE_DIR = '.cache/metrics'
          DISABLE_ENV = 'VIVLIO_METRICS_CACHE'

          def initialize(cache_dir: CACHE_DIR)
            @cache_dir = cache_dir
          end

          # キャッシュが有効か判定する
          def enabled?
            ENV[DISABLE_ENV] != '0'
          end

          # キャッシュディレクトリを初期化する
          def ensure_cache_dir!
            FileUtils.mkdir_p(cache_dir)
          end

          # キャッシュが有効（新鮮）か判定する
          def fresh?(basename, source_path)
            return false unless enabled?
            return false unless source_path

            cache_path = cache_file_path(basename)
            return false unless File.exist?(cache_path)
            return false unless File.exist?(source_path)

            cache_mtime = File.mtime(cache_path)
            source_mtime = File.mtime(source_path)

            cache_mtime >= source_mtime
          rescue Errno::ENOENT
            false
          end

          # キャッシュからデータを読み込む
          def read(basename, source_path)
            return nil unless fresh?(basename, source_path)

            cache_path = cache_file_path(basename)
            data = YAML.safe_load_file(cache_path, permitted_classes: [Symbol])

            CacheEntry.new(basename:, mtime: File.mtime(cache_path), data:)
          rescue Psych::SyntaxError, Errno::ENOENT
            nil
          end

          # キャッシュにデータを書き込む
          def write(basename, data, source_path: nil)
            return unless enabled?

            ensure_cache_dir!
            cache_path = cache_file_path(basename)
            File.write(cache_path, data.to_yaml)
          rescue Errno::EACCES => e
            Common.log_warn("キャッシュ書き込みに失敗: #{e.message}")
          end

          # 全キャッシュをクリアする
          def clear!
            FileUtils.rm_rf(cache_dir)
          end

          # キャッシュファイルのパスを取得する
          def cache_file_path(basename) = File.join(cache_dir, "#{basename}.yml")

          private

          attr_reader :cache_dir
        end
      end
    end
  end
end
