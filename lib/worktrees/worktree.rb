# frozen_string_literal: true

module Worktrees
  SECONDS_PER_DAY = 86_400

  Worktree = Data.define(:path, :head, :branch, :detached, :prunable)

  def self.parse_porcelain(text)
    text.split(/\n\n+/).filter_map do |block|
      lines = block.lines(chomp: true)
      path_line = lines.find { |line| line.start_with?("worktree ") }
      next unless path_line

      Worktree.new(
        path: path_line.delete_prefix("worktree "),
        head: lines.find { |line| line.start_with?("HEAD ") }&.delete_prefix("HEAD "),
        branch: lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch refs/heads/"),
        detached: lines.include?("detached"),
        prunable: lines.any? { |line| line.start_with?("prunable") },
      )
    end
  end

  def self.age_in_days(created_at:, now:)
    [((now - created_at) / SECONDS_PER_DAY).floor, 0].max
  end

  def self.age_label(path:, now:)
    return "missing" unless File.exist?(path)

    "#{age_in_days(created_at: File.birthtime(path), now:)}d"
  rescue NotImplementedError
    "#{age_in_days(created_at: File.mtime(path), now:)}d"
  rescue Errno::ENOENT
    "missing"
  end
end
