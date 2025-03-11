import 'package:mcp_dart/src/json_rpc_message.dart';
import 'package:mcp_dart/src/server/server_config.dart';

abstract class McpClient {
  McpServerConfig get serverConfig;

  Future<void> initialize();
  Future<void> dispose();
  Future<McpJsonRpcMessage> sendMessage(McpJsonRpcMessage message);
  Future<McpJsonRpcMessage> sendInitialize();
  Future<McpJsonRpcMessage> sendPing();
  Future<McpJsonRpcMessage> sendToolList();
  Future<McpJsonRpcMessage> sendToolCall({
    required String name,
    required Map<String, dynamic> arguments,
    String? id,
  });
}
