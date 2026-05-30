# サウンドアセット

このフォルダにはアプリで使用するBGM・効果音を配置します。

## 必須ファイル（BGM）

| ファイル名   | 用途           | 参照コード |
|-------------|----------------|------------|
| **bgm3.mp3** | メインBGM（ループ） | `lib/services/background_music_service.dart` |
| **bgm4.mp3** | メインBGM（bgm3と交互に再生） | 同上 |

- ループ再生されるため、**ループ用のBGM**（終わりが自然に頭に繋がるもの）が適しています。
- 音量はコード側で約30%に設定されています。

## その他参照されているファイル

| ファイル名           | 用途           | 参照コード |
|---------------------|----------------|------------|
| reveal.mp3          | 結果表示時の効果音 | `lib/ui/pages/reveal_page.dart` |
| bell-a-99888.mp3    | 瞑想シーンの鐘の音 | `lib/pages/meditation_scene.dart` |
| sounds/meditation/*.mp3 または *.wav | 瞑想用BGM（神ごと） | `lib/services/background_music_service.dart` |

## 配置手順

1. 上記の **bgm3.mp3** と **bgm4.mp3** をダウンロードまたは用意する。
2. このフォルダ（`assets/sounds/`）にそのまま配置する。
   - 正しいパス例: `assets/sounds/bgm3.mp3` と `assets/sounds/bgm4.mp3`
3. 既に `pubspec.yaml` に `assets/sounds/` が登録されているため、**追加の設定は不要**です。
4. `flutter run` や `flutter build` で再度ビルドする。

## 無料BGMの入手先（商用利用可の例）

- **DOVA-SYNDROME**  
  https://dova-s.jp/  
  MP3でダウンロード可能。ループ用タグで検索すると便利です。

- **フリーBGM・ループ素材**  
  https://freemusic-bgm.com/category/ループ音源/  
  ループ音源専門。

- **Senses Circuit**  
  https://www.senses-circuit.com/  
  ループBGM・効果音を無料配布。

- **freemusic**  
  https://www.freemusic.jp/  
  商用利用OKの高品質BGM。

利用規約・クレジット表記の要否は各サイトで確認してください。

## 注意

- ファイル名は **bgm3.mp3** / **bgm4.mp3** のままにしてください（大文字・小文字、拡張子を含む）。
- 既に `assets/sounds/` には `.keep` のみがあり、上記mp3ファイルはリポジトリに含めていない場合があります。必要なファイルを手元で配置したうえで、必要に応じて `git add` してコミットしてください。
