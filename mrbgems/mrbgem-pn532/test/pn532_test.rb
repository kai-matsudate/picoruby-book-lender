# mrbgems/mrbgem-pn532/test/pn532_test.rb
require "test_helper"
require "mock_i2c"

class PN532FirmwareVersionTest < Minitest::Test
  def setup
    @i2c = MockI2C.new
    @reader = PN532.new(i2c: @i2c, addr: 0x24)
    # sleep を no-op に差し替え (テスト高速化)
    @reader.define_singleton_method(:sleep_ms) { |_ms| nil }
  end

  def test_returns_firmware_version_hash
    # 1. ACK 応答 (ready=01)
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])
    # 2. Information 応答 (ready=01 + frame): IC=0x32 Ver=0x01 Rev=0x06 Support=0x07
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x06, 0xFA, 0xD5, 0x03,
                          0x32, 0x01, 0x06, 0x07, 0xE8, 0x00])

    result = @reader.firmware_version

    assert_equal({ic: 0x32, ver: 0x01, rev: 0x06, support: 0x07}, result)
  end

  def test_sends_get_firmware_version_command
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x06, 0xFA, 0xD5, 0x03,
                          0x32, 0x01, 0x06, 0x07, 0xE8, 0x00])

    @reader.firmware_version

    addr, bytes = @i2c.write_log.first
    assert_equal 0x24, addr
    assert_equal [0x00, 0x00, 0xFF, 0x02, 0xFE, 0xD4, 0x02, 0x2A, 0x00], bytes
  end

  def test_raises_timeout_when_ack_never_arrives
    # ready=00 を何度返しても準備できない
    20.times { @i2c.queue_response([0x00] + [0x00] * 6) }
    assert_raises(PN532::TimeoutError) do
      @reader.firmware_version(timeout_ms: 5)
    end
  end
end
