# picoruby-book-lender

社員証 (Akerun カードなどの FeliCa/MIFARE IC カード) と書籍バーコードをスキャンして、社内の本貸出管理を行うシステム。

エッジ機 (Raspberry Pi Pico W + PicoRuby) で物理スキャンを担当し、軽量バックエンド (CRuby + Sinatra + SQLite) で永続化と Slack 通知を担う **二層構成**。

## 状態

開発中。設計フェーズ完了。実装はこれから。

## 全体構成

```
[社員証 + 本のバーコード]
        │
        ▼
┌─── エッジ機 (Pico W / PicoRuby) ───┐
│ PN532 (NFC) + GM65 (バーコード)    │
│ LED + ブザー                       │
└─────────────┬──────────────────────┘
              │ Wi-Fi / HTTPS
              ▼
┌─── バックエンド (Sinatra) ──────────┐
│ POST /lendings                      │
│ SQLite で貸出履歴永続化              │
│ cron: 期限切れ → Slack 通知          │
└─────────────┬───────────────────────┘
              │
              ▼
           Slack DM + チャンネルメンション
```

## 技術スタック

| レイヤ | 技術 |
| --- | --- |
| エッジ firmware | PicoRuby (R2P2-W) on Raspberry Pi Pico W |
| NFC ドライバ | 自作 mrbgem-pn532 (I2C, FeliCa IDm + MIFARE UID) |
| バーコード | GM65 モジュール (UART 接続) |
| 通信 | Wi-Fi → HTTP POST (X-API-Key 認証) |
| バックエンド | CRuby 3.3+, Sinatra, Sequel, SQLite |
| 通知 | slack-ruby-client (chat.postMessage) |
| エミュレータ | Wokwi (Pico W シミュレータ) + ホストビルド |

## このプロジェクトで何が新しいのか

- **PicoRuby から PN532 を直接叩いて FeliCa IDm を取得する mrbgem-pn532 の実装と公開**
- **Akerun 系社員証 (FeliCa) を社員 ID として運用する Ruby の OSS リファレンス**

業務貸出ロジックそのものは枯れた領域。新規性の核はドライバ層と統合パターンにある。詳細は [docs/superpowers/specs/2026-04-26-picoruby-book-lender-design.md](docs/superpowers/specs/2026-04-26-picoruby-book-lender-design.md) を参照。

## ハードウェア BOM (概算)

| 部品 | 用途 | 価格目安 |
| --- | --- | --- |
| Raspberry Pi Pico W | メイン MCU | ¥1,500 |
| PN532 NFC モジュール | NFC リーダ (I2C) | ¥2,000 |
| GM65 バーコードモジュール | バーコード読み取り (UART) | ¥3,000 |
| LED (緑/赤) + 抵抗 | フィードバック | ¥200 |
| 圧電ブザー | フィードバック | ¥200 |
| ジャンパワイヤ + ブレッドボード | 試作 | ¥1,000 |
| **合計** | | **¥8,000 前後** |

## ライセンス

MIT License — [LICENSE](LICENSE) 参照。

## ステータス追跡

実装は phase 単位で進める。各 phase の進捗は GitHub Issues / Projects で管理予定。

| Phase | 内容 | 状態 |
| --- | --- | --- |
| 0 | repo 初期化 + 設計書 | ✅ 完了 |
| 1a | mrbgem-pn532 (mock 上で実装 + 単体テスト) | 未着手 |
| 1b | Wokwi で I2C 結合 | 未着手 |
| 2 | firmware ロジック (Wokwi 完結) | 未着手 |
| 3 | バックエンド (Sinatra + SQLite + Slack) | 未着手 |
| 4 | 実機検証 (Akerun カード, 部品到着後) | 未着手 |
| 5 | 統合テスト + ドキュメント | 未着手 |
