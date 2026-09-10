# frozen_string_literal: true

require_relative "test_helper"
require "json"

class VsCodeIdentityTest < WorktreesTestCase
  def test_style_command_preserves_repo_color_and_existing_worktree_settings
    Dir.mktmpdir do |directory|
      primary = create_repository(File.join(directory, "zenpayroll"))
      target = File.join(directory, "zenpayroll-feature")
      primary_settings = File.join(primary, ".vscode", "settings.json")
      worktree_settings = File.join(target, ".vscode", "settings.json")
      FileUtils.mkdir_p(File.dirname(primary_settings))
      File.write(primary_settings, JSON.generate("peacock.color" => "#123456"))
      git(primary, "worktree", "add", "-b", "feature", target)
      FileUtils.mkdir_p(File.dirname(worktree_settings))
      File.write(
        worktree_settings,
        JSON.generate(
          "editor.formatOnSave" => true,
          "peacock.excludedSettings" => ["statusBar.background"],
          "workbench.colorCustomizations" => { "editor.background" => "#000000" },
        ),
      )

      stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "style", target)

      assert status.success?, stderr
      assert_equal "", stderr
      assert_includes stdout, "Configured VS Code identity for ZP worktree"
      settings = JSON.parse(File.read(worktree_settings))
      assert_equal true, settings.fetch("editor.formatOnSave")
      assert_equal "#123456", settings.fetch("peacock.color")
      assert_equal false, settings.fetch("peacock.affectTitleBar")
      assert_equal true, settings.fetch("peacock.affectActivityBar")
      assert_equal true, settings.fetch("peacock.affectStatusBar")
      assert_equal(
        "${activeRepositoryBranchName}${separator}WT",
        settings.fetch("window.title"),
      )
      colors = settings.fetch("workbench.colorCustomizations")
      assert_equal "#000000", colors.fetch("editor.background")
      assert_equal "#b45309", colors.fetch("titleBar.activeBackground")
      assert_includes(
        settings.fetch("peacock.excludedSettings"),
        "titleBar.activeBackground",
      )
      assert_includes(
        settings.fetch("peacock.excludedSettings"),
        "statusBar.background",
      )
    end
  end

  def test_style_command_defaults_to_the_current_worktree
    Dir.mktmpdir do |directory|
      primary = create_repository(File.join(directory, "payroll_building_blocks"))
      target = File.join(directory, "pbb-feature")
      git(primary, "worktree", "add", "-b", "feature", target)

      _stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "style", chdir: target)

      assert status.success?, stderr
      settings = JSON.parse(
        File.read(File.join(target, ".vscode", "settings.json")),
      )
      assert_equal "#0b132b", settings.fetch("peacock.color")
      assert_equal(
        "${activeRepositoryBranchName}${separator}WT",
        settings.fetch("window.title"),
      )
    end
  end

  def test_style_command_is_a_no_op_in_the_primary_checkout
    Dir.mktmpdir do |directory|
      primary = create_repository(File.join(directory, "zenpayroll"))

      stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "style", primary)

      assert status.success?, stderr
      assert_equal "", stdout
      refute_path_exists File.join(primary, ".vscode", "settings.json")
    end
  end

  def test_style_command_does_not_overwrite_malformed_worktree_settings
    Dir.mktmpdir do |directory|
      primary = create_repository(File.join(directory, "zenpayroll"))
      target = File.join(directory, "zenpayroll-feature")
      settings_path = File.join(target, ".vscode", "settings.json")
      git(primary, "worktree", "add", "-b", "feature", target)
      FileUtils.mkdir_p(File.dirname(settings_path))
      malformed_settings = "{\n  this is not valid JSON\n}\n"
      File.write(settings_path, malformed_settings)

      stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "style", target)

      assert status.success?, stderr
      assert_equal "", stdout
      assert_includes stderr, "Skipping "
      assert_includes stderr, "/zenpayroll-feature/.vscode/settings.json"
      assert_equal malformed_settings, File.read(settings_path)
    end
  end
end
