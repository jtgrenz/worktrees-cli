# frozen_string_literal: true

require_relative "test_helper"

class WorktreeTest < WorktreesTestCase
  def test_parses_branch_detached_and_prunable_worktrees
    records = Worktrees.parse_porcelain(<<~PORCELAIN)
      worktree /tmp/zenpayroll
      HEAD abc123
      branch refs/heads/main

      worktree /tmp/zenpayroll scratch
      HEAD def456
      detached
      prunable gitdir file points to non-existent location
    PORCELAIN

    assert_equal(
      [
        {
          path: "/tmp/zenpayroll",
          head: "abc123",
          branch: "main",
          detached: false,
          prunable: false,
        },
        {
          path: "/tmp/zenpayroll scratch",
          head: "def456",
          branch: nil,
          detached: true,
          prunable: true,
        },
      ],
      records.map(&:to_h),
    )
  end

  def test_calculates_whole_day_age
    created_at = Time.new(2026, 8, 15, 13, 0, 0, "-04:00")
    now = Time.new(2026, 8, 18, 12, 59, 59, "-04:00")

    assert_equal 2, Worktrees.age_in_days(created_at:, now:)
  end

  def test_never_reports_a_negative_age
    created_at = Time.new(2026, 8, 19, 13, 0, 0, "-04:00")
    now = Time.new(2026, 8, 18, 13, 0, 0, "-04:00")

    assert_equal 0, Worktrees.age_in_days(created_at:, now:)
  end

  def test_reports_a_missing_worktree_without_inventing_an_age
    assert_equal(
      "missing",
      Worktrees.age_label(path: "/tmp/worktrees-does-not-exist", now: Time.now),
    )
  end
end
