# マップタイルエディタ検証記録

確認日：2026-09-08。Godot `4.6.2.stable.official.71f334935`、Windows、GL Compatibility / NVIDIA GeForce RTX 5070 Ti。

## 実装範囲

[実装計画](map-editor-implementation-plan.md) の段階1〜6に対応するプラグイン、作業データ、履歴、検証、保存、素材追加、操作ガイドを実装した。ゲーム本体と同じ `MapData` / `TerrainData` を使用し、Resourceのコンテナーだけを分離する。データクラスはエディタでも動作するよう `@tool` とした。

履歴は専用 `UndoRedo`、保存は `ResourceSaver` で一時ファイルへ書き出し・再読み込み照合後、同じディレクトリーで置き換える。Windows上で既存ファイルへの置き換えと繰り返し保存を確認した。比較用ハッシュ、元のUID、地形と敵の外部Resourceパスを維持する。

## 実行方法

```powershell
$godotExe = 'C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe'
& $godotExe --headless --path . --log-file ./build/map-editor-import.log --editor --quit
& $godotExe --headless --path . --log-file ./build/map-editor-test.log --script res://tests/map_editor_test.gd
& $godotExe --headless --path . --log-file ./build/map-editor-plugin.log --editor --script res://tests/map_editor_plugin_test.gd
& $godotExe --path . --log-file ./build/map-editor-render.log --script res://tests/map_editor_test.gd -- --screenshots
& $godotExe --headless --path . --log-file ./build/logic.log --script res://tests/logic_test.gd
& $godotExe --headless --path . --log-file ./build/integration.log --script res://tests/integration_test.gd
```

テスト用マップ・追加素材・復旧データは `build/map-editor-tests/` に保存し、ゲーム用の `data/maps/*.tres` は書き換えない。実エディタ検証はプラグインを一度無効化して再有効化する。既存のユーザー復旧データを検出した場合はそのテストを中止するため、実行前に編集中のGodotを閉じ、必要な編集を保存しておく。

## 結果

| 検証 | 結果 |
| --- | --- |
| エディタでのインポート・プラグイン登録 | スクリプト解析・読み込み成功 |
| `map_editor_test.gd` | 111項目成功 |
| `map_editor_plugin_test.gd` | 実際のエディタ内で11項目成功 |
| GPUで同じエディタテストを実行 | 描画キャプチャ付きで116項目成功、5画像出力 |
| `logic_test.gd` | 37項目成功 |
| `integration_test.gd` | 共通バリデーター検証を含む106項目成功 |

編集テストは配置、下地への消去、高速ドラッグの補間、同じセルの再通過、範囲外、別キーで同じ地形を指す場合の無変更、Undo／Redoでの文字対応復元、履歴の分離を確認する。GodotのViewportへマウス・キーイベントを送り、キャンバス外での解放、フォーカス喪失、200%表示でスクロール後のセル指定、Ctrl+Z / Ctrl+Shift+Z、文字入力欄のショートカット分離も確認した。

保存テストは全エクスポートプロパティ、寸法、地形・敵の外部参照、保存後の再編集・再保存、保存状態へのUndo／Redo復帰を照合する。外部変更、形式不正、置き換えの権限エラーを模擬した失敗でも、元ファイルと作業内容が残ることを確認した。通路の警告は保存でき、構造エラーでは保存しない。追加地形を別ファイルに保存し、再読み込み後にゲームの `MapData.is_walkable()` が設定どおりになることを確認した。

素材テストは既存7素材、素材フォルダー外のマップ参照、サブフォルダーの新素材発見、追加素材の配置・保存、ID重複・テクスチャ欠落の無効化、決定的なキー割り当てとキー不足を確認した。

実エディタ検証では「マップ」画面の表示、終了時の未保存ステータス、エディタの保存フック、保存後のUndo、無効化後の復旧ファイル、再有効化後の復元を確認した。これはエディタ内でスクリプトから操作する検証で、OSの終了確認ダイアログを人がクリックする手動試験は未実施。

GPUキャプチャは `build/map-editor-tests/screenshots/` の野原・町・洞窟・入力後・保存後。地形、目印、パレット、日本語、ステータスと操作部の表示を確認した。ゲームの既存統合試験では物理移動、壁の衝突、町・洞窟の出入り、回復、戦闘、メニューを確認する。

## 環境上の制限

このサンドボックスではGodot起動時にOSの証明書ストアの読み込み警告、エディタ終了時にユーザーフォルダーの `editor_settings-4.6.tres` への書き込みエラーが出る。マップやテスト出力の保存とは別の環境制限で、上記テストの判定はすべて成功した。

`--editor --script` を組み合わせた検証プロセスの終了時にSceneTree・描画Resourceの残存警告が出る。通常の `--editor --quit` と単独の編集テストでは残存警告は出ない。実エディタテスト用プロセスの終了方法に限定した制約として記録する。

Windowsビルドの作成・テストは今回実施していない。

## NPCと会話の追加検証（2026-09-27）

`map_editor_test.gd` はNPC画面、200%表示・スクロール後の配置とUndoを追加して114項目成功。GPU実行ではNPC詳細と会話プレビューを含む121項目・7画像を保存した。`map_editor_plugin_test.gd` は確定済みのNPC名と本文を未確定の履歴から保存フックへ渡し、再有効化後の復旧まで14項目成功した。いずれも終了コード0。会話Resourceの複製、分岐の保存、実ゲームへの反映は `tests/dialogue_test.gd` の86項目で確認した。詳細は [検証記録](verification.md) を参照。
