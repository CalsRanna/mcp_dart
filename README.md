# mcp_dart

Dart实现的MCP（Model Context Protocol）客户端库，支持通过Stdio和SSE协议与MCP服务端通信。

## 功能特性

✅ 支持Stdio和SSE两种通信协议
✅ 完整的JSON-RPC 2.0实现
✅ 异步消息处理机制
✅ 进程状态监控
✅ 工具调用接口

## 安装

在`pubspec.yaml`中添加依赖：
```yaml
dependencies:
  mcp_dart: ^0.1.0
```

## 基本使用

```dart
import 'package:mcp_dart/mcp_dart.dart';

void main() async {
  final client = StdioMcpClient(
    serverConfig: McpServerConfig(
      command: 'dart',
      args: ['bin/server.dart'],
    ),
  );

  await client.initialize();
  
  // 发送初始化请求
  final response = await client.sendInitialize();
  LoggerUtil.logger.d('初始化响应: $response');

  // 发送心跳检测
  final ping = await client.sendPing();
  LoggerUtil.logger.d('心跳响应: $ping');
}
```

## 贡献指南

欢迎通过Issue和PR参与贡献：
1. Fork仓库
2. 创建特性分支（git checkout -b feature/amazing-feature）
3. 提交修改（git commit -m 'Add some amazing feature'）
4. 推送分支（git push origin feature/amazing-feature）
5. 发起Pull Request

## 许可证

[MIT License](LICENSE)
