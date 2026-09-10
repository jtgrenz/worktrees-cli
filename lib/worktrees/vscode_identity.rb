# frozen_string_literal: true

require "fileutils"
require "json"
require "tempfile"

module Worktrees
  class VsCodeIdentity
    REPOSITORIES = {
      "zenpayroll" => { label: "ZP", color: "#2e3920" },
      "payroll_building_blocks" => { label: "PBB", color: "#0b132b" },
      "payroll_cms" => { label: "CMS", color: "#49335b" },
    }.freeze

    TITLE_COLORS = {
      "titleBar.activeBackground" => "#b45309",
      "titleBar.activeForeground" => "#ffffff",
      "titleBar.inactiveBackground" => "#78350f",
      "titleBar.inactiveForeground" => "#ffffff",
    }.freeze

    def initialize(command_executor:, output: $stdout, error: $stderr)
      @command_executor = command_executor
      @output = output
      @error = error
    end

    def apply(path)
      git_directory = git_path("--git-dir", path:)
      common_directory = git_path("--git-common-dir", path:)
      return false unless linked_worktree?(git_directory, common_directory)

      worktree_root = git_path("--show-toplevel", path:)
      return false unless worktree_root

      repository = REPOSITORIES[File.basename(File.dirname(common_directory))]
      return false unless repository

      settings_path = File.join(worktree_root, ".vscode", "settings.json")
      settings = read_worktree_settings(settings_path)
      return false unless settings

      excluded_settings =
        Array(settings["peacock.excludedSettings"]) | TITLE_COLORS.keys
      settings.merge!(identity_settings(repository, common_directory:))
      settings["peacock.excludedSettings"] = excluded_settings
      settings["workbench.colorCustomizations"] =
        Hash(settings["workbench.colorCustomizations"]).merge(TITLE_COLORS)
      write_settings(settings_path, settings)
      @output.puts(
        "Configured VS Code identity for #{repository.fetch(:label)} " \
        "worktree: #{worktree_root}",
      )
      true
    end

    private

    def git_path(argument, path:)
      result = @command_executor.capture(
        "git", "rev-parse", "--path-format=absolute", argument,
        chdir: path,
      )
      result.stdout.strip if result.success?
    end

    def linked_worktree?(git_directory, common_directory)
      git_directory && common_directory && git_directory != common_directory
    end

    def identity_settings(repository, common_directory:)
      {
        "peacock.color" => primary_peacock_color(
          common_directory:,
          fallback: repository.fetch(:color),
        ),
        "peacock.affectTitleBar" => false,
        "peacock.affectActivityBar" => true,
        "peacock.affectStatusBar" => true,
        "window.title" => "${activeRepositoryBranchName}${separator}WT",
      }
    end

    def primary_peacock_color(common_directory:, fallback:)
      settings_path = File.join(
        File.dirname(common_directory), ".vscode", "settings.json",
      )
      return fallback unless File.exist?(settings_path)

      color = JSON.parse(File.read(settings_path))["peacock.color"]
      color.is_a?(String) && !color.empty? ? color : fallback
    rescue JSON::ParserError
      fallback
    end

    def read_worktree_settings(settings_path)
      return {} unless File.exist?(settings_path)

      JSON.parse(File.read(settings_path))
    rescue JSON::ParserError => error
      @error.puts "Skipping #{settings_path}: #{error.message}"
      nil
    end

    def write_settings(settings_path, settings)
      FileUtils.mkdir_p(File.dirname(settings_path))
      Tempfile.create(["settings", ".json"], File.dirname(settings_path)) do |temporary|
        temporary.write(JSON.pretty_generate(settings) + "\n")
        temporary.close
        File.rename(temporary.path, settings_path)
      end
    end
  end
end
