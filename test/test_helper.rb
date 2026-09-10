# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "stringio"
require "tmpdir"

require_relative "../lib/worktrees"

class WorktreesTestCase < Minitest::Test
  SCRIPT = File.expand_path("../worktrees", __dir__)

  class FakeStatus
    def initialize(success)
      @success = success
    end

    def success?
      @success
    end
  end

  class FakeCommandExecutor
    attr_reader :captures, :runs

    def initialize(
      repository:,
      porcelain:,
      merged_heads: [],
      github_merged_branches: [],
      dirty_paths: [],
      execution_results: []
    )
      @repository = repository
      @porcelain_results = porcelain.is_a?(Array) ? porcelain.dup : [porcelain]
      @merged_heads = merged_heads
      @github_merged_branches = github_merged_branches
      @dirty_paths = dirty_paths
      @execution_results = execution_results.dup
      @captures = []
      @runs = []
    end

    def capture(*command, chdir:)
      @captures << { command:, chdir: }
      case command
      when ["git", "rev-parse", "--show-toplevel"]
        result("#{@repository}\n")
      when ["git", "worktree", "list", "--porcelain"]
        porcelain = @porcelain_results.length > 1 ? @porcelain_results.shift : @porcelain_results.first
        result(porcelain)
      when ["git", "remote", "get-url", "origin"]
        result("git@github.com:example/example_app.git\n")
      when ["git", "branch", "--format=%(refname:short)", "--merged", "origin/main"]
        result("")
      else
        return result(@dirty_paths.include?(chdir) ? "?? scratch.txt\n" : "") if status_check?(command)
        return result("", success: @merged_heads.include?(command[3])) if merge_check?(command)
        return github_merge_result(command) if github_merge_check?(command)

        raise "Unexpected capture: #{command.inspect} in #{chdir}"
      end
    end

    def execute!(*command, chdir:)
      @runs << { command:, chdir: }
      succeeded = @execution_results.empty? ? true : @execution_results.shift
      raise Worktrees::CommandFailed unless succeeded

      true
    end

    private

    def merge_check?(command)
      command.first(3) == ["git", "merge-base", "--is-ancestor"] && command.last == "origin/main"
    end

    def status_check?(command)
      command == ["git", "status", "--porcelain=v1", "--untracked-files=normal"]
    end

    def github_merge_check?(command)
      command.first(4) == ["gh", "api", "graphql", "-f"] && command.length == 5
    end

    def github_merge_result(command)
      branches = command.last.scan(/(branch\d+): pullRequests\([^)]*headRefName: "([^"]+)"/)
      repository = branches.to_h do |name, branch|
        nodes = @github_merged_branches.include?(branch) ? [{ "number" => 1 }] : []
        [name, { "nodes" => nodes }]
      end
      result(JSON.generate("data" => { "repository" => repository }))
    end

    def result(stdout, success: true)
      Worktrees::CommandResult.new(
        stdout:,
        stderr: "",
        status: FakeStatus.new(success),
      )
    end
  end

  class FakeVsCodeIdentity
    attr_reader :paths

    def initialize(success: true)
      @success = success
      @paths = []
    end

    def apply(path)
      @paths << path
      raise Worktrees::CommandFailed unless @success

      true
    end
  end

  private

  def create_repository(path)
    FileUtils.mkdir_p(path)
    git(path, "init", "--initial-branch=main")
    git(path, "config", "user.email", "test@example.com")
    git(path, "config", "user.name", "Test User")
    File.write(File.join(path, "README.md"), "test\n")
    git(path, "add", "README.md")
    git(path, "commit", "-m", "initial")
    path
  end

  def git(path, *arguments)
    _stdout, stderr, status = Open3.capture3("git", *arguments, chdir: path)
    assert status.success?, stderr
  end

  def porcelain(primary:, selected: nil, selected_prunable: false)
    records = <<~PORCELAIN
      worktree #{primary}
      HEAD abc123
      branch refs/heads/main
    PORCELAIN
    return records unless selected

    selected_record = records + <<~PORCELAIN

      worktree #{selected}
      HEAD def456
      branch refs/heads/dev/feature
    PORCELAIN
    return selected_record unless selected_prunable

    selected_record + "prunable gitdir file points to non-existent location\n"
  end
end
