# codes/ — サンプルコードディレクトリ

書籍内で掲載するサンプルコードを配置するディレクトリです。

## 用途

原稿のコードブロックに直接コードを書く代わりに、外部ファイルとして管理できます。

```markdown
```include:sample.rb```

```include:sample.rb:10-20```
```

ファイルを外部管理することで、コードの動作確認やテストがしやすくなります。

## ディレクトリ構成例

```
codes/
  01-intro/
    hello.rb
  11-advanced/
    algorithm.rb
```

章ごとにサブディレクトリを作成して整理することもできます。サブディレクトリ内のファイルも `include` 記法でそのまま参照できます。

```markdown
```include:01-intro/hello.rb```
```include:01-intro/hello.rb:10-20```
```
