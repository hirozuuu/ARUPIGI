# ARUPIGI

草原を歩き、町で休み、岩の洞へ。Godot 4.6向けの小さな手描き風RPGプロトタイプです。

## 遊ぶ

`project.godot` をGodot **4.6.x**で開き、初回インポートが終わってから **F5**でプロジェクトを実行してください。起動すると野原からすぐに探索を開始します。レンダラーはGL Compatibilityです。

現段階ではWindows向けビルドの作成・テストは実施しません。将来Windowsビルドを作成する段階で、書き出しと書き出した実行ファイルの検証を実施します。

| キー | 操作 |
| --- | --- |
| WASD / 矢印 | 探索・戦闘中の移動。戦闘のコマンド選択中と会話の選択肢では上／下で選ぶ |
| Enter / テンキーEnter | 向いている近くのNPCと話す、会話を進める、選択肢を決定する、戦闘の最終結果から探索へ戻る |
| Esc | 探索メニューを開く／閉じる。会話中は無効 |

開始地点から左上にある屋根の印が町です。町では北に進むと回復の泉、南の矢印を踏むと野原に戻れます。洞窟は開始地点の右上にある岩の印です。野原と洞窟では歩いた距離に応じて敵が出現します。戦闘中のEscは無効です。

野原と町のNPCに話しかけられます。相手の近くで向きを合わせると「Enter 話す」の案内が出ます。会話中は移動と遭遇が止まり、本文は最大2行ずつ表示されます。NPC名・ページ数・通常会話中の次へ案内は表示されません。選択肢は上下キーで選び、Enterで決定します。

戦闘はフィールドの上に重なり、主人公はコマンド選択中・途中メッセージ中・結果表示中も枠内を歩けます。敵と枠の線には足元の当たり判定で止まりますが、背景の地形は戦闘中の移動を妨げません。上／下は押したときに選択を1回切り替え、押し続けると移動だけを続けます。

「にげる」を決定すると1.3秒間、外枠の線と当たり判定が消えます。その間に主人公の画像全体が上下左右いずれかの枠外へ出れば、確率判定なしで逃走成功です。敵の当たり判定は残ります。時間切れでは枠をまたいだ主人公を枠内へ戻して外枠を復活させ、敵の反撃を1回受けます。HPが残っていれば直ちに次のコマンドを選べます。逃走成功時も外枠は復活し、結果をEnterで閉じると探索へ戻ります。

画面は960×640の比率を保って拡縮し、ウィンドウの縦横比が異なる場合は余白を設けます。戦闘枠と敵は正方形を維持し、敵名は主人公に重ならない枠外の右上に表示します。

勝利・逃走時は結果をEnterで閉じた時点の位置とHPを引き継ぎます。敗北すると町で全回復します。途中メッセージは自動進行し、最終結果だけEnterで進めます。決定は一度キーを離してから押してください。戦闘中に山・壁・マップ外へ移動して終了した場合も座標は補正されず、探索再開後に通常の地形衝突が働きます。

勝利・逃走でフィールドへ戻った瞬間はカメラ位置を保ちます。主人公がフィールドを歩くとカメラが徐々に通常の追従位置へ戻り、立ち止まっている間はその位置に留まります。

セーブはありません。ゲームを終了して再実行するとHP・位置・遭遇距離が初期化されます。メニューの「ゲームに戻る」またはEscで探索を再開できます。音声、経験値、アイテムなどは今回の範囲外です。

## 開発・検証

エージェント向けの作業案内は [AGENTS.md](AGENTS.md) にあります。変更箇所、検証の選び方、このPCの環境上の注意点をまとめています。

PowerShellをプロジェクトのフォルダーで開きます。このPCでは `godot.exe` は旧版4.4.1のため、4.6.2のパスを明示します。別のPCでは `$godotExe` を変更してください。

```powershell
$godotExe = 'C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force build | Out-Null
& $godotExe --headless --path . --log-file ./build/import.log --editor --quit
& $godotExe --headless --path . --log-file ./build/logic.log --script res://tests/logic_test.gd
& $godotExe --headless --path . --log-file ./build/dialogue.log --script res://tests/dialogue_test.gd
& $godotExe --headless --path . --log-file ./build/integration.log --script res://tests/integration_test.gd
& $godotExe --headless --path . --log-file ./build/map-editor-test.log --script res://tests/map_editor_test.gd
& $godotExe --headless --path . --log-file ./build/map-editor-plugin.log --editor --script res://tests/map_editor_plugin_test.gd
& $godotExe --path . --log-file ./build/render.log --script res://tests/render_smoke.gd
& $godotExe --path . --log-file ./build/dialogue-render.log --script res://tests/dialogue_render_test.gd
```

`render_smoke.gd` は実際のGPU描画を使い、戦闘と会話の各状態を含む25画面を `build/screenshots/` に保存します。ウィンドウサイズの変更はOS側で画面の大きさに制限される場合があります。`--headless` は付けません。撮影スクリプトは押下・保持・リピートの入力イベントも確認します。

`dialogue_render_test.gd` はOSのウィンドウ制限に関係なく、共通の会話UIを720×480、1200×700、720×900の正確な寸法でオフスクリーン描画します。

## 将来Windowsビルドを作成する際の手順（現段階では実施しない）

この節は将来用の手順です。現段階の開発・完了条件にはWindowsビルドの作成、埋め込みパックの統合・描画検証、実行ファイルの起動・操作確認を含めません。Windowsビルドを作成する段階になったら、以下の作成・検証を一通り実施してください。

Godotと同じバージョンのWindowsエクスポートテンプレートが必要です。エディタの「プロジェクト → エクスポート → Windows Desktop」または次のコマンドで作成できます。起動中のARUPIGIを先に閉じてください。

```powershell
& $godotExe --headless --path . --log-file ./build/export.log --export-release 'Windows Desktop' ./build/ARUPIGI.exe
```

作成後は実行ファイルに埋め込まれたデータを検証します。

```powershell
$integrationScript = Join-Path (Get-Location) 'tests/integration_test.gd'
& $godotExe --headless --main-pack ./build/ARUPIGI.exe --log-file ./build/packed-integration.log --script $integrationScript
```

書き出しパックの描画も確認します。`--script` に `tests/render_smoke.gd` の絶対パスを渡し、`--headless` を外します。出力先の絶対パスを末尾の `--` の後に指定できます。

```powershell
$renderScript = Join-Path (Get-Location) 'tests/render_smoke.gd'
$captureDirectory = Join-Path (Get-Location) 'build/packed-screenshots'
& $godotExe --main-pack ./build/ARUPIGI.exe --log-file ./build/packed-render.log --script $renderScript -- $captureDirectory
```

最後に `build/ARUPIGI.exe` をWindowsアプリとして起動し、開始・探索・メニューなどの入力と表示を確認します。ゲームデータは実行ファイルに含まれます。

`build/` と `.godot/` は生成物のためGit管理対象外です。現段階ではソースからチェックアウトした場合もWindows実行ファイルの生成は不要です。

## 調整する場所

| ファイル | 内容 |
| --- | --- |
| `data/config.tres` / `scripts/data/game_config.gd` | HP、攻撃、移動速度、遭遇確率、安全距離、逃走制限時間（`escape_seconds`）、演出時間。省略した値はスクリプトの既定値を使用 |
| `data/maps/*.tres` | 固定マップ、文字ごとの地形、出現位置、出入口、回復地点、敵候補、NPCと会話 |
| `data/terrains/*.tres` | 地形の素材と通行可否 |
| `data/enemies/*.tres` | 敵の名前・HP・攻撃範囲・素材 |
| `assets/art/*.svg` | 独自の地形・旅人・敵・目印 |
| `assets/fonts/ui_font.tres` | Noto Sans JPのウェイト500設定 |
| `scripts/game_ui.gd` | 各画面のレイアウト、色、文言 |

マップの座標は0始まりのセル座標です。`rows` の各文字を `terrains` の定義に対応させ、`width` × `height` に合わせます。出現位置は出入口のセル外に置き、歩ける地形で接続してください。変更後は統合検証を実行してください。

状態遷移は `scripts/main.gd`、探索は `exploration.gd`・`map_controller.gd`・`player.gd`、戦闘枠と敵の表示・衝突は `battle_arena.gd`、進行データは `game_session.gd`、遭遇は `encounter_controller.gd`、戦闘解決は `battle_model.gd` に分離しています。マップ・敵固有の値はResourceで定義します。

Noto Sans JPの再配布ライセンスは `assets/fonts/OFL.txt`、独自SVGの説明は `assets/art/README.md` にあります。詳細は [初期実装計画](docs/implementation-plan.md)、[戦闘表示の実装計画](docs/battle-overlay-implementation-plan.md)、[検証記録](docs/verification.md) を参照してください。

Godot上部の **マップ** から既存マップの地形とNPCを編集できます。NPCの画像・色・本文・選択肢・分岐と、会話プレビューを扱えます。NPCは自動生成されるIDで一覧表示します。Undo／Redo、保存、素材追加、検証、未保存データの復旧に対応しています。[操作ガイド](docs/map-editor-guide.md)、[NPC会話の実装計画](docs/npc-dialogue-implementation-plan.md)、[検証記録](docs/map-editor-verification.md) を参照してください。
