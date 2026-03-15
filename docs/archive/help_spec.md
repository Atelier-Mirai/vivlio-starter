# Vivlio CLI Command & Help Specification

本仕様書は、Vivlio Starter におけるコマンド体系（外部・外部）の分類、および Samovar を用いたヘルプ表示の統一ルールを定義するものである。

---

## 1. コマンドの分類と定義

コマンドは「利用者が直接実行する **Public Commands**」と「システムが内部で呼び出す **Internal Commands**」に厳格に分離する。

### 1.1 利用者向けコマンド (Public API)
これらは `vs --help` または `vs [command] --help` で利用方法が表示される。

| カテゴリ | コマンド名 | 概要 |
| :--- | :--- | :--- |
| **プロジェクト管理** | `help`, `new`, `import`, `doctor`, `delete`, `clean` | プロジェクトの生成、移行、診断、破棄 |
| **執筆・編集支援** | `create`, `rename`, `renumber`, `open` | 原稿ファイルの生成、名称変更、番号振り直し |
| **アセット・索引** | `resize`, `resize:high/medium/low`, `index`, `index:auto/apply` | 画像最適化、索引語の抽出・反映 |
| **ビルド・出力** | `build`, `pdf:compress` | PDF生成、ファイルサイズ圧縮 |

補足: `vs pdf` は内部パイプライン専用コマンドとして扱い、`vs pdf --help` では直接の使い方を表示しない。その代わり `vs pdf --help` 実行時に `pdf:compress` コマンドの存在を案内し、利用者には `vs pdf:compress --help` で詳細を参照してもらう。

### 1.2 内部コマンド (Internal API)
これらは開発者およびシステム内部用であり、標準のヘルプ一覧には表示されない。
詳細は `docs/DEVELOPER_GUIDE.md` にて定義し、ビルドパイプラインのステップとして管理する。

- **ビルドステップ**: `pre_process`, `convert`, `post_process`, `pdf`
- **自動生成要素**: `entries`, `create:titlepage`, `create:colophon`, `create:legalpage`, `toc`

---

## 2. Samovar によるヘルプ実装方針

### 2.1 `print_usage` の統一利用
Thor や独自実装のヘルプ出力、および手動の `puts` による説明表示はすべて廃止し、Samovar のクラス定義に基づく自動生成に一本化する。

- **ルートヘルプ**: `vs` または `vs help` 実行時に、全 Public Commands のサマリを表示する。
- **個別コマンドヘルプ**: `vs [command] --help` または `-h` を受け付け、そのコマンド専用の引数とオプションの詳細を表示する。

### 2.2 内部コマンドの隠蔽
Samovar の `Subcommand` リストには Public Commands のみを登録する。内部コマンドは Samovar のルーティングから外すか、あるいは開発者専用のフラグを介してのみアクセス可能とし、一般利用者の `vs help` には表示させない。

例外として `pdf` のように内部実装上は必要だが関連する Public サブコマンド（`pdf:compress`）を案内したいケースでは、`vs pdf --help` の出力内で `pdf:compress` の存在を告知し、詳細は `vs pdf:compress --help` を見るよう誘導する。

---

## 3. ドキュメント構造の住み分け

### 3.1 外部向けヘルプ (`--help`)
利用者がターミナル上で即座に確認すべき情報を網羅する。
- **Usage**: 正しいコマンドの構文（引数の順序など）。
- **Description**: そのコマンドが「何をするか」の簡潔な説明。
- **Options**: 利用可能なフラグ（例: `--all`, `--force`）とショートハンド。

### 3.2 内部向けドキュメント (`docs/DEVELOPER_GUIDE.md`)
内部コマンドの仕様と、それらが形成する「ビルドライフサイクル」を記述する。
- 各内部コマンドの入力（どのファイルを読むか）と出力（何を書き換えるか）。
- コマンド間の依存関係（例: `toc` の前に `convert` が必要、など）。

---

## 4. マイグレーション・ルール

1. **Thor の完全廃止**: `Thor` を継承している既存の CLI クラスをすべて `Samovar::Command` 形式へ書き換える。
2. **ヘルプ出力の委譲**: `def help` 等を自前で実装せず、Samovar が提供する `print_usage` メソッドに表示ロジックを委ねる。
3. **エラーハンドリング**: 引数が不足している場合や不正なオプションが渡された際、Samovar の標準挙動として適切なヘルプを表示するように設定する。

---

## 5. 表示イメージ

### 公開コマンド一覧
```zsh
$ vs --help
Usage: vs [command] [options]
  new      プロジェクトを新規作成します
  build    書籍をビルドします
  import   Re:VIEW Starter プロジェクトを取り込みます
  ... (他の Public Commands)
```

### 個別コマンドのヘルプ
```
$ vs build --help
Usage: vs build [options]
  --no-clean   中間ファイルを削除せずに残す
  -h, --help   ヘルプを表示
  ... (他のオプション)
```