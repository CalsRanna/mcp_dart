export 'src/client/client.dart';
export '../src/json_rpc_message.dart';

import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/server/server_config.dart';
import 'package:mcp_dart/src/client/sse_client.dart';
import 'package:mcp_dart/src/client/stdio_client.dart';

Future<McpClient> initializeMcpServer(
  Map<String, dynamic> mcpServerConfig,
) async {
  // 获取服务器配置
  final serverConfig = McpServerConfig.fromJson(mcpServerConfig);
  // 根据配置创建相应的客户端
  McpClient mcpClient;
  if (serverConfig.command.startsWith('http')) {
    mcpClient = McpSseClient(serverConfig: serverConfig);
  } else {
    mcpClient = McpStdioClient(serverConfig: serverConfig);
  }
  try {
    // 初始化客户端
    await mcpClient.initialize();
    // 发送初始化消息
    final initResponse = await mcpClient.sendInitialize();
    print('初始化响应: $initResponse');

    final toolListResponse = await mcpClient.sendToolList();
    print('工具列表响应: $toolListResponse');
  } catch (e, stackTrace) {
    print('初始化消息发送失败: $e\n堆栈跟踪:\n$stackTrace');
    rethrow;
  }

  return mcpClient;
}

Future<Map<String, McpClient>> initializeAllMcpServers(
  String configPath,
) async {
  final file = File(configPath);
  final contents = await file.readAsString();

  final Map<String, dynamic> config =
      json.decode(contents) as Map<String, dynamic>? ?? {};

  final mcpServers = config['mcpServers'] as Map<String, dynamic>;

  final Map<String, McpClient> clients = {};

  for (var entry in mcpServers.entries) {
    final serverConfig = entry.value as Map<String, dynamic>;
    final client = await initializeMcpServer(serverConfig);
    clients[entry.key] = client;
  }

  return clients;
}

Future<bool> verifyMcpServer(Map<String, dynamic> mcpServerConfig) async {
  final serverConfig = McpServerConfig.fromJson(mcpServerConfig);
  final mcpClient =
      serverConfig.command.startsWith('http')
          ? McpSseClient(serverConfig: serverConfig)
          : McpStdioClient(serverConfig: serverConfig);

  try {
    await mcpClient.sendInitialize();
    return true;
  } catch (e) {
    return false;
  }
}
