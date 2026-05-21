# frozen_string_literal: true

require 'samovar'

require_relative 'common'
require_relative '../scaffolder'

module VivlioStarter
  module CLI
    # Samovar で再構築する CLI コマンド群の名前空間
    module SamovarCommands
    end
  end
end

require_relative 'samovar/build_command'
require_relative 'samovar/clean_command'
require_relative 'samovar/delete_command'
require_relative 'samovar/doctor_command'
require_relative 'samovar/create_command'
require_relative 'samovar/new_command'
require_relative 'samovar/rename_command'
require_relative 'samovar/help_command'
require_relative 'samovar/pdf_command'
require_relative 'samovar/resize_command'
require_relative 'samovar/index_command'
require_relative 'samovar/open_command'
require_relative 'samovar/import_command'
require_relative 'samovar/cover_command'
require_relative 'samovar/lint_command'
require_relative 'samovar/metrics_command'
require_relative 'samovar/preflight_command'
require_relative 'samovar/root_command'
