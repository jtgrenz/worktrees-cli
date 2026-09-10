# frozen_string_literal: true

module Worktrees
  CreationRequest = Data.define(:branch, :base, :primary_path, :target_path)

  class WorktreeCreationPrompt
    def initialize(input:, output:, error:)
      @input = input
      @output = output
      @error = error
    end

    def collect(primary_path)
      branch = prompt_branch
      return :cancel if branch.equal?(END_OF_INPUT)
      return :invalid if branch == :invalid

      base = prompt_base
      return :cancel if base.equal?(END_OF_INPUT)

      target_path = target_path_for(primary_path:, branch:)
      return report_existing_target(target_path) if File.exist?(target_path)

      show_summary(branch:, base:, target_path:)
      return :cancel unless confirmed?

      CreationRequest.new(branch:, base:, primary_path:, target_path:)
    end

    private

    def prompt_branch
      branch = prompt("Branch: ")
      return END_OF_INPUT if branch.equal?(END_OF_INPUT)
      branch = branch.strip
      return report_invalid_branch("branch cannot be empty") if branch.empty?
      return report_invalid_branch("main belongs in the primary checkout") if branch == "main"

      branch
    end

    def prompt_base
      base = prompt("Base [origin/main]: ")
      return END_OF_INPUT if base.equal?(END_OF_INPUT)

      base.strip.empty? ? "origin/main" : base.strip
    end

    def target_path_for(primary_path:, branch:)
      File.join(
        File.dirname(primary_path),
        "#{File.basename(primary_path)}-#{branch.split("/").last}",
      )
    end

    def show_summary(branch:, base:, target_path:)
      @output.puts "Branch: #{branch}"
      @output.puts "Base: #{base}"
      @output.puts "Path: #{target_path}"
    end

    def confirmed?
      confirmation = prompt("Create? [y/N]: ")
      !confirmation.equal?(END_OF_INPUT) && confirmation.match?(/\Ay(?:es)?\z/i)
    end

    def prompt(message)
      @output.print message
      @output.flush
      line = @input.gets
      line ? line.chomp : END_OF_INPUT
    end

    def report_existing_target(path)
      @error.puts "worktrees: target already exists: #{path}"
      :invalid
    end

    def report_invalid_branch(message)
      @error.puts "worktrees: #{message}"
      :invalid
    end
  end
end
