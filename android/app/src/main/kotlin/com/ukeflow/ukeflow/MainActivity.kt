package com.ukeflow.ukeflow

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 备份「保存到本地」的平台通道(工单 21):系统保存框
// (ACTION_CREATE_DOCUMENT)由用户选目录授权写入——SAF 按次授权,
// App 不申请存储权限,与图片谱/备份导入导出的权限姿态一致。
// FlutterActivity 非 ComponentActivity,走经典 startActivityForResult
// (onActivityResult API 虽标弃用,在纯 Activity 上仍是无依赖的正解)。
class MainActivity : FlutterActivity() {
    companion object {
        private const val SAVE_REQUEST = 2101
        private const val CHANNEL = "ukeflow/save_file"
    }

    private var saveResult: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveJsonFile") {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName == null || bytes == null) {
                        result.error("BAD_ARGS", "缺少文件名或内容", null)
                        return@setMethodCallHandler
                    }
                    saveResult = result
                    saveBytes = bytes
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, fileName)
                    }
                    startActivityForResult(intent, SAVE_REQUEST)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val result = saveResult
        val bytes = saveBytes
        saveResult = null
        saveBytes = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        when {
            uri == null -> result?.success(null) // 用户在保存框取消
            bytes == null -> result?.error("SAVE_FAILED", "备份内容丢失", null)
            else ->
                try {
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    result?.success(uri.toString())
                } catch (e: Exception) {
                    result?.error("SAVE_FAILED", e.message, null)
                }
        }
    }
}
