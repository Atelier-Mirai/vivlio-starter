vivlio-starter 索引・用語集 統合仕様書 (index_glossary_spec.md)

本書は、索引（Index）および用語集（Glossary）機能を一元的に管理するための単一の仕様ソースである。

1. 目的と設計原則
項目,詳細
UX一元化,索引の整理と用語集の執筆を _index_review.md という一つのファイルで完結させる
階層的フラグ,[ig] や [i] などのフラグにより、単語ごとの役割を著者が直感的に制御する
シングルソース,確定データは config/*.yml に保持し、ビルド時に HTML/CSS で最終出力を生成する
柔軟なパース,インデントやフラグの順不同（ig/gi）を許容し、著者の執筆リズムを妨げない

2. ファイル構成
config/
  index_terms.yml        # 承認済み索引辞書
  glossary_terms.yml     # 承認済み用語集辞書（説明文含む）
  index_rejected.yml     # リジェクト済み語
contents/*.md            # 本文ソース
_index_review.md         # 著者が編集する UI（索引・用語集 兼用）
_index_matches.yml       # スキャン結果のキャッシュ
_indexpage.html          # 生成された索引ページ（Vivliostyle用）
_glossarypage.html       # 生成された用語集ページ（Vivliostyle用）

3. レビュー UI (_index_review.md) 仕様
3.1 チェックボックス・フラグ

[ ] 内の文字の有無で、その用語の役割を決定する。文字は順不同。
フラグ,意味,処理内容
i,Index,索引として登録。本文中に <span> を埋め込み、索引ページに掲載。
g,Glossary,用語集として登録。用語集ページに説明文付きで掲載。
ig / gi,Both,索引と用語集の両方に登録。
r,Reject,索引・用語集の両方の候補から除外（リジェクトリスト入り）。
[ ],保留,何もしない。次回の vs index:auto で再度候補として出現。

3.2 説明文（Definition）の記述ルール

用語集（g）として登録する場合、用語行の直後にインデント（スペース2つ以上）を空けてテキストを記述する。

例: 
```markdown
- [ig] **非同期処理** (ひどうきしょり)
  処理の完了を待たずに次のタスクを実行する方式。
  JavaScriptのPromiseなどで利用されます。
```

次の用語行（- [）が始まるまでの全行を説明文として取得する。

インデントはパース時にトリミングされる。

Markdown記法（*強調*、`コード`）の使用を許容する。

4. ワークフロー
4.1 vs index:auto (抽出フェーズ)

    スキャン: 本文から [用語|読み] 記法および MeCab による自動抽出を行う。

    推論:

        定義表現（「〜とは」）を伴う場合は [ig] とし、その一文を説明文候補として挿入。

        それ以外は [i] とする。

    UI生成: 抽出結果を _index_review.md に書き出す。

4.2 vs index:apply (反映フェーズ)

    パース: _index_review.md の全行を走査し、フラグと説明文を解析。

    辞書更新:

        i を含む → index_terms.yml を更新。

        g を含む → glossary_terms.yml を更新（説明文を保存）。

        r を含む → index_rejected.yml へ移動。

    クリーンアップ: 反映済みの _index_review.md を削除（またはリネーム保存）。

4.3 vs build (ビルドフェーズ)

    Pre-process: index_terms.yml に基づき、本文に <dfn> や <span> を自動挿入。

    Page-gen:

        index_terms.yml から _indexpage.html を生成。

        glossary_terms.yml から _glossarypage.html を生成。

    Vivliostyle: ページ番号を CSS target-counter で解決。

5. 辞書データ構造 (YAML)

5.1 config/glossary_terms.yml
terms:
  - term: 非同期処理
    yomi: ひどうきしょり
    definition: |
      処理の完了を待たずに次のタスクを実行する方式。
      JavaScriptのPromiseなどで利用されます。
    approved_at: '2026-01-23 10:00:00'

6. 将来の拡張性

    AI Assist: vs index:auto --ai を実行した際、g 候補の説明文を AI がドラフト生成する。

    Apple Intelligence: macOS 環境において、ローカルリソースを利用した「本文要約型」の用語説明生成をサポートする。

    リンク自動化: 用語集に登録された語に対し、本文から用語集ページへのアンカーリンクを自動生成する。