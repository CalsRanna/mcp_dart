class McpInputSchema {
  final String type;
  final Map<String, McpProperty>? properties;
  final List<String>? required;

  McpInputSchema({required this.type, this.properties, this.required});

  factory McpInputSchema.fromJson(Map<String, dynamic> json) {
    Map<String, McpProperty>? props;
    if (json['properties'] != null) {
      props = Map.fromEntries(
        (json['properties'] as Map<String, dynamic>).entries.map(
          (e) => MapEntry(e.key, McpProperty.fromJson(e.value)),
        ),
      );
    }

    return McpInputSchema(
      type: json['type'],
      properties: props,
      required:
          json['required'] != null ? List<String>.from(json['required']) : null,
    );
  }
}

class McpProperty {
  final String type;
  final String? description;

  McpProperty({required this.type, this.description});

  factory McpProperty.fromJson(Map<String, dynamic> json) {
    return McpProperty(type: json['type'], description: json['description']);
  }
}

class McpTool {
  final String name;
  final String description;
  final McpInputSchema inputSchema;

  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'],
      description: json['description'],
      inputSchema: McpInputSchema.fromJson(json['inputSchema']),
    );
  }
}

class McpToolResponse {
  final List<McpTool> tools;

  McpToolResponse({required this.tools});

  factory McpToolResponse.fromJson(Map<String, dynamic> json) {
    var toolsList = json['tools'] as List;
    List<McpTool> tools = toolsList.map((t) => McpTool.fromJson(t)).toList();
    return McpToolResponse(tools: tools);
  }
}
