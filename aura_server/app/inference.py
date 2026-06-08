# app/inference.py

from typing import Dict, Optional
import numpy as np
import cv2
import sys
from pathlib import Path
import json

from app.config import KAMI_FACE_ORACLE_DIR

# 既存の推論ロジックをインポートするためにパスを追加
# サーバー側では /root/aura_server がプロジェクトルート
personality_dir = KAMI_FACE_ORACLE_DIR / "face_shape_ai" / "personality_diagnosis_complete_version"
python_dir = KAMI_FACE_ORACLE_DIR / "face_shape_ai" / "python"
sys.path.insert(0, str(personality_dir))
sys.path.insert(0, str(python_dir))
# 親ディレクトリも追加（相対インポート用）
sys.path.insert(0, str(KAMI_FACE_ORACLE_DIR / "face_shape_ai"))

# 既存の推論ロジックをインポート（Python推論完全版）
import mediapipe as mp
from personality_diagnosis_complete_version.python_pure_auto_loop import (
    extract_personality_features,
    classify_personality_layer,
    extract_face_type_features,
    classify_face_type,
    load_completed_layers,
    LAYERS
)

# 性格タイプ名のマッピング（新しい18タイプ、実際は15タイプ）
PERSONALITY_TYPE_NAMES = {
    1: '協調的リーダー型',
    2: '情熱的革新者型',
    3: '柔軟な適応者型',
    4: '情熱的表現者型',
    5: '堅実な計画者型',
    6: '社交的楽天家型',
    7: 'バランス型実務家',
    8: '情熱的リーダー型',
    9: '積極的開拓者型',
    10: '複雑な個性型',
    11: '冷静な観察者型',
    12: '寛大な支援者型',
    13: '内向的芸術家型',
    14: '情熱的革新者（協調寄り）',
    15: '冷静な完璧主義者型',
}

# MediaPipe Face Meshのインスタンス（グローバルで再利用）
_face_mesh = None

def _get_face_mesh():
    """MediaPipe Face Meshのインスタンスを取得（シングルトン）"""
    global _face_mesh
    if _face_mesh is None:
        mp_face_mesh = mp.solutions.face_mesh
        _face_mesh = mp_face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5
        )
    return _face_mesh

def _load_personality_mapping_table() -> dict:
    """性格タイプマッピングテーブルを読み込む"""
    mapping_file = KAMI_FACE_ORACLE_DIR / "face_shape_ai" / "personality_diagnosis_complete_version" / "personality_type_mapping.json"
    if not mapping_file.exists():
        # フォールバック: assetsディレクトリも確認
        mapping_file = KAMI_FACE_ORACLE_DIR / "assets" / "personality_type_mapping.json"
    
    if mapping_file.exists():
        with open(mapping_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def _layer_value_to_int(layer_value: str, layer_num: int) -> int:
    """Layerの値を数値化"""
    if layer_num == 2:  # 眉の形状（2分類）
        if '曲線' in layer_value:
            return 1
        elif '直線' in layer_value:
            return 0
        return 0  # デフォルト
    elif layer_num == 9:  # 顔の型
        return _face_type_to_int(layer_value)
    else:  # 第1層、第3-8層（3分類）
        if '大' in layer_value:
            return 2
        elif '中' in layer_value:
            return 1
        elif '小' in layer_value:
            return 0
        return 1  # デフォルト

def _face_type_to_int(face_type: str) -> int:
    """顔の型を数値化（0-7）"""
    face_type_map = {
        '丸顔': 0,
        '卵顔': 1,
        '細長顔': 2,
        '逆三角形顔': 3,
        '四角顔': 4,
        '台座顔': 5,
        '三角形顔': 6,
        '長方形顔': 7,
    }
    return face_type_map.get(face_type, 1)  # デフォルトは卵顔

def _get_pillar_info(personality_type: int) -> Optional[Dict]:
    """性格タイプから柱情報を取得"""
    try:
        # pillar_infoモジュールをインポート
        sys.path.insert(0, str(KAMI_FACE_ORACLE_DIR / "face_shape_ai" / "personality_diagnosis_complete_version" / "personality_mapping"))
        from pillar_info import get_pillar_info
        
        pillar_info = get_pillar_info(personality_type)
        if pillar_info:
            return {
                'pillar_id': pillar_info.get('pillar_id'),
                'pillar_name': pillar_info.get('pillar_name'),
                'pillar_title': pillar_info.get('title'),
                'character_image': pillar_info.get('character_image'),
                'illustration_image': pillar_info.get('illustration_image'),
            }
    except Exception as e:
        print(f"柱情報の取得エラー: {e}")
    return None

def _get_personality_type(layer_results: Dict[str, str], mapping_table: dict) -> int:
    """9層の分類結果から性格タイプを取得"""
    # 各Layerの値を数値化
    l1 = _layer_value_to_int(layer_results.get('L1', ''), 1)
    l2 = _layer_value_to_int(layer_results.get('L2', ''), 2)
    l3 = _layer_value_to_int(layer_results.get('L3', ''), 3)
    l4 = _layer_value_to_int(layer_results.get('L4', ''), 4)
    l5 = _layer_value_to_int(layer_results.get('L5', ''), 5)
    l6 = _layer_value_to_int(layer_results.get('L6', ''), 6)
    l7 = _layer_value_to_int(layer_results.get('L7', ''), 7)
    l8 = _layer_value_to_int(layer_results.get('L8', ''), 8)
    l9 = _layer_value_to_int(layer_results.get('L9', ''), 9)
    
    # 組み合わせキーを生成（例: "1,1,1,1,2,1,1,1,4"）
    key = f"{l1},{l2},{l3},{l4},{l5},{l6},{l7},{l8},{l9}"
    
    # JSONマッピングテーブルから取得を試みる
    if key in mapping_table:
        return mapping_table[key]
    
    # フォールバック: ロジックベースの分類
    sys.path.insert(0, str(KAMI_FACE_ORACLE_DIR / "face_shape_ai" / "personality_diagnosis_complete_version"))
    from test_personality_diagnosis import classify_by_logic
    return classify_by_logic(l1, l2, l3, l4, l5, l6, l7, l8, l9, layer_results.get('L9', ''))

def run_prediction(img_bgr: np.ndarray) -> Optional[Dict]:
    """
    性格診断のメイン推論関数。
    入力: BGR(OpenCV形式)の画像 (np.ndarray)
    出力: レイヤー情報と性格タイプを含む dict
    
    この関数は既存の「性格診断用のPython推論スクリプト」のロジックを使用しています。
    処理フロー:
      1. MediaPipe Face Meshで顔検出
      2. ランドマーク抽出（468点）
      3. 各種特徴量算出(眉角度、眉間距離、目の形、口の大きさなど)
      4. 9レイヤー(L1〜L9)の分類
      5. 9レイヤーの組み合わせから性格タイプを決定
    """
    try:
        # ✅ 性格診断Python推論完成版を使用
        # 完全版のcompleted_layers.jsonを読み込む
        # これにより、完全版と同じ固定閾値ベースの分類が使用される
        # completed_layersが読み込まれているため、classify_personality_layer内で
        # 固定閾値ベースの分類が使用される（完全版と同じ動作）
        completed_layers = load_completed_layers()
        
        # Layer 9の検出回数をリセット（各リクエストごとにリセット）
        from personality_diagnosis_complete_version.python_pure_auto_loop import _face_type_detection_counts, FACE_TYPES
        for face_type in FACE_TYPES:
            _face_type_detection_counts[face_type] = 0
        
        # MediaPipe Face Meshのインスタンスを取得
        face_mesh = _get_face_mesh()
        
        # BGR → RGB変換
        rgb_img = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        image_height, image_width = rgb_img.shape[:2]
        
        # 顔を検出
        results_face = face_mesh.process(rgb_img)
        
        if not results_face.multi_face_landmarks:
            return None  # 顔が検出されなかった
        
        face_landmarks = results_face.multi_face_landmarks[0]
        
        # 性格診断用特徴量を抽出
        personality_features = extract_personality_features(
            face_landmarks, image_width, image_height, None
        )
        
        # 顔型分類用特徴量を抽出
        face_type_features = extract_face_type_features(
            face_landmarks, image_width, image_height
        )
        
        # 各層の分類結果
        layer_results = {}
        for layer_num in range(1, 9):
            category = classify_personality_layer(personality_features, layer_num)
            layer_results[f'L{layer_num}'] = category
        
        # 顔型分類
        face_type = classify_face_type(face_type_features)
        layer_results['L9'] = face_type
        
        # 性格タイプマッピングテーブルを読み込む
        mapping_table = _load_personality_mapping_table()
        
        # 性格タイプを取得
        personality_type = _get_personality_type(layer_results, mapping_table)
        personality_type_name = PERSONALITY_TYPE_NAMES.get(
            personality_type, f'タイプ{personality_type}'
        )
        
        # 柱情報を取得
        pillar_info = _get_pillar_info(personality_type)
        
        # 結果を返す
        result = {
            **layer_results,
            'personality_type': personality_type,
            'personality_type_name': personality_type_name,
        }
        
        # 柱情報を追加
        if pillar_info:
            result.update(pillar_info)
        
        return result
        
    except Exception as e:
        # エラーが発生した場合はNoneを返す（呼び出し側でエラーハンドリング）
        print(f"推論エラー: {e}")
        return None

