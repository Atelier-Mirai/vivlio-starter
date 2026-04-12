# frozen_string_literal: true

# ライブラリからフル CLI（ドメイン + Samovar + `CLI.start`）を読み込む正規エントリ。
# 実体は `cli/startup.rb`（起動）と `cli/loader.rb`（一括 require）に分割している。

require_relative 'cli/startup'
