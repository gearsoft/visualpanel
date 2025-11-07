// Dynamic Flutter HMI: no static PLC info. Allows picking a JSON config file
// or loading the config from the gateway REST API. Displays dynamic tag
// tiles and polls the gateway for live values. Also provides a button to
// clear the UI and request tag deletion on the gateway.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const VisualPanelApp());
}

class VisualPanelApp extends StatelessWidget {
  const VisualPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VisualPanel HMI',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HmiHome(),
    );
  }
}

class HmiHome extends StatefulWidget {
  const HmiHome({super.key});

  @override
  State<HmiHome> createState() => _HmiHomeState();
}

class _HmiHomeState extends State<HmiHome> {
  // tag metadata keyed by tag_id
  final Map<String, Map<String, dynamic>> _tagsMeta = {};
  // latest values keyed by tag_id (may be strings for Decimal values)
  final Map<String, dynamic> _values = {};

  Timer? _pollTimer;
  bool _loading = false;
  final _gatewayBase = 'http://127.0.0.1:5000';

  @override
  void initState() {
    super.initState();
    // don't start polling until config is loaded
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openConfigFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null) return; // user canceled
    try {
      setState(() => _loading = true);
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final decoded = jsonDecode(utf8.decode(bytes));

      // If the file is the HMI `plc_config.json` shape (contains `plcs`),
      // transform it into the gateway-importable shape: {"tags": [ ... ]}
      // and POST it to the gateway import endpoint. Otherwise, pass the
      // decoded object through to _applyConfig which accepts either
      // {"tags": [...]} or a plain list of tags.
      if (decoded is Map && decoded['plcs'] is List) {
        final List<dynamic> plcs = decoded['plcs'] as List<dynamic>;
        final List<Map<String, dynamic>> tags = [];
        for (final plc in plcs) {
          if (plc is Map && plc['tags'] is List) {
            final String? plcId = plc['plc_id']?.toString();
            for (final t in plc['tags']) {
              if (t is Map) {
                final Map<String, dynamic> tag = {};
                // copy fields from the picked tag
                t.forEach((k, v) => tag[k.toString()] = v);
                if (plcId != null) tag['plc_id'] = plcId;
                tags.add(tag);
              }
            }
          }
        }

        // POST to gateway import endpoint so the server becomes the canonical
        // source of tag metadata.
        final uri = Uri.parse('$_gatewayBase/api/v1/tags/import?replace_all=true');
        try {
          final resp = await http
              .put(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'tags': tags}))
              .timeout(const Duration(seconds: 5));
          if (resp.statusCode == 200 || resp.statusCode == 201) {
            // Apply locally so UI updates immediately
            _applyConfig({'tags': tags});
            _showSnack('Imported ${tags.length} tags to gateway');
          } else {
            _showSnack('Gateway rejected import: ${resp.statusCode}');
          }
        } catch (e) {
          _showSnack('Failed to POST config to gateway: $e');
        }
      } else {
        _applyConfig(decoded);
      }
    } catch (e) {
      _showSnack('Failed to load config: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadConfigFromGateway() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('$_gatewayBase/api/v1/hmi/config');
      final r = await http.get(uri).timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        _applyConfig(decoded);
      } else {
        _showSnack('Gateway returned ${r.statusCode}');
      }
    } catch (e) {
      _showSnack('Failed to fetch config: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyConfig(dynamic decoded) {
    // Normalized config: accept either {"tags": [...]} or top-level list
    final List<dynamic> tags = (decoded is Map && decoded['tags'] is List)
        ? decoded['tags'] as List
        : (decoded is List ? decoded : []);
    final Map<String, Map<String, dynamic>> meta = {};
    for (final t in tags) {
      if (t is Map && t['tag_id'] != null) {
        meta[t['tag_id'] as String] = Map<String, dynamic>.from(t);
      }
    }
    setState(() {
      _tagsMeta.clear();
      _tagsMeta.addAll(meta);
      _values.clear();
    });
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_tagsMeta.isEmpty) return;
    try {
      final uri = Uri.parse('$_gatewayBase/api/v1/hmi/data');
      final r = await http.get(uri).timeout(const Duration(seconds: 2));
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        // Expect {"tags": {"tag_id": value, ... }}
        final Map<String, dynamic> incoming =
            decoded is Map && decoded['tags'] is Map ? Map.from(decoded['tags']) : {};
        setState(() {
          for (final entry in incoming.entries) {
            _values[entry.key] = entry.value;
          }
        });
      }
    } catch (_) {
      // ignore network hiccups in the UI polling loop
    }
  }

  Future<void> _clearAndDeleteTags() async {
    if (_tagsMeta.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tags?'),
        content: const Text('This will attempt to delete the tags from the gateway and clear the UI.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final toDelete = List<String>.from(_tagsMeta.keys);
    for (final tagId in toDelete) {
      try {
        final uri = Uri.parse('$_gatewayBase/api/v1/tags/$tagId');
        await http.delete(uri).timeout(const Duration(seconds: 2));
      } catch (_) {
        // best-effort deletion
      }
    }
    setState(() {
      _tagsMeta.clear();
      _values.clear();
    });
    _pollTimer?.cancel();
  }

  String _formatValue(dynamic v, Map<String, dynamic>? meta) {
    if (v == null) return '-';
    // Decimal values from the gateway are serialized as strings. If we
    // detect a numeric string, keep it as-is to preserve trailing zeros.
    if (v is String) return v;
    if (v is num) {
      final decimals = meta != null && meta['decimals'] != null ? meta['decimals'] as int : 2;
      return NumberFormat('#,##0${decimals > 0 ? '.' + ('0' * decimals) : ''}').format(v);
    }
    return v.toString();
  }

  Color _valueColor(dynamic current, dynamic previous) {
    if (current == null) return Colors.grey.shade700;
    if (previous == null) return Colors.black;
    try {
      final cur = double.parse(current.toString());
      final prev = double.parse(previous.toString());
      if (cur > prev) return Colors.green.shade700;
      if (cur < prev) return Colors.red.shade700;
      return Colors.black;
    } catch (_) {
      return Colors.black;
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VisualPanel HMI')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open JSON File'),
                  onPressed: _openConfigFile,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Load from Gateway'),
                  onPressed: _loadConfigFromGateway,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clear & Delete Tags'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: _clearAndDeleteTags,
                ),
                const Spacer(),
                if (_loading) const CircularProgressIndicator(),
              ],
            ),
          ),
          Expanded(
            child: _tagsMeta.isEmpty
                ? const Center(child: Text('No PLC configuration loaded. Open a JSON file or load from gateway.'))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _pollOnce();
                    },
                    child: ListView.builder(
                      itemCount: _tagsMeta.length,
                      itemBuilder: (context, index) {
                        final tagId = _tagsMeta.keys.elementAt(index);
                        final meta = _tagsMeta[tagId];
                        final value = _values[tagId];
                        final prev = null; // not tracking history here; could be extended
                        return ListTile(
                          title: Text(meta?['name'] ?? tagId),
                          subtitle: Text('${meta?['address'] ?? ''} • ${meta?['data_type'] ?? ''}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatValue(value, meta),
                                style: TextStyle(fontSize: 16, color: _valueColor(value, prev)),
                              ),
                              if (meta != null && meta['description'] != null)
                                Text(meta['description'], style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}