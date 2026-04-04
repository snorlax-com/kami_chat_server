/**
 * 相談メール通知の種別（API / メール / ストアで共通）
 * 未指定・未知の値は常に normal として扱う（後方互換）
 */
const NORMAL = "normal";
const PRIORITY_GUIDANCE = "priority_guidance";

/** @param {unknown} v */
function normalizeConsultationType(v) {
  if (v === PRIORITY_GUIDANCE || v === "priorityGuidance") return PRIORITY_GUIDANCE;
  // アプリ・旧クライアントの揺れ吸収（至急フラグのみ送られてきた場合）
  if (v === "urgent" || v === "emergency" || v === true) return PRIORITY_GUIDANCE;
  return NORMAL;
}

module.exports = {
  NORMAL,
  PRIORITY_GUIDANCE,
  normalizeConsultationType,
  /** メール件名（定数） */
  SUBJECT_NORMAL: "[AuraFace] 新しい相談が届きました",
  /** Gmail 一覧・通知で「緊急」が文字として見えるように先頭に付与 */
  SUBJECT_PRIORITY:
    "【緊急】【優先導き】2時間以内要対応｜AuraFace [PRIORITY_GUIDANCE]",
  /** 本文・検索用タグ */
  TAG_PRIORITY: "[PRIORITY_GUIDANCE]",
  /**
   * Gmail 受信トレイの「差出人」欄で通常 / 優先を一目で分ける（MAIL_FROM の表示名として使う）
   */
  FROM_DISPLAY_NORMAL: "AuraFace｜通常相談",
  FROM_DISPLAY_PRIORITY: "【緊急】優先導き・AuraFace",
};
