# 💻 Coding Standards & Gori Style Protocol

<!-- stack:kintone-gas:start -->
## 1. Kintoneカスタマイズにおける堅牢設計（Goriスタイル）

### 1.1 フィールド存在確認のガード処理 (Field Existence Guards)
* **概要**: Kintoneアプリのフィールド構成は管理者による変更や他環境での差異が発生する可能性があります。JSカスタマイズ内でフィールドにアクセスする際は、事前にフィールド自体が存在することを確認するガード処理を徹底します。
* **ルール**: 
  * `record` オブジェクトから値を参照する際は、必ずプロパティの有無を確認する。
  * `kintone.app.record.get()` やイベントオブジェクトの `event.record` で取得したフィールドに安全にアクセスするため、存在チェックを挟む。
* **例**:
  ```javascript
  // NG: フィールドが存在しない場合に TypeError となる
  const value = record.MyField.value;

  // OK: フィールドと value プロパティの存在をガード
  if (record.MyField && record.MyField.value !== undefined) {
      const value = record.MyField.value;
  }
  ```

### 1.2 Null / Undefined に対する安全対策 (Null-Safety)
* **概要**: APIから取得したレコードやCSVのパース結果などに予期しない `null` や `undefined` が含まれていても、プログラムが異常終了しないようにオプショナルチェイニングやデフォルト値の設定を行います。
* **ルール**:
  * 安全なプロパティアクセスには `?.` (オプショナルチェイニング) を活用する。
  * `null` または `undefined` の可能性がある値に対しては、論理和（`||`）やNull合体演算子（`??`）を用いてデフォルト値を保証する。
* **例**:
  ```javascript
  // オプショナルチェイニングとNull合体
  const userName = record.User?.value ?? '未設定';
  ```

### 1.3 Kintoneイベントハンドラ内の try-catch 例外設計
* **概要**: Kintoneの各種イベントハンドラ内で例外が発生すると、フォームの保存処理が意図せず中断したり、画面がフリーズしたりする原因になります。
* **ルール**:
  * イベントハンドラのトップレベル、または主要な処理ブロックは必ず `try-catch` で囲む。
  * `catch` ブロック内では、ユーザーにエラー内容を伝えるための適切なアラート表示、または診断用ログ（`console.error` など）への詳細出力を行い、例外を握り潰さない。
  * 保存イベント（`app.record.create.submit` や `app.record.index.edit.submit` など）の場合は、必要に応じて `return event;` で処理を継続するか、エラーメッセージを `event.error` に格納して保存を阻止する。
* **例**:
  ```javascript
  kintone.events.on('app.record.create.submit', function(event) {
      try {
          // 主要処理
          return event;
      } catch (error) {
          console.error('Submit Event Error:', error);
          event.error = '処理中にエラーが発生しました: ' + error.message;
          return event;
      }
  });
  ```

---
<!-- stack:kintone-gas:end -->

## 2. 追加的変更の原則 (Principles of Additive Change)

### 2.1 既存ロジックの破壊的書き換え禁止 (No Destructive Refactoring)
* **概要**: すでに安定稼働している本番コード（他媒体向けロジックや計算ロジック）を不要に大幅書き換え（リファクタリング）することは、想定外のデグレードを招くため原則禁止します。
* **ルール**:
  * 既存ロジックのロジックフロー自体を書き換えるのではなく、「条件分岐の追加」「新規関数の追加」による部分的な肉付け（追加的変更）で対応する。

### 2.2 影響を局所化するラッパー関数・拡張設計
* **概要**: 既存の共通関数やマッピング処理を拡張する際は、影響範囲がその変更対象のモールや機能だけに限定されるように設計します。
* **ルール**:
  * 既存の関数をラップして新しい条件を適用した関数を別途作成するか、引数によって安全に振る舞いを切り替えるように設計する。

### 2.3 変更マーカーコメントの付与規則
* **概要**: どのタスクで、いつ、どのような意図で追加・修正が行われたかをソースコード上で明示します。
* **ルール**:
  * 追加・修正箇所には必ず日付・種別つきのコメントを付与する。
  * **旧コードをコメントアウトした状態でファイル内に残すことは禁止**とする（履歴の保存はGitの役割であり、コード可読性を著しく下げるため）。
* **例**:
  ```javascript
  // [2026-07-02 ADD] BtoB不一致検知に伴うメール通知機能の追加
  function sendAlertMail() {
      // 新規処理...
  }
  ```
