# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/index_library.rb
# ================================================================
# 責務:
#   索引ライブラリ（書籍間で持ち運べる作者の資産）の export/import。
#   - 用語集の説明文（term/yomi/definition）。用語集の語と、使っていない語の両方
#   - 棄却した語の一覧（候補に出さない語）
#   - 読みの個人辞書（term => yomi。MeCab の誤読補正）
#
#   書籍固有情報（contexts / backlink_sources / link / source / 索引の印 / 主要参照）は
#   含めず、別の書籍へそのまま引き継げる最小限のデータだけを扱う。
#
# 説明文の蓄えとして運ぶ（index-library-reserve-spec.md）:
#   取り込んだ説明文は「使っていない語」として辞書に待たせる。用語集のページには載らず、
#   原稿にその語を書いたとき、説明文を添えた候補としてレビューファイルに出る。用語集に
#   載せるか・索引にも載せるかは、本ごとに決める。取り込みは追記だけで、辞書にある語・
#   新しい本で棄却した語・すでにある読みには触れない。
#
# 仕様: index-library-portability-spec.md・index-library-reserve-spec.md
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../common'
require_relative 'unified_terms_manager'
require_relative 'review_queue_manager'
require_relative 'yomi_overrides'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexLibrary
        SCHEMA_VERSION = 1
        DEFAULT_PATH = 'index_library.yml'

        # import の結果サマリ。
        ImportResult = Data.define(:glossary_added, :glossary_skipped, :reject_added, :reject_skipped,
                                   :yomi_added, :yomi_skipped)

        def initialize(terms_manager: UnifiedTermsManager.new, queue_manager: ReviewQueueManager.new)
          @terms_manager = terms_manager
          @queue_manager = queue_manager
        end

        # export/import の対象パスを解決する。
        # book.yml には置かない——パスを変えたいのは「今回だけ別名で書き出す」ときで、
        # それは vs index:export mybook.yml のように引数で言うほうが早い。
        # @param arg [String, nil] コマンド引数のパス
        def self.resolve_path(arg)
          return File.expand_path(arg) if arg && !arg.to_s.empty?

          File.expand_path(DEFAULT_PATH)
        end

        # --- Phase: export ---

        # 現プロジェクトの用語集の説明文・棄却した語・読みをライブラリファイルへ書き出す。
        def export!(path)
          glossary = export_glossary
          reject = export_reject
          yomi = export_yomi

          if glossary.empty? && reject.empty? && yomi.empty?
            Common.log_warn('書き出す用語集の語・棄却した語・読みがありません（ライブラリは作成しませんでした）')
            return false
          end

          library = {
            'version' => SCHEMA_VERSION,
            'exported_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
            'glossary' => glossary,
            'reject' => reject,
            'yomi' => yomi
          }

          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless dir == '.'
          File.write(path, library.to_yaml, encoding: 'utf-8')
          Common.log_result(
            "索引ライブラリを書き出しました: #{path}" \
            "（用語集の語 #{glossary.size} 件 / 棄却した語 #{reject.size} 件 / 読み #{yomi.size} 件）",
            status: :success
          )
          true
        end

        # 説明文のある語を term 昇順で term/yomi/definition のみ抽出する（固有情報は落とす）。
        # 用語集の語に加えて、使っていない語（説明文だけを残した語）も運ぶ——この本で使わなかった
        # 語の説明文も、次の本では役に立つ。本から本へ引き継ぐ途中で消えないように。
        # 説明文の無い語は運ばない。取り込む側では使っていない語として待たせるので、
        # 説明文の無い記録は意味を持たない（読みは yomi で運ばれる）。
        def export_glossary
          @terms_manager.load_terms
                        .select { glossary_flag?(it) || it['flags'].to_s.empty? }
                        .reject { it['definition'].to_s.strip.empty? }
                        .sort_by { it['term'].to_s }
                        .map { { 'term' => it['term'], 'yomi' => it['yomi'], 'definition' => it['definition'].to_s } }
        end

        # reject 一覧を term 昇順で term(+reason) のみ抽出する。
        def export_reject
          @queue_manager.load_rejected_terms_with_metadata
                        .sort_by { it['term'].to_s }
                        .map do |rejected|
            entry = { 'term' => rejected['term'] }
            entry['reason'] = rejected['reason'] if rejected['reason']
            entry
          end
        end

        # 読みの個人辞書（term => yomi）を term 昇順で抽出する。
        # 作者由来の語（用語集[g]・手動登録）の実読みと、これまでに
        # 蓄積した overrides をまとめる（作者の語の読みを優先）。
        def export_yomi
          from_terms = @terms_manager.load_terms
                                     .select { author_touched?(it) }
                                     .reject { blank_yomi?(it) }
                                     .to_h { [it['term'], it['yomi']] }
          YomiOverrides.load.merge(from_terms).sort.to_h
        end

        def glossary_flag?(term) = term['flags'].to_s.include?('g')

        def author_touched?(term)
          term['flags'].to_s.include?('g') || term['source'] == 'manual_markup'
        end

        def blank_yomi?(term)
          yomi = term['yomi'].to_s
          yomi.empty? || yomi == term['term'].to_s
        end

        # --- Phase: import ---

        # ライブラリファイルを現プロジェクトへ取り込む（追記だけ。辞書・棄却・読みのいまの値は変えない）。
        def import!(path)
          data = load_library(path)
          return nil unless data

          unless data['version'] == SCHEMA_VERSION
            Common.log_warn("未知のライブラリ version: #{data['version'].inspect}（想定 #{SCHEMA_VERSION}）。可能な範囲で取り込みます")
          end

          # 棄却した語を先に読む。取り込む前の一覧で「新しい本で棄却した語」を見分けるため
          rejected_here = @queue_manager.load_rejected_terms
          glossary_added, glossary_skipped = import_glossary(data['glossary'] || [], rejected_here)
          reject_added, reject_skipped = import_reject(data['reject'] || [])
          yomi_added, yomi_skipped = YomiOverrides.merge!(data['yomi'] || {})

          Common.log_result(
            "索引ライブラリを取り込みました: 用語集の語 +#{glossary_added}（スキップ #{glossary_skipped}） / " \
            "棄却した語 +#{reject_added}（スキップ #{reject_skipped}） / " \
            "読み +#{yomi_added}（スキップ #{yomi_skipped}）",
            status: :success
          )
          ImportResult.new(glossary_added:, glossary_skipped:, reject_added:, reject_skipped:,
                           yomi_added:, yomi_skipped:)
        end

        private

        def load_library(path)
          unless File.exist?(path)
            Common.log_error("索引ライブラリが見つかりません: #{path}")
            return nil
          end

          YAML.load_file(path) || {}
        rescue StandardError => e
          Common.log_error("索引ライブラリの読み込みに失敗しました: #{e.message}")
          nil
        end

        # 用語集の説明文を、使っていない語として取り込む。用語集のページには載らず、原稿に
        # その語を書いたとき、説明文を添えた候補に出る（index-library-reserve-spec.md §3.1）。
        # 飛ばすのは、辞書にある語（いまの説明文と印を残す）・新しい本で棄却した語
        # （この本での判断を優先する）・説明文の無い語（使っていない語として残す意味が無い）。
        # @param rejected_here [Array<String>] 取り込む前に、この本で棄却していた語
        def import_glossary(entries, rejected_here)
          existing = @terms_manager.term_names
          skipped = 0

          to_merge = entries.filter_map do |entry|
            term = entry['term']
            next if term.nil? || term.to_s.empty?

            if existing.include?(term) || rejected_here.include?(term) || entry['definition'].to_s.strip.empty?
              skipped += 1
              next
            end

            { 'term' => term, 'yomi' => entry['yomi'] || term, 'definition' => entry['definition'].to_s }
          end

          @terms_manager.merge_terms!(to_merge, flags: '', source: 'imported') if to_merge.any?
          [to_merge.size, skipped]
        end

        # 棄却した語を取り込む。すでに棄却している語と、辞書にある語はスキップ。
        def import_reject(entries)
          already_rejected = @queue_manager.load_rejected_terms
          adopted = @terms_manager.term_names
          skipped = 0

          to_add = entries.filter_map do |entry|
            term = entry['term']
            next if term.nil? || term.to_s.empty?

            if already_rejected.include?(term) || adopted.include?(term)
              skipped += 1
              next
            end

            # 出どころを残し、原稿に出てこない間はレビューファイルの 5 節に並べない（§3.3）
            reject_entry = { 'term' => term, 'source' => 'imported' }
            reject_entry['reason'] = entry['reason'] if entry['reason']
            reject_entry
          end

          @queue_manager.save_rejected_terms(to_add) if to_add.any?
          [to_add.size, skipped]
        end
      end
    end
  end
end
