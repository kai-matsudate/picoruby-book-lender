# picoruby-book-lender 設計仕様書

| 項目 | 内容 |
| --- | --- |
| 作成日 | 2026-04-26 |
| 作成者 | Kai Matsudate |
| 状態 | Draft (実装着手前) |

## 1. 目的とゴール

### 1.1 業務的ゴール

社内の書籍 (技術書・業務書籍) を、社員が物理的にスキャンするだけで貸出・返却できるようにする。返却期限を過ぎた利用者には Slack で能動的に通知する。

### 1.2 技術的ゴール

PicoRuby/mruby エコシステムに対する OSS 貢献として、PN532 NFC リーダのドライバ mrbgem (`mrbgem-pn532`) を実装・公開する。Akerun 系社員証 (FeliCa) を社員 ID として運用する Ruby のリファレンス実装を残す。

### 1.3 非ゴール

- 高度な蔵書管理 (ジャンル別検索、レコメンド、評価) は対象外。
- Web 管理画面は v1 では作らない。
- マルチテナント対応はしない。1 社内 1 インスタンス前提。

## 2. 制約と前提

- 利用者の本人特定は **既存の社員証 (Akerun に紐づく FeliCa/MIFARE IC カード)** で行う。新たに別カードを発行することはしない。
- カードから取得できるのは IDm (FeliCa, 8 byte) または UID (MIFARE TypeA, 4-10 byte) のみ。社員番号などはカード表面から得られないため、**事前に IDm/UID と社員 ID のマッピングを管理する必要がある**。Akerun API はカード番号を公開していないため、自前で初回登録するしかない。
- 通知先は Slack。Bot Token (`SLACK_BOT_TOKEN`) で `chat.postMessage` を叩く。
- 対象企業は本リポジトリの開発者所属企業 (1 拠点) を想定。スケーラビリティは要件外。
- 個人情報を含むマスタデータ (`users.yml`, `books.yml`) は public repo にコミットしない。`*.example.yml` のみを管理する。

## 3. アーキテクチャ

### 3.1 全体図

```
                ┌─────────────────────────┐
                │ エッジ機 (Pico W)        │
                │ ┌─────────────────────┐ │
                │ │ PicoRuby firmware   │ │
                │ │  - main loop        │ │
                │ │  - state machine    │ │
                │ └──┬─────────────────┬┘ │
                │    │ I2C             │UART
                │ ┌──▼──────┐    ┌────▼───┐
                │ │ PN532   │    │ GM65   │
                │ │ (NFC)   │    │ (BC)   │
                │ └─────────┘    └────────┘
                │      LED / ブザー         │
                └────────────┬─────────────┘
                             │ HTTPS POST (Wi-Fi)
                             │ X-API-Key ヘッダ
                             ▼
                ┌─────────────────────────┐
                │ バックエンド (Sinatra)   │
                │  POST /lendings         │
                │  - decide check-out/in  │
                │  - persist SQLite       │
                │  - 200 OK + メッセージ  │
                │                         │
                │ Cron (毎朝 09:00 JST)    │
                │  - 期限切れ抽出          │
                │  - Slack DM + ch メンション│
                └────────────┬─────────────┘
                             │ Slack Web API
                             ▼
                          Slack
```

### 3.2 関心の分離

| 層 | 役割 | 技術 |
| --- | --- | --- |
| エッジ (物理層) | センサ I/O, LED/ブザーフィードバック, Wi-Fi 送信 | Pico W + PicoRuby |
| バックエンド (業務層) | 永続化, 業務判断 (借りる/返す/期限切れ), 通知 | CRuby + Sinatra |
| 通知層 | Slack DM とチャンネルメンション | Slack Web API |

二層に分ける理由は次の 3 点:

1. Pico W のリソース制約 (RAM 264KB) では SQLite + 業務ロジック保持が現実的でない。
2. 業務ロジックの単体テストを CRuby で書く方が圧倒的に早い。
3. 期限切れ判定の cron は Linux 上で動かす方が枯れている。

## 4. コンポーネント詳細

### 4.1 mrbgem-pn532

#### 目的

PicoRuby から PN532 を I2C 経由で叩き、FeliCa IDm / MIFARE UID を返す薄いドライバ。

#### Public API (案)

```ruby
reader = PN532.new(i2c: I2C.new(0, sda: 4, scl: 5), addr: 0x24)
reader.firmware_version  # => {ic: 0x32, ver: 0x01, rev: 0x06, support: 0x07}

# FeliCa IDm を返す。タイムアウト時は nil
idm = reader.poll_felica(timeout_ms: 1000)
# => "0123456789ABCDEF"

# MIFARE Type A UID を返す。タイムアウト時は nil
uid = reader.poll_typeA(timeout_ms: 1000)
# => "04A1B2C3D4"
```

#### 内部実装方針

- I2C は PicoRuby/R2P2 標準の `I2C` クラスを利用。具体的な gem 名は実装着手時に確認。
- 通信プロトコルは NXP UM0701-02 (PN532 User Manual) と Sony/NFC Forum の FeliCa 仕様書に準拠。
- 主に使うコマンドは `GetFirmwareVersion (0x02)`, `InListPassiveTarget (0x4A)`。
- フレーム CRC, ACK 待ち, IRQ ピンの扱い (オプション) を実装。

#### 配置

当面 `picoruby-book-lender/mrbgems/mrbgem-pn532/` 配下に内包する。実装が安定し API が固まった段階で、独立 repo `kai-matsudate/mrbgem-pn532` として切り出す。

切り出しを後回しにする理由は、submodule や `path:` 指定の取り回しが初期開発体験を悪化させるため。

#### テスト戦略

- mock I2C バスを用意し、PN532 仕様書ベースの応答を返すスタブを書く。
- 単体テストはホスト上 (mruby ホストビルド) で完結させ、GitHub Actions で CI を回す。
- 実機検証は Phase 4 で実施。

### 4.2 firmware (Pico W / PicoRuby)

#### メインループの状態機械

```
        ┌──────────────────────────────────┐
        │           idle                   │
        │  (NFC を 1 Hz でポーリング)        │
        └────────────────┬─────────────────┘
                         │ idm 検知
                         ▼
        ┌──────────────────────────────────┐
        │        wait_book                 │
        │  LED 緑、ブザー 1 短音、           │
        │  10 秒以内に GM65 で本を要求       │
        └────┬───────────────────────┬─────┘
             │ ISBN/JAN 受信         │ 10 秒タイムアウト
             ▼                       ▼
        ┌─────────┐              ┌────────┐
        │ submit  │              │ error  │
        │ HTTP    │              │ LED 赤 │
        │ POST    │              └───┬────┘
        └────┬────┘                  │
             │ 結果                  │
             ▼                       ▼
        ┌──────────┐            ┌─────────┐
        │ feedback │            │  idle   │
        │ LED 緑/赤│            └─────────┘
        │ ブザー   │
        └────┬─────┘
             ▼
        ┌─────────┐
        │  idle   │
        └─────────┘
```

#### Wi-Fi/HTTP の取り扱い

- 起動時に Wi-Fi 接続。失敗時は LED 赤点滅で人間に知らせる。
- HTTP POST は同期。タイムアウト 5 秒。失敗時は LED 赤、ブザーエラー音で idle 復帰。
- v1 ではローカルキューを持たない (オフライン時はスキャンを断る)。

### 4.3 backend (CRuby + Sinatra)

#### スタック

`ruby 3.3+`, `sinatra`, `sequel`, `sqlite3`, `slack-ruby-client`, `dotenv`, `rspec`

#### API 仕様

```
POST /lendings
  headers:
    X-API-Key: <token>
    Content-Type: application/json
  body:
    {
      "idm": "0123456789ABCDEF",
      "code": "9784873117027",
      "scanned_at": "2026-04-26T12:34:56+09:00"
    }

  Response 200 OK:
    {
      "action": "checkout" | "return",
      "message": "「Ruby のしくみ」を貸出しました",
      "due_at": "2026-05-10T23:59:59+09:00"  // checkout 時のみ
    }

  Response 4xx:
    {
      "error_code": "unknown_user" | "unknown_book" | "already_lent_to_other" | ...,
      "message": "..."
    }
```

#### 業務判定 (借りる / 返す)

```
POST /lendings 受信
  ↓
idm → user 解決 (失敗で 404 unknown_user)
code → book 解決 (失敗で 404 unknown_book)
  ↓
SELECT lendings WHERE book_id = ? AND returned_at IS NULL
  ↓
  ├─ あり、かつ borrower = user
  │   → returned_at = now で UPDATE → action: return
  │
  ├─ あり、かつ borrower != user
  │   → 409 already_lent_to_other (本は他の人が借りている状態)
  │
  └─ なし
      → INSERT lending(user, book, lent_at=now, due_at=now+14d)
      → action: checkout
```

#### マスタデータ

- `backend/config/users.yml` (gitignore)
  ```yaml
  - idm: "0123456789ABCDEF"
    employee_id: E001
    name: 山田太郎
    slack_user_id: U01ABCDEF
  ```
- `backend/config/books.yml` (gitignore)
  ```yaml
  - code: "9784873117027"
    isbn: "978-4-87311-702-7"
    title: Ruby のしくみ
    author: Pat Shaughnessy
  ```
- `*.example.yml` のみ git 管理。

### 4.4 Slack 通知

#### 認証

- Slack App を作成し、Bot User OAuth Token (`xoxb-...`) を `SLACK_BOT_TOKEN` 環境変数に設定。
- 必要スコープ: `chat:write`, `users:read`, `im:write`。

#### 通知ロジック (`bin/notify_overdue`)

```ruby
# 擬似コード
overdue = Lending
  .where(returned_at: nil)
  .where(Sequel.lit('due_at < ?', Time.now))
  .where(notified_at: nil)  # 1日に複数回送らない

overdue.each do |l|
  user = User.find_by_employee_id(l.employee_id)
  text = "「#{l.book.title}」 の返却期限を過ぎています。返却をお願いします (期限: #{l.due_at})"

  # DM
  Slack.chat_postMessage(channel: user.slack_user_id, text:)

  # 共有チャンネル
  Slack.chat_postMessage(
    channel: '#books-overdue',
    text: "<@#{user.slack_user_id}> #{text}"
  )

  l.update(notified_at: Time.now)
end
```

cron で `0 9 * * *` (毎朝 09:00 JST) に実行する。

## 5. データモデル

```sql
-- backend/db/migrate/20260426_create_lendings.sql 相当

CREATE TABLE lendings (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id TEXT NOT NULL,
  book_code   TEXT NOT NULL,
  lent_at     DATETIME NOT NULL,
  due_at      DATETIME NOT NULL,
  returned_at DATETIME,
  notified_at DATETIME,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lendings_book_active
  ON lendings(book_code) WHERE returned_at IS NULL;

CREATE INDEX idx_lendings_overdue
  ON lendings(due_at) WHERE returned_at IS NULL;
```

`users` と `books` は YAML から起動時にメモリにロードし、SQL では join しない。マスタの規模 (社員数百〜千、書籍数百) であれば全量メモリ展開で十分。

## 6. データフロー

### 6.1 借りる場合

```
1. 利用者が社員証を Pico W にタップ
2. PN532 が IDm を返す → state=wait_book、LED 緑、ブザー beep
3. 利用者が本のバーコードを GM65 に読ませる
4. firmware が POST /lendings (idm, code) を backend に送信
5. backend: アクティブな貸出が無い → 新規 lending を作成
6. 200 + {action: "checkout", message: "「Ruby のしくみ」を貸出しました", due_at: ...}
7. firmware: LED 緑 1 秒、ブザー成功音 → idle 復帰
```

### 6.2 返す場合

```
1〜4 は同じ
5. backend: 同じ employee × book でアクティブな貸出あり → returned_at をセット
6. 200 + {action: "return", message: "「Ruby のしくみ」を返却しました"}
7. firmware: 同じく成功音 → idle 復帰
```

### 6.3 期限切れ通知

```
毎朝 09:00 JST
1. cron: bin/notify_overdue
2. due_at < now AND returned_at IS NULL AND notified_at IS NULL を抽出
3. 各 lending について DM とチャンネルメンションを送信
4. notified_at をセット
```

## 7. エラーハンドリング

| 状況 | エッジ反応 | backend 反応 |
| --- | --- | --- |
| 不明な IDm (マスタ未登録) | LED 赤 1.5 秒、エラー音 | 404 unknown_user |
| 不明な book code | LED 赤 1.5 秒、エラー音 | 404 unknown_book |
| 既に他人が借りている本 | LED 赤 1.5 秒、エラー音 | 409 already_lent_to_other |
| Wi-Fi 切れ | LED 赤点滅 | — |
| 認証エラー (X-API-Key 不一致) | LED 赤 | 401 |
| backend タイムアウト (5秒) | LED 赤、エラー音 | — |
| カードのみタップ後 10 秒沈黙 | LED 赤、idle 復帰 | — |

## 8. テスト戦略

| レベル | 対象 | 手段 |
| --- | --- | --- |
| 単体 | `mrbgem-pn532` の I2C プロトコル処理 | mock I2C, mruby ホストビルド, GitHub Actions CI |
| 単体 | backend の業務ロジック (借りる/返す判定) | RSpec |
| 統合 | backend の HTTP API | RSpec request spec |
| シミュレータ | firmware ロジック全体 | Wokwi (Pico W シミュレータ) |
| 実機 E2E | Akerun カード + 実 PN532 + 実 GM65 + 実 Slack | 手動シナリオ |

## 9. リポジトリ構成

```
picoruby-book-lender/
├── README.md
├── LICENSE
├── .gitignore
├── docs/
│   ├── superpowers/specs/        # 設計スペック (このファイル等)
│   ├── ARCHITECTURE.md           # 後で追加
│   ├── HARDWARE.md               # 配線図, BOM, 写真
│   └── EMULATOR.md               # Wokwi 手順
├── firmware/                     # PicoRuby エッジ
│   ├── build_config.rb
│   ├── src/
│   │   └── main.rb
│   └── test/
├── mrbgems/
│   └── mrbgem-pn532/             # 自作ドライバ (将来切り出し)
│       ├── mrbgem.rake
│       ├── src/
│       └── test/
├── backend/                      # CRuby + Sinatra
│   ├── Gemfile
│   ├── config.ru
│   ├── app.rb
│   ├── config/
│   │   ├── users.example.yml
│   │   └── books.example.yml
│   ├── db/
│   │   └── migrate/
│   ├── lib/
│   ├── bin/
│   │   └── notify_overdue
│   └── spec/
└── wokwi.toml                    # Pico W シミュレータ設定
```

## 10. フェーズ計画

| Phase | 内容 | 工数 (h) |
| --- | --- | --- |
| 0 | repo 初期化 + 設計書 | 1 |
| 1a | mrbgem-pn532 (mock 上で実装 + 単体テスト) | 8-10 |
| 1b | Wokwi で I2C 結合 | 2-3 |
| 2 | firmware ロジック (Wokwi 完結) | 6-8 |
| 3 | backend (Sinatra + SQLite + Slack) | 6-8 |
| 4 | 実機検証 (Akerun カード, 部品到着後) | 4-6 |
| 5 | 統合テスト + ドキュメント | 4-6 |
| **合計** | | **31-42** |

カレンダー上は週末メイン + 平日少しずつで 3-5 週間想定。

## 11. 主要意思決定の経緯と却下案

ブレインストーミング中に検討して却下した案を残す。判断の根拠を後から追えるようにするため。

| 検討案 | 採用しなかった理由 |
| --- | --- |
| RPi 4B + USB カメラで barcode と社員証両方をスキャン | Akerun カードはカメラで読めない (NFC のため)。前提が崩れた |
| RPi 4B + mruby + Python(nfcpy) サブプロセス | RPi 4 上で mruby を選ぶ意義が薄い (RAM/起動時間が制約にならない)。RubyKaigi 2026 のトレンドからも RPi + mruby は本流外 |
| ESP32 + PicoRuby | Pico W で十分。ESP32 を使うほどの理由 (Bluetooth, より多くの GPIO) は当面の要件にない |
| CRuby on RPi 単体で全部やる | 「PicoRuby を使う」という当初の動機を全否定するためボツ。ただし新規性を捨てる選択肢として記録は残す |
| 最初から mrbgem-pn532 を別 repo | 初期の開発体験悪化 (submodule, path: gem) と引き換えにするほどのメリットがない。安定後に切り出す |
| 通知先を Microsoft Teams や メール | ユーザの利用環境が Slack のため不採用 |

## 12. 既知の制限・将来課題

- v1 ではエッジ機がオフライン時のスキャンを受け付けない (queue 化なし)。Wi-Fi 不安定環境では運用に影響あり。
- マスタデータの更新は YAML 編集 + サーバ再起動が必要。Web 管理画面は v2 以降。
- 同一書籍を複数冊持つ運用 (book_code が重複) は未対応。各冊にユニークな運用バーコードを貼る前提とするか、book_id を付与するかは v2 で検討。
- 期限切れの「再通知」は notified_at で 1 度だけ抑制している。N 日経過したら再通知する仕様は v2 で検討。
- `mrbgem-pn532` は当面 FeliCa Polling と MIFARE TypeA UID 取得のみ。書き込み・暗号認証は対象外。

## 13. 参考資料

- [Akerun NFC リーダーに対応するカード/スマートフォン一覧](https://support.akerun.com/hc/ja/articles/222186107)
- [Akerun Developers](https://developers.akerun.com/)
- [PN532 User Manual (NXP UM0701-02)](https://www.nxp.com/docs/en/user-guide/141520.pdf)
- [RubyKaigi 2026 PicoRuby for IoT (Yuhei Okazaki)](https://rubykaigi.org/2026/presentations/Y_uuu.html)
- [RubyKaigi 2026 Uzumibi (udzura)](https://rubykaigi.org/2026/presentations/udzura.html)
- [Adafruit_PN532 (Arduino C++ 参照実装)](https://github.com/adafruit/Adafruit-PN532)
- [Wokwi Pico W シミュレータ](https://wokwi.com/projects/new/pi-pico-w)
