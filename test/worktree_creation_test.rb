# frozen_string_literal: true

require_relative "test_helper"

class WorktreeCreationTest < WorktreesTestCase
  def test_creates_styles_and_opens_a_new_worktree
    Dir.mktmpdir do |directory|
      primary = File.join(directory, "example_app")
      FileUtils.mkdir_p(primary)
      target = File.join(directory, "example_app-new-feature")
      command_executor = FakeCommandExecutor.new(
        repository: primary,
        porcelain: porcelain(primary:),
      )
      vscode_identity = FakeVsCodeIdentity.new
      output = StringIO.new
      app = Worktrees::WorktreesCli.new(
        directory: primary,
        input: StringIO.new("2\ndev/new-feature\n\ny\n"),
        output:,
        error: StringIO.new,
        command_executor:,
        vscode_identity:,
        environment: { "GUI_EDITOR" => "code --reuse-window" },
      )

      assert_equal 0, app.run
      assert_includes output.string, "Base [origin/main]: "
      assert_includes output.string, "Path: #{target}"
      assert_equal(
        [
          {
            command: [
              "git", "worktree", "add", "-b", "dev/new-feature",
              target, "origin/main",
            ],
            chdir: primary,
          },
          {
            command: ["code", "--reuse-window", target],
            chdir: target,
          },
        ],
        command_executor.runs,
      )
      assert_equal [target], vscode_identity.paths
    end
  end

  def test_stops_when_worktree_creation_fails
    Dir.mktmpdir do |directory|
      primary = File.join(directory, "example_app")
      FileUtils.mkdir_p(primary)
      command_executor = FakeCommandExecutor.new(
        repository: primary,
        porcelain: porcelain(primary:),
        execution_results: [false],
      )
      app = Worktrees::WorktreesCli.new(
        directory: primary,
        input: StringIO.new("2\ndev/broken\norigin/main\ny\n"),
        output: StringIO.new,
        error: StringIO.new,
        command_executor:,
        vscode_identity: FakeVsCodeIdentity.new,
        environment: { "GUI_EDITOR" => "code" },
      )

      assert_equal 1, app.run
      assert_equal 1, command_executor.runs.length
      assert_equal "git", command_executor.runs.first.fetch(:command).first
    end
  end

  def test_does_not_create_a_worktree_without_gui_editor
    primary = "/tmp/example_app"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(primary:),
    )
    vscode_identity = FakeVsCodeIdentity.new
    error = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("2\ndev/new-feature\n\ny\n"),
      output: StringIO.new,
      error:,
      command_executor:,
      vscode_identity:,
      environment: {},
    )

    assert_equal 1, app.run
    assert_equal "worktrees: GUI_EDITOR is not set\n", error.string
    assert_empty command_executor.runs
    assert_empty vscode_identity.paths
  end

  def test_stops_when_peacock_styling_fails
    Dir.mktmpdir do |directory|
      primary = File.join(directory, "example_app")
      FileUtils.mkdir_p(primary)
      command_executor = FakeCommandExecutor.new(
        repository: primary,
        porcelain: porcelain(primary:),
        execution_results: [true],
      )
      vscode_identity = FakeVsCodeIdentity.new(success: false)
      app = Worktrees::WorktreesCli.new(
        directory: primary,
        input: StringIO.new("2\ndev/unstyled\n\ny\n"),
        output: StringIO.new,
        error: StringIO.new,
        command_executor:,
        vscode_identity:,
        environment: { "GUI_EDITOR" => "code" },
      )

      assert_equal 1, app.run
      commands = command_executor.runs.map { |run| run.fetch(:command).first }
      assert_equal ["git"], commands
      assert_equal [File.join(directory, "example_app-unstyled")], vscode_identity.paths
    end
  end

  def test_refuses_an_empty_branch
    primary = "/tmp/example_app"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(primary:),
    )
    error = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("2\n\n"),
      output: StringIO.new,
      error:,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
    )

    assert_equal 1, app.run
    assert_includes error.string, "branch cannot be empty"
    assert_empty command_executor.runs
  end

  def test_refuses_to_create_main_as_a_linked_worktree
    primary = "/tmp/example_app"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(primary:),
    )
    error = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("2\nmain\n"),
      output: StringIO.new,
      error:,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
    )

    assert_equal 1, app.run
    assert_equal "worktrees: main belongs in the primary checkout\n", error.string
    assert_empty command_executor.runs
  end

  def test_refuses_an_existing_generated_path
    Dir.mktmpdir do |directory|
      primary = File.join(directory, "example_app")
      existing = File.join(directory, "example_app-taken")
      FileUtils.mkdir_p([primary, existing])
      command_executor = FakeCommandExecutor.new(
        repository: primary,
        porcelain: porcelain(primary:),
      )
      error = StringIO.new
      app = Worktrees::WorktreesCli.new(
        directory: primary,
        input: StringIO.new("2\ndev/taken\n\n"),
        output: StringIO.new,
        error:,
        command_executor:,
        vscode_identity: FakeVsCodeIdentity.new,
      )

      assert_equal 1, app.run
      assert_includes error.string, "target already exists: #{existing}"
      assert_empty command_executor.runs
    end
  end
end
