#!/usr/bin/env ruby
# coding: utf-8
require 'bundler/setup'
require 'csv'
Bundler.require :default

require './datamapper'

ENCODING = 'CP1250'

class Receiver
  class UnknownState < ::StandardError
    def initialize(state)
      super("Unknown state: #{state}")
    end
  end

  class StateMachine
    attr_accessor :last

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
      debug "STATE #{state} = #{value}"
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

    def debug(*args)
      puts(*args) if ENV['DEBUG']
    end
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

  NUMBER = /^\d{3}\s\d{3}\s\d{3}$/
  KIND = /^voice|sms|connect$/
  GROUP_CALLS = /^group|calls$/
  RECEIVER = /\d{11,12}$/
  DURATION = /^\d{2}:\d{2}:\d{2}$/
  DATE = /^\d{1,2}\.\d{1,2}\.$/
  FULL_DATE = /^\d{1,2}\.\d{1,2}\.\d{4}$/
  PRICE = /^\d+,\d+$/
  AMOUNT = /^\d+$/
  SUM_KIND = /^Hlasové služby$/
  SKIP = /^A|AU|Strana$/
  RESET = /^Kč bez DPH$/
  VAT = /^\d+ %$/

  states :kind, :date, :time, :duration, :receiver, :comment, :amount, :for_free, :price

  states :group, :vat

  attr_reader :state
  attr_reader :services, :service
  attr_reader :numbers, :number

  def initialize
    @numbers = Set.new
    @services = Set.new
    @state = StateMachine.new
  end

  def number=(number)
    @number = number
    numbers << number
  end

  def service=(service)
    @service = service
    services << service
  end

  def begin_text_object
    @text_object = true
  end

  def end_text_object
    @text_object = nil
  end

  def respond_to?(method)
    # puts method.inspect
    super
  end

  def page=(page)
    state.reset!
    puts "NEW PAGE #{page.inspect}"
  end

  def debug(*args)
    puts *args if ENV['DEBUG']
  end

  def show_text(text)
    text = convert(text).strip

    return if text.blank?

    if number or kind?
      debug text
    end

    case text

    when NUMBER
      self.number = numbers.find{|n| n == text} || Number.new(text)
      debug "NUMBER = #{text}"
      state.reset!

    when 'Hlasové služby'
      self.service = number && number.service(:voice)
    when 'SMS služby'
      self.service = number && number.service(:sms)
    when 'Data', 'Připojení ze zahraničí'
      self.service = number && number.service(:data)
    when 'Skupinová volání'
      self.service = number && number.service(:groups)
    when 'MMS služby'
      self.service = number && number.service(:mms)
    when 'Roaming - SMS'
      self.service = number && number.service(:roaming_sms)

    when 'MMS služby'

    when 'Používání služeb'
      @inside_group = true

    when KIND
      state.reset!
      debug "KIND: #{text}"
      self.kind = text.to_sym

    when VAT
      self.vat = text

    when GROUP_CALLS
      state.reset!
      self.kind = :voice

    when DATE
      if state == :kind
        self.date = text
      else
        debug "Ignoring unknown DATE state #{text}"
        # raise UnknownState.new(text)
      end

    when FULL_DATE, RESET
      # probably page turn
      state.reset!

    when SKIP
      # skip

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
      when :amount
        # service mode
        self.duration = text
      when :price
        # service mode
        self.for_free = text
      else
        debug "UNKNOWN (#{state.last}): #{text}"
      end

    when PRICE
      self.price = text

    when AMOUNT
      case state.last
      when :price
        self.for_free = text
      else
        self.amount = text
      end

    else

      case state.last
      when :duration, :receiver
        self.comment = text

      else
        if service and @inside_group and not amount?
          state.reset!
          self.group = text
        else
          debug "UNKNOWN: #{text}"
        end
      end
    end

    if service and @inside_group
      valid = case service.name
      when :voice
        group && amount && price && duration and service.sum?(group) || vat
      when :sms
        group && amount && price and service.sum?(group) || vat
      when :data
        group && amount && price
      end

      if valid
        if service.sum?(group)
          unless service.sum
            service.sum ||= Group.new(group, amount, duration, price, for_free)
            debug "group is sum of service #{service.name}"
          else
            debug "service #{service.name} already has sum"
          end
          @inside_group = false
        else
          service.groups << Group.new(group, amount, duration, price, for_free)
        end

        state.reset!
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

  attr_reader :number, :calls, :sms, :services

  def initialize(number)
    @number = number
    @calls = []
    @sms = []
    @services = []
  end

  def number
    @number.tr(' ', '')
  end

  def ==(other)
    @number == other or super
  end

  def service(kind)
    unless service = @services.find{|s| s == kind}
      service = Service.new(kind)
      @services << service
    end
    service
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

  def group_report
    Report.new do |report|
      report.number = self
      report.calls = service(:voice).groups.select(&:paid?).map do |group|
        [ group.name, [ group.amount, group.duration ]]
      end

      report.calls_sum = service(:voice).sum

      report.sms = service(:sms).groups.select(&:paid?).map do |group|
        [ group.name, group.amount ]
      end
      report.sms_sum = service(:sms).sum
    end
  end

  def inline_report
    InlineReport.new.tap do |report|
      report.number = self
      report.calls = service(:voice).groups.select(&:paid?).map do |group|
        [group.name, group.duration]
      end

      report.sms = service(:sms).groups.map do |group|
        [ group.name, group.amount]
      end.compact
    end
  end
end

class Report
  attr_accessor :calls, :sms, :number, :calls_sum, :sms_sum

  def initialize(&block)
    block.call(self)
  end

  def to_csv
    [
      number.number,
      sms_sum && sms_sum.amount,
      sms_sum && sms_sum.price.round.to_i,
      calls_sum && calls_sum.duration.to_minutes,
      calls_sum && calls_sum.price.round.to_i
    ]
  end
end

class InlineReport
  attr_accessor :number, :sms, :calls

  def to_csv
    caller = number.number
    rows = []

    calls.each do |(name, duration)|
      rows << [ caller, 'voice', name, duration.to_minutes ]
    end

    sms.each do |(name, amount)|
      rows << [ caller, 'sms', name, amount]
    end

    rows
  end
end

class Service
  attr_reader :groups
  attr_accessor :sum

  def name
    @kind
  end

  def initialize(kind)
    @kind = kind
    @groups = []
  end

  def ==(other)
    @kind == other or super
  end

  def sum?(text)
    text =~ /^Celkem za/
  end
end

class Group
  attr_reader :name, :amount, :duration, :price

  def initialize(name, amount, duration, price, for_free)
    @name = name
    @amount = amount.to_i
    @duration = duration && Duration.new(duration)
    @price = price && price.tr(',', '.').to_f
    @for_free = for_free

    puts "New #{self.inspect}"
  end

  def paid?
    price > 0 or @for_free
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

  def to_minutes
    (hours * 60 + minutes + seconds / 60).round
  end
end

csv = CSV.new('')
csv << %w[Číslo SMS Cena Volání Cena]

ARGV.each do |file|
  pdf = nil
  begin
    pdf = PDF::Reader.new(file)
  rescue PDF::Reader::EncryptedPDFError
    puts "skippng #{file} - #{$!}"
    next
  end

  receiver = Receiver.new

  pdf.pages.each do |page|
    page.walk(receiver)
    receiver.state.reset!
  end

  csv << [file] if ENV['DEBUG']
  type = 'inline'

  receiver.numbers.each do |number|
    case type
      when 'group'
        csv << number.group_report.to_csv
      when 'inline'
        number.inline_report.to_csv.each do |row|
          csv << row
        end
      else
        raise "Unknown type: #{type}"
    end

  end
end

puts csv.string
