import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

// Flutter Web / Chrome: localhost.

// Android Emulator: ganti menjadi http://10.0.2.2:8080/api

// HP fisik: gunakan IP LAN komputer, misalnya http://192.168.1.10:8080/api

const String apiBaseUrl = 'http://localhost:8080/api';

void main() {
  runApp(const PasataApp());
}

class PasataApp extends StatelessWidget {
  const PasataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PASATA',

      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B52)),

        scaffoldBackgroundColor: const Color(0xFFF5F7F6),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF176B52),

          foregroundColor: Colors.white,
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,

          fillColor: Colors.white,

          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),

            borderSide: const BorderSide(color: Color(0xFFE0E7E3)),
          ),
        ),
      ),

      home: const DashboardPage(),
    );
  }
}

class Warehouse {
  final int id;

  final String code;

  final String name;

  final String? address;

  final String? city;

  final String? phone;

  final int capacityPallet;

  final String status;

  final String? createdAt;

  final String? updatedAt;

  const Warehouse({
    required this.id,

    required this.code,

    required this.name,

    this.address,

    this.city,

    this.phone,

    required this.capacityPallet,

    required this.status,

    this.createdAt,

    this.updatedAt,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: (json['id'] as num).toInt(),

      code: (json['code'] ?? '').toString(),

      name: (json['name'] ?? '').toString(),

      address: json['address']?.toString(),

      city: json['city']?.toString(),

      phone: json['phone']?.toString(),

      capacityPallet: (json['capacity_pallet'] as num?)?.toInt() ?? 0,

      status: (json['status'] ?? 'ACTIVE').toString(),

      createdAt: json['created_at']?.toString(),

      updatedAt: json['updated_at']?.toString(),
    );
  }
}

class WarehouseApi {
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',

    'Accept': 'application/json',
  };

  static Future<List<Warehouse>> list() async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/warehouses'), headers: _headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(response, 'Gagal mengambil data gudang'),
      );
    }

    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw Exception('Format respons daftar gudang tidak valid.');
    }

    return decoded
        .map((item) => Warehouse.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<Warehouse> create(Map<String, dynamic> data) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/warehouses'),

          headers: _headers,

          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      throw Exception(_responseMessage(response, 'Gagal menambahkan gudang'));
    }

    return Warehouse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<Warehouse> update(int id, Map<String, dynamic> data) async {
    final response = await http
        .put(
          Uri.parse('$apiBaseUrl/warehouses/$id'),

          headers: _headers,

          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(_responseMessage(response, 'Gagal mengubah gudang'));
    }

    return Warehouse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // Backend saat ini menggunakan DELETE fisik. Kirim PUT status INACTIVE

  // sebagai gantinya agar riwayat gudang tetap tersimpan.

  static Future<void> deactivate(Warehouse warehouse) async {
    final response = await http
        .put(
          Uri.parse('$apiBaseUrl/warehouses/${warehouse.id}'),

          headers: _headers,

          body: jsonEncode({
            'code': warehouse.code,

            'name': warehouse.name,

            'address': warehouse.address,

            'city': warehouse.city,

            'phone': warehouse.phone,

            'capacity_pallet': warehouse.capacityPallet,

            'status': 'INACTIVE',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(_responseMessage(response, 'Gagal menonaktifkan gudang'));
    }
  }

  static String _responseMessage(http.Response response, String fallback) {
    final body = response.body.trim();

    if (body.isEmpty) return '$fallback (HTTP ${response.statusCode})';

    return '$fallback: $body';
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PASATA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            tooltip: 'Notifikasi',

            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notifikasi belum diimplementasikan.'),
              ),
            ),

            icon: const Icon(Icons.notifications_outlined),
          ),

          const SizedBox(width: 8),
        ],
      ),

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,

          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF176B52)),

              child: Align(
                alignment: Alignment.bottomLeft,

                child: Text(
                  'PASATA\nInventory Management',

                  style: TextStyle(
                    color: Colors.white,

                    fontSize: 21,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            ListTile(
              leading: const Icon(Icons.dashboard_outlined),

              title: const Text('Dashboard'),

              selected: true,

              onTap: () => Navigator.pop(context),
            ),

            ListTile(
              leading: const Icon(Icons.warehouse_outlined),

              title: const Text('Data Gudang'),

              onTap: () {
                Navigator.pop(context);

                Navigator.push(
                  context,

                  MaterialPageRoute(builder: (_) => WarehousePage()),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('Layout Pallet'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LayoutPalletPage()),
                );
              },
            ),

            _unavailableMenu(context, Icons.south_west_rounded, 'Barang Masuk'),

            _unavailableMenu(
              context,
              Icons.north_east_rounded,
              'Barang Keluar',
            ),

            _unavailableMenu(context, Icons.inventory_2_outlined, 'Inventaris'),

            _unavailableMenu(context, Icons.history, 'Riwayat Transaksi'),

            _unavailableMenu(context, Icons.settings_outlined, 'Pengaturan'),
          ],
        ),
      ),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),

          children: [
            const Text(
              'Dashboard',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Text(
              'Ringkasan operasional cold storage',
              style: TextStyle(color: Colors.grey.shade600),
            ),

            const SizedBox(height: 22),

            FutureBuilder<List<Warehouse>>(
              future: WarehouseApi.list(),

              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _SummaryCard(
                    title: 'Total Gudang',

                    value: '—',

                    subtitle: 'Gagal memuat data API',

                    icon: Icons.warehouse_outlined,

                    color: const Color(0xFF176B52),
                  );
                }

                if (!snapshot.hasData) {
                  return const _SummaryCard(
                    title: 'Total Gudang',

                    value: '...',

                    subtitle: 'Memuat data gudang',

                    icon: Icons.warehouse_outlined,

                    color: Color(0xFF176B52),
                  );
                }

                final warehouses = snapshot.data!;

                final totalCapacity = warehouses.fold<int>(
                  0,

                  (total, warehouse) => total + warehouse.capacityPallet,
                );

                return Column(
                  children: [
                    _SummaryCard(
                      title: 'Total Gudang',

                      value: '${warehouses.length}',

                      subtitle: 'Gudang terdaftar',

                      icon: Icons.warehouse_outlined,

                      color: const Color(0xFF176B52),
                    ),

                    const SizedBox(height: 14),

                    _SummaryCard(
                      title: 'Kapasitas Pallet',

                      value: '$totalCapacity',

                      subtitle: 'Kapasitas seluruh gudang',

                      icon: Icons.grid_view_rounded,

                      color: const Color(0xFF2563EB),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 14),

            const _SummaryCard(
              title: 'Barang Masuk',

              value: '—',

              subtitle: 'Belum terhubung ke API',

              icon: Icons.south_west_rounded,

              color: Color(0xFFD97706),
            ),

            const SizedBox(height: 14),

            const _SummaryCard(
              title: 'Barang Keluar',

              value: '—',

              subtitle: 'Belum terhubung ke API',

              icon: Icons.north_east_rounded,

              color: Color(0xFF7C3AED),
            ),

            const SizedBox(height: 24),

            const Text(
              'Aktivitas Terbaru',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Card(
              elevation: 0,

              child: Padding(
                padding: const EdgeInsets.all(20),

                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 40,
                      color: Colors.grey.shade500,
                    ),

                    const SizedBox(height: 10),

                    const Text('Belum ada aktivitas'),

                    const SizedBox(height: 4),

                    Text(
                      'Riwayat aktivitas belum dihubungkan ke API.',

                      textAlign: TextAlign.center,

                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailableMenu(BuildContext context, IconData icon, String title) {
    return ListTile(
      leading: Icon(icon),

      title: Text(title),

      onTap: () {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Menu $title belum diimplementasikan.')),
        );
      },
    );
  }
}

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key});

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  late Future<List<Warehouse>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = WarehouseApi.list();

  Future<void> _form({Warehouse? warehouse}) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(
      text:
          warehouse?.code ??
          'WH-${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    final name = TextEditingController(text: warehouse?.name ?? '');
    final address = TextEditingController(text: warehouse?.address ?? '');
    final city = TextEditingController(text: warehouse?.city ?? '');
    final phone = TextEditingController(text: warehouse?.phone ?? '');
    final capacity = TextEditingController(
      text: '${warehouse?.capacityPallet ?? 100}',
    );
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(warehouse == null ? 'Tambah Gudang' : 'Edit Gudang'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Kode gudang'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nama gudang'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Alamat'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: city,
                    decoration: const InputDecoration(labelText: 'Kota'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor telepon',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Kapasitas pallet',
                    ),
                    validator: (v) =>
                        int.tryParse(v ?? '') == null || int.parse(v!) < 0
                        ? 'Masukkan angka valid'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, {
                'code': code.text.trim(),
                'name': name.text.trim(),
                'address': address.text.trim(),
                'city': city.text.trim(),
                'phone': phone.text.trim(),
                'capacity_pallet': int.parse(capacity.text),
                'status': warehouse?.status ?? 'ACTIVE',
              });
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (data == null) return;
    try {
      if (warehouse == null) {
        await WarehouseApi.create(data);
      } else {
        await WarehouseApi.update(warehouse.id, data);
      }
      if (!mounted) return;
      setState(() {
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warehouse == null
                ? 'Gudang berhasil ditambahkan.'
                : 'Gudang berhasil diperbarui.',
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan gudang: $e')));
    }
  }

  Future<void> _setWarehouseStatus(Warehouse warehouse, String status) async {
    final labels = {
      'ACTIVE': 'Aktif',
      'INACTIVE': 'Nonaktif',
      'MAINTENANCE': 'Pemeliharaan',
    };
    final label = labels[status] ?? status;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ubah status gudang menjadi $label?'),
        content: Text(
          'Gudang ${warehouse.name} tetap disimpan. Hanya statusnya yang diubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Jadikan $label'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await WarehouseApi.update(warehouse.id, {
        'code': warehouse.code,
        'name': warehouse.name,
        'address': warehouse.address,
        'city': warehouse.city,
        'phone': warehouse.phone,
        'capacity_pallet': warehouse.capacityPallet,
        'status': status,
      });
      if (!mounted) return;
      setState(() {
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Status gudang menjadi $label. Data gudang tidak dihapus.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status gudang: $e')),
        );
      }
    }
  }

  Widget _warehouseStatusBadge(String status) {
    final normalized = status.toUpperCase();
    final label = switch (normalized) {
      'INACTIVE' => 'NONAKTIF',
      'MAINTENANCE' => 'PEMELIHARAAN',
      _ => 'AKTIF',
    };
    final color = switch (normalized) {
      'INACTIVE' => const Color(0xFFFFE1E1),
      'MAINTENANCE' => const Color(0xFFFFE9C2),
      _ => const Color(0xFFD9F4E8),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Gudang'),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              _reload();
            }),
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Gudang'),
      ),
      body: FutureBuilder<List<Warehouse>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return _ErrorView(
              message: '${snapshot.error}',
              onRetry: () => setState(() {
                _reload();
              }),
            );
          final warehouses = snapshot.data ?? <Warehouse>[];
          if (warehouses.isEmpty)
            return const Center(child: Text('Belum ada data gudang.'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: warehouses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final w = warehouses[index];
              return Card(
                elevation: 0,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.warehouse_outlined),
                  ),
                  title: Text(
                    '${w.name} (${w.code})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${w.city ?? '-'} · Kapasitas ${w.capacityPallet} pallet',
                      ),
                      Text(w.address ?? 'Alamat belum diisi'),
                      const SizedBox(height: 6),
                      _warehouseStatusBadge(w.status),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (w.status.toUpperCase() != 'ACTIVE')
                        const PopupMenuItem(
                          value: 'ACTIVE',
                          child: Text('Aktifkan'),
                        ),
                      if (w.status.toUpperCase() != 'INACTIVE')
                        const PopupMenuItem(
                          value: 'INACTIVE',
                          child: Text('Nonaktifkan'),
                        ),
                      if (w.status.toUpperCase() != 'MAINTENANCE')
                        const PopupMenuItem(
                          value: 'MAINTENANCE',
                          child: Text('Pemeliharaan'),
                        ),
                    ],
                    onSelected: (v) {
                      if (v == 'edit') {
                        _form(warehouse: w);
                      } else {
                        _setWarehouseStatus(w, v);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LayoutPalletPage extends StatefulWidget {
  const LayoutPalletPage({super.key});
  @override
  State<LayoutPalletPage> createState() => _LayoutPalletPageState();
}

class _LayoutPalletPageState extends State<LayoutPalletPage> {
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _racks = [];
  List<Map<String, dynamic>> _pallets = [];
  int? _selectedAreaId;
  int _selectedLevel = 1;
  bool _loading = true;
  String? _error;
  static const _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  int _num(Map<String, dynamic> m, String k, [int fallback = 0]) {
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  String _str(Map<String, dynamic> m, String k, [String fallback = '']) {
    final v = m[k];
    return v == null || '$v'.trim().isEmpty ? fallback : '$v';
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final r = await http
        .get(Uri.parse('$apiBaseUrl/$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final d = jsonDecode(r.body);
    if (d is! List) throw Exception('Format respons $path tidak valid');
    return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadAreas() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final areas = await _list('warehouse-areas');
      int? areaId = _selectedAreaId;
      if (areas.isNotEmpty && !areas.any((e) => _num(e, 'id') == areaId))
        areaId = _num(areas.first, 'id');
      final racks = areaId == null
          ? <Map<String, dynamic>>[]
          : await _list('racks?area_id=$areaId');
      final pallets = await _list('pallets');
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _selectedAreaId = areaId;
        _racks = racks;
        _pallets = pallets;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _loading = false;
        });
    }
  }

  Future<void> _selectArea(int? id) async {
    if (id == null) return;
    setState(() {
      _selectedAreaId = id;
      _loading = true;
      _error = null;
    });
    try {
      final racks = await _list('racks?area_id=$id');
      final pallets = await _list('pallets');
      if (mounted)
        setState(() {
          _racks = racks;
          _pallets = pallets;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _loading = false;
        });
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(
          Uri.parse('$apiBaseUrl/$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  Future<void> _put(String path, Map<String, dynamic> body) async {
    final r = await http
        .put(
          Uri.parse('$apiBaseUrl/$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  Future<void> _delete(String path) async {
    final r = await http
        .delete(Uri.parse('$apiBaseUrl/$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addRack() async {
    if (_selectedAreaId == null) {
      _message('Pilih area gudang terlebih dahulu.');
      return;
    }
    final code = TextEditingController(
      text:
          'RAK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
    final name = TextEditingController();
    final capacity = TextEditingController(text: '8');
    final levels = TextEditingController(text: '4');
    final slots = TextEditingController(text: '8');
    final formKey = GlobalKey<FormState>();
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Rak'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'Kode rak'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                ),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama rak'),
                ),
                TextFormField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah slot pallet per level',
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) < 1
                      ? 'Minimal 1'
                      : null,
                ),
                TextFormField(
                  controller: levels,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Jumlah level'),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) < 1
                      ? 'Minimal 1'
                      : null,
                ),
                TextFormField(
                  controller: slots,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Slot per level (sama dengan kapasitas di atas)',
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) < 0
                      ? 'Masukkan 0 atau lebih'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.pop(ctx, {
                  'code': code.text.trim(),
                  'name': name.text.trim(),
                  'capacity_pallet': int.parse(capacity.text),
                  'level_count': int.parse(levels.text),
                  'slots_per_level': int.parse(slots.text),
                });
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (data == null) return;
    try {
      data['warehouse_area_id'] = _selectedAreaId;
      await _post('racks', data);
      await _selectArea(_selectedAreaId);
      _message('Rak dan level awal berhasil dibuat.');
    } catch (e) {
      _message('Gagal menambah rak: $e');
    }
  }

  Future<void> _editRack(Map<String, dynamic> rack) async {
    final id = _num(rack, 'id');
    final code = TextEditingController(text: _str(rack, 'code'));
    final name = TextEditingController(text: _str(rack, 'name'));
    final cap = TextEditingController(text: '${_num(rack, 'capacity_pallet')}');
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Rak'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Kode rak'),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nama rak'),
            ),
            TextField(
              controller: cap,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kapasitas pallet'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'code': code.text.trim(),
              'name': name.text.trim(),
              'capacity_pallet': int.tryParse(cap.text) ?? 0,
              'status': _str(rack, 'status', 'ACTIVE'),
            }),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (data == null) return;
    try {
      await _put('racks/$id', data);
      await _selectArea(_selectedAreaId);
      _message('Rak berhasil diperbarui.');
    } catch (e) {
      _message('Gagal edit rak: $e');
    }
  }

  Future<void> _deactivateRack(Map<String, dynamic> rack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan rak?'),
        content: Text('Rak ${_str(rack, 'code')} akan dinonaktifkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _delete('racks/${_num(rack, 'id')}');
      await _selectArea(_selectedAreaId);
      _message('Rak dinonaktifkan.');
    } catch (e) {
      _message('Gagal menonaktifkan rak: $e');
    }
  }

  Future<void> _changeRackStatus(
    Map<String, dynamic> rack,
    String status,
  ) async {
    final id = _num(rack, 'id');
    try {
      await _put('racks/$id', {
        'code': _str(rack, 'code'),
        'name': _str(rack, 'name'),
        'capacity_pallet': _num(rack, 'capacity_pallet', 8),
        'status': status,
      });
      await _selectArea(_selectedAreaId);
      _message(
        status == 'ACTIVE'
            ? 'Rak diaktifkan.'
            : status == 'MAINTENANCE'
            ? 'Rak masuk pemeliharaan.'
            : 'Rak dinonaktifkan.',
      );
    } catch (e) {
      _message('Gagal mengubah status rak: $e');
    }
  }

  Future<void> _addPallet() async {
    final area = _areas.where((a) => _num(a, 'id') == _selectedAreaId).toList();
    if (area.isEmpty) {
      _message('Pilih area gudang terlebih dahulu.');
      return;
    }
    final warehouseId = _num(area.first, 'warehouse_id');
    final code = TextEditingController(
      text:
          'PLT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
    String condition = 'GOOD';
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Tambah Pallet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Kode pallet'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: condition,
                decoration: const InputDecoration(labelText: 'Kondisi'),
                items: const [
                  DropdownMenuItem(value: 'GOOD', child: Text('Baik')),
                  DropdownMenuItem(
                    value: 'NEEDS_REPAIR',
                    child: Text('Perlu perbaikan'),
                  ),
                  DropdownMenuItem(value: 'DAMAGED', child: Text('Rusak')),
                ],
                onChanged: (v) {
                  if (v != null) setDialog(() => condition = v);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Pallet baru dibuat dengan status belum ditempatkan.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'pallet_code': code.text.trim(),
                'warehouse_id': warehouseId,
                'condition': condition,
              }),
              child: const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
    if (data == null) return;
    if ((data['pallet_code'] as String).isEmpty) {
      _message('Kode pallet wajib diisi.');
      return;
    }
    try {
      await _post('pallets', data);
      await _loadAreas();
      _message(
        'Pallet ditambahkan. Seret pallet dari daftar pallet belum ditempatkan ke slot kosong.',
      );
    } catch (e) {
      _message('Gagal menambah pallet: $e');
    }
  }

  Future<void> _movePallet(int palletId, int slotId) async {
    try {
      await _post('pallet-move', {'pallet_id': palletId, 'to_slot_id': slotId});
      await _loadAreas();
      _message('Perpindahan pallet berhasil disimpan.');
    } catch (e) {
      _message('Pallet tidak dapat dipindahkan: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = _areas.where((a) => _num(a, 'id') == _selectedAreaId).toList();
    final areaName = area.isEmpty
        ? 'Pilih area gudang'
        : _str(area.first, 'name', _str(area.first, 'code'));
    final unplaced = _pallets
        .where(
          (p) =>
              _str(p, 'status') == 'UNPLACED' ||
              p['current_slot_id'] == null && _str(p, 'status') != 'INACTIVE',
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layout Pallet'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loadAreas,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRack,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Rak'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _loadAreas)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warehouse_outlined,
                        color: Color(0xFF176B52),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedAreaId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Area gudang',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items: _areas
                              .map(
                                (a) => DropdownMenuItem(
                                  value: _num(a, 'id'),
                                  child: Text(
                                    '${_str(a, 'name', _str(a, 'code'))} (${_str(a, 'code')})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _selectArea,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Tambah pallet',
                        onPressed: _addPallet,
                        icon: const Icon(Icons.add_box_outlined),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$areaName · Level $_selectedLevel',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${_racks.length} rak',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unplaced.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE0E7E3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pallet belum ditempatkan · seret ke slot kosong',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: unplaced
                                .map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Draggable<Map<String, dynamic>>(
                                      data: p,
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: Chip(
                                          avatar: const Icon(
                                            Icons.inventory_2,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          label: Text(
                                            _str(p, 'pallet_code'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: const Color(
                                            0xFF176B52,
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: .3,
                                        child: Chip(
                                          label: Text(_str(p, 'pallet_code')),
                                        ),
                                      ),
                                      child: Chip(
                                        avatar: const Icon(
                                          Icons.drag_indicator,
                                          size: 16,
                                        ),
                                        label: Text(_str(p, 'pallet_code')),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 7, 8),
                        child: Column(
                          children: [
                            for (int level = 4; level >= 1; level--)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: SizedBox(
                                  width: 34,
                                  height: 32,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      backgroundColor: _selectedLevel == level
                                          ? const Color(0xFF176B52)
                                          : Colors.white,
                                      foregroundColor: _selectedLevel == level
                                          ? Colors.white
                                          : Colors.black87,
                                      side: BorderSide(
                                        color: _selectedLevel == level
                                            ? const Color(0xFF176B52)
                                            : const Color(0xFFE0E7E3),
                                      ),
                                    ),
                                    onPressed: () =>
                                        setState(() => _selectedLevel = level),
                                    child: Text(
                                      '$level',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            Text(
                              'Level',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _racks.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.grid_view_outlined,
                                      size: 42,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('Belum ada rak'),
                                    const Text(
                                      'Tekan Tambah Rak untuk membuat rak.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  0,
                                  12,
                                  90,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1.28,
                                    ),
                                itemCount: _racks.length,
                                itemBuilder: (context, index) => _RackLayoutCard(
                                  key: ValueKey(
                                    '${_num(_racks[index], 'id')}-$_selectedLevel',
                                  ),
                                  rack: _racks[index],
                                  selectedLevel: _selectedLevel,
                                  onEdit: () => _editRack(_racks[index]),
                                  onStatusChange: (status) =>
                                      _changeRackStatus(_racks[index], status),
                                  onMove: _movePallet,
                                  getList: _list,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _RackLayoutCard extends StatefulWidget {
  final Map<String, dynamic> rack;
  final int selectedLevel;
  final Future<List<Map<String, dynamic>>> Function(String) getList;
  final Future<void> Function(int, int) onMove;
  final VoidCallback onEdit;
  final Future<void> Function(String status) onStatusChange;
  const _RackLayoutCard({
    super.key,
    required this.rack,
    required this.selectedLevel,
    required this.getList,
    required this.onMove,
    required this.onEdit,
    required this.onStatusChange,
  });
  @override
  State<_RackLayoutCard> createState() => _RackLayoutCardState();
}

class _RackLayoutCardState extends State<_RackLayoutCard> {
  List<Map<String, dynamic>> _slots = [];
  bool _loading = true;
  String? _error;
  int _num(Map<String, dynamic> m, String k, [int fallback = 0]) {
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  String _str(Map<String, dynamic> m, String k, [String fallback = '']) {
    final v = m[k];
    return v == null || '$v'.isEmpty ? fallback : '$v';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RackLayoutCard old) {
    super.didUpdateWidget(old);
    if (old.selectedLevel != widget.selectedLevel ||
        _num(old.rack, 'id') != _num(widget.rack, 'id'))
      _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final levels = await widget.getList(
        'rack-levels?rack_id=${_num(widget.rack, 'id')}',
      );
      final matches = levels
          .where((l) => _num(l, 'level_number') == widget.selectedLevel)
          .toList();
      List<Map<String, dynamic>> slots = [];
      if (matches.isNotEmpty)
        slots = await widget.getList(
          'rack-slots?rack_level_id=${_num(matches.first, 'id')}',
        );
      if (mounted)
        setState(
          () => _slots = slots
            ..sort(
              (a, b) =>
                  _num(a, 'slot_number').compareTo(_num(b, 'slot_number')),
            ),
        );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _buildSlot(Map<String, dynamic> slot) {
    final occupied =
        _str(slot, 'pallet_code').isNotEmpty ||
        _str(slot, 'status') == 'OCCUPIED';
    final palletId = _num(slot, 'pallet_id');
    final slotId = _num(slot, 'id');
    Widget tile = Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: occupied ? const Color(0xFF16866C) : const Color(0xFFF0F3F1),
        border: Border.all(
          color: occupied ? const Color(0xFF16866C) : const Color(0xFFCDD5D1),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Icon(
        occupied ? Icons.inventory_2 : Icons.add,
        size: 28,
        color: occupied ? Colors.white : Colors.grey.shade500,
      ),
    );
    if (occupied && palletId > 0) {
      tile = Draggable<Map<String, dynamic>>(
        data: {'id': palletId, 'pallet_code': _str(slot, 'pallet_code')},
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF176B52),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.inventory_2, size: 28, color: Colors.white),
          ),
        ),
        childWhenDragging: Opacity(opacity: .25, child: tile),
        child: Tooltip(
          message: '${_str(slot, 'pallet_code')} · seret untuk memindahkan',
          child: tile,
        ),
      );
    }
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) =>
          !occupied &&
          slotId > 0 &&
          _str(widget.rack, 'status', 'ACTIVE') == 'ACTIVE',
      onAcceptWithDetails: (d) => widget.onMove(_num(d.data, 'id'), slotId),
      builder: (context, candidates, rejected) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: candidates.isNotEmpty
              ? Border.all(color: const Color(0xFF176B52), width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: tile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rackId = _num(widget.rack, 'id');
    final code = _str(widget.rack, 'code', 'RAK-$rackId');
    final visibleSlots = _slots.take(4).toList();
    final status = _str(widget.rack, 'status', 'ACTIVE');
    final used = visibleSlots
        .where(
          (s) =>
              _str(s, 'pallet_code').isNotEmpty ||
              _str(s, 'status') == 'OCCUPIED',
        )
        .length;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE0E7E3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header tetap utuh: nama rak dan menu di baris pertama.
            Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 150),
                  iconSize: 17,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit rak')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'ACTIVE', child: Text('Aktif')),
                    PopupMenuItem(value: 'INACTIVE', child: Text('Nonaktif')),
                    PopupMenuItem(
                      value: 'MAINTENANCE',
                      child: Text('Pemeliharaan'),
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'edit') {
                      widget.onEdit();
                    } else {
                      widget.onStatusChange(v);
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'ACTIVE'
                        ? const Color(0xFFDDF4E8)
                        : status == 'MAINTENANCE'
                        ? const Color(0xFFFFE9BD)
                        : const Color(0xFFE6E8E7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status == 'ACTIVE'
                        ? 'AKTIF'
                        : status == 'MAINTENANCE'
                        ? 'PEMELIHARAAN'
                        : 'NONAKTIF',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$used/4 pallet',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Pallet 2 x 2: langsung di bawah header, bukan di tengah kartu.
            // Jarak slot seragam dan kartu tetap persegi.
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Gagal memuat slot',
                  style: TextStyle(fontSize: 10),
                ),
              )
            else if (visibleSlots.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Belum ada slot',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int start = 0; start < visibleSlots.length; start += 2)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: start + 2 < visibleSlots.length ? 4 : 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final slot in visibleSlots.skip(start).take(2))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: _buildSlot(slot),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.redAccent,
            ),

            const SizedBox(height: 12),

            const Text(
              'Gagal memuat data gudang',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text(message, textAlign: TextAlign.center),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: onRetry,

              icon: const Icon(Icons.refresh),

              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;

  final String value;

  final String subtitle;

  final IconData icon;

  final Color color;

  const _SummaryCard({
    required this.title,

    required this.value,

    required this.subtitle,

    required this.icon,

    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,

      color: Colors.white,

      child: Padding(
        padding: const EdgeInsets.all(18),

        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),

                borderRadius: BorderRadius.circular(12),
              ),

              child: Icon(icon, color: color, size: 28),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(title, style: TextStyle(color: Colors.grey.shade600)),

                  const SizedBox(height: 5),

                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
