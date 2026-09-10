# frozen_string_literal: true

require "json"

module Worktrees
  PruneCandidate = Data.define(:worktree, :status)

  class WorktreesCli
    def initialize(
      directory: Dir.pwd,
      input: $stdin,
      output: $stdout,
      error: $stderr,
      command_executor: CommandExecutor.new,
      vscode_identity: nil,
      arguments: [],
      now: Time.now,
      interactive: nil,
      read_key: nil,
      environment: ENV
    )
      @directory = directory
      @input = input
      @output = output
      @error = error
      @command_executor = command_executor
      @vscode_identity = vscode_identity
      @workflow = nil
      @creation_prompt = WorktreeCreationPrompt.new(input:, output:, error:)
      @arguments = arguments
      @now = now
      @interactive = interactive.nil? ? input.tty? && output.tty? : interactive
      @read_key = read_key || TerminalKeyReader.new(input).method(:read)
      @colorizer = Colorizer.new(enabled: @interactive && !environment.key?("NO_COLOR"))
    end

    def run
      return run_style_command if @arguments.first == "style"
      return run_prune if @arguments.first == "--prune"

      run_browser
    rescue CommandFailed
      1
    rescue Interrupt
      @output.puts
      130
    end

    private

    def run_browser
      current_path = repository_path
      records = registered_worktrees
      warn_if_main_is_secondary(records)
      act_on(choose_browser(records, current_path:), records:, current_path:)
    end

    def run_prune
      repository_path
      records = registered_worktrees
      @directory = records.first.path
      loop do
        candidates = prune_candidates(records)
        if candidates.empty?
          @output.puts "No secondary worktrees."
          return 0
        end

        result = act_on(choose_prune_candidate(candidates), records: [], current_path: @directory)
        return result unless result == :refresh

        records = registered_worktrees
      end
    end

    def run_style_command
      vscode_identity.apply(@arguments[1] || @directory)
      0
    end

    def repository_path
      result = @command_executor.capture(
        "git", "rev-parse", "--show-toplevel", chdir: @directory,
      )
      raise CommandFailed unless result.success?

      result.stdout.strip
    rescue CommandFailed
      report_outside_repository
      raise
    end

    def registered_worktrees
      result = @command_executor.capture(
        "git", "worktree", "list", "--porcelain", chdir: @directory,
      )
      return Worktrees.parse_porcelain(result.stdout) if result.success?

      report_command_failure(result)
      raise CommandFailed
    end

    def worktree_statuses(records)
      local_merges = locally_merged_statuses(records)
      github_candidates = records.select do |record|
        merge_checkable?(record) && !local_merges.fetch(record.path, false)
      end
      github_merges = github_merged_branches(github_candidates)

      records.map do |record|
        merged = local_merges.fetch(record.path, false) || github_merges.include?(record.branch)
        Thread.new { [record.path, worktree_status(record, merged:)] }
      end.map(&:value).to_h
    end

    def prune_candidates(records)
      secondary_records = records.drop(1)
      statuses = worktree_statuses(secondary_records)
      secondary_records.map do |record|
        PruneCandidate.new(worktree: record, status: statuses.fetch(record.path))
      end
    end

    def worktree_status(record, merged:)
      return "stale" if record.prunable

      status = @command_executor.capture(
        "git", "status", "--porcelain=v1", "--untracked-files=normal",
        chdir: record.path,
      )
      return "unknown" unless status.success?
      return "dirty" unless status.stdout.empty?

      merged ? "merged" : "clean"
    end

    def locally_merged_statuses(records)
      records.filter_map do |record|
        next unless merge_checkable?(record)

        Thread.new { [record.path, locally_merged?(record)] }
      end.map(&:value).to_h
    end

    def merge_checkable?(record)
      !record.prunable && record.branch != "main" && !record.head.nil?
    end

    def locally_merged?(record)
      @command_executor.capture(
        "git", "merge-base", "--is-ancestor", record.head, "origin/main",
        chdir: @directory,
      ).success?
    end

    def github_merged_branches(records)
      return [] if records.empty?

      repository = github_repository
      return [] unless repository

      branches_by_alias = records.each_with_index.to_h do |record, index|
        ["branch#{index}", record.branch]
      end
      fields = branches_by_alias.map do |name, branch|
        "#{name}: pullRequests(first: 1, states: MERGED, headRefName: #{JSON.generate(branch)}) { nodes { number } }"
      end.join(" ")
      owner, name = repository
      query = "query { repository(owner: #{JSON.generate(owner)}, name: #{JSON.generate(name)}) { #{fields} } }"
      result = @command_executor.capture(
        "gh", "api", "graphql", "-f", "query=#{query}",
        chdir: @directory,
      )
      return [] unless result.success?

      pull_requests = JSON.parse(result.stdout).dig("data", "repository") || {}
      branches_by_alias.filter_map do |graphql_name, branch|
        branch unless pull_requests.dig(graphql_name, "nodes").to_a.empty?
      end
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def github_repository
      result = @command_executor.capture("git", "remote", "get-url", "origin", chdir: @directory)
      return unless result.success?

      url = result.stdout.strip
      prefix = ["git@github.com:", "https://github.com/", "ssh://git@github.com/"].find do |candidate|
        url.start_with?(candidate)
      end
      return unless prefix

      owner, name = url.delete_prefix(prefix).delete_suffix(".git").split("/", 2)
      [owner, name] if owner && name
    end

    def act_on(selection, records:, current_path:)
      case selection
      when PruneCandidate then prune_candidate(selection, current_path:)
      when Worktree then workflow.open_in_editor(selection.path, chdir: current_path)
      when :new then create_from_prompt(records.first.path)
      else 0
      end
    end

    def prune_candidate(candidate, current_path:)
      worktree = candidate.worktree
      current_records = registered_worktrees
      primary = current_records.first
      current = current_records.drop(1).find do |record|
        File.expand_path(record.path) == File.expand_path(worktree.path)
      end
      unless current && File.expand_path(current.path) != File.expand_path(primary.path)
        @error.puts "worktrees: #{worktree.path} is no longer a secondary worktree"
        return :refresh
      end

      current_status = worktree_statuses([current]).fetch(current.path)
      answer = prompt("Remove #{current_status} worktree #{worktree.path}? [y/N]: ")
      return :refresh if answer.equal?(END_OF_INPUT)
      return :refresh unless answer.match?(/\Ay(?:es)?\z/i)

      workflow.remove_registration(
        worktree.path,
        chdir: current_path,
        force: current_status == "dirty",
      )
      :refresh
    end

    def warn_if_main_is_secondary(records)
      secondary_main = records.drop(1).find { |record| record.branch == "main" }
      return unless secondary_main

      @error.puts "worktrees: warning: main is checked out in secondary worktree #{secondary_main.path}"
    end

    def report_outside_repository
      @error.puts "worktrees: not inside a Git repository"
    end

    def report_command_failure(result)
      @error.print result.stderr
    end

    def browse_menu_choices(records, current_path:, widths:)
      record_choices = records.each_with_index.map do |record, index|
        current = File.expand_path(record.path) == File.expand_path(current_path)
        marker = current ? @colorizer.green("*") : " "
        worktree = File.basename(record.path).ljust(widths.fetch(:worktree))
        branch = @colorizer.blue((record.branch || "detached").ljust(widths.fetch(:branch)))
        path = @colorizer.dim(display_path(record.path).ljust(widths.fetch(:path)))
        label = "#{(index + 1).to_s.rjust(widths.fetch(:index))}  " \
                "#{marker} #{worktree}  #{branch}  #{path}"
        [label, record]
      end
      record_choices + [
        [@colorizer.green("#{(records.length + 1).to_s.rjust(widths.fetch(:index))}  New worktree"), :new],
        [@colorizer.dim("#{(records.length + 2).to_s.rjust(widths.fetch(:index))}  Cancel"), :cancel],
      ]
    end

    def browse_column_widths(records)
      {
        index: ["#".length, (records.length + 2).to_s.length].max,
        worktree: (["WORKTREE"] + records.map { |record| File.basename(record.path) }).map(&:length).max,
        branch: (["BRANCH"] + records.map { |record| record.branch || "detached" }).map(&:length).max,
        path: (["PATH"] + records.map { |record| display_path(record.path) }).map(&:length).max,
      }
    end

    def prune_menu_choices(candidates, widths:)
      choices = candidates.each_with_index.map do |candidate, index|
        record = candidate.worktree
        worktree = File.basename(record.path).ljust(widths.fetch(:worktree))
        branch = @colorizer.blue((record.branch || "detached").ljust(widths.fetch(:branch)))
        age = Worktrees.age_label(path: record.path, now: @now).ljust(widths.fetch(:age))
        status = color_status(candidate.status) + (" " * (widths.fetch(:status) - candidate.status.length))
        path = @colorizer.dim(display_path(record.path).ljust(widths.fetch(:path)))
        label = "#{(index + 1).to_s.rjust(widths.fetch(:index))}    " \
                "#{worktree}  #{branch}  #{age}  #{status}  #{path}"
        [label, candidate]
      end
      choices << [@colorizer.dim("#{(candidates.length + 1).to_s.rjust(widths.fetch(:index))}  Cancel"), :cancel]
    end

    def prune_column_widths(candidates)
      records = candidates.map(&:worktree)
      {
        index: ["#".length, (candidates.length + 1).to_s.length].max,
        worktree: (["WORKTREE"] + records.map { |record| File.basename(record.path) }).map(&:length).max,
        branch: (["BRANCH"] + records.map { |record| record.branch || "detached" }).map(&:length).max,
        age: (["AGE"] + records.map { |record| Worktrees.age_label(path: record.path, now: @now) }).map(&:length).max,
        status: (["STATUS"] + candidates.map(&:status)).map(&:length).max,
        path: (["PATH"] + records.map { |record| display_path(record.path) }).map(&:length).max,
      }
    end

    def color_status(status)
      return @colorizer.red(status) if status == "stale"
      return @colorizer.yellow(status) if status == "dirty"
      return @colorizer.green(status) if status == "merged"

      status
    end

    def display_path(path)
      home = Dir.home
      path == home || path.start_with?("#{home}/") ? path.sub(home, "~") : path
    end

    def browse_table_header(widths)
      "#{"#".rjust(widths.fetch(:index))}    " \
        "#{"WORKTREE".ljust(widths.fetch(:worktree))}  " \
        "#{"BRANCH".ljust(widths.fetch(:branch))}  " \
        "#{"PATH".ljust(widths.fetch(:path))}"
    end

    def prune_table_header(widths)
      "#{"#".rjust(widths.fetch(:index))}    " \
        "#{"WORKTREE".ljust(widths.fetch(:worktree))}  " \
        "#{"BRANCH".ljust(widths.fetch(:branch))}  " \
        "#{"AGE".ljust(widths.fetch(:age))}  " \
        "#{"STATUS".ljust(widths.fetch(:status))}  " \
        "#{"PATH".ljust(widths.fetch(:path))}"
    end

    def render_menu(choices)
      choices.each { |label, _value| @output.puts label }
    end

    def choose_browser(records, current_path:)
      widths = browse_column_widths(records)
      choices = browse_menu_choices(records, current_path:, widths:)
      choose(choices, header: browse_table_header(widths), footer: "↑/↓ or j/k, Enter to open, q to cancel")
    end

    def choose_prune_candidate(candidates)
      widths = prune_column_widths(candidates)
      choices = prune_menu_choices(candidates, widths:)
      choose(choices, header: prune_table_header(widths), footer: "↑/↓ or j/k, Enter to remove, q to cancel")
    end

    def choose(choices, header:, footer:)
      return choose_interactively(choices, header:, footer:) if @interactive

      choose_by_number(choices, header:)
    end

    def choose_interactively(choices, header:, footer:)
      InteractiveMenu.new(
        output: @output,
        read_key: @read_key,
        colorizer: @colorizer,
        header:,
        footer:,
      ).choose(choices)
    end

    def choose_by_number(choices, header:)
      loop do
        @output.puts header
        render_menu(choices)
        selection = prompt("Select: ")
        return :cancel if selection.equal?(END_OF_INPUT)

        number = Integer(selection, exception: false)
        return choices.fetch(number - 1).last if number&.between?(1, choices.length)

        @error.puts "worktrees: invalid selection"
      end
    end

    def create_from_prompt(primary_path)
      request = @creation_prompt.collect(primary_path)
      case request
      when CreationRequest then workflow.create_style_and_open(**request.to_h)
      when :invalid then 1
      else 0
      end
    end

    def prompt(message)
      @output.print message
      @output.flush
      line = @input.gets
      line ? line.chomp : END_OF_INPUT
    end

    def workflow
      @workflow ||= WorktreeWorkflow.new(
        command_executor: @command_executor,
        vscode_identity:,
      )
    end

    def vscode_identity
      return @vscode_identity if @vscode_identity

      require_relative "vscode_identity"
      @vscode_identity = VsCodeIdentity.new(
        command_executor: @command_executor,
        output: @output,
        error: @error,
      )
    end
  end
end
