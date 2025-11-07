import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class PLCConfigView extends StatefulWidget {
  const PLCConfigView({Key? key}) : super(key: key);

  @override
  _PLCConfigViewState createState() => _PLCConfigViewState();
}

class _PLCConfigViewState extends State<PLCConfigView> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _liveValues;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _startLivePoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startLivePoll() {
    // Poll HMI live data every second from the gateway REST API
    _pollTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      try {
        final uri = Uri.parse('http://127.0.0.1:5000/api/v1/hmi/data');
        final resp = await http.get(uri).timeout(Duration(seconds: 1));
        if (resp.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(resp.body) as Map<String, dynamic>;
          // the script returns a mapping under 'tags' (map tag_id -> value)
          final tags = data['tags'] as Map<String, dynamic>?;
          if (tags != null) {
            setState(() {
              _liveValues = tags;
            });
          }
        }
      } catch (_) {
        // ignore network errors while polling; keep previous values
      }
    });
  }

  Future<void> _loadConfig() async {
    // Try to fetch PLC config from gateway REST API first. If unavailable,
    // fall back to the bundled asset file.
    try {
      final uri = Uri.parse('http://127.0.0.1:5000/api/v1/hmi/config');
      final resp = await http.get(uri).timeout(Duration(milliseconds: 800));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _config = decoded;
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // ignore and fall back to asset
    }

    try {
      final jsonStr = await rootBundle.loadString('assets/plc_config.json');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _config = decoded;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PLC Configuration')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error loading config: $_error'))
              : _buildConfigList(),
    );
  }

  Widget _buildConfigList() {
    final plcs = (_config!['plcs'] as List<dynamic>?) ?? [];
    return ListView.builder(
      itemCount: plcs.length,
      itemBuilder: (context, idx) {
        final plc = plcs[idx] as Map<String, dynamic>;
        final tags = (plc['tags'] as List<dynamic>?) ?? [];
        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            title: Text('${plc['plc_id']} (${plc['type']})'),
            subtitle: Text(plc['host'] ?? ''),
            children: tags.map<Widget>((t) {
              final tag = t as Map<String, dynamic>;
              // Look up live value if available
              final liveVal = _liveValues != null ? _liveValues![tag['tag_id']] : null;
              String valueText = '';
              if (liveVal != null) {
                valueText = ' • Value: $liveVal';
              }
              return ListTile(
                title: Text(tag['name'] ?? tag['tag_id'] ?? ''),
                subtitle: Text('Address: ${tag['address'] ?? ''} • Type: ${tag['data_type'] ?? ''}$valueText'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (tag.containsKey('scale_mul')) Text('scale: ${tag['scale_mul']}'),
                    if (tag.containsKey('decimals')) Text('decimals: ${tag['decimals']}'),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
