/**
 * 相談メール通知の種別（API / メール / ストアで共通）
 * 未指定・未知の値は常に normal として扱う（後方互換）
 */
const NORMAL = "normal";
const PRIORITY_GUIDANCE = "priority_guidance";

/** アプリが本文末尾に付与（JSON の他フィールドが欠落しても message だけ残る経路向け） */
const EMBEDDED_TIER_RE = /\r?\n\r?\n__AURAFACE_SEND_TIER__:(priority_guidance|normal)__\s*$/;

/**
 * @param {unknown} raw
 * @returns {{ cleanText: string, embeddedTierRaw: string | null }}
 */
function extractEmbeddedConsultationTier(raw) {
  const s = raw != null ? String(raw) : "";
  const m = s.match(EMBEDDED_TIER_RE);
  if (!m) return { cleanText: s, embeddedTierRaw: null };
  const cleanText = s.replace(EMBEDDED_TIER_RE, "").trimEnd();
  return { cleanText, embeddedTierRaw: m[1] };
}

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
 * - consultationType / consultation_type（別名）を最優先（非空なら正規化して返す）
 * - 無い場合は HTTP ヘッダー X-AuraFace-Consultation-Type（[headerRaw]）
 * - consultationPriority が 2 なら優先導き
 * - 種別が未指定のとき body.urgent が真なら優先導き
 * - 明示的に "normal" を送った場合は urgent / ヘッダー / 埋め込みがあっても通常のまま
 * @param {Record<string, unknown>|null|undefined} body
 * @param {string|null|undefined} headerRaw
 * @param {string|null|undefined} embeddedTierRaw [extractEmbeddedConsultationTier] の第2戻り値
 */
function resolveConsultationTypeFromSendBody(body, headerRaw, embeddedTierRaw) {
  const b = body && typeof body === "object" ? body : {};
  const fromBody = b.consultationType ?? b.consultation_type;
  const bodyMissing = fromBody == null || (typeof fromBody === "string" && fromBody.trim() === "");
  if (!bodyMissing) {
    return normalizeConsultationType(fromBody);
  }
  if (embeddedTierRaw != null && String(embeddedTierRaw).trim() !== "") {
    const e = normalizeConsultationType(String(embeddedTierRaw).trim());
    if (e === PRIORITY_GUIDANCE || e === NORMAL) {
      return e;
    }
  }
  if (headerRaw != null && String(headerRaw).trim() !== "") {
    const h = normalizeConsultationType(String(headerRaw).trim());
    if (h === PRIORITY_GUIDANCE || h === NORMAL) {
      return h;
    }
  }
  const tier = b.consultationPriority ?? b.consultation_priority;
  if (tier === 2 || tier === "2") {
    return PRIORITY_GUIDANCE;
  }
  if (coerceUrgentFromBody(b.urgent)) {
    return PRIORITY_GUIDANCE;
  }
  return NORMAL;
}

/** @param {unknown} v */
function normalizeConsultationType(v) {
  if (v === true) return PRIORITY_GUIDANCE;
  if (v == null || v === "") return NORMAL;
  if (typeof v === "number") {
    if (v === 2) return PRIORITY_GUIDANCE;
    if (v === 1) return NORMAL;
    return NORMAL;
  }
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
  extractEmbeddedConsultationTier,
  EMBEDDED_TIER_RE,
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
