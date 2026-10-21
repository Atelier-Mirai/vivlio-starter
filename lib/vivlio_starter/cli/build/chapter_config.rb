# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_config.rb
# ================================================================
# 責務:
#   原稿の種類（前書き・本文・付録・後書き）で中間 HTML を絞り込む。
#
# かつては book.yml の chapters 指定を解釈する場所でもあったが、章構成の管理が
# config/catalog.yml へ移った（2025-11-26）ため、番号指定のパーサは撤去した。
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 章 HTML の絞り込みモジュール
      module ChapterConfig
        module_function

        # ディレクトリ内の *.html から、種類が kind のものを番号の順に返す。
        #
        # 種類は TokenResolver が決める——catalog.yml に載った原稿は書かれた区分、載っていない原稿は
        # 番号の範囲（catalog-section-kind-spec.md §2.1）。番号の範囲で集めると、PREFACE に書いた
        # `20-vol2-intro` が本文の中に組み込まれる。区分の中の並びは従来どおり番号の順（§2.3）。
        # 番号だけの原稿（contents/22.md → 22.html）も章として拾う。アンダースコア始まりの特殊ページ（_toc 等）は
        # 番号で始まらないので除かれる
        # @param base_dir [String] HTML の置き場
        # @param kind [Symbol] :preface / :chapter / :appendix / :postface
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] 組む章（空・nil なら絞らない）
        # @return [Array<String>] HTML のパス
        def htmls_for_kind(base_dir, kind, entries_or_keep = nil)
          resolver = TokenResolver::Resolver.new
          kinds = resolver.resolve.to_h { [it.basename, it.kind] }
          keep = keep_numbers(entries_or_keep, resolver)

          Dir.glob(File.join(base_dir, '*.html')).select do |path|
            bn = File.basename(path, '.html')
            number = bn[/\A(\d+)(?=-|\z)/, 1]
            next false unless number
            next false if keep && !keep.include?(number.to_i)

            (kinds[bn] || TokenResolver::Resolver.kind_for_number(number)) == kind
          end.sort
        end

        # 組む章の番号。指定がなければ nil（絞らない）
        # @return [Set<Integer>, nil]
        def keep_numbers(entries_or_keep, resolver)
          raw = Array(entries_or_keep).compact
          return nil if raw.empty?

          raw.filter_map { (it.respond_to?(:number) ? it : resolver.resolve_file(it)).number&.to_i }.to_set
        end
      end
    end
  end
end
