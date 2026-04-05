/**
 * 相談メール通知の種別（API / メール / ストアで共通）
 * 未指定・未知の値は常に normal として扱う（後方互換）
 */
const NORMAL = "normal";
const PRIORITY_GUIDANCE = "priority_guidance";

/** @param {unknown} v */
function coerceUrgentFromBody(v) {
  if (v === true) return true;
  if (v === 1) return true;
  if (typeof v === "string") {
    const s = v.trim().toLowerCase();
    if (s === "true" || s === "1" || s === "yes") return true;
  }
  return false;
}

/**
 * POST /api/chat/send の body から種別を決定。
 * - consultationType / consultation_type（別名）を正規化
 * - 種別フィールドが無い・空のときだけ body.urgent が真なら優先導き（中間層で consultationType だけ落ちる場合の冗長）
 * - 明示的に "normal" を送った場合は urgent があっても通常のまま
 */
function resolveConsultationTypeFromSendBody(body) {
  const b = body && typeof body === "object" ? body : {};
  const raw = b.consultationType ?? b.consultation_type;
  const rawMissing = raw == null || (typeof raw === "string" && raw.trim() === "");
  let t = normalizeConsultationType(raw);
  if (rawMissing && t === NORMAL && coerceUrgentFromBody(b.urgent)) {
    return PRIORITY_GUIDANCE;
  }
  return t;
}

/** @param {unknown} v */
function normalizeConsultationType(v) {
  if (v === true) return PRIORITY_GUIDANCE;
  if (v == null || v === "") return NORMAL;
  if (typeof v === "string") {
    const s = v.trim().toLowerCase().replace(/-/g, "_");
    if (
      s === PRIORITY_GUIDANCE ||
      s === "priorityguidance" ||
      s === "urgent" ||
      s === "emergency" ||
      s === "priority"
    ) {
      return PRIORITY_GUIDANCE;
    }
    if (s === NORMAL) return NORMAL;
    return NORMAL;
  }
  return NORMAL;
}

module.exports = {
  NORMAL,
  PRIORITY_GUIDANCE,
  normalizeConsultationType,
  resolveConsultationTypeFromSendBody,
  /** メール件名（定数） */
  SUBJECT_NORMAL: "[AuraFace] 新しい相談が届きました",
  /**
   * 至急（占い相談の優先導き）。通常は [AuraFace] 始まりなので、先頭を【至急占い】にして一覧・通知の一行目を完全に別物にする。
   */
  SUBJECT_PRIORITY:
    "【至急占い・緊急】2時間以内要対応｜優先導き｜AuraFace [PRIORITY_GUIDANCE]",
  /** 本文・検索用タグ */
  TAG_PRIORITY: "[PRIORITY_GUIDANCE]",
  /**
   * Gmail 受信トレイの「差出人」欄で通常 / 優先を一目で分ける（MAIL_FROM の表示名として使う）
   * 通常「AuraFace｜…」と逆順にして、同じアドレスでも左列の文字列が大きく変わるようにする。
   */
  FROM_DISPLAY_NORMAL: "AuraFace｜通常相談",
  FROM_DISPLAY_PRIORITY: "至急占い相談｜AuraFace【優先導き】",
};
