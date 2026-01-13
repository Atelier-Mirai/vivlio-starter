1. docs/DEVELOPER_GUIDE.md（概要・地図）

ここでは、Vivlio-Starter の「思想」と「構造」の全体像を記述します。

    アーキテクチャ概要: Vivlio-Starter がどのように動作するか（Ruby, CLI, ビルドパイプラインの概念）。

    ディレクトリ構造の解説: contents/, codes/, lib/ などの役割。

    ビルド・ライフサイクル: build コマンドが実行された際、どの内部コマンドがどの順番で呼ばれるかのフロー。

    詳細設計へのリンク:

        インポート処理の仕様

        Markdown変換の仕様

        PDF生成・圧縮の仕様

    開発の進め方: テストの実行方法や、AI（Opus等）を使ってコードを生成する際のプロンプトの指針。

2. docs/specs/xx_spec.md（詳細設計）

ここでは、今回リファクタリングの対象となった 600 行のコードのような、「具体的なロジック」を記述します。

    入力と出力: 何を受け取り、何を生成するか。

    変換ルール: 正規表現のリストや、Rougeを用いた言語判定のアルゴリズムなど。

    例外処理: 特定のタグが見つからなかった場合や、画像変換に失敗した際の挙動。

3. コマンド群

利用者が用いるコマンド
	help, new, build, clean, delete, doctor,
	create, rename, renumber, pdf:compress, resize, resize:high, resize:medium, resize:low, index, index:auto, index:apply, open, import, glossary, lint, metrics, cover
	
内部コマンド
	entries,create:titlepage, create:colophon, create:legalpage,  pre_process, convert, post_process, toc, pdf, vivliostyle

### 内部コマンドの使用法

内部コマンドは、主にビルドパイプラインの中間処理や自動生成ステップとして利用します。個別に実行することもできますが、通常は `vs build` が必要に応じて呼び出します。

* `entries`  
  `contents/` から生成した HTML を走査し、Vivliostyle が参照する `entries.js` を再構築します。章の追加・削除後にリンク切れがないか確認するときに単独実行することもあります。
* `create:titlepage` / `create:colophon` / `create:legalpage`  
  `config/book.yml` のメタデータからタイトルページ・奥付・リーガルページを再生成します。書誌情報を更新した際に再出力したい場合に使用します。
* `pre_process`  
  Markdown から HTML に変換する前処理フェーズを単体で走らせます。`chapter-common.css` で必要な補助ファイルを生成したい場合やデバッグ時に利用します。
* `convert`  
  前処理済み Markdown を Vivliostyle/VFM で HTML に変換するステップのみを実行します。レンダリング差分を確認したい場合に使用します。
* `post_process`  
  HTML の置換や索引用タグ付けなど、変換後の後処理だけを実行します。`pre_process`/`convert` と組み合わせて段階的にデバッグ可能です。
* `toc`  
  目次 HTML（`_toc.html`）を再生成します。手動で章構成を調整した直後に TOC の差分を確認したい場合に便利です。
* `pdf`  
  Vivliostyle CLI を直接叩いて PDF を生成します。`vs build` の内部ステップですが、サンプル HTML だけで試しに PDF を出力したいときに手動実行できます。
* `vivliostyle`  
  `config/book.yml` の設定から `vivliostyle.config.js` を生成します。タイトル・著者・言語・読み進め方向・出力ファイル名などを反映し、既存ファイルがある場合はバックアップを作成します。ビルドパイプラインの初期化時に自動で呼ばれますが、設定変更後に手動で再生成したい場合に単独実行できます。
    
