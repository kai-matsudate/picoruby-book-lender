require "test_helper"
require "mock_i2c"

class MockI2CTest < Minitest::Test
  def setup
    @i2c = MockI2C.new
  end

  def test_write_records_addr_and_bytes
    @i2c.write(0x24, [0x01, 0x02, 0x03])
    assert_equal [[0x24, [0x01, 0x02, 0x03]]], @i2c.write_log
  end

  def test_read_returns_queued_response
    @i2c.queue_response([0xAA, 0xBB, 0xCC])
    assert_equal [0xAA, 0xBB, 0xCC], @i2c.read(0x24, 3)
  end

  def test_read_returns_only_requested_length
    @i2c.queue_response([0x01, 0x02, 0x03, 0x04, 0x05])
    assert_equal [0x01, 0x02], @i2c.read(0x24, 2)
  end

  def test_read_consumes_responses_in_order
    @i2c.queue_response([0x01])
    @i2c.queue_response([0x02])
    assert_equal [0x01], @i2c.read(0x24, 1)
    assert_equal [0x02], @i2c.read(0x24, 1)
  end

  def test_read_raises_when_queue_empty
    assert_raises(RuntimeError) { @i2c.read(0x24, 1) }
  end
end
