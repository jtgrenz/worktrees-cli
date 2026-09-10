# frozen_string_literal: true

module Worktrees
  END_OF_INPUT = Object.new.freeze
end

require_relative "worktrees/worktree"
require_relative "worktrees/colorizer"
require_relative "worktrees/command_executor"
require_relative "worktrees/worktree_workflow"
require_relative "worktrees/worktree_creation_prompt"
require_relative "worktrees/terminal"
require_relative "worktrees/cli"
