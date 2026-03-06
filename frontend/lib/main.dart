import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CheapFoodApp());
}

class CheapFoodApp extends StatelessWidget {
  const CheapFoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheapFood',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MenuScrapeScreen(),
    );
  }
}

class MenuItem {
  final String name;
  final String? description;
  final double? price;
  final String currency;

  const MenuItem({
    required this.name,
    this.description,
    this.price,
    this.currency = 'USD',
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      name: json['name'] as String,
      description: json['description'] as String?,
      price: switch (json['price']) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      },
      currency: (json['currency'] as String?) ?? 'USD',
    );
  }
}

class MenuScrapeScreen extends StatefulWidget {
  const MenuScrapeScreen({super.key});

  @override
  State<MenuScrapeScreen> createState() => _MenuScrapeScreenState();
}

class _MenuScrapeScreenState extends State<MenuScrapeScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<MenuItem> _items = [];
  bool _loading = false;
  String? _error;

  static const String _backendUrl = 'http://localhost:8080';

  Future<void> _scrape() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _items = data
              .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() {
          _error = 'Ошибка сервера: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Не удалось подключиться: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CheapFood'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL ресторана',
                      hintText: 'https://example.com/menu',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _scrape(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _loading ? null : _scrape,
                  child: const Text('Найти'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_items.isNotEmpty) ...[
              Text(
                'Найдено блюд: ${_items.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: item.description != null
                          ? Text(item.description!)
                          : null,
                      trailing: item.price != null
                          ? Text(
                              '${item.price!.toStringAsFixed(2)} ${item.currency}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
