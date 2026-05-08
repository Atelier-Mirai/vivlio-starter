# frontispiece / ornament の設定に関する仕様書

## yamlの設定例
```yaml:book.yml
theme:
  style: image
  frontispiece: basename
    image: 
  ornament: basename
```

- basename: 画像の主ファイル名

## 1. 🔍 画像ファイルの配置と検索順序

| 種類 | 配置先ディレクトリ | 役割 |
| :--- | :--- | :--- |
| **ユーザー提供画像** | `stylesheets/images/` | 利用者が個別に用意・上書きする画像。 |
| **バンドル画像** | `stylesheets/images/bundled/` | Gemが事前に提供しているデフォルト画像。 |

---

### 検索順序

1.  **第一検索 (優先):** `stylesheets/images/` の下で検索します。（ユーザー提供画像を優先）
2.  **第二検索:** 第一検索で見つからなかった場合、`stylesheets/images/bundled/` の下で検索します。（バンドル画像を検索）

---

## 2. 🏞️ `frontispiece` (縦向き：`portrait`) 画像決定ロジック

設定で `frontispiece` が指定された場合の処理フローです。

### 2.1. ユーザー指定ファイル名による検索（例: `image: sl_portrait`）

画像ファイル名_`portrait`の形式で指定された場合: 

| ステップ | 処理内容 | 検索パス | 処理後の動作 |
| :--- | :--- | :--- | :--- |
| **1-A.** | **ユーザー提供画像**を検索。 | `stylesheets/images/sl_portrait.png/jpg/webp` | 見つかった場合、**そのまま** `frontispiece` として使用し、**終了**。 |
| **1-B.** | **バンドル画像**を検索。 | `stylesheets/images/bundled/sl_portrait.png/jpg/webp` | 見つかった場合、**そのまま** `frontispiece` として使用し、**終了**。 |
| **1-C.** | **いずれも見つからなかった場合**、次のセクション (2.2) に進む。 | - | - |

> 📌 **注意:** ステップ 1-A、1-B で画像が見つかった場合、アスペクト比の確認や `generate_frontispiece_and_ornament_from` の起動は行いません。
> 画像ファイル名の確認には、`image_exists_for?(normalized_path)`メソッドを用いると便利です。

---

### 2.2. 画像名による検索・処理（例: `image: sl`）

画像ファイル名_`portrait`の形式ではなく、画像ファイル名のみ指定されている場合: 

ステップ 2.1 で画像が見つからなかった場合、次の処理を行ないます。

#### 2.2.1. ベース画像検索とアスペクト比確認

| ステップ | 処理内容 | 検索パス | 処理後の動作 |
| :--- | :--- | :--- | :--- |
| **2-A.** | **ユーザー提供画像**を検索。 | `stylesheets/images/sl.png/jpg/webp` | **見つかった場合**、次のアスペクト比確認に進む。 |
| **2-B.** | **アスペクト比確認**: 見つかった画像の縦横比が **$4:3 \pm 10\%$** または **$1.414:1 \pm 10\%$** の範囲内か確認する。 | - | **範囲内**の場合、そのまま `frontispiece` として使用し、**終了**。 |
| **2-C.** | **アスペクト比不適合**: 範囲外の場合。 | - | `generate_frontispiece_and_ornament_from` を起動し、`sl_portrait.webp` を生成。生成した画像を `frontispiece` として使用し、**終了**。（※Linux/Windows環境での `waifu2x` 非搭載時は高解像度化は行なわず、低解像度画像のまま使用する） |
| **2-D.** | **見つからなかった場合**、次のセクション (2.2.2) に進む。 | - | - |

#### 2.2.2. 代替 WebP 候補の検索とフレーム生成

ユーザー画像提供ディレクトリに`画像名`形式のファイルが見つからなかった場合、次の処理を行ないます。

| ステップ | 処理内容 | 検索パス | 処理後の動作 |
| :--- | :--- | :--- | :--- |
| **3-A.** | **バンドル WebP 候補A** を検索。 | `stylesheets/images/bundled/sl.webp` | **見つかった場合**、次の処理に進む。 |
| **3-B.** | **フレーム生成 (A)**: `generate_frontispiece_and_ornament_from` を起動し、`sl_portrait.webp` を生成。生成した画像を `frontispiece` として使用し、**終了**。 | - | - |

#### 2.2.3. 最終的な画像無しエラー処理

| ステップ | 処理内容 | 検索パス | 処理後の動作 |
| :--- | :--- | :--- | :--- |
| **4-A.** | 上記全てのステップで画像が見つからなかった場合。 | - | - |
| **4-B.** | テンプレートファイル `images/no_frontispiece.svg` を読み込む。 | - | - |
| **4-C.** | SVG内の文字列を「**sl.webp No Image**」に編集する。 | - | - |
| **4-D.** | 編集後のSVGを `frontispiece` として使用し、**終了**。 | - | **決定** |

**4-C.**で用いる、SVG内の文字列の編集処理は、`placeholder_image_path`メソッドなどを用いると便利です。


---

## 3. 🖼️ `ornament` (横向き：`landscape` 想定) 画像決定ロジック

設定で `ornament: sl` が指定された場合の処理フローです。

1.  **第一検索 (ユーザー提供):** `stylesheets/images/` の下で、`sl.png/jpg/webp` を検索する。
2.  **第二検索 (バンドル):** 1で見つからなかった場合、`stylesheets/images/bundled/` の下で、`sl.png/jpg/webp` を検索する。
3.  **画像決定:** 1または2で見つかった場合、その画像を `ornament` として使用し、**終了**する。
4.  **代替処理:** 1および2で見つからなかった場合、`frontispiece` のステップ **2.2.1.（アスペクト比確認）以降**のロジックに**準じて**処理を続行する。