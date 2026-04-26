# mrbgems/mrbgem-pn532/src/pn532/frame.rb
require "pn532/errors"

class PN532
  module Frame
    PREAMBLE  = 0x00
    START1    = 0x00
    START2    = 0xFF
    POSTAMBLE = 0x00
    TFI_HOST_TO_PN532 = 0xD4
    TFI_PN532_TO_HOST = 0xD5

    ACK_BODY  = [0x00, 0xFF].freeze  # LEN, LCS
    NACK_BODY = [0xFF, 0x00].freeze

    def self.build(cmd, data)
      payload = [TFI_HOST_TO_PN532, cmd, *data]
      len = payload.size
      lcs = (0x100 - len) & 0xFF
      dcs = (0x100 - payload.sum) & 0xFF
      [PREAMBLE, START1, START2, len, lcs, *payload, dcs, POSTAMBLE]
    end

    # 受信バイト列を識別する。:ack / :nack / :error / :information
    # bytes の先頭にあるかもしれない 0x00 / 0xFF パディングは事前に剥がしてから渡される想定。
    def self.classify(bytes)
      raise ProtocolError, "frame too short: #{bytes.inspect}" if bytes.size < 5

      start = find_start(bytes)
      raise ProtocolError, "no start code (00 FF) in #{bytes.inspect}" unless start

      after_start = bytes[(start + 2)..]
      raise ProtocolError, "frame truncated after start code: only #{after_start.size} byte(s) remain" if after_start.size < 2
      return :ack  if after_start[0, 2] == ACK_BODY
      return :nack if after_start[0, 2] == NACK_BODY

      # Error frame: LEN=0x01 LCS=0xFF TFI=0x7F (sum=80 → DCS=0x81)
      return :error if after_start[0, 4] == [0x01, 0xFF, 0x7F, 0x81]

      :information
    end

    # Information frame 専用。cmd と data を返す。
    # 失敗時は ChecksumError / ProtocolError を上げる。
    def self.parse_response(bytes)
      start = find_start(bytes)
      raise ProtocolError, "no start code in #{bytes.inspect}" unless start

      header = bytes[(start + 2)..]
      len = header[0]
      lcs = header[1]
      raise ChecksumError, "LCS mismatch: len=#{len.inspect} lcs=#{lcs.inspect}" \
        unless ((len + lcs) & 0xFF) == 0

      raise ProtocolError, "frame truncated: declared len=#{len} but only #{header.size - 2} bytes remain" \
        if header.size < 2 + len + 1

      payload = header[2, len]
      dcs = header[2 + len]
      raise ChecksumError, "DCS mismatch" unless ((payload.sum + dcs) & 0xFF) == 0

      tfi = payload[0]
      raise ProtocolError, "unexpected TFI: 0x#{tfi.to_s(16)}" unless tfi == TFI_PN532_TO_HOST

      cmd  = payload[1]
      data = payload[2..] || []
      [cmd, data]
    end

    def self.find_start(bytes)
      bytes.each_cons(2).with_index do |(a, b), i|
        return i if a == START1 && b == START2
      end
      nil
    end
  end
end
