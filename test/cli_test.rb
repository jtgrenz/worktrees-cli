# frozen_string_literal: true

require_relative "test_helper"

class CliTest < WorktreesTestCase
  def test_errors_outside_a_git_repository
    Dir.mktmpdir do |directory|
      stdout, stderr, status = Open3.capture3("ruby", SCRIPT, chdir: directory)

      assert_equal "", stdout
      assert_equal "worktrees: not inside a Git repository\n", stderr
      assert_equal 1, status.exitstatus
    end
  end

  def test_lists_the_current_repository_and_all_menu_actions
    Dir.mktmpdir do |directory|
      repository = create_repository(File.join(directory, "repo with spaces"))
      stdout, stderr, status = Open3.capture3(
        "ruby", SCRIPT,
        stdin_data: "3\n",
        chdir: repository,
      )

      assert status.success?, stderr
      assert_equal "", stderr
      assert_includes stdout, "#    WORKTREE"
      assert_includes stdout, "1  * repo with spaces  main"
      assert_includes stdout, repository
      assert_includes stdout, "2  New worktree"
      assert_includes stdout, "3  Cancel"
    end
  end

  def test_regular_list_aligns_only_worktree_branch_and_path_columns_without_scanning_status
    primary = "/tmp/repo"
    selected = "/tmp/much-longer-worktree"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      merged_heads: ["def456"],
      porcelain: <<~PORCELAIN,
        worktree #{primary}
        HEAD abc123
        branch refs/heads/main

        worktree #{selected}
        HEAD def456
        branch refs/heads/dev/feature-with-long-name
      PORCELAIN
    )
    output = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("4\n"),
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
    )

    assert_equal 0, app.run
    header, primary_row, selected_row = output.string.lines(chomp: true)
    worktree_column = header.index("WORKTREE")
    branch_column = header.index("BRANCH")
    path_column = header.index("PATH")

    assert_equal worktree_column, primary_row.index("repo")
    assert_equal worktree_column, selected_row.index("much-longer-worktree")
    assert_equal branch_column, primary_row.index("main")
    assert_equal branch_column, selected_row.index("dev/feature-with-long-name")
    assert_equal path_column, primary_row.index(primary)
    assert_equal path_column, selected_row.index(selected)
    refute_includes header, "AGE"
    refute_includes header, "STATUS"
    refute(command_executor.captures.any? { |capture| capture.fetch(:command).include?("merge-base") })
    refute(command_executor.captures.any? { |capture| capture.fetch(:command).include?("status") })
  end

  def test_prune_list_includes_every_non_primary_worktree_with_status
    primary = "/tmp/zenpayroll"
    secondary_main = "/tmp/zenpayroll main"
    merged = "/tmp/zenpayroll merged"
    dirty = "/tmp/zenpayroll dirty"
    active = "/tmp/zenpayroll active"
    stale = "/tmp/zenpayroll stale"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: <<~PORCELAIN,
        worktree #{primary}
        HEAD abc123
        branch refs/heads/dev/primary-feature

        worktree #{secondary_main}
        HEAD mno345
        branch refs/heads/main

        worktree #{merged}
        HEAD def456
        branch refs/heads/dev/merged-feature

        worktree #{dirty}
        HEAD ghi789
        branch refs/heads/dev/dirty-feature

        worktree #{active}
        HEAD jkl012
        branch refs/heads/dev/active-feature

        worktree #{stale}
        HEAD pqr678
        branch refs/heads/dev/stale-feature
        prunable gitdir file points to non-existent location
      PORCELAIN
      merged_heads: ["def456", "ghi789"],
      dirty_paths: [dirty],
    )
    output = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("6\n"),
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
    )

    assert_equal 0, app.run
    header, main_row, merged_row, dirty_row, active_row, stale_row = output.string.lines(chomp: true)
    status_column = header.index("STATUS")

    assert_includes header, "AGE"
    assert_equal "clean", main_row[status_column, "clean".length]
    assert_equal "merged", merged_row[status_column, "merged".length]
    assert_equal "dirty", dirty_row[status_column, "dirty".length]
    assert_equal "clean", active_row[status_column, "clean".length]
    assert_equal "stale", stale_row[status_column, "stale".length]
    refute_includes output.string, "dev/primary-feature"
    refute_includes output.string, "New worktree"
  end

  def test_regular_list_warns_when_a_secondary_worktree_owns_main
    primary = "/tmp/payroll_building_blocks"
    secondary_main = "/tmp/payroll_building_blocks-name-apostrophes"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: <<~PORCELAIN,
        worktree #{primary}
        HEAD abc123
        branch refs/heads/dev/feature

        worktree #{secondary_main}
        HEAD def456
        branch refs/heads/main
      PORCELAIN
    )
    error = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("4\n"),
      output: StringIO.new,
      error:,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
    )

    assert_equal 0, app.run
    assert_equal(
      "worktrees: warning: main is checked out in secondary worktree #{secondary_main}\n",
      error.string,
    )
  end

  def test_prune_list_includes_a_clean_github_squash_merge
    primary = "/tmp/zenpayroll"
    soap_work = "/tmp/zenpayroll-pr-366505"
    branch = "dev/nys-45/soap-work"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: <<~PORCELAIN,
        worktree #{primary}
        HEAD abc123
        branch refs/heads/main

        worktree #{soap_work}
        HEAD def456
        branch refs/heads/#{branch}
      PORCELAIN
      github_merged_branches: [branch],
    )
    output = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("2\n"),
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
    )

    assert_equal 0, app.run
    assert_includes output.string, branch
    assert_includes output.string, "merged"
    assert_equal(
      1,
      command_executor.captures.count { |capture| capture.fetch(:command).first(3) == ["gh", "api", "graphql"] },
    )
  end

  def test_abbreviates_home_in_menu_without_changing_selected_worktree_path
    primary = File.join(Dir.home, "src/zenpayroll")
    selected = File.join(Dir.home, "src/zenpayroll feature")
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(primary:, selected:),
    )
    output = StringIO.new
    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("2\n"),
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
    )

    assert_equal 0, app.run
    assert_includes output.string, "~/src/zenpayroll"
    refute_includes output.string, Dir.home
    assert_equal(
      [
        {
          command: ["zsh", "-ic", 'edit "$1"', "worktrees", selected],
          chdir: primary,
        },
      ],
      command_executor.runs,
    )
  end

  def test_arrow_keys_select_a_worktree_in_an_interactive_terminal
    primary = "/tmp/zenpayroll"
    selected = "/tmp/zenpayroll feature"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(primary:, selected:),
    )
    keys = [:down, :enter]

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new,
      output: StringIO.new,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      interactive: true,
      read_key: -> { keys.shift },
    )

    assert_equal 0, app.run
    assert_equal selected, command_executor.runs.first.fetch(:command).last
  rescue ArgumentError => error
    flunk "interactive selection is unavailable: #{error.message}"
  end

  def test_interactive_menu_redraws_wrapped_rows_without_appending
    output = StringIO.new
    keys = [:down, :cancel]
    menu = Worktrees::InteractiveMenu.new(
      output:,
      read_key: -> { keys.shift },
      colorizer: Worktrees::Colorizer.new(enabled: false),
      header: "#    WORKTREE  BRANCH  PATH",
    )
    choices = [
      ["1  #{"long worktree row " * 12}", :worktree],
      ["2  Cancel", :cancel],
    ]

    assert_equal :cancel, menu.choose(choices)
    assert_equal 1, output.string.scan("\e[?1049h").length
    assert_equal 2, output.string.scan("\e[H\e[2J").length
    assert_equal 2, output.string.scan("#    WORKTREE  BRANCH  PATH").length
    assert_equal 1, output.string.scan("\e[?1049l").length
    refute_includes output.string, "\e[s"
    refute_includes output.string, "\e[u"
  end

  def test_prune_selection_removes_a_stale_registration_and_refreshes
    primary = "/tmp/zenpayroll"
    stale = "/tmp/zenpayroll stale"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: [
        porcelain(primary:, selected: stale, selected_prunable: true),
        porcelain(primary:, selected: stale, selected_prunable: true),
        porcelain(primary:),
      ],
    )
    keys = [:enter]

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("y\n"),
      output: StringIO.new,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { keys.shift },
    )

    assert_equal 0, app.run
    assert_equal(
      {
        command: ["git", "worktree", "remove", stale],
        chdir: primary,
      },
      command_executor.runs.first,
    )
  rescue ArgumentError => error
    flunk "prunable deletion is unavailable: #{error.message}"
  end

  def test_pruning_the_current_worktree_refreshes_from_the_primary_checkout
    primary = "/tmp/zenpayroll"
    current = "/tmp/zenpayroll feature"
    registered = porcelain(primary:, selected: current)
    command_executor = FakeCommandExecutor.new(
      repository: current,
      porcelain: [registered, registered, porcelain(primary:)],
    )

    app = Worktrees::WorktreesCli.new(
      directory: current,
      input: StringIO.new("y\n"),
      output: StringIO.new,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { :enter },
    )

    assert_equal 0, app.run
    assert_equal primary, command_executor.runs.first.fetch(:chdir)
    worktree_lists = command_executor.captures.select do |capture|
      capture.fetch(:command) == ["git", "worktree", "list", "--porcelain"]
    end
    assert_equal(
      [current, primary, primary],
      worktree_lists.map { |capture| capture.fetch(:chdir) },
    )
  end

  def test_interactive_prune_menu_colours_stale_status_red
    primary = "/tmp/zenpayroll"
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: porcelain(
        primary:,
        selected: "/tmp/zenpayroll stale",
        selected_prunable: true,
      ),
    )
    output = StringIO.new

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new,
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { :cancel },
      environment: {},
    )

    assert_equal 0, app.run
    assert_includes output.string, "\e[31mstale\e[0m"
  end

  def test_confirming_a_dirty_worktree_force_removes_it
    primary = "/tmp/zenpayroll"
    dirty = "/tmp/zenpayroll dirty"
    registered = porcelain(primary:, selected: dirty)
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: [registered, registered, porcelain(primary:)],
      merged_heads: ["def456"],
      dirty_paths: [dirty],
    )
    keys = [:enter]

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("y\n"),
      output: StringIO.new,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { keys.shift },
    )

    assert_equal 0, app.run
    assert_equal(
      {
        command: ["git", "worktree", "remove", "--force", dirty],
        chdir: primary,
      },
      command_executor.runs.first,
    )
  end

  def test_confirming_clean_secondary_main_removes_it_without_force
    primary = "/tmp/payroll_building_blocks"
    secondary_main = "/tmp/payroll_building_blocks-name-apostrophes"
    registered = <<~PORCELAIN
      worktree #{primary}
      HEAD abc123
      branch refs/heads/dev/feature

      worktree #{secondary_main}
      HEAD def456
      branch refs/heads/main
    PORCELAIN
    primary_only = <<~PORCELAIN
      worktree #{primary}
      HEAD abc123
      branch refs/heads/dev/feature
    PORCELAIN
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: [registered, registered, primary_only],
    )

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("y\n"),
      output: StringIO.new,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { :enter },
    )

    assert_equal 0, app.run
    assert_equal(
      {
        command: ["git", "worktree", "remove", secondary_main],
        chdir: primary,
      },
      command_executor.runs.first,
    )
  end

  def test_prune_rechecks_status_before_confirming_removal
    primary = "/tmp/zenpayroll"
    selected = "/tmp/zenpayroll changed"
    merged = porcelain(primary:, selected:).sub("HEAD def456", "HEAD merged123")
    no_longer_merged = merged.sub("HEAD merged123", "HEAD active456")
    command_executor = FakeCommandExecutor.new(
      repository: primary,
      porcelain: [merged, no_longer_merged, porcelain(primary:)],
      merged_heads: ["merged123"],
    )
    output = StringIO.new

    app = Worktrees::WorktreesCli.new(
      directory: primary,
      input: StringIO.new("y\n"),
      output:,
      error: StringIO.new,
      command_executor:,
      vscode_identity: FakeVsCodeIdentity.new,
      arguments: ["--prune"],
      interactive: true,
      read_key: -> { :enter },
    )

    assert_equal 0, app.run
    assert_includes output.string, "Remove clean worktree #{selected}? [y/N]: "
    assert_equal ["git", "worktree", "remove", selected], command_executor.runs.first.fetch(:command)
  end
end
