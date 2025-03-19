import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/process.dart';
import 'package:mcp_dart/src/server/server_config.dart';
import 'package:synchronized/synchronized.dart';

class McpStdioClient implements McpClient {
  @override
  final McpServerConfig serverConfig;
  late final Process process;
  final _writeLock = Lock();
  final _pendingRequests = <String, Completer<McpJsonRpcMessage>>{};
  final List<Function(String)> stdErrCallback;
  final List<Function(String)> stdOutCallback;

  // 添加 StreamController
  final _processStateController = StreamController<ProcessState>.broadcast();

  McpStdioClient({
    required this.serverConfig,
    this.stdErrCallback = const [],
    this.stdOutCallback = const [],
  });

  // 提供公开的 Stream
  Stream<ProcessState> get processStateStream => _processStateController.stream;

  // 修改 dispose 方法
  @override
  Future<void> dispose() async {
    await _processStateController.close();
    process.kill();
  }

  // 添加初始化方法
  @override
  Future<void> initialize() async {
    await _setupProcess();
  }

  @override
  Future<McpJsonRpcMessage> sendInitialize() async {
    // 第一步：发送初始化请求
    final initMessage = McpJsonRpcMessage(
      id: 'init-1',
      method: 'initialize',
      params: {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'roots': {'listChanged': true},
          'sampling': {},
        },
        'clientInfo': {'name': 'DartMCPClient', 'version': '1.0.0'},
      },
    );

    try {
      final initResponse = await sendMessage(initMessage);
      print('初始化请求响应: $initResponse');

      // 第二步：发送初始化完成通知（不需要等待响应）
      final notifyMessage = McpJsonRpcMessage(
        method: 'notifications/initialized', // 移除 notifications/ 前缀
        params: {}, // 添加空的参数对象
      );

      await write(utf8.encode(jsonEncode(notifyMessage.toJson())));
      return initResponse;
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  @override
  Future<McpJsonRpcMessage> sendMessage(McpJsonRpcMessage message) async {
    if (message.id == null) {
      throw ArgumentError('Message must have an id');
    }

    final completer = Completer<McpJsonRpcMessage>();
    _pendingRequests[message.id!] = completer;

    try {
      await write(utf8.encode(jsonEncode(message.toJson())));
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(message.id);
          throw TimeoutException('Request timed out: ${message.id}');
        },
      );
    } catch (e) {
      _pendingRequests.remove(message.id);
      rethrow;
    }
  }

  @override
  Future<McpJsonRpcMessage> sendPing() async {
    final message = McpJsonRpcMessage(id: 'ping-1', method: 'ping');
    return sendMessage(message);
  }

  @override
  Future<McpJsonRpcMessage> sendToolCall({
    required String name,
    required Map<String, dynamic> arguments,
    String? id,
  }) async {
    final message = McpJsonRpcMessage(
      method: 'tools/call',
      params: {
        'name': name,
        'arguments': arguments,
        '_meta': {'progressToken': 0},
      },
      id: id ?? 'tool-call-${DateTime.now().millisecondsSinceEpoch}',
    );

    return sendMessage(message);
  }

  @override
  Future<McpJsonRpcMessage> sendToolList() async {
    final message = McpJsonRpcMessage(id: 'tool-list-1', method: 'tools/list');
    return sendMessage(message);
  }

  Future<void> write(List<int> data) async {
    try {
      await _writeLock.synchronized(() async {
        final String jsonStr = utf8.decode(data);
        process.stdin.writeln(utf8.decode(data));
        await process.stdin.flush();
        print('写入数据: $jsonStr');
      });
    } catch (e) {
      print('写入数据失败: $e');
      rethrow;
    }
  }

  void _handleMessage(McpJsonRpcMessage message) {
    if (message.id != null && _pendingRequests.containsKey(message.id)) {
      final completer = _pendingRequests.remove(message.id);
      completer?.complete(message);
    }
  }

  Future<void> _setupProcess() async {
    try {
      print('启动进程: ${serverConfig.command} ${serverConfig.args.join(" ")}');

      _processStateController.add(const ProcessState.starting());

      process = await startProcess(
        serverConfig.command,
        serverConfig.args,
        serverConfig.env,
      );

      print('进程启动状态：PID=${process.pid}');

      // 使用 utf8 解码器
      final stdoutStream = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      stdoutStream.listen(
        (String line) {
          print(line);
          try {
            for (final callback in stdOutCallback) {
              callback(line);
            }
            final data = jsonDecode(line);
            final message = McpJsonRpcMessage.fromJson(data);
            _handleMessage(message);
          } catch (e, stack) {
            print('解析服务器输出失败: $e\n$stack');
          }
        },
        onError: (error) {
          print('stdout 错误: $error');
          for (final callback in stdErrCallback) {
            callback(error.toString());
          }
        },
        onDone: () {
          print('stdout 流已关闭');
        },
      );

      process.stderr
          .transform(utf8.decoder)
          .listen(
            (String text) {
              Logger.root.warning('服务器错误输出: $text');
              for (final callback in stdErrCallback) {
                callback(text);
              }
            },
            onError: (error) {
              print('stderr 错误: $error');
              for (final callback in stdErrCallback) {
                callback(error.toString());
              }
            },
          );

      // 监听进程退出
      process.exitCode.then((code) {
        print('进程退出，退出码: $code');
        _processStateController.add(ProcessState.exited(code));
      });

      _processStateController.add(const ProcessState.running());
    } catch (e, stack) {
      print('启动进程失败: $e\n$stack');
      _processStateController.add(ProcessState.error(e, stack));
      rethrow;
    }
  }
}

// 添加进程状态类
class ProcessState {
  final ProcessStateType type;
  final dynamic error;
  final StackTrace? stackTrace;
  final int? exitCode;

  const ProcessState.error(dynamic err, StackTrace stack)
    : this._(ProcessStateType.error, error: err, stackTrace: stack);

  const ProcessState.exited(int code)
    : this._(ProcessStateType.exited, exitCode: code);
  const ProcessState.running() : this._(ProcessStateType.running);
  const ProcessState.starting() : this._(ProcessStateType.starting);
  const ProcessState._(this.type, {this.error, this.stackTrace, this.exitCode});
}

// 添加进程状态枚举
enum ProcessStateType { starting, running, error, exited }
