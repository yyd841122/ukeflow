import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/backup/backup_doc.dart';

/// 备份导入/导出流程(工单 21,同工单 18 image_pick_flow 模式):
/// 平台交互注入(pick/save,测试不碰平台通道),控制器只管
/// 「选文件→解码→解析」与「编码→保存框落盘」的可测编排;确认对话框、
/// 落库与 snackbar 是薄 UI,归设置页。
///
/// 导出通道只有一个:系统保存框(SAF 选目录落盘,用户真机验收后
/// 定型——OPPO 分享面板无「保存到文件」目标,分享面板通道已撤)。
///
/// 权限姿态(与工单 18 同纪律):系统文件选择器与保存框都按次授权,
/// App 全程不申请、不持有存储权限;用户取消即静默返回。文件内容一律过
/// [parseBackupJson] 闸,选择器放行任意类型——坏内容在编解码层拦下给
/// 可读错误,不靠扩展名。
sealed class BackupImportOutcome {
  const BackupImportOutcome();
}

/// 选到合法备份:解析完成,等用户确认覆盖导入。
class BackupReadyToRestore extends BackupImportOutcome {
  const BackupReadyToRestore({required this.doc});

  final BackupDoc doc;
}

/// 用户在选择器里取消:静默返回,库无变动、界面无报错。
class BackupImportCancelled extends BackupImportOutcome {
  const BackupImportCancelled();
}

/// 选文件/解码/解析失败:可读文案给引导,库无变动。
class BackupImportFailed extends BackupImportOutcome {
  const BackupImportFailed(this.message);

  final String message;
}

/// 导出(保存框)的结果族。
sealed class BackupSaveOutcome {
  const BackupSaveOutcome();
}

/// 用户在系统保存框选定位置,字节写入完成。
class BackupSaved extends BackupSaveOutcome {
  const BackupSaved();
}

/// 用户在保存框里取消返回:独立结果,页面静默。
class BackupSaveCancelled extends BackupSaveOutcome {
  const BackupSaveCancelled();
}

/// 保存失败:可读文案。
class BackupSaveFailed extends BackupSaveOutcome {
  const BackupSaveFailed(this.message);

  final String message;
}

typedef BackupPickerFn = Future<Uint8List?> Function();
typedef BackupSaveFn =
    Future<BackupSaveOutcome> Function(String fileName, Uint8List bytes);

class BackupFlow {
  BackupFlow({BackupPickerFn? pick, BackupSaveFn? save})
    : pick = pick ?? pickBackupFileFromDevice,
      save = save ?? saveBackupToDevice;

  /// 选文件来源(注入缝:测试给假 picker,生产走系统文件选择器)。
  final BackupPickerFn pick;

  /// 导出落盘出口(注入缝:测试捕获,生产走系统保存框/SAF)。
  final BackupSaveFn save;

  /// 选文件并解析成待还原文档。取消静默;坏文件带编解码层的
  /// 可读中文错误返回,不崩溃。
  Future<BackupImportOutcome> pickAndParse() async {
    final Uint8List? bytes;
    try {
      bytes = await pick();
    } on Object catch (error) {
      debugPrint('UkeFlow: 备份选文件失败 $error');
      return const BackupImportFailed('打开文件没成功——请再试一次');
    }
    if (bytes == null) return const BackupImportCancelled();

    final String json;
    try {
      json = utf8.decode(bytes);
    } on FormatException {
      return const BackupImportFailed('文件不是有效的文本内容——请选择 UkeFlow 导出的备份文件');
    }
    try {
      return BackupReadyToRestore(doc: parseBackupJson(json));
    } on BackupFormatException catch (error) {
      return BackupImportFailed(error.message);
    }
  }

  /// 导出备份:编码为 UTF-8 字节,走系统保存框(SAF)由用户选目录落盘。
  Future<BackupSaveOutcome> export(String json) async {
    try {
      return await save(backupFileName(), utf8.encode(json));
    } on Object catch (error) {
      debugPrint('UkeFlow: 备份导出失败 $error');
      return const BackupSaveFailed('导出没成功——请再试一次');
    }
  }

  /// 备份文件名:带日期,ASCII 安全。
  static String backupFileName() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'ukeflow-backup-${now.year}-$month-$day.json';
  }
}

/// 生产选文件:系统文件选择器,不限类型(坏内容由编解码层拦,
/// 不赌各厂商文件管理器对 .json 的 MIME 标注)。返回 null = 用户取消。
Future<Uint8List?> pickBackupFileFromDevice() async {
  final file = await openFile(confirmButtonText: '导入');
  if (file == null) return null;
  return file.readAsBytes();
}

/// 生产导出:系统保存框(ACTION_CREATE_DOCUMENT,经 MainActivity 的
/// 平台通道,见 android/…/MainActivity.kt)。返回 null = 用户取消;
/// 成功返回写入完成的 content:// uri。免存储权限(SAF 按次授权)。
Future<BackupSaveOutcome> saveBackupToDevice(
  String fileName,
  Uint8List bytes,
) async {
  final channel = MethodChannel('ukeflow/save_file');
  final uri = await channel.invokeMethod<String>('saveJsonFile', {
    'fileName': fileName,
    'bytes': bytes,
  });
  if (uri == null) return const BackupSaveCancelled();
  return const BackupSaved();
}
