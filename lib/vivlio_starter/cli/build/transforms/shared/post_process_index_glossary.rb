# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/post_process_index_glossary.rb
# ================================================================
# 責務:
#   索引・用語集を EPUB 用に書き換える（章の短い名前・切れたリンクの解除）
# ================================================================

require 'cgi'
require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 索引・用語集を EPUB 用に書き換える（章の短い名前・切れたリンクの解除）
      module Transforms::Shared::PostProcessIndexGlossary
        module_function

        # ================================================================
        # EPUB 用 索引・用語集 後処理
        # ================================================================
        # CSS target-counter() は EPUB リーダーで非対応のため、
        # 空の <a> タグにテキストを挿入して可視化する。
        # PDF ビルド完了後に元ファイルを直接修正する方式。
        # （コピーを作ると本文中の †リンクが _glossarypage.html を参照して切れるため）
        # ================================================================

        # 索引・用語集 HTML を EPUB 用に直接修正する
        # リフローにページ番号は無いので、リンクの文字は章の短い名前（序章・第7部 など）にする
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列（書籍構成順）
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          chapter_map = build_chapter_label_map(html_files)
          # 索引・用語集の参照先 id が EPUB 内に実在するか照合するための id 集合（RSC-012 恒常対策）
          existing_ids = collect_existing_fragment_ids(html_files)

          html_files.each do |path|
            basename = File.basename(path, '.html')
            case basename
            when '_indexpage'
              rewrite_index!(path, chapter_map, existing_ids)
            when '_glossarypage'
              rewrite_glossary!(path, chapter_map, existing_ids)
            end
          end
          html_files
        end

        # EPUB に含まれる全 HTML から id 属性値を収集する（RSC-012 恒常対策）。
        # 索引（#idx-…）・用語集バックリンク（#gls-src-…）の参照先が実在するかの照合に使う。
        # epubcheck は当該 EPUB に存在しないフラグメントを指すリンクを RSC-012 ERROR とするため、
        # ここで集めた集合に無い id を指すリンクは rewrite 時に素のテキストへフォールバックする。
        #
        # 重要: 正規表現で `id="…"` を拾うと、コード例として本文に載った
        # `&lt;span id="idx-…"&gt;`（エスケープ済みテキスト）まで実在 id と誤カウントし、
        # 実 DOM には無い id を「実在」と判定して死リンクを温存してしまう（RSC-012 残存）。
        # epubcheck と同じく **実 DOM の要素 id だけ**を数えるため Nokogiri でパースする。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Set<String>] EPUB 内に実在する（要素として存在する）id 値の集合
        def collect_existing_fragment_ids(html_files)
          ids = Set.new
          html_files.each do |path|
            next unless File.exist?(path)

            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            doc.xpath('//*[@id]').each { |node| ids << node['id'] }
          end
          ids
        end

        # 索引・用語集 HTML 内で、参照先フラグメント id が EPUB に実在しないリンクを
        # 素のテキスト（内側の中身）へフォールバックして解除する（RSC-012 恒常対策・付録 A-2）。
        # 索引リンク・用語集バックリンクは中身が空の <a> のため、解除されたリンクは消える。
        # ハッシュ（#）を含まない外部・絶対 URL や、実在 id を指すリンクはそのまま残す。
        #
        # @param html [String] 対象 HTML
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合
        # @return [Array(String, Integer)] [解除後の HTML, 解除したリンク数]
        def unlink_missing_fragment_links(html, existing_ids)
          removed = 0
          updated = html.gsub(%r{<a\b[^>]*\shref="([^"]*)"[^>]*>(.*?)</a>}m) do
            whole = ::Regexp.last_match(0)
            href = ::Regexp.last_match(1)
            inner = ::Regexp.last_match(2)

            fragment = href.split('#', 2)[1]
            # フラグメントを持たないリンク・実在 id へのリンクは温存する
            next whole if fragment.nil? || fragment.empty?
            next whole if existing_ids.include?(decoded_fragment(fragment))

            removed += 1
            inner
          end
          [updated, removed]
        end

        # href のフラグメントを id 属性と同じ土俵へ戻す。
        #
        # href は URL エンコードされて出力される（`#gls-src-31-lint-css組版-1` は
        # `#gls-src-31-lint-css%E7%B5%84%E7%89%88-1`）が、id 属性は素の UTF-8 のまま。
        # 素で突き合わせると CJK を含むアンカーが必ず不一致になり、**実在するリンクまで
        # 解除**してしまう。`+` を空白に変える unescape ではなくパーセント記号だけを解く
        # unescapeURIComponent を使う——id に `+` は現れないが、フラグメントの意味として
        # 正しいのはこちら。
        def decoded_fragment(fragment)
          CGI.unescapeURIComponent(fragment)
        rescue ArgumentError
          fragment # 壊れたエスケープ列は素のまま照合する（握り潰して死リンクを残さない）
        end

        # ファイル名プレフィックス → リンクに出す章の名前 のマッピングを構築する。
        # かつては書籍構成順の連番（0, 1, 2）を出していたが、読者にはどの章か分からなかった。
        # 例: { "07" => "序章", "33" => "第7部", "53" => "特別編" }
        # 題が読めない HTML だけ、構成順の番号で埋める。
        #
        # @param html_files [Array<String>] 書籍構成順の HTML ファイルパス
        # @return [Hash{String => String}] プレフィックス → 章の短い名前
        def build_chapter_label_map(html_files)
          mapping = {}
          html_files.each do |path|
            basename = File.basename(path, '.html')
            next unless basename.match?(/\A\d{2}(?=-|\z)/) # 番号だけの原稿（22.html）も章

            mapping[basename[0, 2]] ||= chapter_label(CLI::EntriesCommands.extract_html_title(path)) || mapping.size.to_s
          end
          Common.log_info("[EPUB] 章の名前: #{mapping.map { |k, v| "#{k}→#{v}" }.join(', ')}")
          mapping
        end

        # 章の題から、索引へ並べられる短い名前を取り出す。
        # 「第7部　通信・システム編」→「第7部」、「第14章 ビルド」→「第14章」。
        # 区切りの無い題はそのまま使い、長ければ切り詰める。
        def chapter_label(title)
          text = title.to_s.strip
          return nil if text.empty?

          head = text[/\A[^　]+(?=　)/] || text[/\A\S*[章部編](?=\s)/] || text
          head.size > CHAPTER_LABEL_MAX ? "#{head[0, CHAPTER_LABEL_MAX]}…" : head
        end


        # 索引 HTML を EPUB 用に書き換える
        # - 空リンクに章の名前を挿入
        # - 連続するリンク間に ", " 区切りを追加
        #
        # @param path [String] _indexpage.html のパス
        # @param chapter_map [Hash{String => String}] プレフィックス → 章の名前
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合（RSC-012 恒常対策）
        def rewrite_index!(path, chapter_map, existing_ids)
          html = File.read(path, encoding: 'utf-8')

          # Step 0: 参照先 id が EPUB に実在しない索引リンクを解除（RSC-012 恒常対策）。
          # 名前の挿入・併合より前に行い、死リンクを空 <a> のうちに取り除く。
          html, removed = unlink_missing_fragment_links(html, existing_ids)
          Common.log_info("[EPUB] #{File.basename(path)} の未定義フラグメント索引リンクを #{removed} 件解除しました") if removed.positive?

          # Step 1: 空の <a> タグに章の名前を挿入
          html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
            tag_open = ::Regexp.last_match(1)
            prefix = ::Regexp.last_match(2)
            "#{tag_open}>#{chapter_map[prefix] || prefix.to_i}</a>"
          end

          # Step 2: 同一番号（同一章＝EPUB 上の同一ページ）を指す連続リンクを併合
          html = dedup_sequential_number_links(html)

          # Step 3: 連続する </a><a を </a>, <a に変換（カンマ区切り）。末尾の別の巻の案内の前も区切る
          html = html.gsub(%r{</a>\s*(<a\s+href="|<span class="index-other-volume">)}, '</a>, \1')

          File.write(path, html, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（章の名前のリンク＋併合＋区切り挿入）")
        end

        # 用語集 HTML を EPUB 用に書き換える
        # - 空バックリンクに章の名前を挿入
        #   CSS の ::before が "→ " を付加するため記号は不要
        #
        # @param path [String] _glossarypage.html のパス
        # @param chapter_map [Hash{String => String}] プレフィックス → 章の名前
        # @param existing_ids [Set<String>] EPUB 内に実在する id 値の集合（RSC-012 恒常対策）
        def rewrite_glossary!(path, chapter_map, existing_ids)
          html = File.read(path, encoding: 'utf-8')

          # RSC-005 是正（§1-8）: <dl class="glossary-list"> 直下のグループ見出し <div> は
          # XHTML5 の dl 内容モデル違反。見出しを <dl> の外（兄弟 <p role=heading>）へ出し、
          # 頭文字ごとに <dl> を分割する。PDF は生成元 HTML をそのまま使うため無影響（EPUB 専用後処理）。
          html = split_glossary_groups(html)

          # 参照先 id が EPUB に実在しない用語集バックリンク（#gls-src-…）を解除（RSC-012 恒常対策）。
          # 名前の挿入・併合より前に行い、死リンクを空 <a> のうちに取り除く。
          html, removed = unlink_missing_fragment_links(html, existing_ids)
          Common.log_info("[EPUB] #{File.basename(path)} の未定義フラグメントバックリンクを #{removed} 件解除しました") if removed.positive?

          # 空の <a> タグに章の名前を挿入
          html = html.gsub(%r{(<a\s+href="(\d{2})[^"]*"[^>]*)>\s*</a>}) do
            tag_open = ::Regexp.last_match(1)
            prefix = ::Regexp.last_match(2)
            "#{tag_open}>#{chapter_map[prefix] || prefix.to_i}</a>"
          end

          # 同一番号（同一章＝EPUB 上の同一ページ）を指す連続バックリンクを併合
          html = dedup_sequential_number_links(html)

          File.write(path, html, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} を書き換えました（章の名前のバックリンク＋併合）")
        end

        # 用語集の <dl> 直下のグループ見出し <div> を <dl> の外へ出し、頭文字ごとに <dl> を分割する。
        # 例: <dl><div class="glossary-group-header">A-Z</div><dt>..</dt><dd>..</dd>..</dl>
        #  → <p class="glossary-group-header">A-Z</p><dl><dt>..</dt><dd>..</dd>..</dl>
        # 各見出しで「dl を閉じ → p 見出し → dl を開く」に置換し、先頭に生じる空の <dl> を除去する。
        # 見出しの role/aria-level 属性はそのまま <p> へ引き継ぐ（見た目はクラスセレクタで不変）。
        #
        # @param html [String] 用語集 HTML
        # @return [String] dl を分割した HTML（RSC-005 解消）
        def split_glossary_groups(html)
          split = html.gsub(%r{<div class="glossary-group-header"([^>]*)>([^<]*)</div>}) do
            attrs = ::Regexp.last_match(1)
            label = ::Regexp.last_match(2)
            %(</dl>\n<p class="glossary-group-header"#{attrs}>#{label}</p>\n<dl class="glossary-list">)
          end
          # 先頭の見出し置換で生じる空の <dl></dl> を取り除く
          split.gsub(%r{<dl class="glossary-list">\s*</dl>\s*}, '')
        end

        # 索引・用語集のリンクのうち、同じ章を指す連続リンクを最初の 1 つに併合する。
        # PDF のページ番号併合（Step 8 の backlink dedup）に相当する処理を、章の名前に対して
        # 文字列処理で行う。名前の挿入後・カンマ区切り挿入前に適用する想定。空白区切りで隣接する
        # <a ...>名前</a> の連なりを対象とし、各連なり内で名前が初出のリンクだけを残す。
        #
        # @param html [String] 章の名前を挿入済みの索引/用語集 HTML
        # @return [String] 同じ章のリンクを併合した HTML
        def dedup_sequential_number_links(html)
          html.gsub(%r{(?:<a\s[^>]*>[^<]+</a>\s*){2,}}) do |run|
            links = run.scan(%r{<a\s[^>]*>[^<]+</a>})
            links.uniq { |link| link[%r{>([^<]+)</a>\z}, 1] }.join(' ')
          end
        end

        # 索引・用語集のリンクに出す章の名前の長さの上限（字）。
        CHAPTER_LABEL_MAX = 8
      end
    end
  end
end
