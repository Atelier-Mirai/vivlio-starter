# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/manuscript_markup.rb
# ================================================================
# 責務:
#   原稿にある、ある語の手動登録の印（`[語]`・`[語|読み]`）を探し、外す。
#   辞書の見出し語の綴りを直したときは、原稿に残る古い綴りを探し、新しい綴りへ直す。
#
# なぜ要るか:
#   原稿に `[語]` と書いた語を、レビューファイルで棄却することがある。辞書だけを
#   棄却すると原稿の印が残り、辞書と原稿が食い違う。`vs index:apply` は著者に
#   確かめたうえで、原稿の印も外す（index-glossary-registration-spec.md §3.1.3）。
#
#   印の見分け方はビルド・lint と同じ IndexMarkup に従う。コード・リンク・脚注・
#   タスクリストのブラケットは印ではないので、探さないし触らない。
#
#   綴りも同じ理由で直す。索引の照合は大文字・小文字を区別し、lint は空白の違いしか
#   見ないので、「ラベルID」を「ラベル id」へ直すと、原稿の「ラベルID」は索引に載らず、
#   lint でも見つからなくなる（index-glossary-registration-spec.md §6・改善案 #103）。
# ================================================================

require_relative '../index_markup'
require_relative '../masking'
require_relative 'code_block_stripper'
require_relative 'term_pattern'

module VivlioStarter
  module CLI
    module IndexCommands
      # 原稿の手動登録の印
      module ManuscriptMarkup
        module_function

        # 語の印がある場所（`11-intro:321` の形）
        # @param term [String] 用語
        # @param paths [Array<String>] 原稿のファイル
        # @return [Array<String>]
        def places(term, paths)
          paths.flat_map do |path|
            # コードを空行にして行数を保つ（行番号を著者に見せるため）
            text = CodeBlockStripper.strip(File.read(path, encoding: 'utf-8'))
            labels = IndexMarkup.link_labels(text)
            text.each_line.with_index(1).flat_map do |line, lineno|
              line.to_enum(:scan, IndexMarkup::TERM_PATTERN).filter_map do
                "#{File.basename(path, '.md')}:#{lineno}" if markup_of?(::Regexp.last_match, term, labels)
              end
            end
          end
        end

        # 語の印を外し、語だけを残す（`[語|読み]` → `語`）。
        # @return [Integer] 外した箇所の数
        def strip!(term, paths)
          paths.sum do |path|
            original = File.read(path, encoding: 'utf-8')
            protected_text, spans = Masking.protect_code(original)
            labels = IndexMarkup.link_labels(protected_text)
            count = 0
            # タスクリストの見分けは行頭からの並びを見るので、行ごとに置き換える
            rewritten = protected_text.each_line.map do |line|
              line.gsub(IndexMarkup::TERM_PATTERN) do
                match = ::Regexp.last_match
                next match[0] unless markup_of?(match, term, labels)

                count += 1
                match[1].split('|', 2).first
              end
            end.join
            File.write(path, Masking.restore_code(rewritten, spans), encoding: 'utf-8') if count.positive?
            count
          end
        end

        # 古い綴りが原稿に残っている場所と、書かれた形。空白だけ違う書き方（「ラベル ID」）も
        # 古い綴りとして数える——著者が直したいのは「その語」で、空白の揺れも含むはずだから。
        # @param old_name [String] 直す前の綴り
        # @param new_name [String] 直した後の綴り
        # @param paths [Array<String>] 原稿のファイル
        # @return [Array<Array(String, String)>] [`25-cross-reference:42`, 書かれた形] の並び
        def spelling_places(old_name, new_name, paths)
          paths.flat_map do |path|
            # コードを空行にして行数を保つ（行番号を著者に見せるため）
            text = CodeBlockStripper.strip(File.read(path, encoding: 'utf-8'))
            text.each_line.with_index(1).flat_map do |line, lineno|
              protected_line, = Masking.protect_code(line)
              stale_spellings(protected_line, old_name, new_name).map do
                ["#{File.basename(path, '.md')}:#{lineno}", it[0]]
              end
            end
          end
        end

        # 原稿に残る古い綴りを、新しい綴りへ直す。コードの中は触らない。
        # @return [Integer] 直した箇所の数
        def respell!(old_name, new_name, paths)
          paths.sum do |path|
            original = File.read(path, encoding: 'utf-8')
            protected_text, spans = Masking.protect_code(original)
            stale = stale_spellings(protected_text, old_name, new_name)
            next 0 if stale.empty?

            # 後ろから置き換えて、前の照合の位置をずらさない
            rewritten = protected_text.dup
            stale.reverse_each { rewritten[it.begin(0)...it.end(0)] = new_name }
            File.write(path, Masking.restore_code(rewritten, spans), encoding: 'utf-8')
            stale.size
          end
        end

        # 書き換える照合の並び。新しい綴りで書かれた範囲に掛かるものは除く
        # ——「Type 3」を「Type 3 フォント」へ直すとき、原稿の「Type 3 フォント」を
        # 「Type 3 フォント フォント」にしないため。英数字の語の途中には当てない
        # （「Type 3」を直しても「Type 30」は残る）。
        def stale_spellings(text, old_name, new_name)
          fresh = text.to_enum(:scan, TermPattern.bounded(new_name)).map { ::Regexp.last_match.offset(0) }
          old_pattern = TermPattern.spacing_insensitive(old_name) || TermPattern.bounded(old_name)
          text.to_enum(:scan, old_pattern).filter_map do
            match = ::Regexp.last_match
            next if fresh.any? { |from, to| from < match.end(0) && match.begin(0) < to }

            match
          end
        end

        # その照合が、語の手動登録の印か
        def markup_of?(match, term, labels)
          inner = match[1]
          return false if IndexMarkup.skip_term?(inner) || IndexMarkup.other_notation?(match, labels)

          inner.split('|', 2).first.strip == term
        end
      end
    end
  end
end
