class PN532
  module Frame
    PREAMBLE  = 0x00
    START1    = 0x00
    START2    = 0xFF
    POSTAMBLE = 0x00
    TFI_HOST_TO_PN532 = 0xD4
    TFI_PN532_TO_HOST = 0xD5

    # cmd: Integer, data: Array<Integer>
    # returns: Array<Integer>
    def self.build(cmd, data)
      payload = [TFI_HOST_TO_PN532, cmd, *data]
      len = payload.size
      lcs = (0x100 - len) & 0xFF
      dcs = (0x100 - payload.sum) & 0xFF
      [PREAMBLE, START1, START2, len, lcs, *payload, dcs, POSTAMBLE]
    end
  end
end
