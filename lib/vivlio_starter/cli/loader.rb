# frozen_string_literal: true

# CLI 全機能利用時の require 順（ドメイン → Samovar）を集約する。
# `cli/startup.rb` から読み込まれ、`cli.rb` は `startup` のみを参照する。

require_relative 'common'
require_relative 'masking'
require_relative 'image_filename_sanitizer'
require_relative 'guards'
require_relative 'create'
require_relative 'delete'
require_relative 'doctor'
require_relative 'entries'
require_relative 'new'
require_relative 'upgrade'
require_relative 'pdf'
require_relative 'post_process'
require_relative 'pre_process'
require_relative 'rename'
require_relative 'renumber'
require_relative 'lint'
require_relative 'metrics'
require_relative 'index'
require_relative 'import'

require_relative 'samovar'
