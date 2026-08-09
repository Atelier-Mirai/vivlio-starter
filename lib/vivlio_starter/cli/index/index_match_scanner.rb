# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/index_match_scanner.rb
# ================================================================
# 責務:
#   Markdown ファイルをスキャンし、索引語記法を検出・変換する。
#   - [用語|読み] 記法を検出し、<dfn> または <span> タグに変換
#   - [用語] 記法（読み省略）を検出し、MeCab で読みを推測
#   - 初出は <dfn>、2回目以降は <span> タグを使用
#   - マッチ情報を _index_matches.yml（ワークスペース直下・P4b §2.5）に保存
#
# Set について:
#   - `require 'set'` は書かない。Ruby 3.4 では core が Set を autoload し
#     （`Object.autoload?(:Set)` が "set" を返す）、4.0 では組み込みになった
#   - Set[] リテラル構文を使用
# ================================================================

require 'yaml'
require 'fileutils'
require 'cgi'
require 'digest'
require_relative '../common'
require_relative '../masking'
require_relative '../index_markup'
require_relative 'term_pattern'
require_relative 'main_reference'
require_relative 'heading_outline'
require_relative 'yomi_inferrer'

module VivlioStarter
  module CLI
    module IndexCommands
      INDEX_TERMS_MISSING_MESSAGE = <<~MSG
        索引語辞書(config/index_glossary_terms.yml)が見つかりませんでした
        🟡  原稿に [用語|読み] という書き方で手動登録した語のみが索引に載ります
        🟡  自動索引機能を有効にするには: vs index:auto -> vs index:apply
      MSG

      def self.add_post_build_message(message)
        @post_build_messages ||= []
        @post_build_messages << message unless @post_build_messages.include?(message)
      end

      def self.flush_post_build_messages
        return if @post_build_messages.nil? || @post_build_messages.empty?

        @post_build_messages.each do |message|
          emit_index_message(message, use_log_warn: false)
        end

        @post_build_messages.clear
      end

      def self.emit_index_message(message, use_log_warn: true)
        message.each_line do |line|
          text = line.rstrip
          next if text.empty?

          if use_log_warn
            Common.log_warn(text.sub(/\A🟡\s*/, ''))
          else
            Common.log_always(text)
          end
        end
      end

      # 索引語スキャン・タグ付けクラス
      class IndexMatchScanner
        # 見出し行とそのレベル（`### 見出し` → 3）
        HEADING_LINE = /\A(\#{1,6})[ \t]+\S/

        # 索引語マッチの正規表現。綴りの定義元は IndexMarkup（唯一の定義元）。
        # [用語|読み] または [用語] 形式を検出し、リンク記法 [text](url) と
        # インライン脚注 ^[本文] は除外される。
        INDEX_TERM_PATTERN = IndexMarkup::TERM_PATTERN

        attr_reader :seen_terms, :term_occurrence, :index_data, :matches, :config_missing, :no_matches,
                    :glossary_backlinks

        def initialize(defer_warnings: false)
          @seen_terms = Set[]
          @term_occurrence = Hash.new(0)
          @index_data = Hash.new { |h, k| h[k] = Set[] }
          @matches = []
          @yomi_inferrer = YomiInferrer.new
          @config_missing = false
          @no_matches = false
          @defer_warnings = defer_warnings
          @unified_terms = load_unified_terms
          @config_terms = longest_first(@unified_terms.select { it['flags'].to_s.include?('i') })
          @glossary_terms = @unified_terms.select { it['flags'].to_s.include?('g') }.to_h { [it['term'], it] }
          @glossary_backlinks = Hash.new { |h, k| h[k] = [] }
          # 用語集のみの用語（索引対象外だがバックリンクは必要）
          @glossary_only_terms = longest_first(@unified_terms.select do |t|
            flags = t['flags'].to_s
            flags.include?('g') && !flags.include?('i')
          end)
          # 主要参照（説明箇所）の指定。辞書の main: を 用語 → 章名の集合に畳む。
          # 単一章とリストの両方を受ける（index-main-reference-spec.md §1.3）。
          # 主要参照の指定。`21#Markdown とは` のような節指定も受ける（R2）
          @main_refs = @unified_terms.to_h do |t|
            [t['term'], Array(t['main']).map { MainReference.parse(it) }]
          end
          @main_chapters = @main_refs.transform_values { it.map(&:chapter).to_set }
          # 主要参照の落とし先（R1）。章を読んだ時点で下見した結果を持つ。
          @has_section_heading = {}
          @has_prose_occurrence = {}
          @main_section_range = {}
          @main_decided = Set[]
          @section_warned = Set[]
          @current_heading_level = nil
          @current_lineno = nil
          # 用語ごとに不変な導出物のキャッシュ（1 行ごとに作り直さない）
          @index_patterns = {}
          @term_yomis = {}
        end

        # 統合用語辞書（config/index_glossary_terms.yml）を読み込む
        def load_unified_terms
          config_file = 'config/index_glossary_terms.yml'
          unless File.exist?(config_file)
            if @defer_warnings
              @config_missing = true
            else
              IndexCommands.emit_index_message(INDEX_TERMS_MISSING_MESSAGE)
            end
            return []
          end

          begin
            data = YAML.load_file(config_file)
            terms = data['terms'] || []
            Common.log_info("統合用語辞書から #{terms.size} 件の語句をロードしました")
            terms
          rescue StandardError => e
            Common.log_warn("config/index_glossary_terms.yml の読み込みに失敗: #{e.message}")
            []
          end
        end

        # 全章ファイルをスキャンして索引語をタグ付け
        # @param chapters [Array<String>] 対象章のファイル名リスト（例: ['11-basics', '12-advanced']）
        # @param read_only [Boolean] 読み取り専用モード（ファイルを書き換えない、contents/ を優先）
        def scan_all_chapters!(chapters, read_only: false)
          Common.log_action("索引語のスキャンを開始します... (対象: #{chapters.size} 章)")

          chapters.each do |chapter|
            # ファイルを探す
            # read_only モードでは contents/ を優先（原稿のマークアップを検出するため）
            # 通常モードではルート直下を優先（pre_process 後のファイルを更新するため）
            md_file = find_chapter_file(chapter, prefer_contents: read_only)

            unless md_file
              Common.log_warn("スキップ (Markdown が見つかりません): #{chapter}")
              next
            end

            scan_and_tag_file!(md_file, read_only: read_only)
          end

          save_matches!
          Common.log_success("索引語スキャン完了: #{@matches.size} 件の索引語を検出")
        end

        # 章ファイルを探す
        # 前処理済み中間 .md はワークスペースの html/ に置かれる（P4 §3.4-1）
        # @param chapter [String] 章名
        # @param prefer_contents [Boolean] contents/ ディレクトリを優先するか
        # @return [String, nil] ファイルパス
        def find_chapter_file(chapter, prefer_contents: false)
          workspace_file = File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")
          contents_file = File.join(Common::CONTENTS_DIR, "#{chapter}.md")

          if prefer_contents
            # contents/ を優先
            return contents_file if File.exist?(contents_file)
            return workspace_file if File.exist?(workspace_file)
          else
            # 前処理済み（ワークスペース）を優先
            return workspace_file if File.exist?(workspace_file)
            return contents_file if File.exist?(contents_file)
          end

          nil
        end

        # 単一ファイルをスキャンしてタグ付け
        # @param md_file [String] Markdown ファイルパス
        # @param read_only [Boolean] 読み取り専用モード（ファイルを書き換えない）
        def scan_and_tag_file!(md_file, read_only: false)
          content = File.read(md_file, encoding: 'utf-8')
          file_basename = File.basename(md_file, '.md')

          # contents/ ディレクトリ内のファイルは常に読み取り専用（原稿保護）
          effective_read_only = read_only || md_file.start_with?(Common::CONTENTS_DIR)

          match_count_before = @matches.size
          Common.log_info("スキャン中: #{md_file} ...")

          # コードブロック内を除外してスキャン
          new_content = process_content_with_code_block_exclusion(content, file_basename)

          match_count_after = @matches.size
          index_diff = match_count_after - match_count_before
          content_changed = new_content != content

          if content_changed
            # read_only モードでない場合のみファイルを書き換え
            if effective_read_only
              Common.log_success("#{md_file}: #{index_diff} 件の索引語を検出しました（読み取り専用）")
            else
              File.write(md_file, new_content, encoding: 'utf-8')
              Common.log_success("#{md_file}: #{index_diff} 件の索引語をタグ付けしました")
            end
          else
            Common.log_info("#{md_file}: 索引語は見つかりませんでした")
          end
        end

        private

        # コードブロックを除外してコンテンツを処理する。
        # コード（フェンス区切り行・内容行）とみなす行は Masking（唯一の実装）が判定し、
        # 地の文の行だけを process_line でタグ付けする。索引タグは行を跨がないため、
        # 地の文行を原文行配列の同位置へ置換して再結合すれば行数・コード行は不変。
        # 可変長フェンス・入れ子・```include: 除外は Masking が一貫して保証する。
        def process_content_with_code_block_exclusion(content, file_basename)
          survey_main_targets(content, file_basename)

          lines = content.lines
          Masking.each_prose_line(content) do |line, lineno|
            # 行が見出しなら、そのレベル。主要参照をどこに落とすかの判断に使う（R1）
            @current_heading_level = line[HEADING_LINE, 1]&.size
            @current_lineno = lineno
            lines[lineno - 1] = process_line(lines[lineno - 1], file_basename)
          end
          @current_heading_level = nil
          @current_lineno = nil
          lines.join
        end

        # 主要参照の落とし先を決めるための下見（index-main-reference-section-spec.md R1）。
        #
        # **章題（h1）は主要参照にしない。** 章の名前であって、その語を腰を据えて
        # 説明している箇所ではない——「Markdown 執筆チュートリアル」を指すと索引が
        # 章扉のページを太字にしてしまい、著者が指したい「## Markdown とは」に届かない。
        #
        # 落とし先は「節見出し（h2〜h6）にその語がある → そこ」「無ければ本文の初出」
        # 「本文にも無ければ（章題にしか無い）章題」の順。これを行ごとの逐次処理で
        # 決めることはできない——本文の初出を採るかどうかが、後に節見出しが来るかに
        # 依るため。章を読んだ時点で先に「どちらがあるか」だけ調べておく。
        def survey_main_targets(content, file_basename)
          names = @main_chapters.select { |_, chapters| chapters.include?(file_basename) }.keys
          return if names.empty?

          sections = []
          prose = []
          Masking.each_prose_line(content) do |line, _|
            case line[HEADING_LINE, 1]&.size
            when nil then prose << line
            when 1 then nil # 章題は数えない
            else
              sections << line
              prose << line
            end
          end

          outline = HeadingOutline.parse(content)
          names.each do |name|
            key = [name, file_basename]
            pattern = TermPattern.for(@unified_terms.find { it['term'] == name } || { 'term' => name })
            @has_section_heading[key] = sections.any? { it.match?(pattern) }
            @has_prose_occurrence[key] = prose.any? { it.match?(pattern) }
            @main_section_range[key] = resolve_section(name, file_basename, outline)
          end
        end

        # 節指定（`21#Markdown とは`）を行範囲へ解決する（R2〜R4）。
        # 見つからない・曖昧なときは知らせるが、**組版は止めない**——推敲の途中で
        # ビルドが通らなくなるより、章単位へ落として先へ進むほうがよい。
        def resolve_section(name, file_basename, outline)
          ref = @main_refs[name]&.find { it.chapter == file_basename && it.section? } or return nil

          located = outline.locate(ref.path)
          return warn_missing_section(name, ref, outline) unless located

          warn_ambiguous_section(name, ref, located) if located.ambiguous
          located.range
        end

        # 見出しの文言は推敲で変わる（「主な用途」→「さまざまな用途」）し、
        # 節ごと消えることもある。**壊れた指定を黙って無視しない。**
        def warn_missing_section(name, ref, outline)
          return nil unless warn_once?(name, ref)

          near = outline.nearest(ref.path)
          Common.log_warn(
            "「#{name}」の主要参照が指す見出しが見つかりません: #{ref}",
            detail: ["#{ref.chapter} の見出し: #{outline.summary.join(' / ')}",
                     near.any? ? "近いもの: #{near.join(' / ')}" : nil,
                     '見出しを書き換えたなら主要参照も直してください。' \
                     "章だけの指定（#{ref.chapter}）に戻すと、その章で最初に説明している節を自動で選びます"].compact.join("\n")
          )
          nil
        end

        # 最初の 1 件を黙って採らない——著者が意図した箇所と違えば、
        # 索引が静かに間違った場所を指す。
        def warn_ambiguous_section(name, ref, located)
          return unless warn_once?(name, ref)

          Common.log_warn(
            "「#{name}」の主要参照 #{ref} は #{located.candidates.size} 箇所あります",
            detail: "親の見出しを添えて絞ってください:\n" \
                    "#{located.candidates.map { "  #{ref.chapter}##{it}" }.join("\n")}"
          )
        end

        # 同じ章を 2 度スキャンしても（build と preflight）同じ警告を繰り返さない
        def warn_once?(name, ref) = @section_warned.add?([name, ref.to_s]) ? true : false

        # この出現を主要参照にするか。章ごとに 1 箇所だけ立てる。
        def main_reference?(term, file_basename)
          key = [term, file_basename]
          return false unless @main_chapters.fetch(term, Set[]).include?(file_basename)
          return false if @main_decided.include?(key)

          # 節を名指しされているなら、その範囲の最初の出現（見出し行を含む）
          if (range = @main_section_range[key])
            return false unless range.cover?(@current_lineno.to_i)

            @main_decided << key
            return true
          end

          level = @current_heading_level
          landed = if @has_section_heading[key] then level.to_i >= 2
                   elsif @has_prose_occurrence[key] then level.nil? || level >= 2
                   else true # 章題にしか無い語は、その章題を指すほかない
                   end
          @main_decided << key if landed
          landed
        end

# 1行を処理して索引語をタグ付け
def process_line(line, file_basename)
  # 1. まず [用語|読み] または [用語] 記法を処理する。
  #    インラインコード `...` 内はリテラル表示が目的なので保護して索引対象から外す
  #    （コメント強調マーカー `[!]` のように [...] と綴る記法が、明示マーカー [用語]
  #     と誤認されて索引語化されるのを防ぐ。後段 2/3 のインラインコード保護に揃える）。
  #    コード領域の解釈は Masking が唯一の実装（P1）。独自パターン /`[^`]+`/ では
  #    N 連バッククォート対（``foo`bar`` の形）の中身が露出し、逆に `` を
  #    「バッククォート・空白・バッククォート」と食べて地の文を飲み込んでいた。
  #    退避トークンは [...] を含まない（含めると INDEX_TERM_PATTERN に自己マッチする）。
  mask = LineMask.new(line)
  mask.protect!(Masking::INLINE_CODE_SPAN)

  mask.substitute_match!(INDEX_TERM_PATTERN) do |match|
    term_text, yomi_raw = extract_term_and_yomi(match[1])

    # 無効な用語をスキップ（元のテキストをそのまま返す）
    if skip_term?(term_text)
      match[0]
    else
      # 読みの決定順序:
      # 1. 記法で指定された読み [用語|読み]
      # 2. config/index_glossary_terms.yml に定義された読み
      # 3. MeCab による推測
      yomi = yomi_raw || lookup_config_yomi(term_text) || @yomi_inferrer.infer(term_text)

      process_term(term_text, yomi, file_basename)
    end
  end

  # 生成したタグは退避しない（従来と同じ粒度）。後段 2 の
  # protect_untouchable_regions! が TAGGED_TERM_PATTERN を先頭で退避するため、
  # 先行タグの中身へ後続の用語が食い込むことはない。
  processed_line = mask.restore

  # 2. 次に config/index_glossary_terms.yml に基づく自動タグ付け（索引用語）
  indexed_line = apply_auto_indexing(processed_line, file_basename)

  # 3. 用語集のみの用語にバックリンク・†リンクを付与
  apply_glossary_only_linking(indexed_line, file_basename)
end

        # 索引対象として無効な用語かどうかを判定（判定の実体は IndexMarkup）。
        # 除外するのは脚注構文 [^id] のみ。著者が意図的にマークアップした
        # [!] [&&] [!DOCTYPE] [<h1>] などは除外しない。
        # @param term_text [String] 用語テキスト
        # @return [Boolean] スキップすべきならtrue
        def skip_term?(term_text) = IndexMarkup.skip_term?(term_text)

        def extract_term_and_yomi(raw_text)
          return [raw_text, nil] unless raw_text&.include?('|')

          pipe_count = raw_text.count('|')

          # 読み指定は「用語|読み」の1本区切りのみ許可し、それ以外はリテラル扱い
          return [raw_text, nil] unless pipe_count == 1

          term_part, yomi_part = raw_text.split('|', 2)

          if term_part.nil? || term_part.empty? || yomi_part.nil? || yomi_part.empty?
            [raw_text, nil]
          else
            [term_part, yomi_part]
          end
        end

        # config/index_glossary_terms.yml から読みを検索
        def lookup_config_yomi(term_text)
          config = @config_terms.find { |t| t['term'] == term_text }
          config ? config['yomi'] : nil
        end

        # 用語を当ててはいけない領域（既にタグ付けされた要素・HTML タグ・振り仮名・
        # インラインコード）を退避してから用語を順に当て、最後にまとめて戻す。
        #
        # 退避を用語ごとにやり直さないのが要点。従来は 1 行あたり用語数（153 語）だけ
        # 4 本の保護 gsub と Regexp 生成を繰り返しており、これがスキャン時間の大半を
        # 占めていた（地の文 7,421 行 × 153 語 = 113 万反復）。
        #
        # 生成したタグは即座に退避するため、後続の用語が先行タグの中身や属性
        # （class="index-term" 等）へ食い込むことはない——従来の「用語ごとに保護し直す」
        # 方式と遮蔽の効果は同じで、結果は 1 バイトも変わらない。
        class LineMask
          # 退避トークンは NUL 区切り。原稿に現れず、用語パターン（/\bTERM\b/）が
          # 退避内容へ食い込む余地もない（従来の `[[HTML_TOKEN_0]]` 形式は文字列
          # "HTML" を含み、直後の `_` が単語文字であるおかげで偶然無事だった）。
          SENTINEL = "\u0000VSIDX"

          def initialize(text)
            @text = text
            @stash = []
          end

          # パターンに一致する箇所を退避する
          def protect!(pattern)
            @text = @text.gsub(pattern) { |match| stash(match) }
          end

          # 退避済みテキストに対して用語を置換する（ブロックはマッチ文字列を受け取る）
          def substitute!(pattern, &) = @text = @text.gsub(pattern, &)

          # 捕捉グループが要る置換。ブロックへ MatchData を渡す。
          #
          # substitute! では足りない——Regexp.last_match（$~）はフレームローカルで、
          # gsub がここで立てる値は「呼び出し側で定義されたブロック」からは見えず常に
          # nil になる。索引マークアップ [用語|読み] は読みの分離に捕捉グループが要る
          # ので、MatchData を明示的に手渡してその制約を越える。
          def substitute_match!(pattern) = @text = @text.gsub(pattern) { yield ::Regexp.last_match }

          # 文字列を退避してトークンを返す（生成したタグを後続の用語から隠すため）
          def stash(content)
            token = "#{SENTINEL}#{@stash.size}\u0000"
            @stash << [token, content]
            token
          end

          def token?(text) = text.include?(SENTINEL)

          # 退避を戻して完成した行を返す。
          # 入れ子（インラインコード `vs build <章名>` は HTML タグを内包する）を正しく
          # 巻き戻すため挿入の逆順（LIFO）で展開する。順方向だと内側のトークンが
          # 未展開のまま表面化して残留する。
          # 置換文字列中の `\\` や `\1` を特殊扱いさせないため、必ずブロック形式で戻す。
          def restore
            @stash.reverse_each { |token, content| @text = @text.gsub(token) { content } }
            @text
          end
        end

        # 既にタグ付けされた索引語要素（直後の用語集リンクを含む）
        TAGGED_TERM_PATTERN =
          %r{(<(?:span|dfn)[^>]*class="index-term"[^>]*>.*?</(?:span|dfn)>)(\s*<a[^>]*class="glossary-link"[^>]*>.*?</a>)?}

        # Markdown のリンク・画像記法 `[ラベル](URL)` / `![alt](path)`。
        # ラベルの中で用語に当たると、用語集リンク <a>†</a> がリンクラベルへ
        # 入れ子になる。Markdown はリンクの入れ子を許さないので外側の
        # `[...](...)` がリンクとして成立せず、`[Vivliostyle†](https://…) [^url2]`
        # が本文へ生のまま組まれていた（前書き「謝辞」で実際に発生）。
        # リンクラベルは行き先を指す文字列で索引の見出しには向かないから、
        # 記法ごと退避して当てない。
        MARKDOWN_LINK_PATTERN = /!?\[[^\[\]\n]*\]\([^()\n]*\)/

        # config/index_glossary_terms.yml に基づく自動タグ付けを適用
        def apply_auto_indexing(line, file_basename)
          return line if @config_terms.empty?

          mask = LineMask.new(line)
          protect_untouchable_regions!(mask)

          @config_terms.each do |config|
            yomi = term_yomi(config)
            mask.substitute!(index_term_pattern(config)) do |match|
              # 退避トークンへのマッチは触らない（念のための保険）
              next match if mask.token?(match)

              # 生成したタグ（索引タグ＋用語集リンク）を丸ごと隠す。従来は次の用語の
              # 保護 gsub が同じ範囲を 1 トークンへ退避していたので粒度も等しい。
              mask.stash(process_term(match, yomi, file_basename))
            end
          end

          mask.restore
        end

        # 長い用語から当てる（最長一致）。
        #
        # 当てた用語はタグごと退避され、後続の用語からは見えなくなる。辞書は読み順に
        # 並ぶので、そのまま回すと短いほうが先に当たって長いほうが二度と一致しない。
        # 実測では「マスター画像」が `<dfn>マスター</dfn>画像` と組まれ、用語集の
        # 「マスター画像」には本文リンクが 1 件も付かなかった（同じ壊れ方が
        # ラベルID・レビューファイル・バンドル画像でも起きていた）。
        # 索引の見出しとしても、長いほうが語として特定的で見出しに向く。
        #
        # 同じ長さなら辞書の並び（読み順）を保つ——sort_by は安定ではないので
        # 添字を第 2 キーに置き、ビルドのたびに順序が揺れないようにする。
        def longest_first(terms)
          terms.each_with_index.sort_by { |term, i| [-term['term'].to_s.length, i] }.map(&:first)
        end

        # 用語を当ててはいけない領域を退避する。
        # 順序は従来の保護順を踏襲する——先に索引語要素を丸ごと退避しないと、
        # 内側の HTML タグだけが個別に退避されて要素が分断される。
        def protect_untouchable_regions!(mask)
          mask.protect!(TAGGED_TERM_PATTERN)  # 既にタグ付けされた索引語要素
          mask.protect!(/<[^>]+>/)            # 残りの HTML タグ（属性内の誤マッチ防止）
          mask.protect!(MARKDOWN_LINK_PATTERN) # リンク・画像記法 [ラベル](URL)
          mask.protect!(/\{[^{}]*\|[^{}]*\}/) # 振り仮名 {漢字|ふりがな}
          # インラインコード（リテラル表示が目的）。解釈の正典は Masking（P1）——
          # 独自パターンだと ``foo`bar`` のような N 連バッククォート対を取りこぼす。
          mask.protect!(Masking::INLINE_CODE_SPAN)
        end

        # 索引語のマッチングパターン。辞書由来で不変なので初回だけ組み立てて使い回す。
        #
        # 綴りの解釈は TermPattern が唯一の定義元。ここには「スラッシュを剥がして
        # Regexp にする」同じ 3 行の写しがあり、TermPattern が `\b` を ASCII の語境界
        # として読むようになったあとも本文タグ付けだけ取り残されていた——広さ計測と
        # 主要参照の候補は TermPattern を通るので、「候補には出るのに索引には載らない」
        # という食い違いになる。
        def index_term_pattern(config)
          @index_patterns[config['term']] ||= TermPattern.for(config)
        end

        # 用語の読み。辞書の指定が無ければ MeCab の推測で、いずれも用語ごとに不変。
        def term_yomi(config)
          @term_yomis[config['term']] ||= config['yomi'] || @yomi_inferrer.infer(config['term'])
        end

        # 用語集のみの用語にバックリンク・†リンクを付与（索引タグは追加しない）。
        # apply_auto_indexing と同じく退避は 1 回だけ行う。生成するのは †リンクのみで、
        # 用語そのものの文字は伏せない——従来も †リンクの <a> タグだけが退避対象で、
        # 用語の文字は次の用語から見えていたため、その粒度を保つ。
        def apply_glossary_only_linking(line, file_basename)
          return line if @glossary_only_terms.empty?

          mask = LineMask.new(line)
          protect_untouchable_regions!(mask)

          @glossary_only_terms.each do |config|
            term = config['term']
            # 索引語と同じ解釈で当てる。完全一致のままだと `CSS` が `CSS3` の中にも
            # †リンクを付けてしまい、索引側と挙動が食い違う
            mask.substitute!(index_term_pattern(config)) do |match|
              next match if mask.token?(match)

              @term_occurrence[term] += 1
              link = build_glossary_link(term, file_basename, @term_occurrence[term])
              link ? "#{match}#{mask.stash(link)}" : match
            end
          end

          mask.restore
        end

        # 索引語を処理してタグを生成
        def process_term(term_text, yomi, file_basename)
          @term_occurrence[term_text] += 1
          occurrence_num = @term_occurrence[term_text]

          is_main = main_reference?(term_text, file_basename)

          # ID の生成（決定的ダイジェストで一意性を保証）
          # String#hash はプロセス毎にシードがランダム化されるため、ビルドの度に
          # ID が変わり、単体/結合ビルドの不一致や冪等性崩れを招いていた。
          # 同一語が常に同一 ID になるよう SHA1 ベースの安定ダイジェストを用いる。
          anchor_id = "idx-#{Digest::SHA1.hexdigest(term_text)[0, 12]}-#{occurrence_num}"

          # 初出判定（O(1) の高速検索）
          is_first = !@seen_terms.include?(term_text)
          @seen_terms << term_text if is_first

          tag_name = is_first ? 'dfn' : 'span'

          # 索引データの蓄積（Set で重複を自動排除）
          @index_data[term_text] << {
            'yomi' => yomi,
            'link' => "#{file_basename}.html##{anchor_id}",
            'file' => file_basename,
            'is_definition' => is_first,
            'is_main' => is_main
          }

          # マッチ情報を記録
          @matches << {
            'id' => anchor_id,
            'term' => term_text,
            'yomi' => yomi,
            'file' => file_basename,
            'is_definition' => is_first,
            'is_main' => is_main,
            'tag_type' => tag_name
          }

          # タグを生成して返す（HTMLタグをエスケープ）
          escaped_term = CGI.escapeHTML(term_text)
          escaped_yomi = CGI.escapeHTML(yomi.to_s)
          index_tag = %(<#{tag_name} id="#{anchor_id}" class="index-term" data-yomi="#{escaped_yomi}">#{escaped_term}</#{tag_name}>)

          # 用語集に登録されている場合は、用語集リンクを追加
          glossary_link = build_glossary_link(term_text, file_basename, occurrence_num)
          glossary_link ? "#{index_tag}#{glossary_link}" : index_tag
        end

        # 用語集インジケータ記号（固定）
        GLOSSARY_INDICATOR = '†'

        # 用語集リンクを生成
        # 常に†記号を上付きで表示し、クリックで用語集ページへジャンプ
        def build_glossary_link(term_text, file_basename, occurrence_num)
          return nil unless @glossary_terms.key?(term_text)

          slug = generate_glossary_slug(term_text)
          # 用語集へのバックリンク情報を記録（章+用語スラッグ+出現番号で一意化）
          gls_src_id = "gls-src-#{file_basename}-#{slug}-#{occurrence_num}"
          @glossary_backlinks[term_text] << {
            'chapter' => file_basename,
            'occurrence' => occurrence_num,
            'anchor_id' => gls_src_id
          }

          # 用語集へのリンクを生成（†記号を上付きで表示）
          %(<a id="#{gls_src_id}" class="glossary-link" href="_glossarypage.html#gls-#{slug}"><sup>#{GLOSSARY_INDICATOR}</sup></a>)
        end

        # 用語集スラッグを生成
        def generate_glossary_slug(term)
          term.downcase.gsub(/\s+/, '-').gsub(/[^\p{L}\p{N}-]/, '')
        end

        # 索引データを _index_matches.yml に保存
        def save_matches!
          # ワークスペース直下へ保存する（P4b §2.5）。vs index 系の単独実行では
          # ワークスペースが未作成のことがあるため、書き出し前に dir を作る。
          cache_file = Common::INDEX_MATCHES_FILE
          FileUtils.mkdir_p(File.dirname(cache_file))

          # 用語名でソートして可読性を向上
          sorted_terms = @index_data.keys.sort.to_h do |term|
            [term, @index_data[term].to_a]
          end

          # 用語集バックリンクは出現情報（派生データ）なので辞書には書かず、
          # matches と書き手・読み手・ライフサイクルが同じ中間 YAML に同居させる（R1/R2）
          sorted_backlinks = @glossary_backlinks.keys.sort.to_h do |term|
            [term, @glossary_backlinks[term]]
          end

          data = {
            'generated_at' => Time.now.iso8601,
            'total_matches' => @matches.size,
            'terms' => sorted_terms,
            'matches' => @matches,
            'glossary_backlinks' => sorted_backlinks
          }

          File.write(cache_file, data.to_yaml, encoding: 'utf-8')
          Common.log_info("索引データを保存: #{cache_file} (合計: #{@matches.size} 件)")
          return unless @matches.empty?

          if @defer_warnings
            @no_matches = true
          else
            IndexCommands.emit_index_message(INDEX_TERMS_MISSING_MESSAGE)
          end
        end
      end
    end
  end
end
