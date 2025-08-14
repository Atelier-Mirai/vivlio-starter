# frozen_string_literal: true
#
# Gemfile — 本プロジェクトで使用するRubyGemsを定義します。
# kramdown を導入して、pre_process 内で Markdown → HTML 変換に利用します。
#
# 使い方:
#   $ bundle install        # 依存関係をインストール
#   $ bundle exec rake ...  # Rakeタスクを実行

source "https://rubygems.org"

# Markdownパーサ（純Ruby・Jekyll実績あり）
# 2.4系を想定。必要に応じてバージョンは調整してください。
# NOTE: GFM準拠を厳密にしたい場合は `kramdown-parser-gfm` の追加も検討。

gem "kramdown", "~> 2.4"
gem "nokogiri", "~> 1.16"

# （任意）RakeをBundler管理したい場合は以下を有効化
# gem "rake", "~> 13.2"
