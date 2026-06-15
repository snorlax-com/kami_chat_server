import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/config/mail_bridge_config.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';

/// FCM デバイストークンを Firestore とサーバー（Admin 経由）に保存する。
class FcmTokenRepository {
  FcmTokenRepository._();

  static String docIdForToken(String token) {
    final tail = token.length > 24 ? token.substring(token.length - 24) : token;
    return '${token.hashCode.abs().toRadixString(16)}_$tail'
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  static Future<void> saveToken({
    required String uid,
    required String token,
    required String platform,
  }) async {
    final docId = docIdForToken(token);
    final data = {
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (CloudService.firestoreUsable) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcm_tokens')
            .doc(docId)
            .set(data, SetOptions(merge: true));
        debugPrint('[FcmToken] Firestore saved users/$uid/fcm_tokens/$docId');
      } catch (e) {
        final es = e.toString();
        if (es.contains('PERMISSION_DENIED') ||
            es.contains('API has not been used') ||
            es.contains('Firestore API')) {
          CloudService.markFirestoreUnavailable(e);
        }
        debugPrint('[FcmToken] Firestore save failed: $e');
      }
    }

    final bridgeUserId = await ConsultationIdentity.bridgeUserIdOrLegacy();
    await _registerOnServer(
      token: token,
      platform: platform,
      bridgeUserId: bridgeUserId,
    );
  }

  static Future<void> removeToken({
    required String uid,
    required String token,
  }) async {
    final docId = docIdForToken(token);
    if (CloudService.firestoreUsable) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcm_tokens')
            .doc(docId)
            .delete();
      } catch (e) {
        final es = e.toString();
        if (es.contains('PERMISSION_DENIED') ||
            es.contains('API has not been used') ||
            es.contains('Firestore API')) {
          CloudService.markFirestoreUnavailable(e);
        }
        debugPrint('[FcmToken] Firestore delete failed: $e');
      }
    }
  }

  static Future<void> _registerOnServer({
    required String token,
    required String platform,
    required String bridgeUserId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final idToken = await user.getIdToken();
      final uri = Uri.parse('$kMailBridgeProductionUrl/api/fcm/register-token');
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'token': token,
              'platform': platform,
              'bridgeUserId': bridgeUserId,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('[FcmToken] server register ok');
      } else {
        debugPrint('[FcmToken] server register ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[FcmToken] server register failed: $e');
    }
  }
}
