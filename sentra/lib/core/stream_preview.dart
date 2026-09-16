import 'dart:convert';

/// Extract display values from partial JSON without waiting for closing braces.
/// Only known result fields are displayed; metadata and keys stay hidden.
String streamPreview(String json) {
  const fields = {
    'text',
    'summary',
    'original',
    'corrected',
    'explanation',
    'part',
    'role',
    'title',
    'naturalness',
    'translation',
  };
  const arrays = {'notes', 'inflections'};
  final containers = <({bool array, String? field})>[];
  final values = <String>[];
  String? key;
  var i = 0;
  while (i < json.length) {
    final c = json[i];
    if (c == '{' || c == '[') {
      containers.add((array: c == '[', field: key));
      key = null;
      i++;
      continue;
    }
    if (c == '}' || c == ']') {
      if (containers.isNotEmpty) containers.removeLast();
      key = null;
      i++;
      continue;
    }
    if (c == ',') {
      key = null;
      i++;
      continue;
    }
    if (c != '"') {
      i++;
      continue;
    }
    final start = ++i;
    while (i < json.length) {
      if (json[i] == '\\') {
        i += 2;
        continue;
      }
      if (json[i] == '"') break;
      i++;
    }
    final complete = i < json.length;
    var raw = json.substring(start, i.clamp(start, json.length));
    if (!complete) {
      // Remove only unfinished escapes, including a split Unicode code point.
      var n = 0;
      while (n < raw.length) {
        if (raw[n] != '\\') {
          n++;
          continue;
        }
        final width = n + 1 < raw.length && raw[n + 1] == 'u' ? 6 : 2;
        if (n + width > raw.length) {
          raw = raw.substring(0, n);
          break;
        }
        n += width;
      }
    }
    String value;
    try {
      value = jsonDecode('"$raw"') as String;
    } on FormatException {
      break;
    }
    // Avoid rendering an unmatched UTF-16 high surrogate during emoji output.
    if (!complete &&
        value.isNotEmpty &&
        value.codeUnitAt(value.length - 1) >= 0xD800 &&
        value.codeUnitAt(value.length - 1) <= 0xDBFF) {
      value = value.substring(0, value.length - 1);
    }
    i = complete ? i + 1 : json.length;
    var next = i;
    while (next < json.length && json[next].trim().isEmpty) {
      next++;
    }
    if (complete && next < json.length && json[next] == ':') {
      key = value;
      i = next + 1;
    } else {
      final inTextArray =
          containers.isNotEmpty &&
          containers.last.array &&
          arrays.contains(containers.last.field);
      if ((fields.contains(key) || inTextArray) && value.isNotEmpty) {
        values.add(value);
      }
      key = null;
    }
  }
  return values.join('\n\n');
}

/// A display-only snapshot of an unfinished JSON object. Never used for saving
/// or validation: the gateway still validates the complete response at the end.
Map<String, dynamic> partialResult(String source) {
  final start = source.indexOf('{');
  if (start < 0) return {};
  final reader = _PartialJsonReader(source.substring(start));
  final value = reader.read();
  return value is Map<String, dynamic> ? value : {};
}

class _PartialJsonReader {
  _PartialJsonReader(this.source);
  final String source;
  int position = 0;
  bool closedString = false;

  void whitespace() {
    while (position < source.length && source[position].trim().isEmpty) {
      position++;
    }
  }

  dynamic read([int depth = 0]) {
    whitespace();
    if (position >= source.length || depth > 40) return null;
    final c = source[position];
    if (c == '"') return string();
    if (c == '{') {
      position++;
      final result = <String, dynamic>{};
      while (position < source.length) {
        whitespace();
        if (position >= source.length) break;
        if (source[position] == '}') {
          position++;
          break;
        }
        if (source[position] != '"') break;
        final key = string();
        if (!closedString) break;
        whitespace();
        if (position >= source.length || source[position] != ':') break;
        position++;
        final value = read(depth + 1);
        if (value != null) result[key] = value;
        whitespace();
        if (position < source.length && source[position] == ',') {
          position++;
        } else {
          if (position < source.length && source[position] == '}') position++;
          break;
        }
      }
      return result;
    }
    if (c == '[') {
      position++;
      final result = <dynamic>[];
      while (position < source.length) {
        whitespace();
        if (position >= source.length) break;
        if (source[position] == ']') {
          position++;
          break;
        }
        final before = position;
        final value = read(depth + 1);
        if (value != null) result.add(value);
        if (position == before) break;
        whitespace();
        if (position < source.length && source[position] == ',') {
          position++;
        } else {
          if (position < source.length && source[position] == ']') position++;
          break;
        }
      }
      return result;
    }
    final start = position;
    while (position < source.length &&
        !',}] \r\n\t'.contains(source[position])) {
      position++;
    }
    try {
      return jsonDecode(source.substring(start, position));
    } on FormatException {
      return null;
    }
  }

  String string() {
    position++;
    final start = position;
    var end = start;
    closedString = false;
    while (position < source.length) {
      final c = source[position];
      if (c == '"') {
        end = position++;
        closedString = true;
        break;
      }
      if (c == '\\') {
        final width =
            position + 1 < source.length && source[position + 1] == 'u' ? 6 : 2;
        if (position + width > source.length) {
          position = source.length;
          break;
        }
        position += width;
      } else {
        position++;
      }
      end = position;
    }
    try {
      var value = jsonDecode('"${source.substring(start, end)}"') as String;
      if (value.isNotEmpty &&
          value.codeUnitAt(value.length - 1) >= 0xD800 &&
          value.codeUnitAt(value.length - 1) <= 0xDBFF) {
        value = value.substring(0, value.length - 1);
      }
      return value;
    } on FormatException {
      return '';
    }
  }
}
