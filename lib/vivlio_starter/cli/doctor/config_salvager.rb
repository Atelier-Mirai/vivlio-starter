# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/doctor/config_salvager.rb
# ================================================================
# 責務:
#   破損した設定ファイルから救出できる値を最善努力（best-effort）で抽出し、
#   scaffold 復元後のファイルへ書き戻して利用者の再入力を減らす。
#   docs/specs/doctor-restore-and-plugin-tools-spec.md §3D（機能 D）の実装。
#
# 大原則（spec §3D.1）:
#   - 正確性は保証しない。誤抽出・取りこぼしがあっても、原本は呼び出し元
#     （doctor の復元処理）が必ず .bak へ退避しているため非破壊。
#   - サルベージに失敗したら nil を返し、素の scaffold 復元へフォールバックする。
#
# 手法（ファイルごとに最適な方法を使い分ける）:
#   - catalog.yml: 破損ファイルをパースせず contents/*.md から章構成を再構築
#   - book.yml:    行スキャンでトップレベル単一行スカラーのみ抽出
# ================================================================

require_relative '../common'
require_relative '../token_resolver'

module VivlioStarter
  module CLI
    module DoctorCommands
      # 破損した設定ファイルからのサルベージ復元（機能 D / best-effort）
      module ConfigSalvager
        module_function

        # サルベージの成果物。
        # @!attribute content [r] 復元ファイルへ書き込む全文
        # @!attribute summary [r] ✅ 行に表示する要約（要確認の明示込み）
        # @!attribute notes [r] 要約の下にインデント表示する補足行の配列
        Result = Data.define(:content, :summary, :notes)

        # 行スキャンで救出を試みる book.yml のトップレベル単一行スカラー。
        # 複数行ブロックスカラー（legal.* 等）は境界判定できないため対象外（spec §3D.3）。
        BOOK_SALVAGE_KEYS = %i[main_title subtitle series release publisher contact author name].freeze

        # scaffold テンプレートのプレースホルダと salvage キーの対応
        BOOK_PLACEHOLDERS = {
          '{{MAIN_TITLE}}' => :main_title,
          '{{SUBTITLE}}' => :subtitle,
          '{{AUTHOR}}' => :author,
          '{{PUBLISHER}}' => :publisher,
          '{{PROJECT_NAME}}' => :name
        }.freeze

        # 救出値が無い場合の既定値（vs new の DEFAULT_ANSWERS と同じ非対話既定）
        BOOK_DEFAULTS = { main_title: '新しい本', subtitle: '', author: '', publisher: '' }.freeze

        # catalog.yml のセクションと章種別の対応（出力順を兼ねる）
        CATALOG_SECTIONS = {
          preface: 'PREFACE', chapter: 'CHAPTERS', appendix: 'APPENDICES', postface: 'POSTFACE'
        }.freeze

        # 破損ファイルから復元内容を生成する。
        # 救出できない・対象外のファイルなら nil（素の scaffold 復元へフォールバック）。
        # @param path [String] 破損した設定ファイルのパス（config/book.yml 等）
        # @param corrupt_content [String] .bak 退避前に読み取った破損ファイルの中身
        # @param scaffold_path [String] scaffold 側の同名ファイル
        # @return [Result, nil]
        def salvage(path, corrupt_content, scaffold_path)
          case File.basename(path)
          when 'catalog.yml' then salvage_catalog
          when 'book.yml' then salvage_book(corrupt_content, scaffold_path)
          end
        end

        # scaffold の book.yml テンプレートを展開する。salvaged の値を優先し、
        # 無いキーは既定値で埋める（機能 A の「欠落 book.yml の素の復元」でも使用）。
        # @param scaffold_path [String]
        # @param salvaged [Hash{Symbol => String}] 救出した値（省略時は全て既定値）
        # @return [String] 展開後の book.yml 全文
        def render_book_yml(scaffold_path, salvaged = {})
          # --- Phase: プレースホルダ展開 ---
          # 単一パス置換で値中の別プレースホルダ文字列の二重展開を防ぐ（vs new と同じ手法）
          substitutions = BOOK_PLACEHOLDERS.to_h do |placeholder, key|
            [placeholder, yaml_escape(salvaged.fetch(key) { default_book_value(key) })]
          end
          pattern = Regexp.union(substitutions.keys)
          content = File.read(scaffold_path, encoding: 'utf-8').gsub(pattern) { substitutions[it] }

          # --- Phase: プレースホルダの無いキーの行置換 ---
          # series / release / contact は scaffold に実値が入っているため、
          # 救出値がある場合のみ該当行の値部分を書き換える
          (salvaged.keys - BOOK_PLACEHOLDERS.values).each do |key|
            content = replace_scalar_line(content, key, salvaged[key])
          end
          content
        end

        # --- catalog.yml: contents/ からの再構築（spec §3D.2）---

        # 破損した catalog.yml は解析せず、contents/*.md の命名規約
        # （NN-slug.md）と章番号レンジから目録を組み立て直す。
        # 部タイトルと意図的な除外（コメントアウト）は catalog.yml にしか
        # 存在しないため構造上復元できない（notes で利用者に明示する）。
        # @return [Result, nil] contents/ に章が 1 つも無ければ nil
        def salvage_catalog
          entries = chapter_entries_from_contents
          return nil if entries.empty?

          grouped = entries.group_by { |_basename, kind| kind }
          body = CATALOG_SECTIONS.map do |kind, section|
            lines = (grouped[kind] || []).map { |basename, _| "  - #{basename}\n" }.join
            "#{section}:\n#{lines}"
          end.join("\n")

          Result.new(
            content: "# vs doctor --fix が contents/ から再構築した目録です（要確認）\n#{body}",
            summary: "config/catalog.yml を contents/ から再構築しました（#{entries.size} 章）",
            notes: ['🟡 部タイトル・除外設定は復元されません。必要なら上記バックアップから書き戻してください']
          )
        end

        # contents/ の章ファイルを [basename, kind] の配列で返す（章番号昇順）。
        # アンダースコア始まりのシステムページと、章番号レンジ外のファイルは除外する。
        def chapter_entries_from_contents
          Dir.glob(File.join(Common::CONTENTS_DIR, '*.md'))
             .map { File.basename(it, '.md') }
             .reject { it.start_with?('_') }
             .filter_map { |base| (number = base[/\A(\d+)(?=[-_]|\z)/, 1]) && [base, number.to_i] }
             .sort_by { |base, number| [number, base] }
             .filter_map { |base, number| (kind = kind_for(number)) && [base, kind] }
        end

        # 章番号→セクション判定は TokenResolver の定義を再利用する（判定ロジックを複製しない）
        def kind_for(number)
          TokenResolver::Resolver::KIND_RANGES.find { |_, range| range.cover?(number) }&.first
        end

        # --- book.yml: 行ベースの最善努力抽出（spec §3D.3）---

        # 破損 book.yml から単一行スカラーを抽出し、テンプレートへ書き戻す。
        # 1 件も救出できなければ nil（素の scaffold 復元へ）。
        def salvage_book(corrupt_content, scaffold_path)
          salvaged = extract_book_scalars(corrupt_content)
          return nil if salvaged.empty?

          notes = salvaged.map { |key, value| "- #{key}: #{value}" }
          notes << '🟡 免責・商標などの複数行設定は復元されません。必要なら上記バックアップから書き戻してください'
          Result.new(
            content: render_book_yml(scaffold_path, salvaged),
            summary: 'config/book.yml を復元し、以下の値を救出しました（要確認）',
            notes:
          )
        end

        # 破損内容を行単位でスキャンし、救出対象キーの値を集める。
        # 破損行は単にマッチしないだけで処理は継続する（取りこぼし容認）。
        def extract_book_scalars(corrupt_content)
          BOOK_SALVAGE_KEYS.each_with_object({}) do |key, found|
            corrupt_content.each_line do |line|
              next unless (value = scalar_value_from(line, key))

              # プレースホルダが残っている値は「利用者の入力」ではないため救出しない
              found[key] = value unless value.empty? || value.include?('{{')
              break
            end
          end
        end

        # 1 行から `  key: value` 形式の値を取り出す。
        # 引用符付き（" / '）と裸の値に対応し、行末コメントは無視する。
        # 閉じ引用符の無い行（破損行）はマッチさせない。
        # @return [String, nil]
        def scalar_value_from(line, key)
          pattern = /\A\s{2}#{Regexp.escape(key.to_s)}:\s*
                     (?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([^"'#\s][^#\n]*?))
                     \s*(?:\#.*)?\z/x
          match = line.match(pattern)
          return nil unless match

          match[1] ? unescape_double_quoted(match[1]) : (match[2] || match[3]&.strip)
        end

        # --- 共通ヘルパー ---

        # 救出値が無いキーの既定値。プロジェクト名はカレントディレクトリ名を使う
        # （vs new がディレクトリ名を既定のプロジェクト名にするのと同じ流儀）
        def default_book_value(key)
          key == :name ? File.basename(Dir.pwd) : BOOK_DEFAULTS.fetch(key, '')
        end

        # `  key: "..."` 行の値部分だけを救出値で置き換える（コメントは保持）
        def replace_scalar_line(content, key, value)
          content.sub(/^(\s{2}#{Regexp.escape(key.to_s)}:\s*)(?:"(?:[^"\\]|\\.)*"|'[^']*'|[^#\n]*?)(\s*#[^\n]*)?$/) do
            %(#{Regexp.last_match(1)}"#{yaml_escape(value)}"#{Regexp.last_match(2)})
          end
        end

        # YAML double-quoted string 内で安全になるよう値をエスケープする
        # （NewCommands.yaml_escape_double_quoted と同等の最小実装）
        def yaml_escape(value)
          value.to_s.gsub(/[\\"\n\r\t]/) do |c|
            { "\\" => '\\\\', '"' => '\\"', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t' }.fetch(c)
          end
        end

        # double-quoted 値のエスケープを復元する（best-effort: 主要シーケンスのみ）
        def unescape_double_quoted(raw)
          raw.gsub(/\\(.)/) { { 'n' => "\n", 't' => "\t", 'r' => "\r" }.fetch(Regexp.last_match(1), Regexp.last_match(1)) }
        end
      end
    end
  end
end
