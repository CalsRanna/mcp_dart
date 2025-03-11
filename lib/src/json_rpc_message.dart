import 'dart:convert';

class McpJsonRpcMessage {
  final String? id;
  final String jsonrpc;
  final String method;
  final Map<String, dynamic>? params;
  final dynamic result;
  final dynamic error;

  McpJsonRpcMessage({
    this.id,
    this.jsonrpc = '2.0',
    required this.method,
    this.params,
    this.result,
    this.error,
  });

  factory McpJsonRpcMessage.fromJson(Map<String, dynamic> json) {
    return McpJsonRpcMessage(
      id: json['id']?.toString(),
      jsonrpc: json['jsonrpc']?.toString() ?? '2.0',
      method: json['method']?.toString() ?? '',
      params: json['params'] as Map<String, dynamic>?,
      result: json['result'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    if (id != null) json.putIfAbsent('id', () => id);
    json.putIfAbsent('jsonrpc', () => jsonrpc);
    json.putIfAbsent('method', () => method);
    if (params != null) json.putIfAbsent('params', () => params);
    json.putIfAbsent('result', () => result);
    json.putIfAbsent('error', () => error);
    return json;
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
