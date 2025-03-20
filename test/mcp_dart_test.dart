import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/src/client/stdio_client.dart';
import 'package:mcp_dart/src/server/server_config.dart';

void main() {
  test('mcp server fetch', () async {
    var server = {
      "command": "uvx",
      "args": ["mcp-server-fetch"],
    };
    final config = McpServerConfig.fromJson(server);
    var client = McpStdioClient(serverConfig: config);
    await client.initialize();
    var tools = await client.listTools();
    expect(tools.isNotEmpty, true);
    var tool = tools.firstWhere((tool) => tool.name == 'fetch');
    expect(tool.name, 'fetch');
    var response = await client.callTool(
      tool.name,
      arguments: {
        'url':
            'https://guangzhengli.com/blog/zh/model-context-protocol/#为什么-mcp-是一个突破',
      },
    );
    var text = response.result['content'].first['text'];
    expect(text, contains('终极指南'));
    client.dispose();
  });

  test('mcp server time', () async {
    var server = {
      'command': 'uvx',
      'args': ['mcp-server-time', '--local-timezone=Asia/Shanghai'],
    };
    final config = McpServerConfig.fromJson(server);
    var client = McpStdioClient(serverConfig: config);
    await client.initialize();
    var tools = await client.listTools();
    expect(tools.isNotEmpty, true);
    var tool = tools.firstWhere((tool) => tool.name == 'get_current_time');
    expect(tool.name, 'get_current_time');
    var response = await client.callTool(
      tool.name,
      arguments: {'timezone': 'Asia/Shanghai'},
    );
    var text = response.result['content'].first['text'];
    expect(text, contains('datetime'));
    client.dispose();
  });
}
