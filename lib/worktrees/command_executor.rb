# frozen_string_literal: true

require "open3"

module Worktrees
  CommandFailed = Class.new(StandardError)
  CommandResult = Data.define(:stdout, :stderr, :status) do
    def success?
      status.success?
    end
  end

  class CommandExecutor
    def capture(*command, chdir:)
      stdout, stderr, status = Open3.capture3(*command, chdir:)
      CommandResult.new(stdout:, stderr:, status:)
    end

    def execute!(*command, chdir:)
      return true if system(*command, chdir:)

      raise CommandFailed
    end
  end
end
