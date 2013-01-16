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

  #def respond_to?(*)
  #  true
  #end

  #def method_missing(method, *args)
  #  # puts [method, args].inspect
  #end

  def begin_text_object
    @object = ""
  end

  def end_text_object
    puts @object
  ensure
    @object = nil
  end

  def numbers
    @numbers ||= Set.new
  end

  def reset!
    @kind = @to = @duration = @last = @date = @comment = @time = nil
  end
  def show_text(text)
    text = convert(text).strip

    return if text.blank?

    if @object and text.length == 1
      @object << text
      return
    end

    puts text

    case text
    when NUMBER
      reset!
      @number = numbers.find{|n| n == text} || Number.new(text)
      numbers << @number
      @last = :number
    when DATE
      if @last == :kind
        @date = text
        @last = :date
      else
        @last = nil
        raise UnknownState.new(text)
      end
    when KIND
      puts "KIND: #{text}"
      @kind = text.to_sym
      @last = :kind
    when GROUP_CALLS
      @kind = :voice
      @last = :kind
    when RECEIVER
      @to = text
      @last = :receiver
    when DURATION
      if @last == :date
        @time = text
        @last = :time
      else
        @duration = text
        @last = :duration
      end

    else

      if @last == :duration
        @comment = text
        @last = :comment
      else
        puts "UNKNOWN: #{text}"
      end
    end

    case @kind

    when :voice
      if @to && @duration
        parts = [2012, @date.split(".").reverse, @time.split(":")].flatten
        date = DateTime.new(*parts.map(&:to_i))
        @number.calls << Call.new(@to, date, @duration)
        reset!
      end

    when :sms
      if @to
        @number.sms << SMS.new(@to)
        reset!
      end

    when :connect
      # TODO: implement data
    end
  end

  def convert(text)
    text.force_encoding(ENCODING).encode(Encoding.default_external)
  end
end

class Number
  def initialize(number)
    @number = number
  end

  def calls
    @calls ||= []
  end

  def sms
    @sms ||= []
  end

  def ==(other)
    @number == other or super
  end
end

class Call
  attr_reader :number

  def initialize(number, date, duration)
    @number = number
    @date = date
    @duration = duration
  end

  def duration
    hours, minutes, seconds = @duration.split(':').map(&:to_i)

    hours = ActiveSupport::Duration.new(hours * 3600, [[:seconds, hours * 3600]])
    minutes = ActiveSupport::Duration.new(minutes, [[:minutes, minutes]])
    seconds = ActiveSupport::Duration.new(seconds, [[:seconds, seconds]])

    hours + minutes + seconds
  end
end

class SMS
  attr_reader :number

  def initialize(number)
    @number = number
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
