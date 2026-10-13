# アイキャッチ用アバター画像仕様

> ※アイキャッチ画像の生成時のみロードしてください。note本文執筆時には不要です。

## 参照画像と個人設定

- `config/user_profile.yaml` の `avatar.reference_image` を読み込み、存在する場合は画像生成ツールの参照画像に指定する。`avatar.head_image` は必要に応じて追加する。画像がなければ本人の容姿を推測して生成せず、ユーザーに参照画像を確認する。
- `avatar.appearance`、`avatar.vehicle`、`avatar.scene_constraints` を、その日の場面に該当する場合だけ適用する。顔の特徴をプロンプト本文で作り直さず、参照画像で維持する。
- `avatar.reference_gallery` が存在する場合は、直近の完成画像を見て画風を確認する。なければ参照画像を基準にする。生成結果の差異はユーザーに伝える。
- アスペクト比は `16:9`。出力後、参照画像が実際に指定されていたか確認する。

## 📐 文字なし構図の3原則（No-Text Composition Principles）

noteのアイキャッチ画像は**タイトル文字のオーバーレイを行わない「文字なし」の1枚絵**として仕上げる。単調な日の丸構図や不自然な空白を防ぎ、映画のワンシーンのような情感と完成度を生み出すため、以下の3原則を厳守すること。

1. **余白を空気感・環境で埋める（Atmospheric Negative Space）**:
   - 文字スペース用の「何もない空虚な空間」を作らない。
   - 余白部分は、差し込む自然光（斜光・木漏れ日・ゴールデンアワーの逆光）、天候（雨の波紋・霧・青空の雲）、街並みのディテール、室内の空気感・グラデーションで美しく満たす。
2. **三分割法の交点に主要要素（Rule of Thirds Alignment）**:
   - アバターや主要オブジェクトを画面中央（ど真ん中）に配置せず、画面を縦横3分割した交点（左右どちらか1/3のライン）に寄せて配置する。
   - 画面に自然な緊張感と物語性が生まれ、プロフェッショナルなシネマティック感が出る。
3. **視線の抜け・導線（Leading Lines & Visual Breathing Room）**:
   - キャラクターの視線方向や進行方向の側に広い空間（抜け）を確保する（窮屈に壁や端で塞がない）。
   - 道路、線路、電線、手すり、街路樹、建物のパースペクティブなどの「消失線（リーディングライン）」を意識し、視線が奥へと引き込まれる奥行きを設計する。

---

## 🎬 シチュエーション別・構図テンプレートカタログ（Composition Library）

日記本文の内容（移動手段、休憩、作業、心理描写など）を読み解き、その日のストーリーに最も適した構図を以下から1つ選定してプロンプトへ組み込む。

### 1. 日常・ドラマシーン構図（Daily Life & Solitude）
- **ベンチ横並び（Bench Companion / Solitary Bench）**:
  - *用途*: 公園・駅・街頭での休憩、思索、会話、一息つく場面。
  - *アングル*: ベンチのやや斜め横から捉えるミドルショット。アバターを片側の三分割線上に配置し、隣の空いた座面や置かれた荷物、足元に伸びる影、背景に広がる木々や街路をボケ味とともに捉える。
- **足元・手元クローズ（Detail & Action Close-Up）**:
  - *用途*: 作業、飲食、思考の深まり、歩行の感覚を強調したい場面。
  - *アングル*: 手元の淹れたてコーヒーとスマホ、キーボードを叩く手、歩道を歩くスニーカーの足元とアスファルトの質感などを強調するクローズアップ。全身を無理に画面に入れず、所作の情緒を切り取る。
- **曲がり角・路地の遭遇（Street Corner / Alleyway Turn）**:
  - *用途*: 街歩き、散歩、予期せぬ発見、移動中のふとした瞬間。
  - *アングル*: 路地やビルの角を曲がろうとするアバターの後ろ姿〜斜め横姿。建物の深い影と、角の向こうから差し込む明るい日差しのコントラストで奥行きを作る。
- **カフェ・デスクサイド（Window Table Silhouette）**:
  - *用途*: カフェでの執筆・作業・内省の日記。
  - *アングル*: 窓際席に座るアバターを室内側から斜めに捉えるアングル。大きなガラス窓越しに外の街並みが見え、窓から差し込む自然光がアバターの輪郭を照らす。

### 2. 乗り物・移動シーン構図（Transit & Commute）
- **向かい合い座席（Train Opposite Seat / Window Vista）**:
  - *用途*: 電車・特急・新幹線・地下鉄での移動、旅情、考え事。
  - *アングル*: 対面の座席からアバターを眺める一人称ライクな視点。車窓を流れる街や田園の風景、窓ガラスへのほのかな映り込み、車内に差し込む光の筋を配置する。
- **つり革・立ち姿（Subway Commute Stance）**:
  - *用途*: 通勤、移動の混雑、都会の日常。
  - *アングル*: 電車の通路に立ち、つり革を掴んで車窓や前を見つめるアバター。奥へと連なるつり革と座席の遠近法（ワンポイントパース）を活かし、三分割ライン上に配置。
- **ホーム見送り・プラットフォーム（Station Platform Vista）**:
  - *用途*: 駅での別れ、待ち合わせ、一日の終わり、移動の節目。
  - *アングル*: プラットフォームの端に佇むアバター。遠ざかる列車のテールランプや、まっすぐ奥へ伸びる線路の消失点と、夕暮れ・夜のホーム照明によるドラマチックな光。

### 3. 乗り物・ツーリング構図（Vehicle Action）
- **斜め前方疾走（Front Three-Quarter Action - 疾走感重視）**:
  - *用途*: バイクで走った日、ツーリング、爽快感。
  - *アングル*: **斜め前〜正面寄り（Front three-quarter / Dynamic forward-facing perspective）**。`avatar.vehicle` に指定した乗り物と人物を斜め前から捉える。乗車時の装備は実際の安全条件に合わせ、背景の流し（Motion Blur）で移動感を出す。

---

## 📝 構図を反映したプロンプト設計ガイド（顔描写完全排除の徹底）

構図テンプレートを選択したら、`generate_image` の `Prompt` に落とし込む。その際、**「参照画像を設定し、言葉で顔を作り直さない」核心ルール**を厳格に適用すること。

### ⭕ 成功例（構図・光・背景のみを指示する）
```text
Cinematic 16:9 composition, wide shot. A character from the provided reference image sits on a wooden park bench located along the right third of the frame. Golden hour sunlight streaming through autumn trees, casting long diagonal shadows on the cobblestone path. Atmospheric negative space on the left showing a tranquil park path vanishing into the soft-focus background. Photorealistic lighting, rich textures, cinematic mood, 8k resolution, no text.
```
- 個人の顔の特徴には一切触れていない。
- 三分割法（right third）、光の方向（golden hour streaming through autumn trees）、余白の空気感（tranquil park path vanishing...）、構図全体のトーンのみを指定。

### ❌ 失敗例（顔を言葉で描写してしまい破綻する）
```text
A character with invented facial features and clothing sitting on a bench...
```
- 言葉で顔やキャラクターをゼロから指示しているため、モデルが勝手に解釈して参照画像と異なる顔を生成してしまう。

## 💾 生成画像の自動エクスポート（ダウンロードフォルダ自動配置）

アイキャッチ画像を生成（または再生成）した際は、**必ず直後に以下の命名規則でユーザーのダウンロードフォルダへ自動コピーすること**。

- **保存先パス**: `~/Downloads/<YYYYMMDD>_eyecatch.jpg`（日付は日記の日付、例: `20260917_eyecatch.jpg`）
- **手順**: `generate_image` で生成された artifact の画像ファイルを、直ちに `cp` コマンド等で `~/Downloads/<YYYYMMDD>_eyecatch.jpg` へコピーして配置する。
- ユーザーに確認を求める際も、「ダウンロードフォルダ（`~/Downloads/<YYYYMMDD>_eyecatch.jpg`）に保存済みであること」を案内する。
