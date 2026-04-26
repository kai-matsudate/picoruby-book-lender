# mrbgem-pn532

PicoRuby/mruby から PN532 NFC リーダを I2C 経由で操作する薄いドライバ。

## サポート機能 (v0.1)

- `GetFirmwareVersion`: 接続確認
- `InListPassiveTarget` 106 kbps Type A: MIFARE 系 UID
- `InListPassiveTarget` 212 kbps FeliCa: IDm (Akerun 系社員証はこちら)

書き込み・暗号認証・MIFARE Classic の Authenticate などは対象外。

## 使い方

```ruby
require "pn532"

i2c = I2C.new(0, sda: 4, scl: 5) # PicoRuby/R2P2 の API に従う
reader = PN532.new(i2c: i2c, addr: 0x24)

p reader.firmware_version
# => {ic: 0x32, ver: 0x01, rev: 0x06, support: 0x07}

if (idm = reader.poll_felica(timeout_ms: 1000))
  puts "FeliCa IDm: #{idm}"
elsif (uid = reader.poll_typeA(timeout_ms: 1000))
  puts "MIFARE UID: #{uid}"
else
  puts "no card"
end
```

## ホストでテストを回す

```bash
cd mrbgems/mrbgem-pn532
bundle install
bundle exec rake test
```

## 配置と切り出し計画

当面は `picoruby-book-lender/mrbgems/mrbgem-pn532/` に内包する。API が安定したら独立 repo `kai-matsudate/mrbgem-pn532` に切り出す予定 (設計書 §4.1)。

## 参考資料

- [NXP UM0701-02 PN532 User Manual](https://www.nxp.com/docs/en/user-guide/141520.pdf)
- [Adafruit_PN532](https://github.com/adafruit/Adafruit-PN532)
