# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/yomi_overrides.rb
# ================================================================
# 責務:
#   読みの個人辞書（config/index_yomi_overrides.yml）の読み書き。
#   index:import で書籍間の読み補正（例: 重力→じゅうりょく）を蓄積し、
#   YomiInferrer が MeCab 推定より優先して返せるようにする。
#
# 読み解決の優先順位:
#   1. 記法 [用語|読み]
#   2. index_glossary_terms.yml の yomi
#   3. index_yomi_overrides.yml（本ファイル）← MeCab の手前
#   4. MeCab 推定
#
# 仕様: docs/specs/index-library-portability-spec.md（Phase 2）
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'

module VivlioStarter
  module CLI
    module IndexCommands
      module YomiOverrides
        module_function

        FILE = 'config/index_yomi_overrides.yml'

        # term => yomi のマップを返す（無ければ空）。
        def load
          return {} unless File.exist?(FILE)

          data = YAML.load_file(FILE)
          (data && data['yomi']) || {}
        rescue StandardError => e
          Common.log_warn("#{FILE} の読み込みに失敗しました: #{e.message}")
          {}
        end

        # 読み辞書を追記マージする。既定は既存優先（prefer_import で上書き）。
        # @return [Array(Integer, Integer)] [書き込み件数, スキップ件数]
        def merge!(map, prefer_import: false)
          return [0, 0] if map.nil? || map.empty?

          existing = load
          written = 0
          skipped = 0

          map.each do |term, yomi|
            next if term.to_s.empty? || yomi.to_s.empty?

            if existing.key?(term) && (!prefer_import || existing[term] == yomi)
              skipped += 1
            else
              existing[term] = yomi
              written += 1
            end
          end

          save(existing) if written.positive?
          [written, skipped]
        end

        # term 昇順で保存する。
        def save(map)
          FileUtils.mkdir_p(File.dirname(FILE))
          data = { 'generated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 'yomi' => map.sort.to_h }
          File.write(FILE, data.to_yaml, encoding: 'utf-8')
        end
      end
    end
  end
end
