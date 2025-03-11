class McpServerConfig {
  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String author;

  const McpServerConfig({
    required this.command,
    required this.args,
    this.env = const {},
    this.author = '',
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      command: json['command']?.toString() ?? '',
      args: (json['args'] as List<dynamic>).cast<String>(),
      env:
          (json['env'] as Map<String, dynamic>?)?.cast<String, String>() ??
          const {},
    );
  }
}
