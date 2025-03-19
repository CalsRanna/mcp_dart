import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/client/stdio_client.dart';
import 'package:mcp_dart/src/server/server_config.dart';

// import 'package:mcp_dart/mcp_dart.dart';

void main() {
  test('adds one to input values', () {
    // final calculator = Calculator();
    // expect(calculator.addOne(2), 3);
    // expect(calculator.addOne(-7), -6);
    // expect(calculator.addOne(0), 1);
  });

  test('mcp client', () async {
    var timeServer = {
      'command': 'uvx',
      'args': ['mcp-server-time', '--local-timezone=America/New_York'],
    };
    var fetchServer = {
      "command": "uvx",
      "args": ["mcp-server-fetch"],
    };
    final serverConfig = McpServerConfig.fromJson(timeServer);
    var mcpClient = McpStdioClient(serverConfig: serverConfig);
    try {
      // 初始化客户端
      await mcpClient.initialize();
      // 发送初始化消息
      final initResponse = await mcpClient.sendInitialize();
      print('初始化响应: $initResponse');

      final toolListResponse = await mcpClient.sendToolList();
      print('工具列表响应: $toolListResponse');
      var timeReponse = await mcpClient.sendToolCall(
        name: 'get_current_time',
        arguments: {'timezone': 'Asia/Shanghai'},
      );
      print('时间响应: $timeReponse');
      // var fetchResponse = await mcpClient.sendToolCall(
      //   name: 'fetch',
      //   arguments: {
      //     'url':
      //         'https://guangzhengli.com/blog/zh/model-context-protocol/#为什么-mcp-是一个突破',
      //   },
      // );
      // print('fetch 响应: $fetchResponse');
      mcpClient.dispose();
    } catch (e, stackTrace) {
      print('初始化消息发送失败: $e\n堆栈跟踪:\n$stackTrace');
      rethrow;
    }
  });
}
