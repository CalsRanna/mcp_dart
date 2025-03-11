import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/client/stdio_client.dart';
import 'package:mcp_dart/src/server/server_config.dart';
import 'package:synchronized/synchronized.dart';

class McpSseClient implements McpClient {
  final McpServerConfig _serverConfig;
  final _pendingRequests = <String, Completer<McpJsonRpcMessage>>{};
  final _processStateController = StreamController<ProcessState>.broadcast();
  StreamSubscription? _sseSubscription;

  final _writeLock = Lock();
  String? _messageEndpoint;
  McpSseClient({required McpServerConfig serverConfig})
    : _serverConfig = serverConfig;

  Stream<ProcessState> get processStateStream => _processStateController.stream;

  @override
  McpServerConfig get serverConfig => _serverConfig;

  @override
  Future<void> dispose() async {
    await _sseSubscription?.cancel();
    await _processStateController.close();
  }

  @override
  Future<void> initialize() async {
    try {
      Logger.root.info('开始 SSE 连接: ${serverConfig.command}');
      _processStateController.add(const ProcessState.starting());

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(serverConfig.command));
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      request.headers.set('Connection', 'keep-alive');

      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('SSE 连接失败: ${response.statusCode}');
      }

      _sseSubscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (String line) {
              if (line.startsWith('event: endpoint')) {
                return;
              }
              if (line.startsWith('data: ')) {
                final data = line.substring(6);
                if (_messageEndpoint == null) {
                  final baseUrl =
                      Uri.parse(
                        serverConfig.command,
                      ).replace(path: '').toString();
                  _messageEndpoint =
                      data.startsWith("http") ? data : baseUrl + data;
                  Logger.root.info('收到消息端点: $_messageEndpoint');
                  _processStateController.add(const ProcessState.running());
                } else {
                  try {
                    final jsonData = jsonDecode(data);
                    final message = McpJsonRpcMessage.fromJson(jsonData);
                    _handleMessage(message);
                  } catch (e, stack) {
                    Logger.root.severe('解析服务器消息失败: $e\n$stack');
                  }
                }
              }
            },
            onError: (error) {
              Logger.root.severe('SSE 连接错误: $error');
              _processStateController.add(
                ProcessState.error(error, StackTrace.current),
              );
            },
            onDone: () {
              Logger.root.info('SSE 连接已关闭');
              _processStateController.add(const ProcessState.exited(0));
            },
          );
    } catch (e, stack) {
      Logger.root.severe('SSE 连接失败: $e\n$stack');
      _processStateController.add(ProcessState.error(e, stack));
      rethrow;
    }
  }

  @override
  Future<McpJsonRpcMessage> sendInitialize() async {
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

    Logger.root.info('初始化请求: ${jsonEncode(initMessage.toString())}');

    final initResponse = await sendMessage(initMessage);
    Logger.root.info('初始化请求响应: $initResponse');

    final notifyMessage = McpJsonRpcMessage(method: 'initialized', params: {});

    await _sendHttpPost(notifyMessage.toJson());
    return initResponse;
  }

  @override
  Future<McpJsonRpcMessage> sendMessage(McpJsonRpcMessage message) async {
    if (message.id == null) {
      throw ArgumentError('消息必须包含 ID');
    }

    final completer = Completer<McpJsonRpcMessage>();
    _pendingRequests[message.id!] = completer;

    try {
      await _sendHttpPost(message.toJson());
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(message.id);
          throw TimeoutException('请求超时: ${message.id}');
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

  void _handleMessage(McpJsonRpcMessage message) {
    if (message.id != null && _pendingRequests.containsKey(message.id)) {
      final completer = _pendingRequests.remove(message.id);
      completer?.complete(message);
    }
  }

  Future<void> _sendHttpPost(Map<String, dynamic> data) async {
    if (_messageEndpoint == null) {
      throw StateError('消息端点尚未初始化 ${jsonEncode(data)}');
    }

    await _writeLock.synchronized(() async {
      try {
        await Dio().post(
          _messageEndpoint!,
          data: jsonEncode(data),
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
      } catch (e) {
        Logger.root.severe('发送 HTTP POST 失败: $e');
        rethrow;
      }
    });
  }
}
