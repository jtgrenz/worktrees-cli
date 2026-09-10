# frozen_string_literal: true

require "io/console"

module Worktrees
  class TerminalKeyReader
    ESCAPE_SEQUENCES = {
      "[A" => :up,
      "[B" => :down,
    }.freeze

    def initialize(input)
      @input = input
    end

    def read
      character = @input.getch
      return :enter if ["\r", "\n"].include?(character)
      return :backspace if ["\b", "\u007F"].include?(character)
      raise Interrupt if character == "\u0003"
      return read_escape_sequence if character == "\e"
      return :up if character == "k"
      return :down if character == "j"
      return :cancel if character == "q"

      character.match?(/\A\d\z/) ? character : :ignore
    end

    private

    def read_escape_sequence
      return :cancel unless IO.select([@input], nil, nil, 0.02)

      sequence = @input.read_nonblock(2, exception: false)
      ESCAPE_SEQUENCES.fetch(sequence, :cancel)
    end
  end

  class InteractiveMenu
    def initialize(
      output:,
      read_key:,
      colorizer:,
      header: nil,
      footer: "↑/↓ or j/k, Enter to open, q to cancel"
    )
      @output = output
      @read_key = read_key
      @colorizer = colorizer
      @header = header
      @footer = footer
    end

    def choose(choices)
      selected_index = 0
      number = +""
      @output.print "\e[?1049h\e[?25l"

      loop do
        render(choices, selected_index:, number:)
        selection = apply_key(@read_key.call, selected_index:, number:, choices:)
        return selection.fetch(:value) if selection.key?(:value)

        selected_index = selection.fetch(:selected_index)
        number = selection.fetch(:number)
      end
    ensure
      @output.print "\e[?25h\e[?1049l"
      @output.flush
    end

    private

    def apply_key(key, selected_index:, number:, choices:)
      return move([selected_index - 1, 0].max) if key == :up
      return move([selected_index + 1, choices.length - 1].min) if key == :down
      return { value: :cancel } if key == :cancel
      return select(choices, selected_index:, number:) if key == :enter
      return { selected_index:, number: number.chop } if key == :backspace
      return { selected_index:, number: number + key } if key.is_a?(String)

      { selected_index:, number: }
    end

    def move(selected_index)
      { selected_index:, number: +"" }
    end

    def select(choices, selected_index:, number:)
      numbered_index = Integer(number, exception: false)
      index = numbered_index&.between?(1, choices.length) ? numbered_index - 1 : selected_index
      { value: choices.fetch(index).last }
    end

    def render(choices, selected_index:, number:)
      @output.print "\e[H\e[2J"
      @output.print "\e[2K\r  #{@header}\n" if @header
      choices.each_with_index do |(label, _value), index|
        marker = index == selected_index ? "#{@colorizer.cyan_bold("❯")} " : "  "
        @output.print "\e[2K\r#{marker}#{label}\n"
      end
      @output.print "\e[2K\r#{@footer}"
      @output.print " — #{number}" unless number.empty?
      @output.print "\n"
      @output.flush
    end
  end
end
