# `vs preflight` 章別エラー・警告サマリー 仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）**
> 対象: PLANNED.md:98 [Medium]「`vs preflight` の章別エラー・警告サマリー」＋付随の非対称（Guard 系 `:warn` が最終サマリーに反映されない）の解消
> 決定事項（本仕様の提案）:
> - **`LinkImageValidator` を汎用化するのではなく、横断的な `IssueRegistry`（新規）を一段上に設ける**。LinkImageValidator・コードインクルード・クロスリファレンス・QueryStream・Guard 警告の各発生源は registry へ「章・行・重要度・カテゴリ・メッセージ」を積むだけにする（LinkImageValidator の内部構造 `ValidationReport` は現状のまま温存し、registry へのブリッジのみ足す——改修範囲を最小化）
> - リアルタイムのログ出力（🔴🟡 の逐次表示）は**廃止しない**。従来どおり流し、**最後に章別サマリー表を追加**する（逐次表示は「どこで詰まったか」の手掛かりとして有用）
> - 終了コードの意味は**変えない**（エラーまたは既存 `any_issues?` 相当 → 1、警告のみ → 0）。変えるのは**文言**（警告件数を拾う）だけ
> 関連: `lib/vivlio_starter/cli/samovar/preflight_command.rb:104,145`（`print_preflight_summary`）, `lib/vivlio_starter/cli/pre_process/link_image_validator.rb:44,187,198`（`ValidationReport`・`any_issues?`・`record_code_include_error`）, `lib/vivlio_starter/cli/pre_process/cross_reference_processor.rb`, `lib/vivlio_starter/cli/pre_process/data_render.rb`（QueryStream の on_error/on_warning）, `lib/vivlio_starter/cli/guards/container_class_check.rb`（`:warn` を出す Guard の代表例）

## 0. 背景・問題

1. **混在出力**: preflight は前処理をファイル単位（並列）で流すため、🔴🟡 が章をまたいで時系列に混在する。数十件出ると「21 章に何件あるのか」が読み取れない
2. **サマリーの非対称**: 最終行（`print_preflight_summary`）は `LinkImageValidator.any_issues?` **だけ**を見る。`ContainerClassCheck` が未知クラスを 🟡 警告しても最終行は「✅ Preflight 完了: 良好な状態です」になる一方、裸 URL 警告は `link_issues` に積まれるため「課題あり」に転ぶ。同じ「警告」なのに最終判定への影響が発生源次第で変わる

## 1. 出力仕様（著者向け）

従来の逐次ログの後に、章別サマリーと総括を表示する:

```
📋 章別サマリー
   00 前書き            ✅
   10 はじめに          🟡 警告 1 件
   21 画像              🔴 エラー 2 件・🟡 警告 3 件
   90 付録A             ✅
   （全章 ✅ の場合は表自体を「✅ 全 42 章: 問題なし」の 1 行に短縮）

   章に紐付かない指摘    🟡 警告 1 件   ← Guard 警告など（例: 未知コンテナクラス）

⚠️ Preflight 完了: エラー 2 件・警告 5 件 — 詳細は上記ログを確認してください
   文章校正（表記揺れ・スペル）は vs lint で行えます。
```

- 章の並びは番号順。**指摘ゼロの章も表示**する（「検査した」ことの証明。ただし章数が多く全て ✅ なら 1 行へ短縮）
- 最終行は 3 段階: 🔴 エラーあり（従来の `:failure`）／🟡 **警告のみ**（新設・`⚠️ Preflight 完了: 警告 N 件（ビルドは可能です）`・終了コード 0）／✅ 指摘なし
- 章単位実行（`vs preflight 21`）でも同形式（対象章のみ）

## 2. 実装

### 2.1 `IssueRegistry`（新規・横断収集器）

`lib/vivlio_starter/cli/pre_process/issue_registry.rb`:

```ruby
Issue = Data.define(:chapter, :line, :severity, :category, :message)
# chapter:  章 basename（"21-images"）。章に紐付かない指摘は nil
# severity: :error / :warn
# category: :image / :link / :code_include / :cross_reference / :query_stream / :guard など
```

- `record(chapter:, severity:, category:, message:, line: nil)`・`reset!`・`summary_by_chapter`・`counts` を提供
- 並列前処理から呼ばれるため **Mutex で同期**（LinkImageValidator と同様の配慮）
- **表示はしない**。逐次ログは従来どおり各発生源が `log_error/log_warn` で出す（registry は集計専用。二重表示の責務分離）

### 2.2 発生源のブリッジ（影響 4〜5 ファイル＝PLANNED の見積りに一致）

| 発生源 | 変更 |
|---|---|
| `LinkImageValidator` | `validate` / `record_code_include_error` / `check_external_urls!` で report へ積む際に registry にも record（image→:image/:code_include、link→:link）。内部構造は不変 |
| `CrossReferenceProcessor` | 未解決参照などの 🔴/🟡 出力箇所に record を併記 |
| `DataRender`（QueryStream） | `on_error` / `on_warning` コールバック内で record（location "file:line" から章・行を分解） |
| Guards（`Guard.run!`） | Check が返す `:warn` 結果を registry へ record（chapter: nil）。Guard の実行は preflight 冒頭＝`reset!` 後に移す（現状も本処理前なので順序調整のみ） |
| `preflight_command.rb` | `reset!` 呼び出し・章別サマリー表示・`print_preflight_summary` の 3 段階化（§1） |

### 2.3 `print_preflight_summary` の書き換え

```ruby
def print_preflight_summary
  errors, warns = PreProcessCommands::IssueRegistry.counts
  if errors.positive?
    Common.log_result("Preflight 完了: エラー #{errors} 件・警告 #{warns} 件 — 詳細は上記を確認してください", status: :failure)
  elsif warns.positive?
    Common.log_result("Preflight 完了: 警告 #{warns} 件（ビルドは可能です）", status: :warning)  # log_result に :warning が無ければ追加
  else
    Common.log_result('Preflight 完了: 良好な状態です', status: :success)
  end
  ...
end
```

- 終了コードは従来判定（`LinkImageValidator.any_issues?`）を維持する。registry の warn を終了コードに影響させない（設計どおり 0。PLANNED の注記に従う）
- なお現状 `any_issues?` は裸 URL「警告」でも 1 を返す。この歪みも registry 移行後は「終了コードは severity :error のみで決める」へ寄せたいが、**挙動変更になるため本仕様では現状維持**とし、KNOWN_ISSUES に転記して別途判断する

### 2.4 build コマンドへの波及

`vs build` も同じ発生源を通るため、registry は自動的に積まれる。build 側では章別サマリー表は**出さず**（ビルド成果物の一覧が主役）、既存 `LinkImageValidator.print_summary` の末尾に「⚠️ ほか警告 N 件（詳細は vs preflight で確認できます）」の 1 行だけ追加する。

## 3. テスト

1. **issue_registry_test**（新規）: record/counts/summary_by_chapter・章 nil の扱い・並列 record（スレッド 8 本で競合しない）
2. **preflight_command 系**: エラーのみ/警告のみ/ゼロの 3 パターンで最終行文言と終了コード（1/0/0）。章別表に指摘ゼロ章が載る・全 ✅ 短縮
3. **ブリッジ**: 各発生源 1 ケースずつ「ログが出る＋registry に category 付きで積まれる」（既存テストへの追記で足りる見込み）
4. **Guard 警告の反映**: `ContainerClassCheck` が warn を返すフィクスチャで、最終行が ⚠️（警告 N 件）になり終了コード 0

## 4. 手順（実装順序）

1. `IssueRegistry` ＋テスト
2. LinkImageValidator ブリッジ（最多数の発生源・効果が最大）→ preflight のサマリー表と 3 段階最終行 → この時点で一度リリース可能な単位
3. Guard :warn・CrossReference・QueryStream のブリッジを順次追加
4. build 側の 1 行追加（§2.4）
5. `rake test`・実プロジェクトで `vs preflight` 目視

## 5. スコープ外

- 終了コード体系の変更（§2.3 のとおり KNOWN_ISSUES 送り）
- `vs lint`（textlint/spellcheck）の指摘統合——preflight は構造チェック専用という既存の役割分担を維持
- JSON 等の機械可読出力（CI 連携）: 要望が出たら registry からのシリアライズとして追加しやすい構造にはなっている
