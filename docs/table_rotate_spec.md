# 横長表のページ内回転機能 (table-rotate) 仕様書

## 1. 概要

本機能は、横に長く、通常の縦向きページでは収まりきらない表（`<table>`要素）を、ページいっぱいに縦に回転（90度）させて配置するための機能です。

Markdownのフェンス記法（`:::`）を利用して、表を回転させるラッパー要素（`<div class="table-rotate">`）で囲みます。さらに、表のサイズや位置を細かく調整するためのCSSカスタムプロパティ（CSS変数）の値を、フェンス記法の属性として設定できるようにします。

## 2. 構文と変換規則

### 2.1. 基本構文（Markdown）

Markdownのフェンス記法を用いて、表を `table-rotate` クラスで囲みます。

```markdown
:::{.table-rotate [オプション属性]}
| ヘッダー1 | ヘッダー2 | ... |
|---|---|---|
| データ1 | データ2 | ... |
:::
```

### 2.2. HTML変換規則

上記Markdownは、以下のHTML構造に変換されます。

#### 基本変換

| Markdown | HTML変換 |
|---|---|
| `:::{.table-rotate}` | `<div class="table-rotate">` |
| 表の内容 | `<table>...</table>` |
| `:::` | `</div>` |

#### オプション属性適用時の変換

フェンス記法の属性として指定されたカスタムプロパティの値は、ラッパー要素の `style` 属性に直接変換されます。

| Markdown例 | HTML変換例 |
|---|---|
| `:::{.table-rotate scale:60% shift-y:20%}` | `<div class="table-rotate" style="--table-rotate-scale: 60%; --table-rotate-shift-y: +20%;">` |
| `:::{.table-rotate scale:0.50 shift-y:0.10}` | `<div class="table-rotate" style="--table-rotate-scale: 50%; --table-rotate-shift-y: +10%;">` |

## 3. オプション属性（カスタムプロパティの調整）

表の回転後の表示を調整するために、以下のカスタムプロパティの値を属性として指定できます。

### 3.1. 利用可能なオプション属性

| 属性名 | 対応カスタムプロパティ | 役割 | 単位/形式 | 既定値（未指定時） |
|---|---|---|---|---|
| `scale` | `--table-rotate-scale` | 回転後の表の縮尺率（縦向きページに収めるための縮小率） | 小数（0.xx）またはパーセント（xx%） | 70% |
| `shift-y` | `--table-rotate-shift-y` | 回転後の表の垂直方向の微調整（ページ中央からの上下シフト量） | 小数（0.xx）またはパーセント（xx%） | +25% |

#### 💡 注意点

- `scale` 属性にパーセント値（例: `scale:60%`）を指定した場合、HTMLの `style` 属性にはパーセント形式（例: `--table-rotate-scale: 60%;`）で出力されます。
- `scale` 属性に小数（例: `scale:0.60`）を指定した場合、HTMLの `style` 属性には自動的にパーセント（例: `--table-rotate-scale: 60%;`）に変換されます。
- `shift-y` 属性にパーセント値（例: `shift-y:20%`）を指定した場合、HTMLの `style` 属性にはパーセント形式（例: `--table-rotate-shift-y: +20%;`）で出力されます。
- `shift-y` 属性に小数（例: `shift-y:0.20`）を指定した場合、HTMLの `style` 属性には自動的にパーセント（例: `--table-rotate-shift-y: +20%;`）に変換されます。

### 3.2. 属性の指定例

#### 3.2.1. 既定値の利用（調整なし）

```markdown
:::{.table-rotate}
... 表の内容 ...
:::
```

**変換結果:** `<div class="table-rotate">` （既定値 `--table-rotate-scale: 70%;` `--table-rotate-shift-y: +25%;` が適用されます）

#### 3.2.2. 縮尺とシフト量の調整

##### 例1: 縮尺を60%、Y軸シフトを20%に設定

```markdown
:::{.table-rotate scale:60% shift-y:20%}
... 表の内容 ...
:::
```

**変換結果:** `<div class="table-rotate" style="--table-rotate-scale: 60%; --table-rotate-shift-y: +20%;">`

##### 例2: 縮尺を50%、Y軸シフトを10%に設定

```markdown
:::{.table-rotate scale:0.50 shift-y:0.10}
... 表の内容 ...
:::
```

**変換結果:** `<div class="table-rotate" style="--table-rotate-scale: 50%; --table-rotate-shift-y: +10%;">`

## 4. CSS定義（参照情報）

本機能を実現するための主要なCSS定義は以下の通りです。

```css
/* =====================================================================
    縦置きのまま「表だけ」を 90 度回転してページいっぱいに配置するユーティリティ（90°固定）
    ===================================================================== */

.table-rotate {
  /* 配置ラッパ（子tableの絶対配置の基準） */
  display: block;
  position: relative;

  /* 専用ページ化 */
  break-before: page;
  break-after: page;
  break-inside: avoid;

  /* ページ領域いっぱい確保（@page の margin を除く） */
  block-size: 100%;
  min-block-size: 100%;
  overflow: visible;

  /* 既定の回転テーブル用パラメータ（スタイル属性で上書き可能） */
  --table-rotate-scale: 70%;
  --table-rotate-shift-y: +25%;

  /* ラッパのサイズ（暫定） */
  width: 100%;
  height: clamp(320px, calc(500px * var(--paper-scale)), 560px);
}

.table-rotate > table {
  position: absolute;
  top: 50%;
  left: 50%;
  transform-origin: center center;
  /* 回転、縮尺、シフトの適用 */
  transform: translate(-50%, var(--table-rotate-shift-y)) rotate(-90deg) scale(var(--table-rotate-scale));
  margin: 0;
  inline-size: max-content;
  max-inline-size: none;
  z-index: 0;
}
```