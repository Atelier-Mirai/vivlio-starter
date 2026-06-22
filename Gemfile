# frozen_string_literal: true

source 'https://rubygems.org'

# Dependencies are defined in the gemspec to keep a single source of truth.
gemspec

# query-stream は公開済みバージョンを使用
gem 'query-stream', '~> 1.2.2'

# vivlio-starter-pdf（AGPL の Enhanced プラグイン）は rubygems.org で公開済み（>= 1.1.1）。
# MIT 本体の bundle へ AGPL を取り込まないため Gemfile には含めず、`gem install vivlio-starter-pdf`
# 済みなら provider.rb が自動検出して Enhanced モードに切り替える。
# プラグイン本体をローカル開発する場合のみ、次行を有効化する:
# gem 'vivlio-starter-pdf', path: '../vivlio-starter-pdf'
