#!/bin/bash
# 実機にアプリをインストール（既存データ削除のため先にアンインストール）
set -e
cd "$(dirname "$0")"

echo "接続デバイス確認..."
if ! adb devices | grep -q 'device$'; then
  echo "エラー: 実機が接続されていません。"
  echo "  - USBデバッグを有効にしてください（設定 → 開発者向けオプション）"
  echo "  - 接続時に「このパソコンを許可しますか？」で許可をタップしてください"
  exit 1
fi

echo "既存アプリのデータ削除（アンインストール）..."
adb uninstall com.auraface.kami_face_oracle 2>/dev/null || true

echo "リリース APK をビルドしてインストール..."
flutter install --release

echo "完了しました。"
