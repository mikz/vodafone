#!/usr/bin/env ruby
#
require 'bundler/setup'
Bundler.require :default

require './datamapper'

ENCODING = 'CP1250'

class Receiver
  class UnknownState < ::StandardError
    def initialize(state)
      super("Unknown state: #{state}")
    end
  end

  NUMBER = /^\d{3}\s\d{3}\s\d{3}$/
  KIND = /^voice|sms|connect$/
  GROUP_CALLS = /^group|calls$/
  RECEIVER = /\d{11,12}$/
  DURATION = /^\d{2}:\d{2}:\d{2}$/
  DATE = /^\d{1,2}\.\d{1,2}\.$/
  PRICE = /^\d+,\d+$/
  AMOUNT = /^\d$/

  class StateMachine
    attr_reader :last

    def initialize
      @hash = {}
    end

    def reset!
      @last = nil
      @hash = {}
    end

    def set(state, value)
      @hash.store(state.to_sym, value)
      @last = state.to_sym
      puts "STATE #{state} = #{value}"
    end

    def get(state)
      @hash.fetch(state) { nil }
    end

    def has?(state)
      @hash.has_key?(state)
    end

    def ==(other)
      last == other or super
    end
    alias :=== :==
  end

  def initialize
    @numbers = Set.new
    @state = StateMachine.new
  end

  def self.states(*states)
    states.each do |name|
      self.state name
    end
  end

  def self.state(state)
    define_method("#{state}=") do |value|
      @state.set(state, value)
    end

    define_method(state) do
      @state.get(state)
    end

    define_method("#{state}?") do
      @state.has?(state)
    end
  end

  states :kind, :date, :time, :duration, :receiver, :comment, :amount, :for_free, :price
  attr_reader :state, :numbers, :number

  def number=(number)
    @number = number
    numbers << number
  end

  def begin_text_object
    @text_object = true
  end

  def end_text_object
    @text_object = nil
  end

  def show_text(text)
    text = convert(text).strip

    return if text.blank?

    if number or kind?
      puts text
    end

    case text

    when NUMBER
      self.number = numbers.find{|n| n == text} || Number.new(text)
      state.reset!

    when KIND
      state.reset!
      puts "KIND: #{text}"
      self.kind = text.to_sym

    when GROUP_CALLS
      state.reset!
      self.kind = :voice

    when DATE
      if state == :kind
        self.date = text
      else
        raise UnknownState.new(text)
      end

    when RECEIVER
      self.receiver = text

    when DURATION
      case state.last
      when :date
        self.time = text
      when :receiver
        self.duration = text
      when :comment
        self.for_free = text
      else
        puts "UNKNOWN (#{state.last}): #{text}"
      end

    when PRICE
      self.price = text

    when AMOUNT
      self.amount = text

    else

      case state.last
      when :duration, :receiver
        self.comment = text

      else
        puts "UNKNOWN: #{text}"
      end
    end

    return unless price?

    case kind

    when :voice
      if receiver? and duration? and comment?
        number.calls << Call.new(receiver, timestamp, duration, price, for_free, comment)
        state.reset!
      end

    when :sms
      if receiver?
        number.sms << SMS.new(receiver, timestamp, amount, price, comment)
        state.reset!
      end

    when :connect
      # TODO: implement data
    end
  end

  def timestamp
    parts = [2012, date.split(".").reverse, time.split(":")].flatten
    date = DateTime.new(*parts.map(&:to_i))
  end

  def convert(text)
    text.force_encoding(ENCODING).encode(Encoding.default_external)
  end
end

class Number

  attr_reader :number, :calls, :sms

  def initialize(number)
    @number = number
    @calls = []
    @sms = []
  end

  def number
    @number.tr(' ', '')
  end

  def ==(other)
    @number == other or super
  end

  def report
    call_groups = calls.group_by(&:comment)
    sms_groups = sms.group_by(&:comment)

    {
      calls: Hash[call_groups.map{ |key, calls|
              [key, [calls.count, calls.map(&:duration).reduce(:+)] ] }],
      sms: Hash[sms_groups.map{ |key, sms| [key, sms.count] } ]
    }
  end
end

class Call
  attr_reader :number, :date, :duration, :price, :for_free, :comment

  def initialize(number, date, duration, price, for_free, comment)
    @number = number
    @date = date
    @duration = Duration.new(duration)
    @comment = comment
    @price = price && price.tr(',', '.').to_f

    @for_free = for_free && Duration.new(for_free)

    puts "New call to #{number} on #{date} took #{duration}"
  end

  def paid?
    for_free || price > 0
  end

  class Duration
    attr_reader :hours, :minutes, :seconds

    def initialize(duration)
      @hours, @minutes, @seconds = duration.split(':').map(&:to_i)
    end

    def inspect
      "#<#{self.class}:#{object_id} #{to_s}>"
    end

    def to_s
      "%02d:%02d:%02d" % [ hours, minutes, seconds ]
    end

    def seconds=(value)
      @seconds = value.to_i.remainder(60)
      self.minutes += value.to_i/60
    end

    def minutes=(value)
      @minutes = value.to_i.remainder(60)
      self.hours += value.to_i/60
    end

    def hours=(value)
      @hours = value
    end

    def +(other)
      copy = dup

      if Duration === other
        copy.hours += other.hours
        copy.minutes += other.minutes
        copy.seconds += other.seconds
      else
        copy.seconds += other
      end

      copy
    end
  end
end

class SMS
  attr_reader :number, :date, :price, :comment, :amount

  def initialize(number, date, amount, price, comment)
    @number = number
    @date = date
    @price = price && price.tr(',', '.').to_f
    @comment = comment
    @amount = amount && amount.to_i

    puts "New SMS to #{number} on #{date}"
  end

  def paid?
    price > 0 or amount
  end
end

ARGV.each do |file|
  pdf = PDF::Reader.new(file)

  receiver = Receiver.new

  pdf.pages.each do |page|
    page.walk(receiver)
  end
  binding.pry
end
