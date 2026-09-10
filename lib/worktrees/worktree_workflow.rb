# frozen_string_literal: true

module Worktrees
  class WorktreeWorkflow
    def initialize(command_executor:, vscode_identity:)
      @command_executor = command_executor
      @vscode_identity = vscode_identity
    end

    def create_style_and_open(branch:, base:, primary_path:, target_path:)
      create(branch:, base:, primary_path:, target_path:)
      style(target_path)
      open_in_editor(target_path, chdir: target_path)
      0
    end

    def open_in_editor(path, chdir:)
      @command_executor.execute!(
        "zsh", "-ic", 'edit "$1"', "worktrees", path,
        chdir:,
      )
      0
    end

    def remove_registration(path, chdir:, force: false)
      command = ["git", "worktree", "remove"]
      command << "--force" if force
      @command_executor.execute!(*command, path, chdir:)
      0
    end

    private

    def create(branch:, base:, primary_path:, target_path:)
      @command_executor.execute!(
        "git", "worktree", "add", "-b", branch, target_path, base,
        chdir: primary_path,
      )
    end

    def style(target_path)
      @vscode_identity.apply(target_path)
    end
  end
end
