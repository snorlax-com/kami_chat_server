/**
 * 相談メール通知の種別（API / メール / ストアで共通）
 * 未指定・未知の値は常に normal として扱う（後方互換）
 */
const NORMAL = "normal";
const PRIORITY_GUIDANCE = "priority_guidance";

/** @param {unknown} v */
function normalizeConsultationType(v) {
  if (v === PRIORITY_GUIDANCE || v === "priorityGuidance") return PRIORITY_GUIDANCE;
  return NORMAL;
}

module.exports = {
  NORMAL,
  PRIORITY_GUIDANCE,
  normalizeConsultationType,
  /** メール件名（定数） */
  SUBJECT_NORMAL: "[AuraFace] 新しい相談が届きました",
  SUBJECT_PRIORITY:
    "【要確認】【優先導き】2時間以内対応｜AuraFace [PRIORITY_GUIDANCE]",
  /** 本文・検索用タグ */
  TAG_PRIORITY: "[PRIORITY_GUIDANCE]",
};
