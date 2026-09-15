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
