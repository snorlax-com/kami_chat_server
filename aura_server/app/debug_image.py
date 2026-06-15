"""
画像受信時のデバッグ・健全性チェックモジュール

ステップ1: 受信画像の健全性を100%可視化
- ファイルサイズ、画像サイズ、モード、EXIF回転をログ出力
- 補正後の画像を保存
- OpenCVでの読み込み結果を保存

ステップ3: 顔検出の「0件」vs「例外/None」を分離
"""
import os
import uuid
from pathlib import Path
from PIL import Image, ImageOps
import cv2
import numpy as np
import mediapipe as mp


def save_and_sanity_check_image(image_path: str, debug_dir: str = "/tmp/face_debug") -> str:
    """
    受信画像の健全性をチェックし、デバッグ用に保存する
    
    Args:
        image_path: 受信した画像ファイルのパス
        debug_dir: デバッグ画像を保存するディレクトリ
    
    Returns:
        補正後の画像パス
    
    Raises:
        FileNotFoundError: 画像ファイルが存在しない
        ValueError: 画像が小さすぎる、または破損している
    """
    os.makedirs(debug_dir, exist_ok=True)
    
    # ファイル存在確認
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"image not found: {image_path}")
    
    # ファイルサイズ確認
    size = os.path.getsize(image_path)
    if size < 10_000:  # 10KB未満は異常
        raise ValueError(f"image too small (likely broken upload): {size} bytes")
    
    print(f"[DEBUG][IMG] file_size={size} bytes")
    print(f"[DEBUG][IMG] original_path={image_path}")
    
    # PILで画像を開く
    try:
        img = Image.open(image_path)
        before = (img.width, img.height, img.mode)
        print(f"[DEBUG][IMG] before(w,h,mode)={before}")
        
        # EXIF回転を補正
        img = ImageOps.exif_transpose(img)
        after = (img.width, img.height, img.mode)
        print(f"[DEBUG][IMG] after_exif(w,h,mode)={after}")
        
        # 補正後の画像を保存
        out1 = os.path.join(debug_dir, "received_after_exif.jpg")
        img.convert("RGB").save(out1, quality=95)
        print(f"[DEBUG][IMG] saved={out1}")
        
        return out1
        
    except Exception as e:
        print(f"[DEBUG][IMG] PIL error: {e}")
        raise ValueError(f"PIL image open failed: {e}")


def load_as_rgb(image_path: str, debug_dir: str = "/tmp/face_debug") -> np.ndarray:
    """
    OpenCVで画像を読み込み、RGBに変換して保存する
    
    Args:
        image_path: 画像ファイルのパス
        debug_dir: デバッグ画像を保存するディレクトリ
    
    Returns:
        RGB形式のnumpy配列 (H, W, 3)
    
    Raises:
        ValueError: cv2.imreadが失敗した場合
    """
    os.makedirs(debug_dir, exist_ok=True)
    
    # OpenCVで読み込み（BGR形式）
    bgr = cv2.imread(image_path)
    if bgr is None:
        raise ValueError(f"cv2.imread failed (decode error): {image_path}")
    
    print(f"[DEBUG][CV2] bgr_shape={bgr.shape} dtype={bgr.dtype}")
    
    # BGR -> RGB に変換
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    print(f"[DEBUG][CV2] rgb_shape={rgb.shape} dtype={rgb.dtype}")
    
    # RGB画像を保存（目視確認用）
    rgb_path = os.path.join(debug_dir, "received_rgb.jpg")
    Image.fromarray(rgb).save(rgb_path, quality=95)
    print(f"[DEBUG][CV2] saved={rgb_path}")
    
    return rgb


def upscale_if_needed(rgb: np.ndarray, min_size: int = 512) -> tuple[np.ndarray, bool]:
    """
    画像の短辺が指定サイズ未満の場合、2倍に拡大する
    
    Args:
        rgb: RGB画像 (H, W, 3)
        min_size: 最小サイズ（デフォルト512）
    
    Returns:
        (拡大後の画像, 拡大したかどうか)
    """
    h, w, _ = rgb.shape
    short = min(h, w)
    
    if short >= min_size:
        print(f"[DEBUG][UPSCALE] skip (short={short} >= {min_size})")
        return rgb, False
    
    # 2倍に拡大
    rgb2 = cv2.resize(rgb, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_LINEAR)
    print(f"[DEBUG][UPSCALE] {w}x{h} -> {rgb2.shape[1]}x{rgb2.shape[0]}")
    
    # 拡大後の画像を保存
    debug_dir = "/tmp/face_debug"
    os.makedirs(debug_dir, exist_ok=True)
    upscaled_path = os.path.join(debug_dir, "received_upscaled.jpg")
    Image.fromarray(rgb2).save(upscaled_path, quality=95)
    print(f"[DEBUG][UPSCALE] saved={upscaled_path}")
    
    return rgb2, True


def run_face_detection(rgb: np.ndarray, min_conf: float = 0.5):
    """
    顔検出を実行（MediaPipe Face Detection）
    
    Args:
        rgb: RGB画像 (H, W, 3)
        min_conf: 最小検出信頼度
    
    Returns:
        (検出件数, resultsオブジェクト)
    
    Raises:
        Exception: 顔検出処理中に例外が発生した場合
    """
    print(f"[DEBUG][MP] mediapipe_version={mp.__version__} min_conf={min_conf}")
    
    mp_fd = mp.solutions.face_detection
    try:
        with mp_fd.FaceDetection(model_selection=1, min_detection_confidence=min_conf) as fd:
            results = fd.process(rgb)
        
        if results is None:
            print("[DEBUG][FD] results=None")
            return 0, None
        
        if not results.detections:
            print("[DEBUG][FD] detections=0")
            return 0, results
        
        print(f"[DEBUG][FD] detections={len(results.detections)}")
        return len(results.detections), results
        
    except Exception as e:
        import traceback
        print(f"[DEBUG][FD] ❌ 例外発生: {e}")
        print(f"[DEBUG][FD] traceback:\n{traceback.format_exc()}")
        raise

