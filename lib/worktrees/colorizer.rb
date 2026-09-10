# frozen_string_literal: true

module Worktrees
  class Colorizer
    CODES = {
      blue: 34,
      cyan_bold: "1;36",
      dim: 2,
      green: 32,
      red: 31,
      yellow: 33,
    }.freeze

    def initialize(enabled:)
      @enabled = enabled
    end

    CODES.each do |name, code|
      define_method(name) do |text|
        @enabled ? "\e[#{code}m#{text}\e[0m" : text
      end
    end
  end
end
