import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/src/message.dart';
import 'package:mcp_dart/src/method.dart';
import 'package:mcp_dart/src/process.dart';
import 'package:mcp_dart/src/server/server_config.dart';
import 'package:mcp_dart/src/util/logger_util.dart';
import 'package:synchronized/synchronized.dart';

class McpStdioClient {
  final McpServerConfig serverConfig;
  late final Process process;
  final _writeLock = Lock();
  final _pendingRequests = <String, Completer<McpJsonRpcResponse>>{};
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

  Future<void> dispose() async {
    await _processStateController.close();
    process.kill();
  }

  Future<void> initialize() async {
    await _setup();
    await _initialize();
  }

  Future<void> notify(McpJsonRpcNotification notification) async {
    LoggerUtil.logger.d('RpcJsonNotification: $notification');
    await _writeStdin(utf8.encode(jsonEncode(notification.toJson())));
  }

  Future<McpJsonRpcResponse> request(McpJsonRpcRequest request) async {
    LoggerUtil.logger.d('RpcJsonRequest: $request');
    final completer = Completer<McpJsonRpcResponse>();
    _pendingRequests[request.id] = completer;

    try {
      await _writeStdin(utf8.encode(jsonEncode(request.toJson())));
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(request.id);
          throw TimeoutException('Request timed out: ${request.id}');
        },
      );
    } catch (e) {
      _pendingRequests.remove(request.id);
      rethrow;
    }
  }

  Future<McpJsonRpcResponse> sendPing() async {
    final message = McpJsonRpcRequest(method: 'ping');
    return request(message);
  }

  Future<McpJsonRpcResponse> callTool(
    String name, {
    Map<String, dynamic>? arguments,
  }) async {
    final message = McpJsonRpcRequest(
      method: McpMethod.callTool.value,
      params: {'name': name, 'arguments': arguments},
    );
    return request(message);
  }

  Future<McpJsonRpcResponse> listTools() async {
    final message = McpJsonRpcRequest(method: McpMethod.listTools.value);
    return request(message);
  }

  void _handleMessage(McpJsonRpcResponse response) {
    if (_pendingRequests.containsKey(response.id)) {
      final completer = _pendingRequests.remove(response.id);
      completer?.complete(response);
    }
  }

  Future<void> _initialize() async {
    final initializeRequest = McpJsonRpcRequest(
      method: McpMethod.initialize.value,
      params: {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'roots': {'listChanged': true},
          'sampling': {},
        },
        'clientInfo': {'name': 'McpStdioClient', 'version': '1.0.0'},
      },
    );
    try {
      await request(initializeRequest);
      final notification = McpJsonRpcNotification(
        method: McpMethod.notificationsInitialized.value,
      );
      await notify(notification);
    } catch (e) {
      LoggerUtil.logger.e(e);
      rethrow;
    }
  }

  Future<void> _setup() async {
    try {
      LoggerUtil.logger.d(
        'Run: ${serverConfig.command} ${serverConfig.args.join(" ")}',
      );

      _processStateController.add(const ProcessState.starting());

      process = await startProcess(
        serverConfig.command,
        serverConfig.args,
        serverConfig.env,
      );

      const lineSplitter = LineSplitter();
      final stdoutStream = process.stdout
          .transform(utf8.decoder)
          .transform(lineSplitter);

      stdoutStream.listen(
        (String line) {
          try {
            final response = McpJsonRpcResponse.fromJson(jsonDecode(line));
            LoggerUtil.logger.d('JsonRpcResponse: $response');
            _handleMessage(response);
          } catch (e, stack) {
            LoggerUtil.logger.e('Unknown error: $e\n$stack');
          }
        },
        onError: (error) {
          LoggerUtil.logger.e('stdout 错误: $error');
          for (final callback in stdErrCallback) {
            callback(error.toString());
          }
        },
        onDone: () {
          LoggerUtil.logger.d('stdout 流已关闭');
        },
      );

      process.stderr
          .transform(utf8.decoder)
          .listen(
            (String text) {
              LoggerUtil.logger.e('服务器错误输出: $text');
              for (final callback in stdErrCallback) {
                callback(text);
              }
            },
            onError: (error) {
              LoggerUtil.logger.e('stderr 错误: $error');
              for (final callback in stdErrCallback) {
                callback(error.toString());
              }
            },
          );

      // 监听进程退出
      process.exitCode.then((code) {
        LoggerUtil.logger.d('进程退出，退出码: $code');
        _processStateController.add(ProcessState.exited(code));
      });

      _processStateController.add(const ProcessState.running());
    } catch (e, stack) {
      LoggerUtil.logger.d('启动进程失败: $e\n$stack');
      _processStateController.add(ProcessState.error(e, stack));
      rethrow;
    }
  }

  Future<void> _writeStdin(List<int> data) async {
    try {
      await _writeLock.synchronized(() async {
        final String request = utf8.decode(data);
        process.stdin.writeln(request);
        await process.stdin.flush();
      });
    } catch (e) {
      LoggerUtil.logger.d('写入数据失败: $e');
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
