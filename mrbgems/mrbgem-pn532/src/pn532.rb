# mrbgems/mrbgem-pn532/src/pn532.rb
require "pn532/errors"
require "pn532/frame"

class PN532
  VERSION = "0.0.1"
  DEFAULT_ADDR = 0x24
  DEFAULT_TIMEOUT_MS = 1000
  POLL_INTERVAL_MS   = 1

  CMD_GET_FIRMWARE_VERSION  = 0x02
  CMD_INLIST_PASSIVE_TARGET = 0x4A

  def initialize(i2c:, addr: DEFAULT_ADDR)
    @i2c = i2c
    @addr = addr
  end

  def firmware_version(timeout_ms: DEFAULT_TIMEOUT_MS)
    cmd, data = round_trip(CMD_GET_FIRMWARE_VERSION, [], timeout_ms: timeout_ms)
    raise ProtocolError, "unexpected response cmd 0x#{cmd.to_s(16)}" unless cmd == CMD_GET_FIRMWARE_VERSION + 1
    raise ProtocolError, "firmware version data too short" if data.size < 4
    {ic: data[0], ver: data[1], rev: data[2], support: data[3]}
  end

  # MIFARE Type A UID を hex 文字列で返す。検出なし or タイムアウトは nil。
  def poll_typeA(timeout_ms: DEFAULT_TIMEOUT_MS)
    poll_passive_target(brty: 0x00, init_data: [], timeout_ms: timeout_ms) do |data|
      extract_typeA_uid(data)
    end
  end

  # Sleep を host テストで上書きできるよう切り出す。実機では Kernel.sleep を使う。
  def sleep_ms(ms)
    sleep(ms / 1000.0)
  end

  private

  # コマンドを送り、ACK と応答を待って (cmd_response, data) を返す
  def round_trip(cmd, data, timeout_ms:)
    @i2c.write(@addr, Frame.build(cmd, data))
    wait_for_ack(timeout_ms)
    read_response(timeout_ms)
  end

  def wait_for_ack(timeout_ms)
    bytes = poll_until_ready(7, timeout_ms)
    kind = Frame.classify(bytes)
    raise ProtocolError, "expected ACK, got #{kind}" unless kind == :ack
  end

  def read_response(timeout_ms)
    # 応答長は不明なので長めに 32 byte 読む。Frame.parse_response は start code を探すので余分は無害。
    bytes = poll_until_ready(32, timeout_ms)
    Frame.parse_response(bytes)
  end

  # I2C は最初の 1 byte に ready status を返す。bit0=1 になるまで待ち、
  # ready になったら追加分を読む。MockI2C では 1 回の read(len) で全部返ってくるため、
  # ここでは「先頭バイトの bit0 をチェックし、駄目なら次の応答キューを試す」という
  # 簡易プロトコルにする。実機向け実装は Phase 1b で I2C 仕様に合わせて見直す。
  def poll_until_ready(len, timeout_ms)
    elapsed = 0
    loop do
      raise TimeoutError, "PN532 did not become ready within #{timeout_ms}ms" if elapsed >= timeout_ms

      chunk = @i2c.read(@addr, len + 1) # +1 for ready status byte
      ready = chunk[0]
      if ready & 0x01 == 1
        return chunk[1..]
      end
      sleep_ms(POLL_INTERVAL_MS)
      elapsed += POLL_INTERVAL_MS
    end
  end

  # 共通: InListPassiveTarget を投げ、検出失敗/タイムアウトは nil、成功は yield 経由で抽出
  def poll_passive_target(brty:, init_data:, timeout_ms:)
    @i2c.write(@addr, Frame.build(CMD_INLIST_PASSIVE_TARGET, [0x01, brty, *init_data]))
    begin
      wait_for_ack(timeout_ms)
      cmd, data = read_response(timeout_ms)
    rescue TimeoutError
      return nil
    end
    raise ProtocolError, "unexpected response cmd 0x#{cmd.to_s(16)}" unless cmd == CMD_INLIST_PASSIVE_TARGET + 1
    return nil if data.first == 0  # NbTg = 0 → カード未検出
    yield data
  end

  # InListPassiveTarget Type A 応答 data の構造:
  #   NbTg(1) Tg(1) SENS_RES(2) SEL_RES(1) NFCIDLen(1) NFCID(NFCIDLen) [ATSLen ATS]
  # data[0]=NbTg, data[1]=Tg, data[2..3]=SENS_RES, data[4]=SEL_RES, data[5]=NFCIDLen
  def extract_typeA_uid(data)
    nfcid_len = data[5]
    raise ProtocolError, "invalid NFCID length: #{nfcid_len}" if nfcid_len.nil? || nfcid_len < 4 || nfcid_len > 10
    uid_bytes = data[6, nfcid_len]
    bytes_to_hex(uid_bytes)
  end

  def bytes_to_hex(bytes)
    bytes.map { |b| format("%02X", b) }.join
  end
end
