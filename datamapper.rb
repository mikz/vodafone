#DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, 'sqlite::memory:')

class Entry
  include DataMapper::Resource

  property :id,           Serial
  property :source,       String
  property :destination,  String
  property :service,      String
  property :time,         DateTime
  property :length,       Integer
  property :price,        Decimal
end


DataMapper.finalize
DataMapper.auto_migrate!
