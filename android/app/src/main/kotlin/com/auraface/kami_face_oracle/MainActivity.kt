package com.auraface.kami_face_oracle

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.auraface.kami_face_oracle/file_access"
    private val INTENT_CHANNEL = "com.auraface.kami_face_oracle/intent"
    private var latestIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        latestIntent = intent
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Intentで受け取った画像パスとauto_modeをFlutterに渡す
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getIntentImagePath" -> {
                    val imagePath = getIntentImagePath()
                    result.success(imagePath)
                }
                "getIntentExtra" -> {
                    val extra = handleGetIntentExtra()
                    result.success(extra)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyExternalFileToInternal" -> {
                    val externalPath = call.argument<String>("externalPath")
                    if (externalPath != null) {
                        try {
                            val internalPath = copyFileToInternalStorage(externalPath)
                            if (internalPath != null) {
                                result.success(internalPath)
                            } else {
                                result.error("COPY_FAILED", "ファイルのコピーに失敗しました", null)
                            }
                        } catch (e: Exception) {
                            result.error("COPY_ERROR", e.message ?: "不明なエラー", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "ファイルパスが指定されていません", null)
                    }
                }
                "canReadFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val canRead = File(filePath).canRead()
                        result.success(canRead)
                    } else {
                        result.success(false)
                    }
                }
                "copyExternalFileToAppCache" -> {
                    val externalPath = call.argument<String>("externalPath")
                    if (externalPath != null) {
                        try {
                            val cachePath = copyFileToAppExternalCache(externalPath)
                            if (cachePath != null) {
                                result.success(cachePath)
                            } else {
                                result.error("COPY_FAILED", "ファイルのコピーに失敗しました", null)
                            }
                        } catch (e: Exception) {
                            result.error("COPY_ERROR", e.message ?: "不明なエラー", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "ファイルパスが指定されていません", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun copyFileToInternalStorage(externalPath: String): String? {
        return try {
            val cacheDir = applicationContext.cacheDir
            val fileName = File(externalPath).name
            val internalFile = File(cacheDir, "copied_${System.currentTimeMillis()}_$fileName")

            // 方法1: 直接ファイルパスでアクセスを試行（Android 10以下、または権限がある場合）
            var inputStream: InputStream? = null
            try {
                val externalFile = File(externalPath)
                if (externalFile.exists() && externalFile.canRead()) {
                    inputStream = FileInputStream(externalFile)
                }
            } catch (e: Exception) {
                // 直接アクセスが失敗した場合、ContentResolverを使用
            }

            // 方法2: ContentResolverを使用（Android 11以降）
            if (inputStream == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    val uri = getUriFromPath(externalPath)
                    if (uri != null) {
                        inputStream = contentResolver.openInputStream(uri)
                    }
                } catch (e: Exception) {
                    // ContentResolverが失敗した場合
                }
            }

            // 方法3: ファイル名からMediaStoreを検索
            if (inputStream == null) {
                try {
                    val uri = findFileInMediaStore(fileName)
                    if (uri != null) {
                        inputStream = contentResolver.openInputStream(uri)
                    }
                } catch (e: Exception) {
                    // MediaStore検索が失敗した場合
                }
            }

            if (inputStream == null) {
                return null
            }

            // ファイルをコピー
            inputStream.use { input ->
                FileOutputStream(internalFile).use { output ->
                    input.copyTo(output)
                }
            }

            internalFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getUriFromPath(filePath: String): Uri? {
        return try {
            // ファイルパスからURIを生成
            val file = File(filePath)
            if (file.exists()) {
                Uri.fromFile(file)
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun findFileInMediaStore(fileName: String): Uri? {
        return try {
            val projection = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DISPLAY_NAME)
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ?"
            val selectionArgs = arrayOf(fileName)

            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    val idColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                    val id = it.getLong(idColumn)
                    Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id.toString())
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun copyFileToAppExternalCache(externalPath: String): String? {
        return try {
            android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 開始, path=$externalPath")
            
            // アプリの外部ストレージディレクトリを取得
            val externalCacheDir = getExternalCacheDir()
            if (externalCacheDir == null) {
                android.util.Log.e("MainActivity", "copyFileToAppExternalCache: getExternalCacheDir()がnull")
                return null
            }
            android.util.Log.d("MainActivity", "copyFileToAppExternalCache: cacheDir=${externalCacheDir.absolutePath}")

            val fileName = File(externalPath).name
            val cacheFile = File(externalCacheDir, "copied_${System.currentTimeMillis()}_$fileName")
            android.util.Log.d("MainActivity", "copyFileToAppExternalCache: コピー先=${cacheFile.absolutePath}")

            // 方法1: 直接ファイルパスでアクセスを試行
            var inputStream: InputStream? = null
            try {
                val externalFile = File(externalPath)
                android.util.Log.d("MainActivity", "copyFileToAppExternalCache: ファイル存在確認=${externalFile.exists()}, 読み取り可能=${externalFile.canRead()}")
                if (externalFile.exists() && externalFile.canRead()) {
                    inputStream = FileInputStream(externalFile)
                    android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 方法1成功（直接アクセス）")
                } else {
                    android.util.Log.w("MainActivity", "copyFileToAppExternalCache: 方法1失敗（ファイルが存在しないか読み取り不可）")
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "copyFileToAppExternalCache: 方法1エラー", e)
            }

            // 方法2: ContentResolverを使用（Android 11以降）
            if (inputStream == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 方法2を試行（ContentResolver）")
                    val uri = getUriFromPath(externalPath)
                    if (uri != null) {
                        android.util.Log.d("MainActivity", "copyFileToAppExternalCache: URI取得成功=$uri")
                        inputStream = contentResolver.openInputStream(uri)
                        android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 方法2成功（ContentResolver）")
                    } else {
                        android.util.Log.w("MainActivity", "copyFileToAppExternalCache: 方法2失敗（URIがnull）")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "copyFileToAppExternalCache: 方法2エラー", e)
                }
            }

            // 方法3: MediaStoreからファイル名で検索
            if (inputStream == null) {
                try {
                    android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 方法3を試行（MediaStore）")
                    val uri = findFileInMediaStore(fileName)
                    if (uri != null) {
                        android.util.Log.d("MainActivity", "copyFileToAppExternalCache: MediaStore URI取得成功=$uri")
                        inputStream = contentResolver.openInputStream(uri)
                        android.util.Log.d("MainActivity", "copyFileToAppExternalCache: 方法3成功（MediaStore）")
                    } else {
                        android.util.Log.w("MainActivity", "copyFileToAppExternalCache: 方法3失敗（MediaStore URIがnull）")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "copyFileToAppExternalCache: 方法3エラー", e)
                }
            }

            if (inputStream == null) {
                android.util.Log.e("MainActivity", "copyFileToAppExternalCache: すべての方法が失敗")
                return null
            }

            // ファイルをコピー
            android.util.Log.d("MainActivity", "copyFileToAppExternalCache: ファイルコピー開始")
            inputStream.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            android.util.Log.d("MainActivity", "copyFileToAppExternalCache: ファイルコピー成功, サイズ=${cacheFile.length()}")

            cacheFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "copyFileToAppExternalCache: 例外発生", e)
            e.printStackTrace()
            null
        }
    }
    
    private fun getIntentImagePath(): String? {
        return try {
            val intent = intent
            if (intent?.action == android.content.Intent.ACTION_VIEW) {
                val uri = intent.data
                if (uri != null) {
                    // URIからファイルパスを取得
                    val scheme = uri.scheme
                    if (scheme == "file") {
                        // file:// スキームの場合
                        val path = uri.path
                        if (path != null && File(path).exists()) {
                            android.util.Log.d("MainActivity", "Intentから画像パスを取得: $path")
                            return path
                        }
                    } else if (scheme == "content") {
                        // content:// スキームの場合（MediaStoreなど）
                        // 一時ファイルにコピーしてパスを返す
                        val inputStream = contentResolver.openInputStream(uri)
                        if (inputStream != null) {
                            val cacheDir = applicationContext.cacheDir
                            val tempFile = File(cacheDir, "intent_image_${System.currentTimeMillis()}.jpg")
                            inputStream.use { input ->
                                FileOutputStream(tempFile).use { output ->
                                    input.copyTo(output)
                                }
                            }
                            android.util.Log.d("MainActivity", "Intentから画像をコピー: ${tempFile.absolutePath}")
                            return tempFile.absolutePath
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Intent画像パス取得エラー", e)
            null
        }
    }
    
    private fun handleGetIntentExtra(): Map<String, Any?> {
        val currentIntent = latestIntent ?: intent
        val imagePath = currentIntent?.getStringExtra("image_path")
        val autoMode = currentIntent?.getBooleanExtra("auto_mode", false) ?: false

        android.util.Log.i(
            "AURAFACE",
            "handleGetIntentExtra: image_path=$imagePath auto_mode=$autoMode intent=$currentIntent"
        )

        // externalCacheDir の auto_input.png の存在も確認してログ出力
        val cacheDir = externalCacheDir
        val cachePath = if (cacheDir != null) {
            val f = File(cacheDir, "auto_input.png")
            if (f.exists()) {
                android.util.Log.i("AURAFACE", "[AUTO_MODE] externalCacheDir auto_input.png exists: ${f.path}")
                f.path
            } else {
                android.util.Log.i("AURAFACE", "[AUTO_MODE] externalCacheDir auto_input.png NOT FOUND: ${f.path}")
                null
            }
        } else {
            android.util.Log.i("AURAFACE", "[AUTO_MODE] externalCacheDir is null")
            null
        }

        val map = HashMap<String, Any?>()
        map["image_path"] = imagePath
        map["auto_mode"] = autoMode
        map["cache_auto_input"] = cachePath
        return map
    }
    
    private fun getIntentExtra(): Map<String, Any?> {
        return handleGetIntentExtra()
    }
    
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Activity がシングルタスク/シングルトップで再利用されたときにも Intent を更新
        latestIntent = intent
        setIntent(intent)
        android.util.Log.i("AURAFACE", "onNewIntent: $intent")
    }
}
