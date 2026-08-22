# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index_markup.rb
# ================================================================
# 責務:
#   索引マークアップ `[用語]` / `[用語|読み]` の綴りの唯一の定義元。
#   「その `[` は索引マークアップのものか、それとも別の記法が自分の構文として
#   持っているブラケットか」の判定を 1 箇所へ集約する。
#
# なぜこのモジュールがあるか:
#   同じ判定が前処理・索引スキャナ・辞書登録の 3 箇所へコピーされ、しかも
#   どれもインライン脚注 `^[本文]` を除外していなかった（実害はコピーごとに
#   別々に現れる: 本文へ脚注が流れ込む／脚注本文が索引語になる／辞書が汚れる）。
#   notation-implementation-guide.md §2 の「同じ責務のコードを書き始めたら
#   基盤側に API を足すサイン」に従って引き上げたもの。
#
# なぜ Masking ではないのか:
#   Masking は「コード領域解釈の唯一の実装」として 10 箇所以上から使われる
#   基盤で、記法の知識を混ぜると無関係な前処理まで意味が変わる。記法の知識は
#   その記法のモジュールが持つ——Lint::NotationGuard と同じ型に揃えている。
#
# 仕様: inline-footnote-index-collision-spec.md §4
#       index-markup-plain-fallback-spec.md §4.1（plain_text）
# ================================================================

require 'cgi'

module VivlioStarter
  module CLI
    # 索引マークアップの綴りの正典。
    module IndexMarkup
      module_function

      # --- 除外している「[...] と綴る他の記法」 -----------------------------
      #
      # 記法を増やしてブラケットが衝突したら、ここへ 1 項目足せば 3 箇所すべてが
      # 追従する（Lint::NotationGuard::MACHINE_DATA_CONTAINERS と同じ運用）。
      #
      #   (?!\()   リンク・画像記法 `[text](url)` … `]` の直後が `(`
      #   (?<!\^)  インライン脚注 `^[本文]`       … `[` の直前が `^`
      #
      # 参照脚注 `[^id]` は「ブラケットの中身」で見分けるのでパターンでは弾かず、
      # skip_term? が落とす。ブラケットの外と中で担当が分かれている。

      # 索引マークアップ全体（`[用語]` と `[用語|読み]` の双方に一致し、
      # 読みの分離は利用側が行う）。前処理・索引スキャナが使う。
      TERM_PATTERN = /(?<!\^)\[([^\[\]\n]+)\](?!\()/

      # 読み付き `[用語|読み]`。辞書登録が読みを取り出すために使う。
      TERM_WITH_YOMI_PATTERN = /(?<!\^)\[([^\]|]+)\|([^\]]+)\]/

      # 読みなし `[用語]` のみ（`|` を含むものは TERM_WITH_YOMI_PATTERN の担当）。
      # 辞書登録が 2 パターンを順に当てる方式のため、こちらは `|` を持たない。
      TERM_ONLY_PATTERN = /(?<!\^)\[([^\]|]+)\](?!\()/

      # --- 参照リンク（CommonMark）との共存 -------------------------------
      #
      # `[foo]` が参照リンクになるのは、**同じ文書に `[foo]: url` の定義がある
      # ときだけ**と CommonMark が定めている。定義が無ければただの文字列である。
      # この規則をそのまま使えば、判定の根拠が「Vivlio Starter の都合」ではなく
      # Markdown の仕様になる。仕様: markdown-notation-collision-spec.md §3
      #
      # これを入れる前は、参照リンクもリンク定義も索引語に化けて**リンクが消えて
      # いた**（実測: `[本文][ref]` が 2 つの索引語になり、`[ref]: url` の定義行も
      # 索引語＋素の URL になっていた）。

      # リンク参照定義の行。CommonMark は行頭のインデントを 3 つまで認める。
      # **脚注定義 `[^1]: …` を除く。** 綴りは同じでも別の記法で、拾うとラベル表が
      # 汚れる（実測: 本書 4 章と雛形 2 ファイルの脚注が入り込んでいた）。
      LINK_DEFINITION = /\A[ \t]{0,3}\[(?!\^)([^\[\]\n]+)\]:[ \t]*\S/

      # 文書に定義されたリンクラベルを集める。
      # コード領域は呼び出し側が Masking で除いてから渡す。
      # @param text [String] 章の内容
      # @return [Array<String>] 正規化済みラベル
      def link_labels(text)
        text.to_s.each_line.filter_map do |line|
          matched = line.match(LINK_DEFINITION)
          normalize_label(matched[1]) if matched
        end.uniq
      end

      # ラベルの正規化。CommonMark は大文字小文字を区別せず、連続する空白を 1 つに畳む。
      def normalize_label(label) = label.to_s.strip.gsub(/\s+/, ' ').downcase

      # そのマッチは参照リンクの一部か（＝索引マークアップではないか）。
      #
      # 見分けるのは 2 つの形だけでよい。
      #   1. **隣接した `][`** … `[本文][ref]` `[ref][]`。定義の有無を問わず外す
      #      ——索引語を 2 つ区切りなしで並べる用途は存在しないので、表を引くまでもない
      #   2. **定義済みラベルの単独形** … `[ref]`。ここだけラベル表を引く
      # 定義行そのもの（`[ref]: url`）は 2 に含まれる（自分のラベルは必ず表にある）。
      #
      # 前後 1 文字は MatchData から引く。走査対象の文字列を受け取らずに済むので、
      # 退避（マスク）済みの行を扱う索引スキャナからも、素の本文を扱う前処理からも
      # 同じ呼び方ができる。
      #
      # @param match [MatchData] TERM_PATTERN のマッチ
      # @param labels [Array<String>] link_labels の戻り
      # @return [Boolean] 参照リンクなら true
      def reference_link?(match, labels)
        return true if match.post_match.start_with?('[')  # [本文][ref] の前半・[ref][]
        return true if match.pre_match.end_with?(']')     # 後半の [ref]

        labels.include?(normalize_label(match[1]))
      end

      # --- GFM のタスクリストとの共存 --------------------------------------
      #
      # `- [ ]` `- [x]` はリスト項目の先頭に置くタスクリスト・マーカーで、GFM が
      # 定めた記法である。VFM は最初から対応しているのに、索引スキャン（Step 4）が
      # VFM 変換（Step 5）より前に走るため、マーカーが索引語に化けて VFM へ届いて
      # いなかった（実測: `[ ]` の空白 1 文字にアンカーまで振られていた）。
      # 仕様: markdown-notation-collision-spec.md §4

      # マーカーの手前に置ける並び。`- ` `* ` `+ ` と番号付き（`1. ` `1) `）。
      TASK_MARKER_PREFIX = /\A[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\z/

      # マーカーの中身。GFM は空白・`x`・`X` を認める。
      TASK_MARKER_STATES = [' ', 'x', 'X'].freeze

      # そのマッチはタスクリストのマーカーか。
      # **行中の `[ ]` は対象にしない**——タスクリストではないので従来どおり扱う。
      # @param match [MatchData] TERM_PATTERN のマッチ
      # @return [Boolean]
      def task_list_marker?(match)
        return false unless TASK_MARKER_STATES.include?(match[1])
        return false unless match.pre_match.match?(TASK_MARKER_PREFIX)

        # GFM はマーカーの直後に空白を求める。
        match.post_match.empty? || match.post_match.match?(/\A[ \t\r\n]/)
      end

      # そのマッチは索引マークアップ**ではない**（他の記法が持つブラケット）か。
      # 消費側はこれ 1 つを見ればよい——記法が増えたらここへ 1 行足す。
      # @param match [MatchData] TERM_PATTERN のマッチ
      # @param labels [Array<String>] link_labels の戻り
      # @return [Boolean]
      def other_notation?(match, labels = [])
        reference_link?(match, labels) || task_list_marker?(match)
      end

      # ブラケットの中身が索引語として無効か。
      # パターンが弾けない「中身で見分ける記法」——参照脚注 `[^id]`——を落とす。
      # @param term_text [String, nil] ブラケットの中身
      # @return [Boolean] 索引語として扱わないなら true
      def skip_term?(term_text)
        return true if term_text.nil? || term_text.empty?

        # 脚注参照 [^id]。著者が意図的にマークアップした [!] [&&] [<h1>] は除外しない
        term_text.start_with?('^')
      end

      # --- 索引タグを付けられないときの素のテキスト表現 ---------------------
      #
      # 索引スキャナが走らないビルド（`index_glossary.enabled: false` 等）では
      # `[用語]` を素のテキストへ落とす。その姿をここに置くのは、**同じ「索引語を
      # 表示する」処理が 2 箇所にあってエスケープの有無が食い違っていた**ため。
      # 索引スキャナは `CGI.escapeHTML` を通すのに前処理は素通ししており、
      # `[<h1>]` が生タグとして VFM に渡って**本物の章見出しになっていた**
      # （目次と PDF アウトラインまで汚染。index-markup-plain-fallback-spec.md §2.2）。
      #
      # 読み（`|` 以降）を落とす規則も前処理にしか無かったので、ここへ寄せる。
      #
      # @param term_text [String] ブラケットの中身（`用語` または `用語|読み`）
      # @return [String] エスケープ済みの用語部分
      def plain_text(term_text)
        term = term_text.include?('|') ? term_text.split('|', 2).first : term_text
        CGI.escapeHTML(term.to_s)
      end
    end
  end
end
