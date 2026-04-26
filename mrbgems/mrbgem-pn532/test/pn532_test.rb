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

class PN532PollTypeATest < Minitest::Test
  def setup
    @i2c = MockI2C.new
    @reader = PN532.new(i2c: @i2c, addr: 0x24)
    @reader.define_singleton_method(:sleep_ms) { |_ms| nil }
  end

  # 4-byte UID (一般的な MIFARE Classic) を検出
  # 応答: D5 4B 01 (NbTg) 01 (Tg) 00 04 (SENS_RES) 08 (SEL_RES) 04 (NFCIDLen) 04 A1 B2 C3 (UID)
  # LEN = 1 + 1 + 1 + 1 + 1 + 2 + 1 + 1 + 4 = 12
  # payload = D5 4B 01 01 00 04 08 04 04 A1 B2 C3
  # sum  = 0x34C → DCS = 0x100 - 0x4C = 0xB4
  # LCS = 0x100 - 0x0C = 0xF4
  def test_returns_uid_hex_string_when_card_detected
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])  # ACK
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x0C, 0xF4, 0xD5, 0x4B,
                          0x01, 0x01, 0x00, 0x04, 0x08, 0x04, 0x04, 0xA1, 0xB2, 0xC3,
                          0xB4, 0x00])

    uid = @reader.poll_typeA(timeout_ms: 100)

    assert_equal "04A1B2C3", uid
  end

  # 7-byte UID (NTAG215 など)。NFCIDLen=7
  # payload = D5 4B 01 01 00 44 00 07 04 11 22 33 44 55 66
  # sum  = 0x2D6 → DCS = 0x100 - 0xD6 = 0x2A
  # LEN = 15, LCS = 0xF1
  def test_returns_7byte_uid
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x0F, 0xF1, 0xD5, 0x4B,
                          0x01, 0x01, 0x00, 0x44, 0x00, 0x07, 0x04, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66,
                          0x2A, 0x00])

    uid = @reader.poll_typeA(timeout_ms: 100)

    assert_equal "04112233445566", uid
  end

  # NbTg=0: カード未検出 → nil
  # payload = D5 4B 00, sum=120, DCS=E0, LEN=3, LCS=FD
  def test_returns_nil_when_no_card_detected
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x03, 0xFD, 0xD5, 0x4B, 0x00, 0xE0, 0x00])

    assert_nil @reader.poll_typeA(timeout_ms: 100)
  end

  def test_sends_inlist_passive_target_typeA_command
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x03, 0xFD, 0xD5, 0x4B, 0x00, 0xE0, 0x00])

    @reader.poll_typeA(timeout_ms: 100)

    _, bytes = @i2c.write_log.first
    # cmd=0x4A, data=[0x01, 0x00] (MaxTg=1, BrTy=0x00=TypeA)
    assert_equal [0x00, 0x00, 0xFF, 0x04, 0xFC, 0xD4, 0x4A, 0x01, 0x00, 0xE1, 0x00], bytes
  end

  def test_returns_nil_on_ack_timeout
    20.times { @i2c.queue_response([0x00] + [0x00] * 32) }
    assert_nil @reader.poll_typeA(timeout_ms: 5)
  end

  # NFCIDLen=07 だが UID 領域が 4 byte しか無いトランケート応答 → ProtocolError
  # payload = D5 4B 01 01 00 04 08 07 04 A1 B2 C3 (12 bytes)
  # LEN=0x0C, LCS=0xF4, sum=0x34F, DCS=0xB1
  def test_raises_on_truncated_nfcid_payload
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00])  # ACK
    @i2c.queue_response([0x01, 0x00, 0x00, 0xFF, 0x0C, 0xF4, 0xD5, 0x4B,
                          0x01, 0x01, 0x00, 0x04, 0x08, 0x07, 0x04, 0xA1, 0xB2, 0xC3,
                          0xB1, 0x00])
    assert_raises(PN532::ProtocolError) { @reader.poll_typeA(timeout_ms: 100) }
  end
end
