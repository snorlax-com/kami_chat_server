import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloudService {
  static bool _initialized = false;
  static bool _available = false; // ランタイムで失敗したらfalse

  /// Firebase が利用可能か（相談送信・履歴取得に必要）
  static bool get isAvailable => _available;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      await FirebaseAuth.instance.signInAnonymously();
      _available = true;
      debugPrint('[CloudService] Firebase initialized successfully');
    } catch (e) {
      _available = false; // Firebase未設定でもアプリは継続
      debugPrint('[CloudService] Firebase initialization failed: $e');
      // Firebaseが使えない場合はローカルストレージを使用
    }
  }

  static Future<void> saveDailyRecord(Map<String, dynamic> record) async {
    if (!_available) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final date = (record['date'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('records')
        .doc(date)
        .set(record, SetOptions(merge: true));
  }

  static Future<void> addConsultation(String text, {required bool urgent, required int cost}) async {
    if (!_available) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final deadline = urgent
        ? DateTime.now().add(const Duration(hours: 12)) // 至急: 12時間以内
        : DateTime.now().add(const Duration(days: 3)); // 通常: 3日以内

    await FirebaseFirestore.instance.collection('users').doc(uid).collection('consultations').add({
      'text': text,
      'urgent': urgent,
      'cost': cost,
      'status': 'pending', // pending, answered, expired
      'deadline': deadline.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'answer': null,
    });
  }

  static Future<void> addInventoryItem(String type, Map<String, dynamic> payload) async {
    if (_available) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final itemData = {
            'type': type,
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
            'timestamp': DateTime.now().toIso8601String(),
          };
          debugPrint('[CloudService] addInventoryItem: Adding item to Firestore: $itemData');
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('inventory').add(itemData);
          debugPrint('[CloudService] addInventoryItem: Successfully added to Firestore');
          return; // Firestore保存成功
        } catch (e) {
          debugPrint('[CloudService] addInventoryItem Firestore error: $e, falling back to local storage');
        }
      }
    }

    // Firebase未使用時またはエラー時はローカルストレージに保存
    debugPrint('[CloudService] addInventoryItem: Saving to local storage');
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'inventory_${type}_${DateTime.now().millisecondsSinceEpoch}';
      final itemData = {
        'id': key,
        'type': type,
        ...payload,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(itemData));

      // インデックスリストを更新
      final indexKey = 'inventory_index_$type';
      final index = prefs.getStringList(indexKey) ?? [];
      index.add(key);
      await prefs.setStringList(indexKey, index);
      debugPrint('[CloudService] addInventoryItem: Successfully saved to local storage');
    } catch (e) {
      debugPrint('[CloudService] addInventoryItem local storage error: $e');
    }
  }

  /// 日次記録にコメントを生成（beauty/qi/fukuに基づく）
  static String generateComment({
    required String deityId,
    double? beauty,
    double? qi,
    double? fuku,
  }) {
    final b = beauty ?? 0.5;
    final q = qi ?? 0.5;
    final f = fuku ?? 0.5;
    final avg = (b + q + f) / 3.0;

    String base;
    if (avg >= 0.8) {
      base = '今日は特に運気が上昇しています。';
    } else if (avg >= 0.6) {
      base = '良い一日になりそうです。';
    } else if (avg >= 0.4) {
      base = '小さな変化に気を配りましょう。';
    } else {
      base = '静かに過ごすのも一つの選択です。';
    }

    final details = <String>[];
    if (b >= 0.7) details.add('肌の調子が良い');
    if (q >= 0.7) details.add('気力が充実');
    if (f >= 0.7) details.add('福運に恵まれている');
    if (details.isNotEmpty) {
      base += ' ${details.join('・')}今日。';
    }

    return base;
  }

  /// 日次記録を取得（直近N件）
  static Future<List<Map<String, dynamic>>> getDailyRecords({int limit = 30, String? date}) async {
    if (!_available) return [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    try {
      Query query = FirebaseFirestore.instance.collection('users').doc(uid).collection('records');

      if (date != null) {
        // 特定の日付の記録を取得
        query = query.where('date', isEqualTo: date).limit(1);
      } else {
        // 直近N件を取得
        query = query.orderBy('date', descending: true).limit(limit);
      }

      final snap = await query.get();
      return snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 在庫アイテムを取得（type指定可）
  static Future<List<Map<String, dynamic>>> getInventory({String? type, int limit = 100}) async {
    List<Map<String, dynamic>> items = [];

    // まずFirestoreから取得を試みる
    if (_available) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          Query query = FirebaseFirestore.instance.collection('users').doc(uid).collection('inventory');
          if (type != null) {
            query = query.where('type', isEqualTo: type);
          }
          final snap = await query.get();
          debugPrint('[CloudService] getInventory: Found ${snap.docs.length} items from Firestore (type: $type)');
          items = snap.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          }).toList();
        } catch (e) {
          debugPrint('[CloudService] getInventory Firestore error: $e, falling back to local storage');
        }
      }
    }

    // Firestoreから取得できなかった場合、ローカルストレージから取得
    if (items.isEmpty) {
      debugPrint('[CloudService] getInventory: Loading from local storage');
      try {
        final prefs = await SharedPreferences.getInstance();

        if (type != null) {
          // 特定タイプのインデックスを使用
          final indexKey = 'inventory_index_$type';
          final index = prefs.getStringList(indexKey) ?? [];
          final itemsFromIndex = <Map<String, dynamic>>[];
          for (final key in index) {
            final jsonStr = prefs.getString(key);
            if (jsonStr != null) {
              try {
                final item = jsonDecode(jsonStr) as Map<String, dynamic>;
                itemsFromIndex.add(item);
              } catch (e) {
                debugPrint('[CloudService] Error parsing item $key: $e');
              }
            }
          }
          items = itemsFromIndex;
        } else {
          // 全タイプのインデックスを取得
          final allKeys = prefs.getKeys().where((k) => k.startsWith('inventory_') && !k.contains('_index_')).toList();
          final allItems = <Map<String, dynamic>>[];
          for (final key in allKeys) {
            final jsonStr = prefs.getString(key);
            if (jsonStr != null) {
              try {
                final item = jsonDecode(jsonStr) as Map<String, dynamic>;
                allItems.add(item);
              } catch (e) {
                debugPrint('[CloudService] Error parsing item $key: $e');
              }
            }
          }
          items = allItems;
        }

        debugPrint('[CloudService] getInventory: Found ${items.length} items from local storage (type: $type)');
      } catch (e) {
        debugPrint('[CloudService] getInventory local storage error: $e');
      }
    }

    // timestampでソート
    items.sort((a, b) {
      final aTime = a['createdAt'] ?? a['timestamp'] ?? '';
      final bTime = b['createdAt'] ?? b['timestamp'] ?? '';
      if (aTime == null || bTime == null) return 0;
      if (aTime is! String && aTime.toString().contains('Timestamp')) {
        return 0;
      }
      if (bTime is! String && bTime.toString().contains('Timestamp')) {
        return 0;
      }
      if (aTime is String && bTime is String) {
        return bTime.compareTo(aTime);
      }
      return 0;
    });

    return items.take(limit).toList();
  }

  /// 在庫アイテムを削除（使用時など）
  static Future<void> removeInventoryItem(String itemId) async {
    // まずFirestoreから削除を試みる
    if (_available) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('inventory').doc(itemId).delete();
          debugPrint('[CloudService] removeInventoryItem: Removed from Firestore');
          return;
        } catch (e) {
          debugPrint('[CloudService] removeInventoryItem Firestore error: $e, trying local storage');
        }
      }
    }

    // Firestoreから削除できなかった場合、ローカルストレージから削除
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(itemId);

      // インデックスからも削除
      final allIndexKeys = prefs.getKeys().where((k) => k.startsWith('inventory_index_')).toList();
      for (final indexKey in allIndexKeys) {
        final index = prefs.getStringList(indexKey) ?? [];
        if (index.contains(itemId)) {
          index.remove(itemId);
          await prefs.setStringList(indexKey, index);
        }
      }
      debugPrint('[CloudService] removeInventoryItem: Removed from local storage');
    } catch (e) {
      debugPrint('[CloudService] removeInventoryItem local storage error: $e');
    }
  }

  /// 相談履歴を取得
  static Future<List<Map<String, dynamic>>> getConsultations({int limit = 50}) async {
    if (!_available) return [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('consultations')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 相談回答を取得（リアルタイムリスナーも可能だが、ここでは単発取得）
  static Stream<List<Map<String, dynamic>>> watchConsultations({int limit = 50}) {
    if (!_available) {
      return Stream.value([]);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream.value([]);
    }
    try {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('consultations')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {'id': doc.id, ...data};
        }).toList();
      });
    } catch (_) {
      return Stream.value([]);
    }
  }
}
