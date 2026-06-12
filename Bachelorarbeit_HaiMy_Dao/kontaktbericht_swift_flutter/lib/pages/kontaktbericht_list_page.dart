import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kontaktbericht_swift_flutter/pages/kontaktbericht_form_page.dart';
import 'package:native_kontaktbericht/native_kontaktbericht.dart';

class KontaktberichtListPage extends StatefulWidget {
  const KontaktberichtListPage({super.key});

  @override
  State<KontaktberichtListPage> createState() => _KontaktberichtListPageState();
}

class _KontaktberichtListPageState extends State<KontaktberichtListPage> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => loading = true);
    try {
      final res = await compute(_ffiList, 0);
      if (!mounted) return;
      setState(() => items = res);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await compute(_ffiDelete, id);
    if (!mounted) return;
    if (ok) {
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Löschen fehlgeschlagen')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kontaktberichte')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Form öffnen; wenn zurück, reload
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KontaktberichtFormPage()),
          );
          await _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Neu'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Keine Kontaktberichte'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = items[i];
                    final ansp = (b['ansprechpartner'] ?? '').toString();
                    final typ = (b['typ'] ?? '').toString();
                    final inhalt = (b['inhalt'] ?? '').toString();
                    final dateISO = (b['dateISO'] ?? '').toString();
                    final id = (b['id'] ?? '').toString();

                    return ListTile(
                      title: Text(ansp.isEmpty ? 'Ohne Ansprechpartner' : ansp),
                      subtitle: Text('$typ\n$inhalt', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(id),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => KontaktberichtDetailPage(item: b),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

// isolate helpers
List<Map<String, dynamic>> _ffiList(int _) {
  final list = listKontaktberichte();
  return list;
}

bool _ffiDelete(String id) {
  return deleteKontaktbericht(id);
}

/// Simple Detail View
class KontaktberichtDetailPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const KontaktberichtDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final ansp = (item['ansprechpartner'] ?? '').toString();
    final typ = (item['typ'] ?? '').toString();
    final inhalt = (item['inhalt'] ?? '').toString();
    final dateISO = (item['dateISO'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Bericht')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kv('Ansprechpartner', ansp.isEmpty ? '—' : ansp),
          _kv('Datum', dateISO.isEmpty ? '—' : dateISO),
          _kv('Gesprächstyp', typ.isEmpty ? '—' : typ),
          const SizedBox(height: 12),
          const Text('Inhalt', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(inhalt.isEmpty ? '—' : inhalt),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
