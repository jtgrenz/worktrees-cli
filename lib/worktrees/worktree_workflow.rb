# frozen_string_literal: true

require "shellwords"

module Worktrees
  EditorError = Class.new(StandardError)

  class WorktreeWorkflow
    def initialize(command_executor:, vscode_identity:, gui_editor:)
      @command_executor = command_executor
      @vscode_identity = vscode_identity
      @gui_editor = gui_editor
    end

    def create_style_and_open(branch:, base:, primary_path:, target_path:)
      editor_command
      create(branch:, base:, primary_path:, target_path:)
      style(target_path)
      open_in_editor(target_path, chdir: target_path)
      0
    end

    def open_in_editor(path, chdir:)
      @command_executor.execute!(*editor_command, path, chdir:)
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

    def editor_command
      command = Shellwords.split(@gui_editor.to_s)
      raise EditorError, "GUI_EDITOR is not set" if command.empty?

      command
    rescue ArgumentError => error
      raise EditorError, "GUI_EDITOR is invalid: #{error.message}"
    end
  end
end
