class MockI2C
  attr_reader :write_log

  def initialize
    @write_log = []
    @read_queue = []
  end

  def write(addr, bytes)
    @write_log << [addr, bytes.dup]
    nil
  end

  def read(addr, len)
    raise "MockI2C: read called with empty response queue (addr=#{addr.inspect}, len=#{len})" if @read_queue.empty?
    response = @read_queue.shift
    response.first(len)
  end

  def queue_response(bytes)
    @read_queue << bytes.dup
  end
end
