# 方針

1. content/以下にmarkdownファイルを配置する。vivliostyleではプロジェクトルート以下にファイルを置く必要がので、workspaceディレクトリは、削除する。
2. markdownファイルに、次の前処理を行い、プロジェクトルート以下にコピーする。
    1. ![](shogiban.png) -> ![](images/00-preface/shogiban.png)のように画像パスを付与する
    2. markdownの種類に応じたフロントマターを付与する
        - 00-preface.md, 98-postface.md の場合
            ---
            link:
            - rel: 'stylesheet'
                href: 'stylesheets/matter.css'
            lang: 'ja'
            ---
        - 01-toc.md の場合
            ---
            link:
            - rel: 'stylesheet'
                href: 'stylesheets/toc.css'
            lang: 'ja'
            ---
        - 11-chapter1.md, 12-chapter2.md, ... の場合
            ---
            link:
            - rel: 'stylesheet'
                href: 'stylesheets/body.css'
            - rel: 'stylesheet'
                href: 'stylesheets/11.css'
            lang: 'ja'
            ---
        - 91-appendix-a.md, 92-appendix-b.md, ... の場合
            ---
            link:
            - rel: 'stylesheet'
                href: 'stylesheets/appendix.css'
            lang: 'ja'
            ---
        - 99-colophone.md の場合
            ---
            link:
            - rel: 'stylesheet'
                href: 'stylesheets/colophon.css'
            lang: 'ja'
            ---
3. vfmコマンドを用いて、markdownファイルをHTMLファイルに変換する
4. 変換したhtmlファイルを、_postReplaceList.jsonに基づき、置換する
5. (もし全ファイルのPDFを生成するならば)toc.htmlを生成する。
6. entries.js を自動生成する。
7. vivliostyle build で、pdfを生成する
8. 生成した pdf以外のファイルを削除して、cleanup する。

# コマンド

## プロジェクト初期化用
rake init

## 前処理用
rake preprocess

## 指定ファイルの前処理用
rake preprocess 00-preface
rake preprocess 11-gift 12-source 13-unit

## markdownファイルの変換用 (_postReplaceList.jsonに基づく置換処理も含む)
rake convert

## 指定ファイルの変換用
rake convert 00-preface
rake convert 11-gift 12-source 13-unit

## toc.html生成用
rake toc

## entries.js生成用
rake entries

## 全ファイルビルド用 (PDF生成)
rake build

## 指定ファイルビルド用 (PDF生成)
rake build 00-preface
rake build 11-gift 12-source 13-unit

## imageディレクトリ生成用
rake images

## 不要ファイルの削除用
rake clean