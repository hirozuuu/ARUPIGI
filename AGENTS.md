# ARUPIGI の作業案内

Godot 4.6.x / GDScript の小規模RPG。GL Compatibilityを使用する。
ユーザーへの説明と開発ドキュメントは日本語を基本とする。

## 作業範囲

- 依頼に必要な実装・確認・不具合修正まで進める。通常のローカル編集や既存テストの実行は、途中の確認待ちにしない。
- 現段階ではWindowsビルドの作成・実行ファイルの検証は不要。明示的に依頼された段階でREADMEの書き出し手順を使う。
- `.godot/` と `build/` は生成物。既存の `.uid` とResource参照を維持する。

## 変更箇所と参照先

- 起動・状態遷移: `scenes/main.tscn`、`scripts/main.gd`。
- 探索: `scripts/exploration.gd`、`map_controller.gd`、`player.gd`。
- 進行・遭遇・戦闘: `scripts/game_session.gd`、`encounter_controller.gd`、`battle_model.gd`。
- UI: `scripts/game_ui.gd`。調整値・マップ・敵・地形は `data/` のResourceと `scripts/data/`。
- マップエディタ: `addons/map_editor/`。操作は `docs/map-editor-guide.md`、検証は `docs/map-editor-verification.md`。
- 起動方法・テストコマンドは `README.md`。ゲームの仕様・過去の検証は `docs/implementation-plan.md` と `docs/verification.md`。必要なものだけ参照する。

## ローカル検証

PowerShellをリポジトリルートで使用する。このPCの `godot.exe` は4.4.1なので、次の4.6.2を明示する。他の環境ではパスを調整する。

```powershell
$godotExe = 'C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe'
```

初回またはクラス・素材追加後はREADMEのheadlessインポートを実行する。変更内容に対応する検証を選び、ドキュメントだけの変更ではゲーム全体の再検証は不要。

| 変更内容 | 検証スクリプト |
| --- | --- |
| 進行・遭遇・戦闘ロジック | `tests/logic_test.gd` |
| 状態遷移・移動・マップResource | `tests/integration_test.gd` |
| マップ編集・保存・検証・パネル | `tests/map_editor_test.gd` |
| プラグイン登録・保存フック・復旧 | `tests/map_editor_plugin_test.gd`（`--editor` が必要） |
| ゲームの見た目 | `tests/render_smoke.gd`（GPU使用、`--headless` を付けない） |

マップエディタのテストデータは `build/map-editor-tests/` に出力する。プラグイン検証は有効化状態や復旧を操作するため、編集中のGodotを保存して閉じた状態で実施する。既存の復旧データによる中止を、データ削除で回避しない。詳細と描画テストのコマンドは `docs/map-editor-verification.md` にある。

サンドボックスでは証明書ストアの読み込みとユーザーフォルダーへのエディタ設定保存にエラーが出る場合がある。既知の環境制約として、テストのPASS/FAIL・終了コード・スクリプトエラーと区別して報告する。

Gitがこの作業フォルダーで `dubious ownership` を返す場合は、所有者と対象パスを確認し、そのコマンドだけに例外を指定できる。

```powershell
git -c safe.directory=C:/Users/hiroz/Documents/GodotEngine/arupigi status --short
```

他のGitコマンドにも同じ `-c` を付ける。別のチェックアウトでは実際のパスを使う。
