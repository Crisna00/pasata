 import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

// Flutter Web / Chrome: localhost.

// Android Emulator: ganti menjadi http://10.0.2.2:8080/api

// HP fisik: gunakan IP LAN komputer, misalnya http://192.168.1.10:8080/api

const String apiBaseUrl = 'http://localhost:8080/api';

String? sessionToken;
Map<String, dynamic>? currentUser;
Map<String, String> get apiHeaders => {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  if (sessionToken != null && sessionToken!.isNotEmpty)
    'Authorization': 'Bearer $sessionToken',
};

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

      home: const LoginPage(),
    );
  }
}

Future<void> _logout(BuildContext context) async {
  final token = sessionToken;
  if (token != null) {
    try {
      await http
          .post(Uri.parse('$apiBaseUrl/auth/logout'), headers: apiHeaders)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
  sessionToken = null;
  currentUser = null;
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }
}

Future<void> _switchAccount(BuildContext context) async {
  await _logout(context);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _checking = true;
  bool _needsFirstAdmin = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBootstrap();
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkBootstrap() async {
    try {
      final r = await http
          .get(Uri.parse('$apiBaseUrl/auth/bootstrap'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (mounted)
          setState(() => _needsFirstAdmin = data['needs_first_admin'] == true);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Backend belum tersambung. Jalankan backend Go terlebih dahulu.',
        );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/login'),
            headers: apiHeaders,
            body: jsonEncode({
              'identifier': _identifier.text.trim(),
              'password': _password.text,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(r.body);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception(
          data is Map ? (data['error'] ?? 'Login gagal') : 'Login gagal',
        );
      }
      sessionToken = data['token'] as String;
      currentUser = Map<String, dynamic>.from(data['user'] as Map);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warehouse_rounded,
                        size: 54,
                        color: Color(0xFF176B52),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'PASATA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Warehouse & Inventory Management',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _identifier,
                        decoration: const InputDecoration(
                          labelText: 'Username atau email',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Username/email wajib diisi'
                            : null,
                        onFieldSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Password wajib diisi'
                            : null,
                        onFieldSubmitted: (_) => _login(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _loading ? null : _login,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_loading ? 'Memproses...' : 'Login'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      if (_checking) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (!_checking && _needsFirstAdmin) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Belum ada akun. Buat akun Super Admin pertama untuk memulai.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const RegisterPage(firstAdmin: true),
                            ),
                          ),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Buat Admin Pertama'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  final bool firstAdmin;
  const RegisterPage({super.key, this.firstAdmin = false});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  List<Map<String, dynamic>> _roles = [];
  int? _selectedRoleId;
  bool _loading = false;
  bool _loadingRoles = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.firstAdmin) _loadRoles();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final r = await http
          .get(Uri.parse('$apiBaseUrl/auth/roles'), headers: apiHeaders)
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(r.body);
      if (r.statusCode != 200)
        throw Exception(
          decoded is Map ? decoded['error'] : 'Gagal memuat role',
        );
      _roles = (decoded as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (_roles.isNotEmpty)
        _selectedRoleId = (_roles.first['id'] as num).toInt();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.firstAdmin && _selectedRoleId == null) {
      setState(() => _error = 'Pilih role untuk pengguna baru.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'full_name': _fullName.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'password': _password.text,
        if (!widget.firstAdmin) 'role_id': _selectedRoleId,
      };
      final r = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/register'),
            headers: apiHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(r.body);
      if (r.statusCode < 200 || r.statusCode >= 300)
        throw Exception(
          decoded is Map
              ? (decoded['error'] ?? 'Register gagal')
              : 'Register gagal',
        );
      if (!mounted) return;
      if (widget.firstAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Super Admin berhasil dibuat. Silakan login.'),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User berhasil dibuat.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstAdmin = widget.firstAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(firstAdmin ? 'Buat Super Admin Pertama' : 'Register User'),
      ),
      drawer: firstAdmin ? null : const PasataNavigationDrawer(activeMenu: 'Register User'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        firstAdmin
                            ? Icons.admin_panel_settings_outlined
                            : Icons.person_add_alt_1_outlined,
                        size: 46,
                        color: const Color(0xFF176B52),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        firstAdmin
                            ? 'Pendaftaran admin pertama'
                            : 'Buat akun pengguna baru',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        firstAdmin
                            ? 'Akun pertama otomatis diberi role Super Admin.'
                            : 'Pilih role sesuai tanggung jawab pengguna.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _fullName,
                        decoration: const InputDecoration(
                          labelText: 'Nama lengkap',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().length < 3)
                            ? 'Username minimal 3 karakter'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) =>
                            (v == null || !v.contains('@') || !v.contains('.'))
                            ? 'Masukkan email yang valid'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Nomor telepon (opsional)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      if (!firstAdmin) ...[
                        const SizedBox(height: 12),
                        if (_loadingRoles)
                          const LinearProgressIndicator()
                        else
                          DropdownButtonFormField<int>(
                            value: _selectedRoleId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Role pengguna',
                              prefixIcon: Icon(Icons.assignment_ind_outlined),
                            ),
                            items: _roles
                                .map(
                                  (role) => DropdownMenuItem<int>(
                                    value: (role['id'] as num).toInt(),
                                    child: Text(
                                      '${role['name']} (${role['code']})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedRoleId = value),
                            validator: (value) =>
                                value == null ? 'Role wajib dipilih' : null,
                          ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password (minimal 8 karakter)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 8)
                            ? 'Password minimal 8 karakter'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmPassword,
                        obscureText: !_showPassword,
                        decoration: const InputDecoration(
                          labelText: 'Konfirmasi password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                        validator: (v) => v != _password.text
                            ? 'Konfirmasi password tidak sama'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: (_loading || _loadingRoles) ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _loading ? 'Menyimpan...' : 'Simpan Pengguna',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
  static Map<String, String> get _headers => apiHeaders;

  static Future<List<Warehouse>> list() async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/warehouses'), headers: apiHeaders)
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

          headers: apiHeaders,

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

          headers: apiHeaders,

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

          headers: apiHeaders,

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


/// Navigasi bersama agar seluruh halaman utama memakai hamburger yang sama.
class PasataNavigationDrawer extends StatelessWidget {
  final String activeMenu;
  const PasataNavigationDrawer({super.key, required this.activeMenu});

  void _open(BuildContext context, String menu) {
    Navigator.pop(context);
    if (menu == activeMenu) return;
    Widget page;
    switch (menu) {
      case 'Dashboard': page = const DashboardPage(); break;
      case 'Data Gudang': page = WarehousePage(); break;
      case 'Area Gudang': page = const AreaColdStoragePage(initialTab: 0); break;
      case 'Cold Storage': page = const AreaColdStoragePage(initialTab: 1); break;
      case 'Master Pallet': page = const MasterPalletPage(); break;
      case 'Pallet Content': page = const PalletContentPage(); break;
      case 'Stock & Physical Summary': page = const StockPhysicalSummaryPage(); break;
      case 'Master SKU': page = const MasterSkuPage(); break;
      case 'Scanner & Validasi SKU': page = const ScannerValidasiSkuPage(); break;
      case 'Barang Masuk': page = const InboundPage(); break;
      case 'Barang Keluar': page = const OutboundPage(); break;
      case 'Monitoring': page = const MonitoringPage(); break;
      case 'Register User': page = const RegisterPage(); break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Menu $menu belum tersedia.')),
        );
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: Color(0xFF176B52)),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              'PASATA\nInventory Management\n${currentUser?['full_name'] ?? 'Pengguna'} · ${currentUser?['role_name'] ?? ''}',
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        _item(context, 'Dashboard', Icons.dashboard_outlined),
        _item(context, 'Data Gudang', Icons.warehouse_outlined),
        _item(context, 'Area Gudang', Icons.domain_outlined),
        _item(context, 'Cold Storage', Icons.ac_unit_outlined),
        _item(context, 'Master Pallet', Icons.view_module_outlined),
        _item(context, 'Pallet Content', Icons.inventory_2_outlined),
        _item(context, 'Stock & Physical Summary', Icons.summarize_outlined),
        _item(context, 'Master SKU', Icons.qr_code_2_outlined),
        _item(context, 'Scanner & Validasi SKU', Icons.document_scanner_outlined),
        _item(context, 'Barang Masuk', Icons.south_west_rounded),
        _item(context, 'Barang Keluar', Icons.north_east_rounded),
        _item(context, 'Monitoring', Icons.monitor_heart_outlined),
        if (currentUser != null && currentUser!['role_code'] == 'SUPER_ADMIN')
          _item(context, 'Register User', Icons.person_add_alt_1_outlined),
        if (currentUser != null)
          ListTile(leading: const Icon(Icons.switch_account_outlined), title: const Text('Switch Account'), onTap: () { Navigator.pop(context); _switchAccount(context); }),
        if (currentUser != null)
          ListTile(leading: const Icon(Icons.logout_outlined), title: const Text('Logout'), onTap: () => _logout(context)),
      ],
    ),
  );

  Widget _item(BuildContext context, String label, IconData icon) => ListTile(
    leading: Icon(icon), title: Text(label), selected: activeMenu == label,
    onTap: () => _open(context, label),
  );
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

      drawer: const PasataNavigationDrawer(activeMenu: 'Dashboard'),

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

class InboundPage extends StatefulWidget {
  final int? palletId;
  final String? palletCode;
  const InboundPage({super.key, this.palletId, this.palletCode});
  @override
  State<InboundPage> createState() => _InboundPageState();
}

class _InboundPageState extends State<InboundPage> {
  bool loading = true, saving = false;
  String? error;
  List<Map<String,dynamic>> warehouses=[], skus=[], pallets=[], slots=[], transactions=[];
  int? warehouseId, selectedPalletId, selectedSkuId, selectedSlotId;
  final supplier = TextEditingController(), refDoc = TextEditingController(), plate = TextEditingController(), driver = TextEditingController(), notes = TextEditingController();
  final batch = TextEditingController(), expiry = TextEditingController(), qtyExpected = TextEditingController(text:'0'), qtyReceived = TextEditingController(text:'1'), weight = TextEditingController(text:'0'), packagingQty = TextEditingController(text:'0'), temp = TextEditingController(), itemNotes = TextEditingController();
  String packagingType='CARTON', condition='GOOD';
  Map<String,dynamic>? activeTx, detail;
  final Map<int,bool> checklistState={};
  @override void initState(){super.initState();if(widget.palletId!=null)selectedPalletId=widget.palletId;loadCatalog();}
  @override void dispose(){for(final c in [supplier,refDoc,plate,driver,notes,batch,expiry,qtyExpected,qtyReceived,weight,packagingQty,temp,itemNotes]){c.dispose();}super.dispose();}
  Future<dynamic> api(String path,{String method='GET',Map<String,dynamic>? body}) async {final uri=Uri.parse('$apiBaseUrl/$path');late http.Response r;final encoded=body==null?null:jsonEncode(body);if(method=='POST'){r=await http.post(uri,headers:apiHeaders,body:encoded).timeout(const Duration(seconds:20));}else if(method=='PUT'){r=await http.put(uri,headers:apiHeaders,body:encoded).timeout(const Duration(seconds:20));}else{r=await http.get(uri,headers:apiHeaders).timeout(const Duration(seconds:20));}dynamic data;try{data=jsonDecode(r.body);}catch(_){data=r.body;}if(r.statusCode<200||r.statusCode>=300){final msg=data is Map?(data['error']??data['detail']??data['message']??r.body):data.toString();throw Exception('$msg (HTTP ${r.statusCode})');}return data;}
  void toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> loadCatalog() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      // Ambil katalog dari endpoint yang memang terdaftar di backend.
      // Backend tidak memiliki endpoint /inbound-catalog; memanggilnya menyebabkan HTTP 404.
      // Endpoint /api/rack-slots wajib menerima rack_level_id. Untuk inbound,
      // gunakan endpoint khusus yang memang mengembalikan slot EMPTY per gudang.
      final catalog = await Future.wait([
        api('warehouses'),
        api('skus'),
        api('pallets'),
      ]);
      warehouses = List<Map<String, dynamic>>.from(catalog[0] as List);
      skus = List<Map<String, dynamic>>.from(catalog[1] as List);
      pallets = List<Map<String, dynamic>>.from(catalog[2] as List);
      if (warehouseId == null && warehouses.isNotEmpty) {
        warehouseId = (warehouses.first['id'] as num).toInt();
      }
      slots = warehouseId == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await api('inbound-slots?warehouse_id=$warehouseId') as List,
            );
      await loadTransactions(showLoading: false);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  Future<void> loadTransactions({bool showLoading=true}) async {if(showLoading&&mounted)setState(()=>loading=true);try{transactions=List<Map<String,dynamic>>.from(await api('inbound-transactions'));}catch(e){error=e.toString();}if(showLoading&&mounted)setState(()=>loading=false);}
  Future<void> createTransaction() async {
    if (warehouseId == null || supplier.text.trim().isEmpty) {
      toast('Pilih gudang dan isi nama pemasok.');
      return;
    }
    if (selectedSkuId == null) {
      toast('Pilih minimal satu SKU untuk barang inbound.');
      return;
    }
    final q = double.tryParse(qtyReceived.text) ?? 0;
    final w = double.tryParse(weight.text) ?? -1;
    final pq = int.tryParse(packagingQty.text) ?? -1;
    final qe = double.tryParse(qtyExpected.text) ?? 0;
    if (q <= 0 || w < 0 || pq < 0 || qe < 0) {
      toast('Qty diterima harus lebih dari 0; qty, berat, dan packaging tidak boleh negatif.');
      return;
    }
    final item = <String, dynamic>{
      'sku_id': selectedSkuId,
      'pallet_id': selectedPalletId,
      'rack_slot_id': selectedSlotId,
      'batch_no': batch.text.trim(),
      'expiry_date': expiry.text.trim(),
      'packaging_type': packagingType,
      'packaging_qty': pq,
      'qty_expected': qe,
      'qty_received': q,
      'weight_kg': w,
      'condition': condition,
      'notes': itemNotes.text.trim(),
    };
    if (temp.text.trim().isNotEmpty) {
      final parsedTemp = double.tryParse(temp.text.trim());
      if (parsedTemp == null) {
        toast('Suhu saat tiba harus berupa angka.');
        return;
      }
      item['arrival_temp'] = parsedTemp;
    }

    setState(() => saving = true);
    try {
      final d = Map<String, dynamic>.from(await api(
        'inbound-transactions',
        method: 'POST',
        body: {
          'warehouse_id': warehouseId,
          'supplier_name': supplier.text.trim(),
          'reference_doc_no': refDoc.text.trim(),
          'truck_plate': plate.text.trim(),
          'driver_name': driver.text.trim(),
          'notes': notes.text.trim(),
          'arrived_at': DateTime.now().toUtc().toIso8601String(),
          'items': [item],
        },
      ));
      activeTx = d;
      await refreshDetail();
      await loadTransactions(showLoading: false);
      toast('Inbound ${d['transaction_no']} dibuat dengan 1 item.');
    } catch (e) {
      toast('Gagal membuat inbound: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
  Future<void> refreshDetail() async {if(activeTx==null)return;try{detail=Map<String,dynamic>.from(await api('inbound-transactions/${activeTx!['id']}/detail'));checklistState.clear();for(final c in List<Map<String,dynamic>>.from(detail!['checklist']??[])){checklistState[(c['id'] as num).toInt()]=c['is_passed']==true;}}catch(e){toast('Gagal memuat detail: $e');}if(mounted)setState((){});}
  Future<void> addItem() async {if(activeTx==null||selectedSkuId==null){toast('Pilih SKU.');return;}final q=double.tryParse(qtyReceived.text)??0,w=double.tryParse(weight.text)??-1,pq=int.tryParse(packagingQty.text)??-1,qe=double.tryParse(qtyExpected.text)??0;if(q<=0||w<0||pq<0||qe<0){toast('Jumlah diterima harus > 0. Jumlah, berat, packaging tidak boleh negatif.');return;}setState(()=>saving=true);try{final body=<String,dynamic>{'sku_id':selectedSkuId,'pallet_id':selectedPalletId,'rack_slot_id':selectedSlotId,'batch_no':batch.text.trim(),'expiry_date':expiry.text.trim(),'packaging_type':packagingType,'packaging_qty':pq,'qty_expected':qe,'qty_received':q,'weight_kg':w,'condition':condition,'notes':itemNotes.text.trim()};if(temp.text.trim().isNotEmpty)body['arrival_temp']=double.parse(temp.text.trim());await api('inbound-transactions/${activeTx!['id']}/items',method:'POST',body:body);await refreshDetail();await loadCatalog();toast(selectedSlotId==null?'Item tersimpan dengan status Unplaced.':'Item inbound tersimpan.');}catch(e){toast('Gagal menambah item: $e');}finally{if(mounted)setState(()=>saving=false);}}
  Future<void> saveChecklist(int id,bool value) async {try{await api('inbound-transactions/${activeTx!['id']}/checklist',method:'PUT',body:{'items':[{'id':id,'is_passed':value,'notes':''}]});checklistState[id]=value;await refreshDetail();}catch(e){toast('Gagal menyimpan checklist: $e');}}
  Future<void> submitTx() async {
    if (activeTx == null) return;

    // Jangan approve jika checklist masih ada yang belum lolos.
    final checklist = List<Map<String, dynamic>>.from(detail?['checklist'] ?? []);
    if (checklist.isEmpty || checklist.any((c) => c['is_passed'] != true)) {
      toast('Semua checklist harus lolos sebelum inbound disetujui.');
      return;
    }

    setState(() => saving = true);
    try {
      await api(
        'inbound-transactions/${activeTx!['id']}/approve',
        method: 'POST',
        body: {},
      );
      toast('Inbound berhasil disetujui dan stok diperbarui.');
      activeTx = null;
      detail = null;
      await loadTransactions();
    } catch (e) {
      toast('Belum bisa menyetujui inbound: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> rejectTx() async {
    if (activeTx == null) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tolak inbound'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Masukkan alasan penolakan agar dapat ditindaklanjuti.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan penolakan *',
                hintText: 'Contoh: jumlah barang tidak sesuai',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Alasan penolakan wajib diisi.')),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Tolak inbound'),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (reason == null || reason.trim().isEmpty || activeTx == null) return;

    setState(() => saving = true);
    try {
      await api(
        'inbound-transactions/${activeTx!['id']}/reject',
        method: 'POST',
        body: {'reason': reason.trim()},
      );
      toast('Inbound berhasil ditolak.');
      activeTx = null;
      detail = null;
      await loadTransactions();
    } catch (e) {
      toast('Gagal menolak inbound: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
  Future<void> openTx(Map<String,dynamic> tx) async {activeTx=tx;await refreshDetail();}
  List<Map<String,dynamic>> get warehousePallets=>pallets.where((p)=>(p['warehouse_id'] as num?)?.toInt()==warehouseId&&p['status']!='INACTIVE').toList();
  List<Map<String,dynamic>> get warehouseSlots=>slots.where((s)=>(s['warehouse_id'] as num?)?.toInt()==warehouseId).toList();
  Widget field(String label,TextEditingController c,{String? hint,TextInputType type=TextInputType.text})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,keyboardType:type,decoration:InputDecoration(labelText:label,hintText:hint,border:const OutlineInputBorder(),isDense:true)));
  Widget dropdown(String label,int? value,List<Map<String,dynamic>> items,String idKey,String labelKey,ValueChanged<int?> onChanged,{bool enabled=true})=>Padding(padding:const EdgeInsets.only(bottom:12),child:DropdownButtonFormField<int>(value:items.any((e)=>(e[idKey] as num?)?.toInt()==value)?value:null,isExpanded:true,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),isDense:true),items:items.map((e)=>DropdownMenuItem<int>(value:(e[idKey] as num).toInt(),child:Text('${e[labelKey]??'-'}',overflow:TextOverflow.ellipsis))).toList(),onChanged:enabled?onChanged:null));
  Widget section(String title,Widget child)=>Card(margin:const EdgeInsets.only(bottom:14),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),const SizedBox(height:14),child])));
  @override
  Widget build(BuildContext context) {
    final tx = activeTx;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway Inbound'),
        actions: [
          IconButton(
            onPressed: loadCatalog,
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
      drawer: const PasataNavigationDrawer(activeMenu: 'Barang Masuk'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && warehouses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: loadCatalog,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (tx == null) ...[
                      section(
                        'Registrasi kedatangan',
                        Column(
                          children: [
                            dropdown(
                              'Gudang',
                              warehouseId,
                              warehouses,
                              'id',
                              'name',
                              (v) async {
                                setState(() => warehouseId = v);
                                if (v == null) {
                                  setState(() => slots = []);
                                  return;
                                }
                                try {
                                  final result = await api('inbound-slots?warehouse_id=$v');
                                  if (mounted) setState(() => slots = List<Map<String, dynamic>>.from(result as List));
                                } catch (e) {
                                  toast('Gagal memuat slot inbound: $e');
                                }
                              },
                            ),
                            field('Nama pemasok *', supplier),
                            field('No. surat jalan / PO', refDoc),
                            field('Nomor kendaraan', plate),
                            field('Nama pengemudi', driver),
                            field('Catatan kedatangan', notes),
                            const Divider(height: 28),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Barang inbound (minimal 1 item)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 12),
                            dropdown(
                              'SKU *', selectedSkuId, skus, 'id', 'name',
                              (v) => setState(() => selectedSkuId = v),
                            ),
                            dropdown(
                              'Pallet (opsional)', selectedPalletId, warehousePallets,
                              'id', 'pallet_code',
                              (v) => setState(() => selectedPalletId = v),
                            ),
                            dropdown(
                              'Lokasi slot (opsional)', selectedSlotId, warehouseSlots,
                              'id', 'code',
                              (v) => setState(() => selectedSlotId = v),
                            ),
                            field('Nomor batch', batch),
                            field('Tanggal kedaluwarsa (YYYY-MM-DD)', expiry),
                            Row(
                              children: [
                                Expanded(child: field('Qty rencana', qtyExpected, type: TextInputType.number)),
                                const SizedBox(width: 8),
                                Expanded(child: field('Qty diterima *', qtyReceived, type: const TextInputType.numberWithOptions(decimal: true))),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: field('Berat (kg) *', weight, type: const TextInputType.numberWithOptions(decimal: true))),
                                const SizedBox(width: 8),
                                Expanded(child: field('Jumlah packaging', packagingQty, type: TextInputType.number)),
                              ],
                            ),
                            DropdownButtonFormField<String>(
                              value: packagingType,
                              decoration: const InputDecoration(labelText: 'Jenis packaging', border: OutlineInputBorder(), isDense: true),
                              items: const ['CARTON', 'SACK', 'BOX', 'OTHER'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (v) => setState(() => packagingType = v ?? 'CARTON'),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: condition,
                              decoration: const InputDecoration(labelText: 'Kondisi barang', border: OutlineInputBorder(), isDense: true),
                              items: const ['GOOD', 'DAMAGED', 'EXPIRED', 'TEMP_DEVIATION'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (v) => setState(() => condition = v ?? 'GOOD'),
                            ),
                            const SizedBox(height: 12),
                            field('Suhu saat tiba (°C)', temp, type: const TextInputType.numberWithOptions(decimal: true)),
                            field('Catatan item', itemNotes),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: saving ? null : createTransaction,
                                icon: const Icon(Icons.add_box_outlined),
                                label: Text(
                                  saving
                                      ? 'Menyimpan...'
                                      : 'Buat registrasi inbound',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      section(
                        'Riwayat registrasi inbound',
                        transactions.isEmpty
                            ? const Text('Belum ada transaksi inbound.')
                            : Column(
                                children: transactions.map((t) {
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.move_to_inbox_outlined,
                                    ),
                                    title: Text(
                                      '${t['transaction_no']} · ${t['supplier_name']}',
                                    ),
                                    subtitle: Text(
                                      '${t['warehouse_name']} • ${t['status']} • ${t['item_count']} item',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => openTx(t),
                                  );
                                }).toList(),
                              ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${tx['transaction_no']}\n'
                              '${tx['supplier_name']} · ${tx['status']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                activeTx = null;
                                detail = null;
                              });
                            },
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Daftar'),
                          ),
                        ],
                      ),
                      section(
                        'Registrasi barang',
                        const Text(
                          'Barang pada transaksi ini dikirim saat registrasi dibuat. '
                          'Untuk menambah baris barang tambahan, backend perlu menyediakan '
                          'endpoint tambah item khusus; endpoint tersebut belum tersedia pada API saat ini.',
                        ),
                      ),
                      section(
                        'Barang yang diregistrasi',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...List<Map<String, dynamic>>.from(
                              detail?['items'] ?? [],
                            ).map((i) {
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.inventory_2_outlined,
                                ),
                                title: Text(
                                  '${i['sku_code']} · ${i['sku_name']}',
                                ),
                                subtitle: Text(
                                  'Qty ${i['qty_received']} • '
                                  '${i['weight_kg']} kg • '
                                  '${i['packaging_type']} ${i['packaging_qty']} • '
                                  'Batch ${i['batch_no'] ?? '-'}\n'
                                  'Pallet ${i['pallet_code'] ?? '-'} • '
                                  'Lokasi ${i['slot_code'] ?? 'UNPLACED'}',
                                ),
                                isThreeLine: true,
                              );
                            }),
                            if ((detail?['items'] as List? ?? []).isEmpty)
                              const Text('Belum ada item.'),
                          ],
                        ),
                      ),
                      section(
                        'Checklist inbound (semua harus lolos)',
                        Column(
                          children: [
                            ...List<Map<String, dynamic>>.from(
                              detail?['checklist'] ?? [],
                            ).map((c) {
                              final id = (c['id'] as num).toInt();

                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: checklistState[id] ?? false,
                                title: Text(c['checklist_item'].toString()),
                                subtitle: c['is_passed'] == true
                                    ? const Text('Lolos tersimpan')
                                    : null,
                                onChanged: (v) =>
                                    saveChecklist(id, v ?? false),
                              );
                            }),
                            if ((tx['status'] ?? '').toString() == 'WAITING_VERIFICATION') ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: saving ? null : rejectTx,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        side: BorderSide(color: Colors.red.shade700),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      icon: const Icon(Icons.cancel_outlined),
                                      label: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: saving ? null : submitTx,
                                      icon: const Icon(Icons.check_circle_outline),
                                      label: const Text('Approve & proses stok'),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Transaksi ini berstatus ${tx['status']}. Aksi approve/reject hanya tersedia saat menunggu verifikasi.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            const SizedBox(height: 8),
                            const Text(
                              'Persetujuan hanya dapat dilakukan oleh Warehouse Supervisor/Admin. '
                              'Semua checklist harus lolos sebelum stok diproses.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class OutboundPage extends StatefulWidget {
  final int? palletId;
  final String? palletCode;
  const OutboundPage({super.key, this.palletId, this.palletCode});

  @override
  State<OutboundPage> createState() => _OutboundPageState();
}

class _OutboundPageState extends State<OutboundPage> {
  bool loading = true;
  bool saving = false;
  bool fullOutbound = true;
  String? error;
  String search = '';
  List<Map<String, dynamic>> pallets = [];
  List<Map<String, dynamic>> stockItems = [];
  List<Map<String, dynamic>> outboundHistory = [];
  bool historyLoading = false;
  String? historyError;
  Map<String, dynamic>? selectedItem;
  final quantityController = TextEditingController();
  final weightController = TextEditingController();
  final notesController = TextEditingController();
  final Map<String, bool> checks = {
    'SKU dan pallet sesuai permintaan': false,
    'Jumlah dan berat sudah diverifikasi': false,
    'Kondisi barang dan kemasan diperiksa': false,
    'Lokasi pengambilan sudah sesuai': false,
  };

  int _int(Map<String, dynamic> row, String key, [int fallback = 0]) {
    final value = row[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  double _double(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  String _str(Map<String, dynamic> row, String key, [String fallback = '-']) {
    final value = row[key];
    if (value == null || '$value'.trim().isEmpty) return fallback;
    return '$value';
  }

  String _palletCode(Map<String, dynamic> item) {
    final palletId = _int(item, 'pallet_id');
    final pallet = pallets.where((p) => _int(p, 'id') == palletId).toList();
    if (pallet.isNotEmpty) return _str(pallet.first, 'pallet_code', 'Pallet $palletId');
    return 'Pallet $palletId';
  }

  String _location(Map<String, dynamic> item) {
    final palletId = _int(item, 'pallet_id');
    final pallet = pallets.where((p) => _int(p, 'id') == palletId).toList();
    if (pallet.isEmpty) return 'Lokasi tidak tersedia';
    final p = pallet.first;
    for (final key in ['slot_code', 'current_slot_code', 'location_code', 'slot_label', 'location']) {
      final value = p[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    final slotId = p['current_slot_id'];
    if (slotId == null) return 'UNPLACED';
    return 'Slot ID $slotId';
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
        .timeout(const Duration(seconds: 20));
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['error'] ?? decoded['message'] ?? decoded['detail'] ?? response.body)
          : decoded.toString();
      throw Exception('$message (HTTP ${response.statusCode})');
    }
    if (decoded is! List) throw Exception('Respons $path bukan daftar data.');
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> loadHistory() async {
    if (mounted) setState(() { historyLoading = true; historyError = null; });
    try {
      final rows = await _getList('outbound-transactions');
      rows.sort((a, b) {
        final aDate = DateTime.tryParse(_str(a, 'created_at', '')) ?? DateTime(1970);
        final bDate = DateTime.tryParse(_str(b, 'created_at', '')) ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
      if (!mounted) return;
      setState(() {
        outboundHistory = rows;
        historyLoading = false;
        historyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        historyLoading = false;
        historyError = '$e';
      });
    }
  }

  String _formatHistoryDate(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return value == null ? '-' : '$value';
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Color _historyStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED': return Colors.green;
      case 'REJECTED': return Colors.red;
      default: return Colors.orange;
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loadedPallets = await _getList('pallets');
      final items = <Map<String, dynamic>>[];
      final candidates = loadedPallets.where((p) {
        final status = _str(p, 'status', '').toUpperCase();
        return status != 'INACTIVE';
      }).toList();
      for (final pallet in candidates) {
        final id = _int(pallet, 'id');
        if (id <= 0) continue;
        try {
          final contents = await _getList('pallet-items?pallet_id=$id');
          for (final item in contents) {
            if (_double(item, 'quantity') > 0 && _str(item, 'status', 'AVAILABLE').toUpperCase() == 'AVAILABLE') {
              items.add(item);
            }
          }
        } catch (_) {
          // Pallet tanpa isi atau pallet yang tidak dapat dibaca tidak ditampilkan sebagai stok tersedia.
        }
      }
      items.sort((a, b) {
        final aDate = DateTime.tryParse(_str(a, 'received_at', '')) ?? DateTime(9999);
        final bDate = DateTime.tryParse(_str(b, 'received_at', '')) ?? DateTime(9999);
        final dateOrder = aDate.compareTo(bDate);
        return dateOrder != 0 ? dateOrder : _int(a, 'id').compareTo(_int(b, 'id'));
      });
      if (!mounted) return;
      setState(() {
        pallets = loadedPallets;
        stockItems = items;
        loading = false;
        if (widget.palletId != null) {
          final matches = stockItems.where((x) => _int(x, 'pallet_id') == widget.palletId).toList();
          if (matches.isNotEmpty) _selectItem(matches.first);
        }
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = '$e'; });
    }
  }

  void _selectItem(Map<String, dynamic> item) {
    selectedItem = item;
    fullOutbound = true;
    quantityController.text = _double(item, 'quantity').toString();
    weightController.text = _double(item, 'weight_kg').toString();
    checks.updateAll((key, value) => false);
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submitOutbound({bool asDraft = false}) async {
    final item = selectedItem;
    if (item == null) {
      _message('Pilih stok SKU/pallet yang akan dikeluarkan.');
      return;
    }
    if (!asDraft && checks.values.any((value) => !value)) {
      _message('Selesaikan semua checklist outbound sebelum mengirim untuk verifikasi.');
      return;
    }
    final skuId = _int(item, 'sku_id');
    final fifoCandidates = stockItems.where((x) => _int(x, 'sku_id') == skuId && _double(x, 'quantity') > 0).toList()..sort((a, b) {
      final aDate = DateTime.tryParse(_str(a, 'received_at', '')) ?? DateTime(9999);
      final bDate = DateTime.tryParse(_str(b, 'received_at', '')) ?? DateTime(9999);
      final order = aDate.compareTo(bDate);
      return order != 0 ? order : _int(a, 'id').compareTo(_int(b, 'id'));
    });
    if (fifoCandidates.isNotEmpty && _int(fifoCandidates.first, 'id') != _int(item, 'id')) {
      _message('FIFO: keluarkan stok SKU ini dari pallet ${_palletCode(fifoCandidates.first)} terlebih dahulu.');
      return;
    }
    final availableQty = _double(item, 'quantity');
    final availableWeight = _double(item, 'weight_kg');
    final qty = double.tryParse(quantityController.text.trim());
    final weight = double.tryParse(weightController.text.trim());
    if (qty == null || qty <= 0 || qty > availableQty) {
      _message('Jumlah keluar harus lebih dari 0 dan tidak boleh melebihi stok tersedia ($availableQty).');
      return;
    }
    if (weight == null || weight < 0 || weight > availableWeight + 0.0001) {
      _message('Berat keluar tidak boleh negatif atau melebihi berat tersedia ($availableWeight kg).');
      return;
    }
    if (fullOutbound && (qty - availableQty).abs() > 0.0001) {
      _message('Mode full outbound harus mengeluarkan seluruh jumlah stok.');
      return;
    }
    if (qty == availableQty && (weight - availableWeight).abs() > 0.0001) {
      _message('Jika seluruh jumlah dikeluarkan, berat keluar harus sama dengan berat tersisa.');
      return;
    }
    setState(() => saving = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/outbound-transactions'),
        headers: apiHeaders,
        body: jsonEncode({
          'pallet_item_id': _int(item, 'id'),
          'quantity': qty,
          'weight_kg': weight,
          'notes': notesController.text.trim(),
          'status': asDraft ? 'DRAFT' : 'PENDING',
          'checklist': checks.entries.map((e) => {'label': e.key, 'passed': e.value}).toList(),
        }),
      ).timeout(const Duration(seconds: 20));
      dynamic decoded;
      try { decoded = jsonDecode(response.body); } catch (_) { decoded = response.body; }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? decoded['detail'] ?? response.body)
            : decoded.toString();
        throw Exception('$message (HTTP ${response.statusCode})');
      }
      await load();
      await loadHistory();
      if (mounted) {
        setState(() {
          selectedItem = null;
          quantityController.clear();
          weightController.clear();
          notesController.clear();
          checks.updateAll((key, value) => false);
        });
      }
      _message(asDraft ? 'Draft outbound tersimpan. Stok belum berubah.' : 'Transaksi dikirim untuk verifikasi. Stok belum berubah sampai disetujui supervisor.');
    } catch (e) {
      _message('Outbound gagal: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reviewOutbound() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/outbound-transactions'), headers: apiHeaders).timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? response.body)
            : decoded.toString();
        throw Exception(message);
      }
      if (decoded is! List) {
        throw Exception('Respons review outbound bukan daftar JSON yang valid: ${decoded.toString()}');
      }
      final rows = List<Map<String, dynamic>>.from(decoded);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) {
        final pending = rows.where((x) => ['DRAFT','PENDING','APPROVED','REJECTED','COMPLETED'].contains('${x['status']}'.toUpperCase())).toList();
        Future<void> decide(Map<String,dynamic> row, String action) async {
          String reason = '';
          if (action == 'submit' || action == 'complete') {
            try {
              final res = await http.post(Uri.parse('$apiBaseUrl/outbound-transactions/${row['id']}/$action'), headers: apiHeaders, body: jsonEncode({})).timeout(const Duration(seconds: 20));
              dynamic data; try { data = jsonDecode(res.body); } catch (_) { data = res.body; }
              if (res.statusCode < 200 || res.statusCode >= 300) throw Exception(data is Map ? (data['error'] ?? res.body) : data.toString());
              row['status'] = action == 'submit' ? 'PENDING' : 'COMPLETED'; refreshDialog(() {}); await load();
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(action == 'submit' ? 'Draft dikirim untuk verifikasi.' : 'Transaksi ditandai Completed.')));
            } catch (e) { if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Aksi transaksi gagal: $e'))); }
            return;
          }
          if (action == 'reject') {
            final controller = TextEditingController();
            final value = await showDialog<String>(context: context, builder: (c) => AlertDialog(title: const Text('Alasan penolakan'), content: TextField(controller: controller, autofocus: true, maxLines: 3, decoration: const InputDecoration(labelText: 'Alasan wajib diisi')), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Lanjutkan'))]));
            controller.dispose(); if (value == null || value.isEmpty) return; reason = value;
          }
          try {
            final res = await http.post(Uri.parse('$apiBaseUrl/outbound-transactions/${row['id']}/$action'), headers: apiHeaders, body: jsonEncode({'reason': reason})).timeout(const Duration(seconds: 20));
            dynamic data; try { data = jsonDecode(res.body); } catch (_) { data = res.body; }
            if (res.statusCode < 200 || res.statusCode >= 300) throw Exception(data is Map ? (data['error'] ?? res.body) : data.toString());
            row['status'] = action == 'approve' ? 'APPROVED' : 'REJECTED'; if (action == 'reject') row['decision_note'] = reason; refreshDialog(() {}); await load(); await loadHistory();
            if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(action == 'approve' ? 'Outbound disetujui dan stok difinalisasi.' : 'Outbound ditolak. Stok tidak berubah.')));
          } catch (e) { if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('Gagal memutuskan outbound: $e'))); }
        }
        return AlertDialog(
          title: const Text('Registrasi outbound'),
          content: SizedBox(
            width: 560,
            child: pending.isEmpty
                ? const Text('Tidak ada pengajuan outbound yang menunggu validasi.')
                : ListView(
                    shrinkWrap: true,
                    children: pending.map((row) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['transaction_no']} · ${row['sku_code']} ${row['sku_name']}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text('Status: ${row['status']}'),
                              Text('Pallet ${row['pallet_id']} · Diminta ${row['quantity']} · ${row['weight_kg']} kg'),
                              Text('Stok saat review: ${row['available_quantity']} · ${row['available_weight']} kg'),
                              if ('${row['notes']}'.trim().isNotEmpty)
                                Text('Catatan: ${row['notes']}'),
                              const SizedBox(height: 6),
                              const Text('Barang yang diajukan', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('FIFO / waktu penerimaan: ${row['received_at']}'),
                              if (row['checklist'] is List && (row['checklist'] as List).isNotEmpty) ...[
                                const SizedBox(height: 6),
                                const Text('Checklist outbound', style: TextStyle(fontWeight: FontWeight.bold)),
                                ...(row['checklist'] as List).map((item) {
                                  final label = item is Map ? '${item['label'] ?? item['name'] ?? 'Checklist'}' : '$item';
                                  final passed = item is Map && item['passed'] == true;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        Icon(passed ? Icons.check_circle : Icons.cancel, size: 16, color: passed ? Colors.green : Colors.red),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(label)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              const SizedBox(height: 8),
                              if ('${row['status']}'.toUpperCase() == 'DRAFT') OutlinedButton.icon(onPressed: () => decide(row, 'submit'), icon: const Icon(Icons.send), label: const Text('Kirim verifikasi')),
                              if ('${row['status']}'.toUpperCase() == 'PENDING') Wrap(spacing: 8, children: [
                                OutlinedButton.icon(onPressed: () => decide(row, 'reject'), icon: const Icon(Icons.close), label: const Text('Reject')),
                                FilledButton.icon(onPressed: () => decide(row, 'approve'), icon: const Icon(Icons.check), label: const Text('Approve & finalisasi')),
                              ]),
                              if ('${row['status']}'.toUpperCase() == 'APPROVED') FilledButton.icon(onPressed: () => decide(row, 'complete'), icon: const Icon(Icons.task_alt), label: const Text('Tandai Completed')),
                              if ('${row['status']}'.toUpperCase() == 'REJECTED' && '${row['decision_note'] ?? ''}'.trim().isNotEmpty) Text('Alasan: ${row['decision_note']}'),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        );
      }));
    } catch (e) { _message('Gagal memuat review outbound: $e'); }
  }

  @override
  void initState() {
    super.initState();
    load();
    loadHistory();
  }

  @override
  void dispose() {
    quantityController.dispose();
    weightController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final visibleItems = stockItems.where((item) {
      final haystack = '${_str(item, 'sku_code', '')} ${_str(item, 'sku_name', '')} ${_palletCode(item)} ${_location(item)} ${_str(item, 'batch_no', '')}'.toLowerCase();
      if (widget.palletId != null && _int(item, 'pallet_id') != widget.palletId) return false;
      return query.isEmpty || haystack.contains(query);
    }).toList();
    final selected = selectedItem;
    final availableQty = selected == null ? 0.0 : _double(selected, 'quantity');
    final availableWeight = selected == null ? 0.0 : _double(selected, 'weight_kg');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway Outbound'),
        actions: [IconButton(tooltip: 'Review outbound', onPressed: saving ? null : _reviewOutbound, icon: const Icon(Icons.fact_check_outlined)), IconButton(tooltip: 'Muat ulang', onPressed: saving ? null : () async { await load(); await loadHistory(); }, icon: const Icon(Icons.refresh))],
      ),
      drawer: const PasataNavigationDrawer(activeMenu: 'Barang Keluar'),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Gagal memuat stok: $error'), const SizedBox(height: 12), FilledButton(onPressed: load, child: const Text('Coba lagi'))])))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Cari stok tersedia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cari SKU, pallet, batch, atau lokasi'), onChanged: (v) => setState(() => search = v)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text('Stok tersedia: ${visibleItems.length} baris', style: const TextStyle(fontWeight: FontWeight.w500))),
                      const Chip(label: Text('FIFO: tertua dahulu')),
                    ]),
                    if (visibleItems.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('Tidak ada stok tersedia yang cocok dengan pencarian.')),
                    ...visibleItems.map((item) {
                      final isSelected = selected != null && _int(selected, 'id') == _int(item, 'id');
                      final received = DateTime.tryParse(_str(item, 'received_at', ''));
                      return Card(
                        color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: ListTile(
                          leading: Icon(isSelected ? Icons.radio_button_checked : Icons.inventory_2_outlined),
                          title: Text('${_str(item, 'sku_code')} · ${_str(item, 'sku_name')}'),
                          subtitle: Text('${_palletCode(item)} · ${_location(item)}\nStok ${_double(item, 'quantity')} ${_str(item, 'unit')} · ${_double(item, 'weight_kg')} kg\nBatch ${_str(item, 'batch_no')} · Masuk ${received == null ? _str(item, 'received_at') : received.toLocal().toString().substring(0, 16)}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => _selectItem(item)),
                        ),
                      );
                    }),
                  ]))),
                  const SizedBox(height: 12),
                  Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Detail pengeluaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (selected == null) const Text('Pilih salah satu baris stok di atas untuk memulai outbound.') else ...[
                      Text('${_str(selected, 'sku_code')} · ${_str(selected, 'sku_name')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Pallet ${_palletCode(selected)} · Lokasi ${_location(selected)}'),
                      Text('Tersedia ${availableQty.toStringAsFixed(2)} ${_str(selected, 'unit')} · ${availableWeight.toStringAsFixed(2)} kg'),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [ButtonSegment(value: true, label: Text('Full outbound'), icon: Icon(Icons.inventory_2)), ButtonSegment(value: false, label: Text('Partial outbound'), icon: Icon(Icons.exposure_minus_1))],
                        selected: {fullOutbound},
                        onSelectionChanged: saving ? null : (v) => setState(() {
                          fullOutbound = v.first;
                          if (fullOutbound && selectedItem != null) {
                            quantityController.text = availableQty.toString();
                            weightController.text = availableWeight.toString();
                          } else if (!fullOutbound) {
                            quantityController.text = '';
                            weightController.text = '';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: quantityController, readOnly: fullOutbound, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Jumlah keluar (${_str(selected, 'unit')})', helperText: fullOutbound ? 'Seluruh stok akan dikeluarkan.' : 'Masukkan jumlah yang diminta; sisa stok tetap tersimpan.')),
                      const SizedBox(height: 10),
                      TextField(controller: weightController, readOnly: fullOutbound, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Berat keluar (kg)', helperText: fullOutbound ? 'Berat mengikuti seluruh stok tersisa.' : 'Masukkan berat aktual yang dikeluarkan.')),
                      const SizedBox(height: 10),
                      TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Catatan / referensi outbound (opsional)')),
                      const Divider(height: 24),
                      const Text('Checklist outbound', style: TextStyle(fontWeight: FontWeight.w600)),
                      ...checks.keys.map((label) => CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.trailing, title: Text(label), value: checks[label], onChanged: saving ? null : (v) => setState(() => checks[label] = v ?? false))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: OutlinedButton.icon(onPressed: saving ? null : () => _submitOutbound(asDraft: true), icon: const Icon(Icons.save_outlined), label: const Text('Simpan Draft'))),
                        const SizedBox(width: 8),
                        Expanded(child: FilledButton.icon(onPressed: saving ? null : () => _submitOutbound(), icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.output), label: Text(saving ? 'Mengirim...' : 'Kirim verifikasi'))),
                      ]),
                      const SizedBox(height: 8),
                      const Text('Draft dapat disimpan sebelum checklist lengkap. Kirim verifikasi hanya setelah checklist lengkap. Stok baru berkurang setelah supervisor menyetujui transaksi.', style: TextStyle(fontSize: 12)),
                    ],
                  ]))),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Riwayat outbound', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                              IconButton(
                                tooltip: 'Muat ulang riwayat',
                                onPressed: historyLoading ? null : loadHistory,
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                          const Text('Buka setiap transaksi untuk melihat detail pengeluaran dan hasil finalisasi.'),
                          const SizedBox(height: 8),
                          if (historyLoading && outboundHistory.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (historyError != null && outboundHistory.isEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Riwayat gagal dimuat: $historyError'),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(onPressed: loadHistory, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
                                ),
                              ],
                            )
                          else if (outboundHistory.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Belum ada riwayat outbound.'),
                            )
                          else
                            ...outboundHistory.map((row) {
                              final status = _str(row, 'status', 'PENDING').toUpperCase();
                              final statusColor = _historyStatusColor(status);
                              final quantity = _double(row, 'quantity');
                              final weight = _double(row, 'weight_kg');
                              final unit = _str(row, 'unit', '');
                              final stockQty = _double(row, 'available_quantity');
                              final stockWeight = _double(row, 'available_weight');
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ExpansionTile(
                                  leading: const Icon(Icons.outbox_outlined),
                                  title: Text('${_str(row, 'transaction_no', 'Outbound')} · ${_str(row, 'sku_code')} ${_str(row, 'sku_name')}'),
                                  subtitle: Text('${_formatHistoryDate(row['created_at'])} · Pallet ${_palletCode(row)}'),
                                  trailing: Chip(
                                    label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    backgroundColor: statusColor,
                                    side: BorderSide.none,
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  children: [
                                    const Divider(),
                                    _historyDetailRow('Lokasi', _location(row)),
                                    _historyDetailRow('Batch', _str(row, 'batch_no')),
                                    _historyDetailRow('Jumlah keluar', '${quantity.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}'),
                                    _historyDetailRow('Berat keluar', '${weight.toStringAsFixed(2)} kg'),
                                    _historyDetailRow('Stok saat riwayat dimuat', '${stockQty.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'} · ${stockWeight.toStringAsFixed(2)} kg'),
                                    _historyDetailRow('Waktu pengajuan', _formatHistoryDate(row['created_at'])),
                                    _historyDetailRow('Waktu keputusan', _formatHistoryDate(row['decided_at'])),
                                    _historyDetailRow('Catatan pengajuan', _str(row, 'notes', '-')),
                                    _historyDetailRow('Keputusan supervisor', _str(row, 'decision_note', '-')),
                                    _historyDetailRow('Pengaju (user ID)', _str(row, 'requested_by', '-')),
                                    _historyDetailRow('Pemutus (user ID)', _str(row, 'decided_by', '-')),
                                    if (status == 'APPROVED')
                                      const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 8), child: Text('Finalisasi berhasil: stok telah diproses saat approval.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500))),),
                                    if (status == 'REJECTED')
                                      const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 8), child: Text('Pengajuan ditolak; stok tidak dikurangi.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),),
                                  ],
                                ),
                              );
                            }),
                          if (historyLoading && outboundHistory.isNotEmpty)
                            const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                          if (historyError != null && outboundHistory.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Pembaruan riwayat gagal: $historyError', style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _historyDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 190, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
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
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (scaffoldContext) => IconButton(
            tooltip: 'Buka menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
          ),
        ),
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
      drawer: const PasataNavigationDrawer(activeMenu: 'Data Gudang'),
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

class AreaColdStoragePage extends StatefulWidget {
  final int initialTab;
  const AreaColdStoragePage({super.key, this.initialTab = 0});
  @override
  State<AreaColdStoragePage> createState() => _AreaColdStoragePageState();
}

class _AreaColdStoragePageState extends State<AreaColdStoragePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _coldStorages = [];
  List<Warehouse> _warehouses = [];
  static const _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  int _id(Map<String, dynamic> m, String key) =>
      (m[key] as num?)?.toInt() ?? int.tryParse('${m[key]}') ?? 0;
  String _value(Map<String, dynamic> m, String key, [String fallback = '']) =>
      m[key] == null ? fallback : '${m[key]}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final r = await http
        .get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final decoded = jsonDecode(r.body);
    if (decoded is! List) throw Exception('Respons $path bukan daftar');
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        WarehouseApi.list(),
        _getList('warehouse-areas'),
        _getList('cold-storages'),
      ]);
      if (!mounted) return;
      setState(() {
        _warehouses = results[0] as List<Warehouse>;
        _areas = results[1] as List<Map<String, dynamic>>;
        _coldStorages = results[2] as List<Map<String, dynamic>>;
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

  Future<void> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$apiBaseUrl/$path');
    late http.Response r;
    if (method == 'POST') {
      r = await http
          .post(uri, headers: apiHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } else if (method == 'PUT') {
      r = await http
          .put(uri, headers: apiHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } else {
      r = await http
          .delete(uri, headers: apiHeaders)
          .timeout(const Duration(seconds: 15));
    }
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  void _toast(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _areaForm({Map<String, dynamic>? item}) async {
    if (_warehouses.isEmpty) {
      _toast('Tambahkan data gudang terlebih dahulu.');
      return;
    }
    final form = GlobalKey<FormState>();
    final code = TextEditingController(text: _value(item ?? {}, 'code'));
    final name = TextEditingController(text: _value(item ?? {}, 'name'));
    final capacity = TextEditingController(
      text: item?['capacity_pallet'] == null
          ? ''
          : '${item?['capacity_pallet']}',
    );
    final description = TextEditingController(
      text: _value(item ?? {}, 'description'),
    );
    int warehouseId = _id(item ?? {}, 'warehouse_id');
    if (!_warehouses.any((w) => w.id == warehouseId))
      warehouseId = _warehouses.first.id;
    String type = _value(item ?? {}, 'area_type', 'FROZEN');
    String status = _value(item ?? {}, 'status', 'ACTIVE');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(item == null ? 'Tambah Area Gudang' : 'Edit Area Gudang'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: warehouseId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Gudang'),
                      items: _warehouses
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(
                                '${w.name} (${w.code})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => warehouseId = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'Kode area'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Kode wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nama area'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Jenis area',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'AMBIENT',
                          child: Text('Ambient'),
                        ),
                        DropdownMenuItem(
                          value: 'CHILLED',
                          child: Text('Chilled'),
                        ),
                        DropdownMenuItem(
                          value: 'FROZEN',
                          child: Text('Frozen'),
                        ),
                        DropdownMenuItem(value: 'DOCK', child: Text('Dock')),
                        DropdownMenuItem(
                          value: 'STAGING',
                          child: Text('Staging'),
                        ),
                        DropdownMenuItem(value: 'AISLE', child: Text('Aisle')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => type = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Kapasitas pallet (opsional)',
                      ),
                      validator: (v) =>
                          (v != null &&
                              v.trim().isNotEmpty &&
                              (int.tryParse(v) == null || int.parse(v) < 0))
                          ? 'Masukkan angka nol atau lebih'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi (opsional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Aktif')),
                        DropdownMenuItem(
                          value: 'MAINTENANCE',
                          child: Text('Pemeliharaan'),
                        ),
                        DropdownMenuItem(
                          value: 'INACTIVE',
                          child: Text('Nonaktif'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      },
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
                if (!form.currentState!.validate()) return;
                Navigator.pop(ctx, {
                  'warehouse_id': warehouseId,
                  'code': code.text.trim(),
                  'name': name.text.trim(),
                  'area_type': type,
                  'capacity_pallet': capacity.text.trim().isEmpty
                      ? null
                      : int.parse(capacity.text),
                  'description': description.text.trim(),
                  'status': status,
                });
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await _send(
        item == null ? 'POST' : 'PUT',
        item == null ? 'warehouse-areas' : 'warehouse-areas/${_id(item, 'id')}',
        result,
      );
      await _load();
      _toast(
        item == null
            ? 'Area berhasil ditambahkan.'
            : 'Area berhasil diperbarui.',
      );
    } catch (e) {
      _toast('Gagal menyimpan area: $e');
    }
  }

  Future<void> _coldForm({Map<String, dynamic>? item}) async {
    if (_areas.isEmpty) {
      _toast('Tambahkan area gudang terlebih dahulu.');
      return;
    }
    final form = GlobalKey<FormState>();
    final code = TextEditingController(text: _value(item ?? {}, 'code'));
    final name = TextEditingController(text: _value(item ?? {}, 'name'));
    final minTemp = TextEditingController(
      text: _value(item ?? {}, 'min_temp', '-25'),
    );
    final maxTemp = TextEditingController(
      text: _value(item ?? {}, 'max_temp', '-18'),
    );
    final currentTemp = TextEditingController(
      text: _value(item ?? {}, 'current_temp'),
    );
    final capacity = TextEditingController(
      text: item?['capacity_pallet'] == null
          ? ''
          : '${item?['capacity_pallet']}',
    );
    int areaId = _id(item ?? {}, 'warehouse_area_id');
    if (!_areas.any((a) => _id(a, 'id') == areaId))
      areaId = _id(_areas.first, 'id');
    String type = _value(item ?? {}, 'storage_type', 'FROZEN');
    String status = _value(item ?? {}, 'status', 'ACTIVE');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            item == null ? 'Tambah Cold Storage' : 'Edit Cold Storage',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: areaId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Area gudang',
                      ),
                      items: _areas
                          .map(
                            (a) => DropdownMenuItem(
                              value: _id(a, 'id'),
                              child: Text(
                                '${_value(a, 'name')} (${_value(a, 'code')})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => areaId = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: code,
                      decoration: const InputDecoration(
                        labelText: 'Kode cold storage',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Kode wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Nama cold storage',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Jenis penyimpanan',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'CHILLED',
                          child: Text('Chilled'),
                        ),
                        DropdownMenuItem(
                          value: 'FROZEN',
                          child: Text('Frozen'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => type = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: minTemp,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Suhu minimum °C',
                            ),
                            validator: (v) => double.tryParse(v ?? '') == null
                                ? 'Angka tidak valid'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: maxTemp,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Suhu maksimum °C',
                            ),
                            validator: (v) => double.tryParse(v ?? '') == null
                                ? 'Angka tidak valid'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: currentTemp,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Suhu saat ini °C (opsional)',
                      ),
                      validator: (v) =>
                          v != null &&
                              v.trim().isNotEmpty &&
                              double.tryParse(v) == null
                          ? 'Angka tidak valid'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Kapasitas pallet (opsional)',
                      ),
                      validator: (v) =>
                          (v != null &&
                              v.trim().isNotEmpty &&
                              (int.tryParse(v) == null || int.parse(v) < 0))
                          ? 'Masukkan angka nol atau lebih'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Aktif')),
                        DropdownMenuItem(
                          value: 'MAINTENANCE',
                          child: Text('Pemeliharaan'),
                        ),
                        DropdownMenuItem(
                          value: 'INACTIVE',
                          child: Text('Nonaktif'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      },
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
                if (!form.currentState!.validate()) return;
                final min = double.parse(minTemp.text);
                final max = double.parse(maxTemp.text);
                if (min > max) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Suhu minimum tidak boleh lebih besar dari maksimum.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'warehouse_area_id': areaId,
                  'code': code.text.trim(),
                  'name': name.text.trim(),
                  'storage_type': type,
                  'min_temp': min,
                  'max_temp': max,
                  'current_temp': currentTemp.text.trim().isEmpty
                      ? null
                      : double.parse(currentTemp.text),
                  'capacity_pallet': capacity.text.trim().isEmpty
                      ? null
                      : int.parse(capacity.text),
                  'status': status,
                });
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await _send(
        item == null ? 'POST' : 'PUT',
        item == null ? 'cold-storages' : 'cold-storages/${_id(item, 'id')}',
        result,
      );
      await _load();
      _toast(
        item == null
            ? 'Cold storage berhasil ditambahkan.'
            : 'Cold storage berhasil diperbarui.',
      );
    } catch (e) {
      _toast('Gagal menyimpan cold storage: $e');
    }
  }

  Future<void> _deactivate(Map<String, dynamic> item, bool cold) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan data?'),
        content: Text(
          '${_value(item, 'name')} akan dinonaktifkan dan tidak dihapus permanen.',
        ),
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
      await _send(
        'DELETE',
        '${cold ? 'cold-storages' : 'warehouse-areas'}/${_id(item, 'id')}',
      );
      await _load();
      _toast('Data berhasil dinonaktifkan.');
    } catch (e) {
      _toast('Gagal menonaktifkan data: $e');
    }
  }

  Widget _status(String status) {
    final active = status == 'ACTIVE';
    final maintenance = status == 'MAINTENANCE';
    final color = active
        ? const Color(0xFFDDF4E8)
        : maintenance
        ? const Color(0xFFFFE9BD)
        : const Color(0xFFE6E8E7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        active
            ? 'AKTIF'
            : maintenance
            ? 'PEMELIHARAAN'
            : 'NONAKTIF',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _areaList() {
    if (_areas.isEmpty)
      return const Center(child: Text('Belum ada area gudang.'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _areas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final a = _areas[i];
        final wh = _warehouses
            .where((w) => w.id == _id(a, 'warehouse_id'))
            .toList();
        return Card(
          elevation: 0,
          child: ListTile(
            isThreeLine: true,
            leading: const CircleAvatar(child: Icon(Icons.domain_outlined)),
            title: Text('${_value(a, 'name')} (${_value(a, 'code')})'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gudang: ${wh.isEmpty ? _id(a, 'warehouse_id') : wh.first.name}',
                ),
                Text(
                  'Jenis: ${_value(a, 'area_type')} · Kapasitas: ${_value(a, 'capacity_pallet', '-')} pallet',
                ),
                const SizedBox(height: 5),
                _status(_value(a, 'status', 'ACTIVE')),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit')
                  _areaForm(item: a);
                else
                  _deactivate(a, false);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (_value(a, 'status') != 'INACTIVE')
                  const PopupMenuItem(value: 'off', child: Text('Nonaktifkan')),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _coldList() {
    if (_coldStorages.isEmpty)
      return const Center(child: Text('Belum ada cold storage.'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _coldStorages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final c = _coldStorages[i];
        final a = _areas
            .where((x) => _id(x, 'id') == _id(c, 'warehouse_area_id'))
            .toList();
        return Card(
          elevation: 0,
          child: ListTile(
            isThreeLine: true,
            leading: const CircleAvatar(child: Icon(Icons.ac_unit_outlined)),
            title: Text('${_value(c, 'name')} (${_value(c, 'code')})'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Area: ${a.isEmpty ? _id(c, 'warehouse_area_id') : a.first['name']} · ${_value(c, 'storage_type')}',
                ),
                Text(
                  'Rentang: ${_value(c, 'min_temp')}°C s.d. ${_value(c, 'max_temp')}°C · Saat ini: ${_value(c, 'current_temp', '-')}°C',
                ),
                Text('Kapasitas: ${_value(c, 'capacity_pallet', '-')} pallet'),
                const SizedBox(height: 5),
                _status(_value(c, 'status', 'ACTIVE')),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit')
                  _coldForm(item: c);
                else
                  _deactivate(c, true);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (_value(c, 'status') != 'INACTIVE')
                  const PopupMenuItem(value: 'off', child: Text('Nonaktifkan')),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: PasataNavigationDrawer(activeMenu: _tabs.index == 0 ? 'Area Gudang' : 'Cold Storage'),
    appBar: AppBar(
      title: const Text('Area & Cold Storage'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Area Gudang'),
          Tab(text: 'Cold Storage'),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _tabs.index == 0 ? _areaForm() : _coldForm(),
      icon: const Icon(Icons.add),
      label: Text(_tabs.index == 0 ? 'Tambah Area' : 'Tambah Cold Storage'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorView(message: _error!, onRetry: _load)
        : TabBarView(controller: _tabs, children: [_areaList(), _coldList()]),
  );
}




class ScannerValidasiSkuPage extends StatefulWidget {
  const ScannerValidasiSkuPage({super.key});

  @override
  State<ScannerValidasiSkuPage> createState() => _ScannerValidasiSkuPageState();
}

class _ScannerValidasiSkuPageState extends State<ScannerValidasiSkuPage> {
  final TextEditingController _search = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  List<Map<String, dynamic>> _skus = [];
  Map<String, dynamic>? _matchedSku;
  String _query = '';
  String _message = 'Scan barcode atau masukkan kode SKU untuk validasi.';
  bool _loading = true;
  bool _showScanner = false;
  bool _notFound = false;
  bool _processingScan = false;

  String _value(dynamic value, [String fallback = '-']) =>
      value == null || '$value'.trim().isEmpty ? fallback : '$value';

  @override
  void initState() {
    super.initState();
    _loadSkus();
  }

  @override
  void dispose() {
    _search.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadSkus() async {
    setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/skus'), headers: apiHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw Exception('Format data SKU tidak sesuai.');
      if (!mounted) return;
      setState(() {
        _skus = decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
      if (_query.trim().isNotEmpty) _validate(_query);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Gagal memuat Master SKU: $error';
      });
    }
  }

  void _validate(String rawValue) {
    final input = rawValue.trim();
    if (input.isEmpty) {
      setState(() {
        _query = '';
        _matchedSku = null;
        _notFound = false;
        _message = 'Masukkan kode SKU atau barcode terlebih dahulu.';
      });
      return;
    }
    final normalized = input.toLowerCase();
    Map<String, dynamic>? match;
    for (final sku in _skus) {
      final code = _value(sku['sku_code'], '').trim().toLowerCase();
      final barcode = _value(sku['barcode'], '').trim().toLowerCase();
      if (code == normalized || (barcode.isNotEmpty && barcode == normalized)) {
        match = sku;
        break;
      }
    }
    setState(() {
      _query = input;
      _matchedSku = match;
      _notFound = match == null;
      if (match == null) {
        _message = 'PERINGATAN: SKU/barcode "$input" tidak terdaftar di Master SKU.';
      } else if (match['is_active'] == false) {
        _message = 'SKU ditemukan, tetapi statusnya NONAKTIF. Jangan gunakan untuk transaksi baru.';
      } else {
        _message = 'SKU valid dan terdaftar di Master SKU.';
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processingScan) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code == null) return;
    _processingScan = true;
    _scannerController.stop();
    _search.text = code;
    setState(() => _showScanner = false);
    _validate(code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Barcode terbaca: $code')),
    );
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      _processingScan = false;
    });
  }

  List<Map<String, dynamic>> get _searchResults {
    final q = _query.toLowerCase();
    if (q.isEmpty) return _skus.where((sku) => sku['is_active'] != false).take(10).toList();
    return _skus.where((sku) {
      return ['sku_code', 'barcode', 'name', 'category'].any(
        (key) => _value(sku[key], '').toLowerCase().contains(q),
      );
    }).take(20).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner & Validasi SKU'),
        actions: [
          IconButton(tooltip: 'Muat ulang Master SKU', onPressed: _loadSkus, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: const PasataNavigationDrawer(activeMenu: 'Scanner & Validasi SKU'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSkus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [Icon(Icons.qr_code_scanner), SizedBox(width: 8), Expanded(child: Text('Validasi Barcode / SKU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))]),
                        const SizedBox(height: 8),
                        const Text('Scan menggunakan kamera atau masukkan kode dari scanner barcode USB/Bluetooth.'),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _validate,
                          decoration: InputDecoration(
                            labelText: 'Barcode atau kode SKU',
                            hintText: 'Contoh: SKU-FRZ-001',
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(icon: const Icon(Icons.clear), tooltip: 'Hapus', onPressed: () { _search.clear(); _validate(''); }),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(onPressed: () => _validate(_search.text), icon: const Icon(Icons.fact_check_outlined), label: const Text('Validasi SKU')),
                          OutlinedButton.icon(onPressed: () async { setState(() => _showScanner = !_showScanner); if (_showScanner) { await _scannerController.start(); } else { await _scannerController.stop(); } }, icon: Icon(_showScanner ? Icons.close : Icons.camera_alt_outlined), label: Text(_showScanner ? 'Tutup kamera' : 'Scan dengan kamera')),
                        ]),
                        if (_showScanner) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(height: 300, child: MobileScanner(controller: _scannerController, onDetect: _onDetect)),
                          ),
                          const SizedBox(height: 6),
                          const Text('Arahkan kamera ke barcode. Izin kamera harus diizinkan di browser/perangkat.', style: TextStyle(fontSize: 12)),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: _notFound
                        ? Theme.of(context).colorScheme.errorContainer
                        : _matchedSku != null && _matchedSku!['is_active'] == false
                            ? Colors.orange.shade100
                            : _matchedSku != null
                                ? Colors.green.shade50
                                : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_notFound ? Icons.warning_amber_rounded : _matchedSku != null && _matchedSku!['is_active'] != false ? Icons.check_circle_outline : Icons.info_outline),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Hasil Validasi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                        ]),
                        const SizedBox(height: 8),
                        Text(_message),
                        if (_matchedSku != null) ...[
                          const Divider(height: 24),
                          Text('${_value(_matchedSku!['sku_code'])} · ${_value(_matchedSku!['name'])}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('Barcode: ${_value(_matchedSku!['barcode'])}'),
                          Text('Kategori: ${_value(_matchedSku!['category'])}'),
                          Text('Satuan: ${_value(_matchedSku!['unit'])}'),
                          Text('Penyimpanan: ${_value(_matchedSku!['storage_type'])}'),
                          Text('Status SKU: ${_matchedSku!['is_active'] == false ? 'NONAKTIF' : 'AKTIF'}'),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('SKU ${_query.isEmpty ? 'Aktif' : 'yang cocok'} (${_searchResults.length})', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  if (_searchResults.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Tidak ada SKU yang cocok.'))),
                  ..._searchResults.map((sku) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.qr_code_2_outlined),
                      title: Text('${_value(sku['sku_code'])} · ${_value(sku['name'])}'),
                      subtitle: Text('Barcode: ${_value(sku['barcode'])} · ${_value(sku['category'])}'),
                      trailing: Chip(label: Text(sku['is_active'] == false ? 'NONAKTIF' : 'AKTIF')),
                      onTap: () { _search.text = _value(sku['barcode'], _value(sku['sku_code'], '')); _validate(_search.text); },
                    ),
                  )),
                ],
              ),
            ),
    );
  }
}


class MasterSkuPage extends StatefulWidget {
  const MasterSkuPage({super.key});
  @override
  State<MasterSkuPage> createState() => _MasterSkuPageState();
}

class _MasterSkuPageState extends State<MasterSkuPage> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String query = '';
  String statusFilter = 'SEMUA';
  String error = '';

  String val(dynamic v, [String fallback = '-']) => v == null || '$v'.trim().isEmpty ? fallback : '$v';
  double? numVal(dynamic v) => v == null ? null : double.tryParse('$v');
  void toast(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }

  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final r = await http.get(Uri.parse('$apiBaseUrl/skus'), headers: apiHeaders).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception(r.body.isEmpty ? 'HTTP ${r.statusCode}' : r.body);
      final data = jsonDecode(r.body);
      if (data is! List) throw Exception('Format data SKU tidak sesuai.');
      setState(() { rows = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(); loading = false; });
    } catch (e) { setState(() { loading = false; error = '$e'; }); }
  }

  Future<void> saveSku({Map<String, dynamic>? existing}) async {
    final editing = existing != null;
    final code = TextEditingController(text: val(existing?['sku_code'], ''));
    final barcode = TextEditingController(text: val(existing?['barcode'], ''));
    final name = TextEditingController(text: val(existing?['name'], ''));
    final category = TextEditingController(text: val(existing?['category'], ''));
    final minTemp = TextEditingController(text: existing?['min_temp'] == null ? '' : '${existing!['min_temp']}');
    final maxTemp = TextEditingController(text: existing?['max_temp'] == null ? '' : '${existing!['max_temp']}');
    final weight = TextEditingController(text: existing?['weight_per_unit'] == null ? '' : '${existing!['weight_per_unit']}');
    final shelf = TextEditingController(text: existing?['shelf_life_days'] == null ? '' : '${existing!['shelf_life_days']}');
    String unit = val(existing?['unit'], 'KG');
    String storage = val(existing?['storage_type'], 'FROZEN');
    String skuStatus = existing?['is_active'] == false ? 'NONAKTIF' : 'AKTIF';
    final result = await showDialog<Map<String, dynamic>>(context: context, barrierDismissible: false, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: Text(editing ? 'Edit SKU' : 'Tambah SKU'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Informasi Dasar Barang', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Kode SKU *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code_2))),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama barang *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.inventory_2_outlined))),
              const SizedBox(height: 10),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Jenis barang / kategori', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category_outlined))),
              const SizedBox(height: 10),
              TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Barcode (opsional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code_scanner))),
              const SizedBox(height: 10),
              const Text('Status SKU *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: skuStatus,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.toggle_on_outlined), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                items: const [DropdownMenuItem(value: 'AKTIF', child: Text('Aktif')), DropdownMenuItem(value: 'NONAKTIF', child: Text('Nonaktif'))],
                onChanged: (v) => refresh(() => skuStatus = v ?? 'AKTIF'),
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Informasi Penyimpanan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text('Satuan *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: unit,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.scale_outlined), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                items: const ['KG','PCS','CARTON','SACK','BOX','PACK'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (v) => refresh(() => unit = v ?? 'KG'),
              ),
              const SizedBox(height: 12),
              const Text('Tipe penyimpanan *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: storage,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.ac_unit), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                items: const [DropdownMenuItem(value: 'AMBIENT', child: Text('Ambient (suhu ruang)')), DropdownMenuItem(value: 'CHILLED', child: Text('Chilled (dingin)')), DropdownMenuItem(value: 'FROZEN', child: Text('Frozen (beku)'))],
                onChanged: (v) => refresh(() => storage = v ?? 'FROZEN'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: minTemp, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Suhu minimum (°C)', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: maxTemp, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Suhu maksimum (°C)', border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Berat per unit (kg)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.monitor_weight_outlined))),
              const SizedBox(height: 10),
              TextField(controller: shelf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Masa simpan (hari)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.event_outlined))),
              const SizedBox(height: 8),
              const Text('* wajib diisi', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, {'sku_code': code.text.trim().toUpperCase(), 'barcode': barcode.text.trim(), 'name': name.text.trim(), 'category': category.text.trim(), 'unit': unit, 'storage_type': storage, 'min_temp': minTemp.text.trim(), 'max_temp': maxTemp.text.trim(), 'weight_per_unit': weight.text.trim(), 'shelf_life_days': shelf.text.trim(), 'is_active': skuStatus == 'AKTIF'}), child: const Text('Simpan')),
      ],
    )));
    if (result == null) return;
    if ((result['sku_code'] as String).isEmpty || (result['name'] as String).isEmpty) { toast('Kode SKU dan nama barang wajib diisi.'); return; }
    double? mn, mx, wt; int? life;
    for (final key in ['min_temp','max_temp','weight_per_unit']) {
      final raw = (result[key] as String).trim();
      if (raw.isNotEmpty && double.tryParse(raw) == null) { toast('Nilai $key harus berupa angka.'); return; }
    }
    mn = (result['min_temp'] as String).isEmpty ? null : double.parse(result['min_temp'] as String);
    mx = (result['max_temp'] as String).isEmpty ? null : double.parse(result['max_temp'] as String);
    wt = (result['weight_per_unit'] as String).isEmpty ? null : double.parse(result['weight_per_unit'] as String);
    if ((result['shelf_life_days'] as String).trim().isNotEmpty) { life = int.tryParse(result['shelf_life_days'] as String); if (life == null || life < 0) { toast('Masa simpan harus bilangan bulat nol atau lebih.'); return; } }
    if (mn != null && mx != null && mn > mx) { toast('Suhu minimum tidak boleh lebih besar dari suhu maksimum.'); return; }
    if (wt != null && wt < 0) { toast('Berat per unit tidak boleh negatif.'); return; }
    final body = <String, dynamic>{'sku_code':result['sku_code'],'barcode':(result['barcode'] as String).isEmpty?null:result['barcode'],'name':result['name'],'category':(result['category'] as String).isEmpty?null:result['category'],'unit':result['unit'],'storage_type':result['storage_type'],'min_temp':mn,'max_temp':mx,'weight_per_unit':wt,'shelf_life_days':life,'is_active':result['is_active']};
    try {
      final id = existing?['id'];
      final uri = Uri.parse('$apiBaseUrl/skus${id == null ? '' : '/$id'}');
      final response = id == null
        ? await http.post(uri, headers:apiHeaders, body:jsonEncode(body)).timeout(const Duration(seconds:15))
        : await http.put(uri, headers:apiHeaders, body:jsonEncode(body)).timeout(const Duration(seconds:15));
      if (response.statusCode != 200 && response.statusCode != 201) throw Exception(response.body.isEmpty?'HTTP ${response.statusCode}':response.body);
      toast(editing?'SKU berhasil diperbarui.':'SKU berhasil ditambahkan.'); await load();
    } catch(e) { toast('Gagal menyimpan SKU: $e'); }
  }

  Future<void> deactivateSku(Map<String,dynamic> sku) async {
    final yes = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Nonaktifkan SKU?'),content:Text('SKU ${val(sku['sku_code'])} akan dinonaktifkan. Data isi pallet dan riwayat yang sudah ada tidak dihapus.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Nonaktifkan'))]));
    if (yes != true) return;
    try { final r=await http.delete(Uri.parse('$apiBaseUrl/skus/${sku['id']}'),headers:apiHeaders).timeout(const Duration(seconds:15)); if(r.statusCode!=200) throw Exception(r.body.isEmpty?'HTTP ${r.statusCode}':r.body); toast('SKU dinonaktifkan.'); await load(); } catch(e) { toast('Gagal menonaktifkan SKU: $e'); }
  }

  @override
  void initState(){super.initState();load();}
  @override
  Widget build(BuildContext context) {
    final filtered = rows.where((x) {
      final q = query.toLowerCase();
      final matches = q.isEmpty ||
          ['sku_code', 'barcode', 'name', 'category'].any(
            (k) => val(x[k], '').toLowerCase().contains(q),
          );
      final active = x['is_active'] != false;
      return matches &&
          (statusFilter == 'SEMUA' ||
              (statusFilter == 'AKTIF' && active) ||
              (statusFilter == 'NONAKTIF' && !active));
    }).toList();

    final activeCount = rows.where((x) => x['is_active'] != false).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Master SKU'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const PasataNavigationDrawer(activeMenu: 'Master SKU'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => saveSku(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah SKU'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Gagal memuat Master SKU\n$error',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _summary('Total SKU', rows.length, Icons.qr_code_2),
                          _summary('Aktif', activeCount, Icons.check_circle_outline),
                          _summary(
                            'Nonaktif',
                            rows.length - activeCount,
                            Icons.pause_circle_outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Cari kode, barcode, nama, kategori',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['SEMUA', 'AKTIF', 'NONAKTIF']
                            .map(
                              (x) => DropdownMenuItem<String>(
                                value: x,
                                child: Text(x),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => statusFilter = v ?? 'SEMUA');
                        },
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('Tidak ada data SKU yang cocok.'),
                          ),
                        ),
                      ...filtered.map(
                        (sku) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${val(sku['sku_code'])} · ${val(sku['name'])}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        sku['is_active'] == false
                                            ? 'NONAKTIF'
                                            : 'AKTIF',
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Barcode: ${val(sku['barcode'])} · '
                                  'Kategori: ${val(sku['category'])}',
                                ),
                                Text(
                                  'Satuan: ${val(sku['unit'])} · '
                                  'Penyimpanan: ${val(sku['storage_type'])}',
                                ),
                                Text(
                                  'Suhu: ${val(sku['min_temp'])}°C sampai '
                                  '${val(sku['max_temp'])}°C · '
                                  'Berat/unit: ${val(sku['weight_per_unit'])} kg',
                                ),
                                Text(
                                  'Masa simpan: ${val(sku['shelf_life_days'])} hari',
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => saveSku(existing: sku),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit'),
                                    ),
                                    if (sku['is_active'] != false)
                                      TextButton.icon(
                                        onPressed: () => deactivateSku(sku),
                                        icon: const Icon(Icons.block_outlined),
                                        label: const Text('Nonaktifkan'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _summary(String label,int count,IconData icon)=>SizedBox(width:145,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon),const SizedBox(height:8),Text('$count',style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),Text(label)]))));
}


class StockPhysicalSummaryPage extends StatefulWidget {
  const StockPhysicalSummaryPage({super.key});
  @override
  State<StockPhysicalSummaryPage> createState() => _StockPhysicalSummaryPageState();
}

class _StockPhysicalSummaryPageState extends State<StockPhysicalSummaryPage> {
  bool loading = true;
  String? error;
  String search = '';
  String packageFilter = 'SEMUA';
  List<Map<String, dynamic>> rows = [];

  int _id(Map<String, dynamic> x, String k) {
    final v = x[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
  double _num(Map<String, dynamic> x, String k) {
    final v = x[k];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
  String _text(Map<String, dynamic> x, String k, [String fallback = '-']) {
    final v = x[k];
    return v == null || '$v'.trim().isEmpty ? fallback : '$v';
  }
  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final r = await http.get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final data = jsonDecode(r.body);
    if (data is! List) throw Exception('Respons $path bukan daftar data');
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final pallets = await _getList('pallets');
      final all = <Map<String, dynamic>>[];
      for (final p in pallets) {
        final id = _id(p, 'id');
        if (id <= 0) continue;
        final items = await _getList('pallet-items?pallet_id=$id');
        for (final item in items) {
          all.add({...item, 'pallet_code': p['pallet_code'] ?? p['code'] ?? 'Pallet $id'});
        }
      }
      if (!mounted) return;
      setState(() { rows = all; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; loading = false; });
    }
  }
  double _sum(String key) => rows.fold<double>(0, (sum, x) => sum + _num(x, key));
  double _outboundQty(Map<String, dynamic> x) => (_num(x, 'initial_quantity') - _num(x, 'quantity')).clamp(0, double.infinity).toDouble();
  double _outboundWeight(Map<String, dynamic> x) => (_num(x, 'initial_weight_kg') - _num(x, 'weight_kg')).clamp(0, double.infinity).toDouble();
  int _outboundPacks(Map<String, dynamic> x) => (_id(x, 'initial_packaging_qty') - _id(x, 'packaging_qty')).clamp(0, 1 << 31).toInt();
  List<Map<String, dynamic>> get _filtered => rows.where((x) {
    final q = search.trim().toLowerCase();
    final matches = q.isEmpty || ['sku_code','sku_name','pallet_code','batch_no'].any((k) => _text(x,k,'').toLowerCase().contains(q));
    final pack = _text(x, 'packaging_type', '').toUpperCase();
    return matches && (packageFilter == 'SEMUA' || pack == packageFilter);
  }).toList();
  Widget _metric(String title, String value, IconData icon) => SizedBox(width: 210, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 25), const SizedBox(height: 10), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(title)]))));
  @override
  void initState() { super.initState(); load(); }
  @override
  Widget build(BuildContext context) {
    final initialQty = _sum('initial_quantity');
    final remainingQty = _sum('quantity');
    final initialWeight = _sum('initial_weight_kg');
    final remainingWeight = _sum('weight_kg');
    final outboundQty = rows.fold<double>(0, (s, x) => s + _outboundQty(x));
    final outboundWeight = rows.fold<double>(0, (s, x) => s + _outboundWeight(x));
    int initialPack(String type) => rows.where((x) => _text(x,'packaging_type','').toUpperCase()==type).fold<int>(0,(s,x)=>s+_id(x,'initial_packaging_qty'));
    int remainingPack(String type) => rows.where((x) => _text(x,'packaging_type','').toUpperCase()==type).fold<int>(0,(s,x)=>s+_id(x,'packaging_qty'));
    int outboundPack(String type) => rows.where((x) => _text(x,'packaging_type','').toUpperCase()==type).fold<int>(0,(s,x)=>s+_outboundPacks(x));
    return Scaffold(
      appBar: AppBar(title: const Text('Stock & Physical Summary'), actions: [IconButton(tooltip:'Muat ulang', onPressed:load, icon:const Icon(Icons.refresh))]),
      drawer: const PasataNavigationDrawer(activeMenu:'Stock & Physical Summary'),
      body: loading ? const Center(child:CircularProgressIndicator()) : error != null ? Center(child:Padding(padding:const EdgeInsets.all(24), child:Column(mainAxisSize:MainAxisSize.min, children:[Text('Gagal memuat ringkasan stok\n$error',textAlign:TextAlign.center),const SizedBox(height:12),FilledButton(onPressed:load,child:const Text('Coba lagi'))]))) : RefreshIndicator(onRefresh:load, child:ListView(padding:const EdgeInsets.all(16), children:[
        Text('Ringkasan seluruh pallet berdasarkan data isi pallet yang tercatat.', style:Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          _metric('Total berat awal', '${initialWeight.toStringAsFixed(2)} kg', Icons.scale_outlined),
          _metric('Berat tersisa', '${remainingWeight.toStringAsFixed(2)} kg', Icons.inventory_2_outlined),
          _metric('Berat outbound', '${outboundWeight.toStringAsFixed(2)} kg', Icons.output_outlined),
          _metric('Quantity awal', initialQty.toStringAsFixed(2), Icons.add_box_outlined),
          _metric('Quantity tersisa', remainingQty.toStringAsFixed(2), Icons.inventory_outlined),
          _metric('Quantity outbound', outboundQty.toStringAsFixed(2), Icons.remove_circle_outline),
        ]),
        const SizedBox(height:16),
        Text('Ringkasan kemasan', style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        Card(child:SingleChildScrollView(scrollDirection:Axis.horizontal, child:DataTable(columns:const [DataColumn(label:Text('Kemasan')),DataColumn(label:Text('Awal')),DataColumn(label:Text('Tersisa')),DataColumn(label:Text('Outbound'))],rows:[
          for(final entry in const [('CARTON','Karton'),('SACK','Sak'),('BOX','Box')]) DataRow(cells:[DataCell(Text(entry.$2)),DataCell(Text('${initialPack(entry.$1)}')),DataCell(Text('${remainingPack(entry.$1)}')),DataCell(Text('${outboundPack(entry.$1)}'))]),
        ]))),
        const SizedBox(height:16),
        TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Cari SKU, nama barang, pallet, batch',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>search=v)),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(initialValue:packageFilter,decoration:const InputDecoration(labelText:'Jenis kemasan',border:OutlineInputBorder()),items:const ['SEMUA','CARTON','SACK','BOX','OTHER'].map((x)=>DropdownMenuItem(value:x,child:Text(x=='SEMUA'?'Semua kemasan':x=='CARTON'?'Karton':x=='SACK'?'Sak':x=='BOX'?'Box':'Lainnya'))).toList(),onChanged:(v)=>setState(()=>packageFilter=v??'SEMUA')),
        const SizedBox(height:8),
        if (_filtered.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Center(child:Text('Tidak ada data stok yang cocok.'))),
        ..._filtered.map((x) => Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text('${_text(x,'sku_code')} · ${_text(x,'sku_name')}',style:const TextStyle(fontWeight:FontWeight.bold))),Chip(label:Text(_text(x,'status')))]),
          Text('Pallet: ${_text(x,'pallet_code')} · Batch: ${_text(x,'batch_no')}'),
          Text('Quantity: awal ${_num(x,'initial_quantity').toStringAsFixed(2)} · tersisa ${_num(x,'quantity').toStringAsFixed(2)} · outbound ${_outboundQty(x).toStringAsFixed(2)} ${_text(x,'unit')}'),
          Text('Berat: awal ${_num(x,'initial_weight_kg').toStringAsFixed(2)} kg · tersisa ${_num(x,'weight_kg').toStringAsFixed(2)} kg · outbound ${_outboundWeight(x).toStringAsFixed(2)} kg'),
          Text('Kemasan: ${_text(x,'packaging_type')} · awal ${_id(x,'initial_packaging_qty')} · tersisa ${_id(x,'packaging_qty')} · outbound ${_outboundPacks(x)}'),
        ])))),
      ])),
    );
  }
}

class PalletContentPage extends StatefulWidget {
  const PalletContentPage({super.key});
  @override
  State<PalletContentPage> createState() => _PalletContentPageState();
}

class _PalletContentPageState extends State<PalletContentPage> {
  List<Map<String, dynamic>> pallets = [];
  List<Map<String, dynamic>> skus = [];
  List<Map<String, dynamic>> items = [];
  int? selectedPalletId;
  bool loading = true;
  String? error;

  int n(Map<String, dynamic> m, String k, [int d=0]) { final v=m[k]; if(v is num) return v.toInt(); return int.tryParse('$v') ?? d; }
  double d(Map<String, dynamic> m, String k) { final v=m[k]; if(v is num) return v.toDouble(); return double.tryParse('$v') ?? 0; }
  String t(Map<String, dynamic> m, String k, [String fallback='-']) { final v=m[k]; return v==null || '$v'.trim().isEmpty ? fallback : '$v'; }

  Future<List<Map<String,dynamic>>> getList(String path) async {
    final r=await http.get(Uri.parse('$apiBaseUrl/$path'),headers:apiHeaders).timeout(const Duration(seconds:15));
    if(r.statusCode!=200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final v=jsonDecode(r.body); if(v is! List) throw Exception('Respons $path tidak valid');
    return v.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<void> load({bool initial=false}) async {
    if(mounted) setState(() { loading=true; error=null; });
    try {
      final ps=await getList('pallets');
      final ss=await getList('skus');
      final id=selectedPalletId ?? (ps.isNotEmpty?n(ps.first,'id'):null);
      final its=id==null ? <Map<String,dynamic>>[] : await getList('pallet-items?pallet_id=$id');
      if(!mounted)return;
      setState(() { pallets=ps; skus=ss; selectedPalletId=id; items=its; loading=false; error=null; });
    } catch(e) { if(mounted) setState(() { loading=false; error='$e'; }); }
  }
  Future<void> selectPallet(int? id) async { if(id==null)return; setState(()=>selectedPalletId=id); await load(); }
  Future<void> post(String path, Map<String,dynamic> body) async {
    final r=await http.post(Uri.parse('$apiBaseUrl/$path'),headers:apiHeaders,body:jsonEncode(body)).timeout(const Duration(seconds:15));
    if(r.statusCode<200||r.statusCode>=300) throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }
  void msg(String value) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value))); }

  Future<void> addItem() async {
    if(selectedPalletId==null){msg('Pilih pallet terlebih dahulu.');return;}
    if(skus.isEmpty){msg('Master SKU masih kosong.');return;}
    int? skuId=n(skus.first,'id');
    final qty=TextEditingController(text:'1'), weight=TextEditingController(text:'0'), packs=TextEditingController(text:'0'), batch=TextEditingController();
    DateTime received=DateTime.now(), expiry=DateTime.now().add(const Duration(days:30));
    String packaging='CARTON';
    final data=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,sd)=>AlertDialog(
      title:const Text('Tambah Isi Pallet'),
      content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:skuId,isExpanded:true,decoration:const InputDecoration(labelText:'SKU'),items:skus.where((x)=>x['is_active']!=false).map((x)=>DropdownMenuItem(value:n(x,'id'),child:Text('${t(x,'sku_code')} · ${t(x,'name')}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>sd(()=>skuId=v)),
        const SizedBox(height:10),TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Jumlah awal')),
        const SizedBox(height:10),TextField(controller:weight,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Berat total (kg)')),
        const SizedBox(height:10),TextField(controller:packs,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah kemasan')),
        const SizedBox(height:10),TextField(controller:batch,decoration:const InputDecoration(labelText:'Nomor batch (opsional)')),
        const SizedBox(height:10),DropdownButtonFormField<String>(value:packaging,decoration:const InputDecoration(labelText:'Jenis kemasan'),items:const [DropdownMenuItem(value:'CARTON',child:Text('Karton')),DropdownMenuItem(value:'SACK',child:Text('Karung')),DropdownMenuItem(value:'BOX',child:Text('Box')),DropdownMenuItem(value:'OTHER',child:Text('Lainnya'))],onChanged:(v)=>sd(()=>packaging=v??'CARTON')),
        const SizedBox(height:10),Row(children:[Expanded(child:Text('Diterima: ${received.toIso8601String().substring(0,10)}')),TextButton(onPressed:()async{final v=await showDatePicker(context:ctx,initialDate:received,firstDate:DateTime(2000),lastDate:DateTime(2100));if(v!=null)sd(()=>received=v);},child:const Text('Pilih tanggal'))]),
        Row(children:[Expanded(child:Text('Kedaluwarsa: ${expiry.toIso8601String().substring(0,10)}')),TextButton(onPressed:()async{final v=await showDatePicker(context:ctx,initialDate:expiry,firstDate:DateTime(2000),lastDate:DateTime(2100));if(v!=null)sd(()=>expiry=v);},child:const Text('Pilih tanggal'))]),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'sku_id':skuId,'quantity':double.tryParse(qty.text.trim()),'weight_kg':double.tryParse(weight.text.trim()),'packaging_qty':int.tryParse(packs.text.trim()),'batch_no':batch.text.trim(),'packaging_type':packaging,'received_at':received.toUtc().toIso8601String(),'expiry_date':expiry.toIso8601String().substring(0,10)}),child:const Text('Simpan'))],
    )));
    qty.dispose();weight.dispose();packs.dispose();batch.dispose();
    if(data==null)return;
    final q=data['quantity'] as double?;final w=data['weight_kg'] as double?;final pk=data['packaging_qty'] as int?;
    if(data['sku_id']==null||q==null||q<=0||w==null||w<0||pk==null||pk<0){msg('Periksa jumlah, berat, dan jumlah kemasan.');return;}
    try { await post('pallet-items',{'pallet_id':selectedPalletId,...data}); await load();msg('Isi pallet berhasil ditambahkan.'); } catch(e){msg('Gagal menambahkan isi pallet: $e');}
  }
  Future<void> outbound(Map<String,dynamic> item) async {
    final qty=TextEditingController();final weight=TextEditingController();final note=TextEditingController();
    final data=await showDialog<Map<String,dynamic>>(context:context,builder:(ctx)=>AlertDialog(title:Text('Barang Keluar · ${t(item,'sku_code')}'),content:SizedBox(width:400,child:Column(mainAxisSize:MainAxisSize.min,children:[Text('Stok tersedia: ${item['quantity']} ${t(item,'unit')} · ${item['weight_kg']} kg'),const SizedBox(height:12),TextField(controller:qty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Jumlah keluar')),const SizedBox(height:10),TextField(controller:weight,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Berat keluar (kg)')),const SizedBox(height:10),TextField(controller:note,decoration:const InputDecoration(labelText:'Catatan (opsional)'))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,{'pallet_item_id':n(item,'id'),'quantity':double.tryParse(qty.text.trim()),'weight_kg':double.tryParse(weight.text.trim()),'notes':note.text.trim()}),child:const Text('Konfirmasi keluar'))]));
    qty.dispose();weight.dispose();note.dispose();if(data==null)return;
    final q=data['quantity'] as double?;final w=data['weight_kg'] as double?;
    if(q==null||q<=0||w==null||w<0){msg('Jumlah keluar harus lebih dari 0 dan berat tidak boleh negatif.');return;}
    try { await post('pallet-item-outbound',data); await load();msg('Barang keluar berhasil dicatat.'); } catch(e){msg('Barang keluar gagal: $e');}
  }
  @override void initState(){super.initState();load(initial:true);}
  @override Widget build(BuildContext context){
    final totalQty=items.fold<double>(0,(a,x)=>a+d(x,'quantity'));final totalWeight=items.fold<double>(0,(a,x)=>a+d(x,'weight_kg'));
    return Scaffold(appBar:AppBar(title:const Text('Pallet Content'),actions:[IconButton(tooltip:'Muat ulang',onPressed:load,icon:const Icon(Icons.refresh))]),drawer:const PasataNavigationDrawer(activeMenu:'Pallet Content'),floatingActionButton:FloatingActionButton.extended(onPressed:addItem,icon:const Icon(Icons.add),label:const Text('Tambah Isi')),
      body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[Text('Gagal memuat data: $error'),const SizedBox(height:12),FilledButton(onPressed:load,child:const Text('Coba lagi'))]))):Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        DropdownButtonFormField<int>(value:selectedPalletId,isExpanded:true,decoration:const InputDecoration(labelText:'Pilih pallet'),items:pallets.where((p)=>t(p,'status')!='INACTIVE').map((p)=>DropdownMenuItem(value:n(p,'id'),child:Text('${t(p,'pallet_code')} · ${t(p,'status')}'))).toList(),onChanged:selectPallet),const SizedBox(height:12),
        Wrap(spacing:12,runSpacing:8,children:[Chip(label:Text('Item aktif: ${items.length}')),Chip(label:Text('Total jumlah: ${totalQty.toStringAsFixed(2)}')),Chip(label:Text('Total berat: ${totalWeight.toStringAsFixed(2)} kg'))]),const SizedBox(height:8),
        Expanded(child:items.isEmpty?const Center(child:Text('Belum ada isi pada pallet ini.')):ListView.builder(itemCount:items.length,itemBuilder:(ctx,i){final x=items[i];return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text('${t(x,'sku_code')} · ${t(x,'sku_name')}',style:const TextStyle(fontWeight:FontWeight.bold))),Text(t(x,'status'))]),const SizedBox(height:6),Text('Stok awal: ${x['initial_quantity']??x['quantity']} ${t(x,'unit')} · Tersisa: ${x['quantity']} ${t(x,'unit')}'),Text('Berat awal: ${x['initial_weight_kg']??x['weight_kg']} kg · Berat tersisa: ${x['weight_kg']} kg'),Text('Kemasan: ${t(x,'packaging_type')} (${x['packaging_qty']??0}) · Batch: ${t(x,'batch_no')}'),Text('Diterima: ${t(x,'received_at')} · Kedaluwarsa: ${t(x,'expiry_date')}'),Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>outbound(x),icon:const Icon(Icons.output),label:const Text('Barang keluar sebagian')))])));})),
      ])));
  }
}

class MasterPalletPage extends StatefulWidget {
  const MasterPalletPage({super.key});
  @override
  State<MasterPalletPage> createState() => _MasterPalletPageState();
}

class _MasterPalletPageState extends State<MasterPalletPage> {
  List<Map<String, dynamic>> _pallets = [];
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';
  String _query = '';
  final _search = TextEditingController();

  bool get _canManage {
    final role = '${currentUser?['role_code'] ?? ''}'.toUpperCase();
    return {'SUPER_ADMIN', 'WAREHOUSE_ADMIN', 'WAREHOUSE_OPERATOR'}.contains(role);
  }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  int _num(Map<String, dynamic> m, String k, [int fallback = 0]) {
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }
  String _str(Map<String, dynamic> m, String k, [String fallback = '-']) {
    final v = m[k];
    return v == null || '$v'.trim().isEmpty ? fallback : '$v';
  }
  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final r = await http.get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    final decoded = jsonDecode(r.body);
    if (decoded is! List) throw Exception('Respons $path tidak valid');
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([_getList('pallets'), _getList('warehouses')]);
      if (!mounted) return;
      setState(() { _pallets = results[0]; _warehouses = results[1]; _loading = false; });
    } catch (e) { if (mounted) setState(() { _error = '$e'; _loading = false; }); }
  }
  Future<void> _add() async {
    if (!_canManage) { _message('Role akun tidak memiliki akses pengelolaan pallet.'); return; }
    if (_warehouses.isEmpty) { _message('Tambahkan data gudang terlebih dahulu.'); return; }
    final code = TextEditingController(text: _nextCode());
    int? warehouseId = _num(_warehouses.first, 'id');
    String condition = 'GOOD';
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: const Text('Registrasi Pallet'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Kode pallet', helperText: 'Kode tetap digunakan meskipun isi pallet berganti.')),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: warehouseId, isExpanded: true, decoration: const InputDecoration(labelText: 'Gudang'),
          items: _warehouses.map((w) => DropdownMenuItem(value: _num(w, 'id'), child: Text('${_str(w, 'code')} · ${_str(w, 'name')}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setDialog(() => warehouseId = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: condition, decoration: const InputDecoration(labelText: 'Kondisi pallet'),
          items: const [DropdownMenuItem(value: 'GOOD', child: Text('Baik')), DropdownMenuItem(value: 'NEEDS_REPAIR', child: Text('Perlu perbaikan')), DropdownMenuItem(value: 'DAMAGED', child: Text('Rusak'))],
          onChanged: (v) { if (v != null) setDialog(() => condition = v); }),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Text('Status awal: UNPLACED (belum ditempatkan).', style: TextStyle(fontSize: 12))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, {'pallet_code': code.text.trim(), 'warehouse_id': warehouseId, 'condition': condition}), child: const Text('Simpan'))],
    )));
    code.dispose();
    if (data == null) return;
    if ((data['pallet_code'] as String).isEmpty || data['warehouse_id'] == null) { _message('Kode pallet dan gudang wajib diisi.'); return; }
    try {
      final r = await http.post(Uri.parse('$apiBaseUrl/pallets'), headers: apiHeaders, body: jsonEncode(data)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 201) throw Exception('HTTP ${r.statusCode}: ${r.body}');
      await _load(); _message('Pallet berhasil didaftarkan.');
    } catch (e) { _message('Gagal mendaftarkan pallet: $e'); }
  }
  String _nextCode() {
    var max = 0;
    final re = RegExp(r'^P-(\d+)$', caseSensitive: false);
    for (final p in _pallets) { final m = re.firstMatch(_str(p, 'pallet_code', '')); if (m != null) max = max > int.parse(m.group(1)!) ? max : int.parse(m.group(1)!); }
    return 'P-${(max + 1).toString().padLeft(3, '0')}';
  }
  Future<void> _edit(Map<String, dynamic> pallet) async {
    if (!_canManage) { _message('Role akun tidak memiliki akses pengelolaan pallet.'); return; }
    String condition = _str(pallet, 'condition', 'GOOD');
    final hasLocation = pallet['current_slot_id'] != null;
    String status = _str(pallet, 'status', 'UNPLACED');
    final allowedStatuses = hasLocation ? <String>['STORED'] : <String>['EMPTY', 'UNPLACED', 'INACTIVE'];
    if (!allowedStatuses.contains(status)) status = allowedStatuses.first;
    final data = await showDialog<Map<String, String>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text('Ubah ${_str(pallet, 'pallet_code')}'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: condition, decoration: const InputDecoration(labelText: 'Kondisi'), items: const [DropdownMenuItem(value: 'GOOD', child: Text('Baik')), DropdownMenuItem(value: 'NEEDS_REPAIR', child: Text('Perlu perbaikan')), DropdownMenuItem(value: 'DAMAGED', child: Text('Rusak'))], onChanged: (v) { if (v != null) setDialog(() => condition = v); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: status, decoration: const InputDecoration(labelText: 'Status'), items: allowedStatuses.map((v) => DropdownMenuItem(value: v, child: Text(_statusLabel(v)))).toList(), onChanged: (v) { if (v != null) setDialog(() => status = v); }),
        const SizedBox(height: 8),
        const Text('Status STORED/MOVING dikelola melalui proses penempatan dan perpindahan pallet.', style: TextStyle(fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')), FilledButton(onPressed: () => Navigator.pop(ctx, {'condition': condition, 'status': status}), child: const Text('Simpan'))],
    )));
    if (data == null) return;
    try {
      final id = _num(pallet, 'id');
      final r = await http.put(Uri.parse('$apiBaseUrl/pallets/$id'), headers: apiHeaders, body: jsonEncode(data)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}: ${r.body}');
      await _load(); _message('Data pallet diperbarui.');
    } catch (e) { _message('Gagal memperbarui pallet: $e'); }
  }
  String _statusLabel(String s) => switch (s) { 'EMPTY' => 'Kosong', 'UNPLACED' => 'Belum ditempatkan', 'STORED' => 'Tersimpan', 'MOVING' => 'Dalam perpindahan', 'INACTIVE' => 'Nonaktif', _ => s };
  String _conditionLabel(String s) => switch (s) { 'GOOD' => 'Baik', 'NEEDS_REPAIR' => 'Perlu perbaikan', 'DAMAGED' => 'Rusak', _ => s };
  void _message(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  @override
  Widget build(BuildContext context) {
    final filtered = _pallets.where((p) {
      final matchesStatus = _filter == 'ALL' || _str(p, 'status') == _filter;
      final q = _query.toLowerCase();
      final matchesQuery = q.isEmpty || _str(p, 'pallet_code', '').toLowerCase().contains(q) || _str(p, 'rack_code', '').toLowerCase().contains(q) || _str(p, 'slot_code', '').toLowerCase().contains(q);
      return matchesStatus && matchesQuery;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Master Pallet'), actions: [IconButton(tooltip: 'Buka layout gudang', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LayoutPalletPage())), icon: const Icon(Icons.grid_view_rounded)), IconButton(tooltip: 'Muat ulang', onPressed: _load, icon: const Icon(Icons.refresh))]),
      drawer: const PasataNavigationDrawer(activeMenu: 'Master Pallet'),
      floatingActionButton: _canManage ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Registrasi Pallet')) : null,
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? _ErrorView(message: _error!, onRetry: _load) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 16, runSpacing: 12, children: [
          _masterStat('Total pallet', '${_pallets.length}', Icons.view_module_outlined),
          _masterStat('Tersimpan', '${_pallets.where((p) => _str(p, 'status') == 'STORED').length}', Icons.inventory_2_outlined),
          _masterStat('Belum ditempatkan', '${_pallets.where((p) => _str(p, 'status') == 'UNPLACED').length}', Icons.move_to_inbox_outlined),
          _masterStat('Perlu perhatian', '${_pallets.where((p) => ['NEEDS_REPAIR','DAMAGED'].contains(_str(p, 'condition'))).length}', Icons.build_outlined),
        ]))),
        const SizedBox(height: 12),
        TextField(controller: _search, decoration: InputDecoration(labelText: 'Cari kode pallet atau lokasi', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); setState(() => _query = ''); }),), onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _filter, decoration: const InputDecoration(labelText: 'Filter status'), items: const [DropdownMenuItem(value: 'ALL', child: Text('Semua status')), DropdownMenuItem(value: 'EMPTY', child: Text('Kosong')), DropdownMenuItem(value: 'UNPLACED', child: Text('Belum ditempatkan')), DropdownMenuItem(value: 'STORED', child: Text('Tersimpan')), DropdownMenuItem(value: 'MOVING', child: Text('Dalam perpindahan')), DropdownMenuItem(value: 'INACTIVE', child: Text('Nonaktif'))], onChanged: (v) => setState(() => _filter = v ?? 'ALL')),
        const SizedBox(height: 12),
        if (filtered.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada data pallet yang cocok.')))),
        ...filtered.map((p) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          leading: CircleAvatar(backgroundColor: const Color(0xFFE3F1EB), child: const Icon(Icons.view_module_outlined, color: Color(0xFF176B52))),
          title: Text(_str(p, 'pallet_code', 'Tanpa kode'), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text('Status: ${_statusLabel(_str(p, 'status'))}\nKondisi: ${_conditionLabel(_str(p, 'condition'))}\nLokasi: ${_str(p, 'rack_code', 'Belum ada rak')} / ${_str(p, 'slot_code', 'Belum ada slot')}\nDibuat: ${_str(p, 'created_at')}')),
          isThreeLine: true, trailing: _canManage ? IconButton(tooltip: 'Ubah data', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(p)) : null,
        ))),
        const SizedBox(height: 80),
      ])),
    );
  }
  Widget _masterStat(String label, String value, IconData icon) => SizedBox(width: 190, child: Row(children: [Icon(icon, color: const Color(0xFF176B52), size: 28), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: TextStyle(color: Colors.grey.shade700))]))]));
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
  final TextEditingController _layoutSearchController = TextEditingController();
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
        .get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
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
          headers: apiHeaders,
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
          headers: apiHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
  }

  Future<void> _delete(String path) async {
    final r = await http
        .delete(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
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
    final capacity = TextEditingController(text: '4');
    final levels = TextEditingController(text: '4');
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
                    labelText: 'Jumlah slot pallet per level (maks. 4)',
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ||
                          int.parse(v!) < 1 ||
                          int.parse(v) > 4
                      ? 'Jumlah level harus 1 sampai 4'
                      : null,
                ),
                TextFormField(
                  controller: levels,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Jumlah level'),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ||
                          int.parse(v!) < 1 ||
                          int.parse(v) > 4
                      ? 'Masukkan 1 sampai 4 slot'
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
            onPressed: () async {
              final enteredCapacity = int.tryParse(capacity.text.trim());
              if (enteredCapacity != null && enteredCapacity > 4) {
                await showDialog<void>(
                  context: ctx,
                  builder: (alertCtx) => AlertDialog(
                    title: const Text('Kapasitas melebihi batas'),
                    content: const Text(
                      'Maksimal 4 pallet dalam satu level. Ubah jumlah slot per level menjadi 4 atau kurang.',
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(alertCtx),
                        child: const Text('Mengerti'),
                      ),
                    ],
                  ),
                );
                return;
              }
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, {
                'code': code.text.trim(),
                'name': name.text.trim(),
                'capacity_pallet': enteredCapacity,
                'level_count': int.parse(levels.text),
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

  Future<void> _manageRackLayout(Map<String, dynamic> rack) async {
    final rackId = _num(rack, 'id');
    Future<void> refreshDialog(StateSetter setDialog) async => setDialog(() {});
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Kelola level & slot · ${_str(rack, 'code')}'),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _list('rack-levels?rack_id=$rackId'),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError)
                  return Text('Gagal memuat level: ${snapshot.error}');
                final levels = [...?snapshot.data]
                  ..sort(
                    (a, b) => _num(
                      a,
                      'level_number',
                    ).compareTo(_num(b, 'level_number')),
                  );
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          final next = levels.isEmpty
                              ? 1
                              : levels
                                        .map((e) => _num(e, 'level_number'))
                                        .reduce((a, b) => a > b ? a : b) +
                                    1;
                          final countCtrl = TextEditingController(text: '4');
                          final maxWeightCtrl = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dctx) => AlertDialog(
                              title: Text('Tambah Level $next'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    controller: countCtrl,
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Jumlah slot (maks. 4)'),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: maxWeightCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'Batas berat level (kg, opsional)'),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dctx, false),
                                  child: const Text('Batal'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dctx, true),
                                  child: const Text('Tambah'),
                                ),
                              ],
                            ),
                          );
                          final count = int.tryParse(countCtrl.text) ?? 0;
                          if (ok != true) return;
                          if (count < 1 || count > 4) {
                            _message('Jumlah slot level harus 1 sampai 4.');
                            return;
                          }
                          final maxWeightText = maxWeightCtrl.text.trim().replaceAll(',', '.');
                          final maxWeight = maxWeightText.isEmpty ? null : double.tryParse(maxWeightText);
                          if (maxWeightText.isNotEmpty && (maxWeight == null || maxWeight < 0)) {
                            _message('Batas berat harus berupa angka 0 atau lebih.');
                            return;
                          }
                          try {
                            await _post('rack-levels', {
                              'rack_id': rackId,
                              'level_number': next,
                              'slot_count': count,
                              'code': 'L$next',
                              if (maxWeight != null) 'max_weight_kg': maxWeight,
                            });
                            setDialog(() {});
                            await _selectArea(_selectedAreaId);
                            _message('Level $next ditambahkan.');
                          } catch (e) {
                            _message('Gagal menambah level: $e');
                          }
                        },
                        icon: const Icon(Icons.layers_outlined),
                        label: const Text('Tambah level'),
                      ),
                      const SizedBox(height: 12),
                      if (levels.isEmpty)
                        const Text('Rak ini belum memiliki level.'),
                      for (final level in levels)
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _list(
                            'rack-slots?rack_level_id=${_num(level, 'id')}',
                          ),
                          builder: (ctx, slotSnapshot) {
                            final slots =
                                slotSnapshot.data ?? <Map<String, dynamic>>[];
                            final levelId = _num(level, 'id');
                            final levelNo = _num(level, 'level_number');
                            return Card(
                              margin: const EdgeInsets.only(top: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Level $levelNo · ${slotSnapshot.connectionState == ConnectionState.done ? slots.length : '…'} slot',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Atur batas berat level',
                                          icon: const Icon(Icons.scale_outlined),
                                          onPressed: () async {
                                            final weightCtrl = TextEditingController(text: _str(level, 'max_weight_kg', ''));
                                            var applyCapacityToSlots = true;
                                            final save = await showDialog<bool>(
                                              context: ctx,
                                              builder: (dctx) => StatefulBuilder(
                                                builder: (dctx, setCapacityDialogState) => AlertDialog(
                                                  title: Text('Batas berat Level $levelNo'),
                                                  content: SizedBox(
                                                    width: 380,
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        TextField(
                                                          controller: weightCtrl,
                                                          autofocus: true,
                                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                          decoration: const InputDecoration(labelText: 'Maksimum berat level (kg)', hintText: 'Contoh: 50'),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        CheckboxListTile(
                                                          contentPadding: EdgeInsets.zero,
                                                          value: applyCapacityToSlots,
                                                          onChanged: (value) => setCapacityDialogState(() => applyCapacityToSlots = value ?? false),
                                                          title: const Text('Terapkan juga sebagai kapasitas awal semua slot di level ini'),
                                                          subtitle: const Text('Direkomendasikan agar pallet bisa ditempatkan. Kapasitas slot bisa disesuaikan satu per satu setelahnya.'),
                                                          controlAffinity: ListTileControlAffinity.leading,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Batal')),
                                                    FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Simpan')),
                                                  ],
                                                ),
                                              ),
                                            );
                                            if (save != true) return;
                                            final weight = double.tryParse(weightCtrl.text.trim().replaceAll(',', '.'));
                                            if (weight == null || weight <= 0) { _message('Masukkan batas berat lebih dari 0 kg.'); return; }
                                            try {
                                              await _put('rack-levels/$levelId', {
                                                'max_weight_kg': weight,
                                                'apply_to_slots': applyCapacityToSlots,
                                              });
                                              await _selectArea(_selectedAreaId);
                                              setDialog(() {});
                                              _message(applyCapacityToSlots
                                                  ? 'Batas level dan kapasitas ${slots.length} slot diperbarui. Kamu bisa mencoba memindahkan pallet sekarang.'
                                                  : 'Batas berat level diperbarui. Atur kapasitas slot tujuan sebelum memindahkan pallet.');
                                            } catch (e) { _message('Gagal menyimpan batas berat level/slot: $e'); }
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Hapus level kosong',
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                                  context: ctx,
                                                  builder: (dctx) => AlertDialog(
                                                    title: Text(
                                                      'Hapus Level $levelNo?',
                                                    ),
                                                    content: const Text(
                                                      'Level hanya bisa dihapus jika tidak ada pallet di dalamnya.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dctx,
                                                              false,
                                                            ),
                                                        child: const Text(
                                                          'Batal',
                                                        ),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              dctx,
                                                              true,
                                                            ),
                                                        child: const Text(
                                                          'Hapus',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                            if (confirm != true) return;
                                            try {
                                              await _delete(
                                                'rack-levels/$levelId',
                                              );
                                              await _selectArea(
                                                _selectedAreaId,
                                              );
                                              setDialog(() {});
                                              _message('Level dihapus.');
                                            } catch (e) {
                                              _message(
                                                'Gagal menghapus level: $e',
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final slot in slots.take(4))
                                          PopupMenuButton<String>(
                                            tooltip: 'Atur slot',
                                            onSelected: (action) async {
                                              final slotId = _num(slot, 'id');
                                              if (action == 'capacity') {
                                                final capCtrl = TextEditingController(text: _str(slot, 'capacity_kg', ''));
                                                final save = await showDialog<bool>(
                                                  context: ctx,
                                                  builder: (dctx) => AlertDialog(
                                                    title: Text('Kapasitas Slot S${_num(slot, 'slot_number')}'),
                                                    content: TextField(
                                                      controller: capCtrl,
                                                      autofocus: true,
                                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                      decoration: const InputDecoration(labelText: 'Batas berat slot (kg)', hintText: 'Contoh: 100'),
                                                    ),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Batal')),
                                                      FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Simpan')),
                                                    ],
                                                  ),
                                                );
                                                if (save != true) return;
                                                final cap = double.tryParse(capCtrl.text.trim().replaceAll(',', '.'));
                                                if (cap == null || cap < 0) { _message('Kapasitas harus angka 0 atau lebih.'); return; }
                                                try {
                                                  await _put('rack-slots/$slotId', {'capacity_kg': cap});
                                                  await _selectArea(_selectedAreaId);
                                                  setDialog(() {});
                                                  _message('Kapasitas slot diperbarui.');
                                                } catch (e) { _message('Gagal mengubah kapasitas: $e'); }
                                              } else if (action == 'delete') {
                                                try {
                                                  await _delete('rack-slots/$slotId');
                                                  await _selectArea(_selectedAreaId);
                                                  setDialog(() {});
                                                  _message('Slot dihapus.');
                                                } catch (e) { _message('Slot tidak dapat dihapus: $e'); }
                                              } else {
                                                try {
                                                  await _put('rack-slots/$slotId', {'status': action});
                                                  await _selectArea(_selectedAreaId);
                                                  setDialog(() {});
                                                  _message('Status slot diperbarui.');
                                                } catch (e) { _message('Gagal mengubah status slot: $e'); }
                                              }
                                            },
                                            itemBuilder: (menuCtx) => [
                                              PopupMenuItem<String>(value: 'capacity', child: Text('Atur kapasitas: ${_str(slot, 'capacity_kg', 'belum diatur')} kg')),
                                              if (_str(slot, 'pallet_code').isEmpty && _str(slot, 'status', 'EMPTY') != 'OCCUPIED') ...[
                                                const PopupMenuItem<String>(value: 'EMPTY', child: Text('Tandai kosong')),
                                                const PopupMenuItem<String>(value: 'QUARANTINE', child: Text('Karantina')),
                                                const PopupMenuItem<String>(value: 'MAINTENANCE', child: Text('Pemeliharaan')),
                                                const PopupMenuItem<String>(value: 'UNAVAILABLE', child: Text('Tidak tersedia')),
                                              ],
                                              if (_str(slot, 'pallet_code').isEmpty && _str(slot, 'status', 'EMPTY') == 'EMPTY') ...[
                                                const PopupMenuDivider(),
                                                const PopupMenuItem<String>(value: 'delete', child: Text('Hapus slot')),
                                              ],
                                            ],
                                            child: Chip(
                                              avatar: const Icon(Icons.tune, size: 16),
                                              label: Text(
                                                'S${_num(slot, 'slot_number')} · ${_str(slot, 'pallet_code').isNotEmpty ? _str(slot, 'pallet_code') : _str(slot, 'status', 'EMPTY')} · ${_str(slot, 'capacity_kg', '—')} kg',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (slots.length > 4) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'PERLU DIBERESKAN: ${slots.length - 4} slot lama di luar batas 4. Slot aktif per level maksimal 4. Hapus slot lama yang kosong; slot berisi pallet harus dipindahkan dahulu.',
                                        style: const TextStyle(
                                          color: Colors.deepOrange,
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final slot in slots.where(
                                            (s) => _num(s, 'slot_number') > 4,
                                          ))
                                            Chip(
                                              label: Text(
                                                'Slot lama S${_num(slot, 'slot_number')} · ${_str(slot, 'pallet_code').isNotEmpty ? _str(slot, 'pallet_code') : _str(slot, 'status', 'EMPTY')}',
                                              ),
                                              deleteIcon: const Icon(
                                                Icons.close,
                                                size: 16,
                                              ),
                                              onDeleted: () async {
                                                try {
                                                  await _delete(
                                                    'rack-slots/${_num(slot, 'id')}',
                                                  );
                                                  await _selectArea(
                                                    _selectedAreaId,
                                                  );
                                                  setDialog(() {});
                                                  _message(
                                                    'Slot lama dihapus.',
                                                  );
                                                } catch (e) {
                                                  _message(
                                                    'Slot lama tidak dapat dihapus: $e',
                                                  );
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: slots.length >= 4
                                                ? null
                                                : () async {
                                                    try {
                                                      await _post(
                                                        'rack-slots',
                                                        {
                                                          'rack_level_id':
                                                              levelId,
                                                          'slot_count': 1,
                                                        },
                                                      );
                                                      await _selectArea(
                                                        _selectedAreaId,
                                                      );
                                                      setDialog(() {});
                                                      _message(
                                                        'Slot ditambahkan.',
                                                      );
                                                    } catch (e) {
                                                      _message(
                                                        'Gagal menambah slot: $e',
                                                      );
                                                    }
                                                  },
                                            icon: const Icon(Icons.add),
                                            label: const Text('Tambah 1 slot'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final emptySlots = slots
                                                  .where(
                                                    (s) =>
                                                        _str(
                                                              s,
                                                              'status',
                                                              'EMPTY',
                                                            ) ==
                                                            'EMPTY' &&
                                                        _num(s, 'pallet_id') ==
                                                            0 &&
                                                        _str(
                                                          s,
                                                          'pallet_code',
                                                        ).isEmpty,
                                                  )
                                                  .toList();
                                              if (emptySlots.isEmpty) {
                                                _message(
                                                  'Tidak ada slot kosong yang bisa dinonaktifkan.',
                                                );
                                                return;
                                              }
                                              try {
                                                await _put(
                                                  'rack-slots/${_num(emptySlots.last, 'id')}',
                                                  {'status': 'UNAVAILABLE'},
                                                );
                                                await _selectArea(
                                                  _selectedAreaId,
                                                );
                                                setDialog(() {});
                                                _message(
                                                  'Slot terakhir ditandai tidak tersedia.',
                                                );
                                              } catch (e) {
                                                _message(
                                                  'Gagal mengubah slot: $e',
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.block),
                                            label: const Text(
                                              'Nonaktifkan slot kosong',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
    await _selectArea(_selectedAreaId);
  }

  Future<void> _editRack(Map<String, dynamic> rack) async {
    final id = _num(rack, 'id');
    final code = TextEditingController(text: _str(rack, 'code'));
    final name = TextEditingController(text: _str(rack, 'name'));
    final cap = TextEditingController(
      text:
          '${_num(rack, 'capacity_pallet') > 4 ? 4 : (_num(rack, 'capacity_pallet') < 1 ? 4 : _num(rack, 'capacity_pallet'))}',
    );
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
              decoration: const InputDecoration(
                labelText: 'Slot per level (maks. 4)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final n = int.tryParse(cap.text.trim());
              if (n != null && n > 4) {
                await showDialog<void>(
                  context: ctx,
                  builder: (alertCtx) => AlertDialog(
                    title: const Text('Kapasitas melebihi batas'),
                    content: const Text(
                      'Maksimal 4 pallet dalam satu level. Rak tidak dapat disimpan dengan kapasitas lebih dari 4 slot per level.',
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(alertCtx),
                        child: const Text('Mengerti'),
                      ),
                    ],
                  ),
                );
                return;
              }
              if (n == null || n < 1) {
                await showDialog<void>(
                  context: ctx,
                  builder: (alertCtx) => AlertDialog(
                    title: const Text('Kapasitas tidak valid'),
                    content: const Text('Masukkan angka dari 1 sampai 4.'),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(alertCtx),
                        child: const Text('Mengerti'),
                      ),
                    ],
                  ),
                );
                return;
              }
              Navigator.pop(ctx, {
                'code': code.text.trim(),
                'name': name.text.trim(),
                'capacity_pallet': n,
                'status': _str(rack, 'status', 'ACTIVE'),
              });
            },
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
        'capacity_pallet':
            (_num(rack, 'capacity_pallet', 4) > 4 ||
                _num(rack, 'capacity_pallet', 4) < 1)
            ? 4
            : _num(rack, 'capacity_pallet', 4),
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

  Future<void> _addPalletItem() async {
    final activePallets = _pallets
        .where((p) => _str(p, 'status') != 'INACTIVE')
        .toList();
    if (activePallets.isEmpty) {
      _message('Buat pallet terlebih dahulu.');
      return;
    }
    List<Map<String, dynamic>> skus;
    try {
      skus = await _list('skus');
    } catch (e) {
      _message('Gagal memuat SKU: $e');
      return;
    }
    if (skus.isEmpty) {
      _message(
        'Belum ada SKU aktif. Tambahkan master barang/SKU terlebih dahulu.',
      );
      return;
    }
    int? palletId = _num(activePallets.first, 'id');
    int? skuId = _num(skus.first, 'id');
    final qty = TextEditingController(text: '1');
    final weight = TextEditingController(text: '0');
    final batch = TextEditingController();
    String packaging = 'CARTON';
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Isi Pallet & Berat'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: palletId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Pallet'),
                    items: activePallets
                        .map(
                          (p) => DropdownMenuItem(
                            value: _num(p, 'id'),
                            child: Text(_str(p, 'pallet_code')),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialog(() => palletId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: skuId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Barang / SKU',
                    ),
                    items: skus
                        .map(
                          (sku) => DropdownMenuItem(
                            value: _num(sku, 'id'),
                            child: Text(
                              '${_str(sku, 'sku_code')} · ${_str(sku, 'name')}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialog(() => skuId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Jumlah barang',
                      hintText: 'Contoh: 12',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Berat total isi (kg)',
                      hintText: 'Contoh: 125.5',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: batch,
                    decoration: const InputDecoration(
                      labelText: 'Nomor batch (opsional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: packaging,
                    decoration: const InputDecoration(
                      labelText: 'Jenis kemasan',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CARTON', child: Text('Karton')),
                      DropdownMenuItem(value: 'SACK', child: Text('Karung')),
                      DropdownMenuItem(value: 'BOX', child: Text('Box')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Lainnya')),
                    ],
                    onChanged: (v) =>
                        setDialog(() => packaging = v ?? 'CARTON'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Berat yang dimasukkan adalah total berat isi untuk item ini, bukan berat per unit.',
                    style: TextStyle(fontSize: 12),
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
              onPressed: () => Navigator.pop(ctx, {
                'pallet_id': palletId,
                'sku_id': skuId,
                'quantity': double.tryParse(qty.text.trim()),
                'weight_kg': double.tryParse(weight.text.trim()),
                'batch_no': batch.text.trim(),
                'packaging_type': packaging,
              }),
              child: const Text('Simpan isi pallet'),
            ),
          ],
        ),
      ),
    );
    if (data == null) return;
    final q = data['quantity'] as double?;
    final w = data['weight_kg'] as double?;
    if (data['pallet_id'] == null ||
        data['sku_id'] == null ||
        q == null ||
        q <= 0 ||
        w == null ||
        w < 0) {
      _message('Jumlah harus lebih dari 0 dan berat tidak boleh negatif.');
      return;
    }
    try {
      await _post('pallet-items', data);
      await _loadAreas();
      _message('Isi pallet dan berat berhasil disimpan.');
    } catch (e) {
      _message('Gagal menyimpan isi pallet: $e');
    }
  }

  Future<void> _searchWarehouse(String rawQuery) async {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      _message('Masukkan kode pallet, kode SKU, atau nama barang.');
      return;
    }
    try {
      final skus = await _list('skus');
      final allItems = <Map<String, dynamic>>[];
      for (final pallet in _pallets) {
        final id = _num(pallet, 'id');
        if (id <= 0) continue;
        try {
          final items = await _list('pallet-items?pallet_id=$id');
          for (final item in items) {
            allItems.add({
              ...item,
              '_search_pallet_id': id,
              '_search_pallet_code': _str(pallet, 'pallet_code'),
            });
          }
        } catch (_) {
          /* Item pallet yang gagal dibaca tidak menggagalkan pencarian lainnya. */
        }
      }
      final matchingPalletIds = <int>{};
      for (final pallet in _pallets) {
        if (_str(pallet, 'pallet_code').toLowerCase().contains(query))
          matchingPalletIds.add(_num(pallet, 'id'));
      }
      final matchingSkuIds = <int>{};
      for (final sku in skus) {
        if (_str(sku, 'sku_code').toLowerCase().contains(query) ||
            _str(sku, 'name').toLowerCase().contains(query))
          matchingSkuIds.add(_num(sku, 'id'));
      }
      for (final item in allItems) {
        if (matchingSkuIds.contains(_num(item, 'sku_id')))
          matchingPalletIds.add(_num(item, '_search_pallet_id'));
      }
      final results = <Map<String, dynamic>>[];
      for (final rack in _racks) {
        final levels = await _list('rack-levels?rack_id=${_num(rack, 'id')}');
        for (final level in levels) {
          final slots = await _list(
            'rack-slots?rack_level_id=${_num(level, 'id')}',
          );
          for (final slot in slots) {
            final palletId = _num(slot, 'pallet_id');
            if (palletId > 0 && matchingPalletIds.contains(palletId)) {
              final pallet = _pallets
                  .where((p) => _num(p, 'id') == palletId)
                  .toList();
              final itemNames = allItems
                  .where(
                    (i) =>
                        _num(i, '_search_pallet_id') == palletId &&
                        matchingSkuIds.contains(_num(i, 'sku_id')),
                  )
                  .map((i) => '${_str(i, 'sku_code')} · ${_str(i, 'sku_name')}')
                  .toSet()
                  .join(', ');
              results.add({
                'pallet_id': palletId,
                'pallet_code': pallet.isEmpty
                    ? _str(slot, 'pallet_code')
                    : _str(pallet.first, 'pallet_code'),
                'rack': _str(rack, 'code'),
                'rack_id': _num(rack, 'id'),
                'level': _num(level, 'level_number'),
                'slot': _num(slot, 'slot_number'),
                'sku': itemNames,
              });
            }
          }
        }
      }
      for (final pallet in _pallets) {
        final id = _num(pallet, 'id');
        if (matchingPalletIds.contains(id) &&
            !results.any((r) => _num(r, 'pallet_id') == id)) {
          final itemNames = allItems
              .where(
                (i) =>
                    _num(i, '_search_pallet_id') == id &&
                    matchingSkuIds.contains(_num(i, 'sku_id')),
              )
              .map((i) => '${_str(i, 'sku_code')} · ${_str(i, 'sku_name')}')
              .toSet()
              .join(', ');
          results.add({
            'pallet_id': id,
            'pallet_code': _str(pallet, 'pallet_code'),
            'rack': 'Belum ditempatkan',
            'rack_id': 0,
            'level': 0,
            'slot': 0,
            'sku': itemNames,
          });
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Hasil pencarian (${results.length})'),
          content: SizedBox(
            width: 520,
            child: results.isEmpty
                ? const Text(
                    'Tidak ditemukan pallet atau barang yang cocok di area terpilih.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final result = results[index];
                      final placed = _num(result, 'rack_id') > 0;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(_str(result, 'pallet_code')),
                        subtitle: Text(
                          placed
                              ? '${_str(result, 'rack')} · Level ${_num(result, 'level')} · Slot S${_num(result, 'slot')}${_str(result, 'sku').isNotEmpty ? '\n${_str(result, 'sku')}' : ''}'
                              : 'Belum ditempatkan${_str(result, 'sku').isNotEmpty ? '\n${_str(result, 'sku')}' : ''}',
                        ),
                        isThreeLine: _str(result, 'sku').isNotEmpty,
                        onTap: !placed
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(
                                  () => _selectedLevel = _num(result, 'level'),
                                );
                                _message(
                                  'Lokasi ${_str(result, 'rack')} · Level ${_num(result, 'level')} · Slot S${_num(result, 'slot')}',
                                );
                              },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('Pencarian gagal: $e');
    }
  }

  Future<void> _movePallet(int palletId, int slotId) async {
    String palletCode = 'Pallet #$palletId';
    final palletMatches = _pallets
        .where((p) => _num(p, 'id') == palletId)
        .toList();
    if (palletMatches.isNotEmpty) {
      palletCode = _str(palletMatches.first, 'pallet_code', palletCode);
    }

    String fromLocation = 'lokasi saat ini';
    String toLocation = 'slot tujuan';
    try {
      for (final rack in _racks) {
        final rackCode = _str(rack, 'code', _str(rack, 'name', 'Rak'));
        final levels = await _list('rack-levels?rack_id=${_num(rack, 'id')}');
        for (final level in levels) {
          final levelNumber = _num(level, 'level_number');
          final slots = await _list(
            'rack-slots?rack_level_id=${_num(level, 'id')}',
          );
          for (final slot in slots) {
            final slotNumber = _num(slot, 'slot_number');
            final location =
                '$rackCode · Level $levelNumber · Slot S$slotNumber';
            if (_num(slot, 'id') == slotId) toLocation = location;
            if (_num(slot, 'pallet_id') == palletId) fromLocation = location;
          }
        }
      }
    } catch (_) {
      // Tetap tampilkan konfirmasi sederhana jika detail lokasi gagal dimuat.
    }

    if (!mounted) return;
    final confirmation = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PalletMovementConfirmDialog(
        palletCode: palletCode,
        fromLocation: fromLocation,
        toLocation: toLocation,
      ),
    );
    if (confirmation == null || confirmation['confirmed'] != true) return;
    final reason = (confirmation['reason'] as String? ?? '').trim();
    if (reason.isEmpty) {
      _message('Alasan perpindahan wajib diisi.');
      return;
    }

    try {
      await _post('pallet-move', {
        'pallet_id': palletId,
        'to_slot_id': slotId,
        'reason': reason,
      });
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
      drawer: const PasataNavigationDrawer(activeMenu: 'Master Pallet'),
      appBar: AppBar(
        title: const Text('Master Pallet · Layout Gudang'),
        leading: IconButton(
          tooltip: 'Kembali ke Master Pallet',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.grid_view_rounded),
        ),
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
                        tooltip: 'Isi pallet dan berat',
                        onPressed: _addPalletItem,
                        icon: const Icon(Icons.scale_outlined),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _layoutSearchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchWarehouse,
                    decoration: InputDecoration(
                      hintText: 'Cari kode pallet, SKU, atau nama barang',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Cari',
                        onPressed: () =>
                            _searchWarehouse(_layoutSearchController.text),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
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
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      childAspectRatio: 1.55,
                                    ),
                                itemCount: _racks.length,
                                itemBuilder: (context, index) => _RackLayoutCard(
                                  key: ValueKey(
                                    '${_num(_racks[index], 'id')}-$_selectedLevel',
                                  ),
                                  rack: _racks[index],
                                  selectedLevel: _selectedLevel,
                                  onEdit: () => _editRack(_racks[index]),
                                  onManageLayout: () =>
                                      _manageRackLayout(_racks[index]),
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

class _PalletMovementConfirmDialog extends StatefulWidget {
  const _PalletMovementConfirmDialog({
    required this.palletCode,
    required this.fromLocation,
    required this.toLocation,
  });

  final String palletCode;
  final String fromLocation;
  final String toLocation;

  @override
  State<_PalletMovementConfirmDialog> createState() =>
      _PalletMovementConfirmDialogState();
}

class _PalletMovementConfirmDialogState
    extends State<_PalletMovementConfirmDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _validationMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Konfirmasi perpindahan'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Yakin ingin memindahkan ${widget.palletCode}\ndari ${widget.fromLocation}\nke ${widget.toLocation}?',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('pallet-movement-reason'),
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan perpindahan *',
                hintText: 'Contoh: penataan ulang gudang',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_validationMessage != null) {
                  setState(() => _validationMessage = null);
                }
              },
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                _validationMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              setState(
                () => _validationMessage = 'Alasan perpindahan wajib diisi.',
              );
              return;
            }
            Navigator.pop(context, {'confirmed': true, 'reason': reason});
          },
          child: const Text('Ya, pindahkan'),
        ),
      ],
    );
  }
}

class _RackLayoutCard extends StatefulWidget {
  final Map<String, dynamic> rack;
  final int selectedLevel;
  final Future<List<Map<String, dynamic>>> Function(String) getList;
  final Future<void> Function(int, int) onMove;
  final VoidCallback onEdit;
  final VoidCallback onManageLayout;
  final Future<void> Function(String status) onStatusChange;
  const _RackLayoutCard({
    super.key,
    required this.rack,
    required this.selectedLevel,
    required this.getList,
    required this.onMove,
    required this.onEdit,
    required this.onManageLayout,
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

  Future<void> _showPalletDetail(Map<String, dynamic> slot) async {
    final palletId = _num(slot, 'pallet_id');
    if (palletId <= 0) return;
    List<Map<String, dynamic>> items = [];
    String? loadError;
    try {
      items = await widget.getList('pallet-items?pallet_id=$palletId');
    } catch (e) {
      loadError = '$e';
    }
    if (!mounted) return;
    final totalQty = items.fold<double>(0, (sum, item) {
      final v = item['quantity'];
      return sum + (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    });
    final totalWeight = items.fold<double>(0, (sum, item) {
      final v = item['weight_kg'];
      return sum + (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Detail Pallet · ${_str(slot, 'pallet_code', 'Pallet')}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rak: ${_str(widget.rack, 'code')} · Level ${widget.selectedLevel} · Slot S${_num(slot, 'slot_number')}',
                ),
                const SizedBox(height: 8),
                Text('Status: ${_str(slot, 'status', 'OCCUPIED')}'),
                const Divider(height: 24),
                if (loadError != null)
                  Text('Gagal memuat isi pallet: $loadError'),
                if (loadError == null && items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Belum ada data barang di pallet ini. Tekan tombol Isi Pallet & Berat untuk menambahkan barang.',
                    ),
                  ),
                if (items.isNotEmpty) ...[
                  const Text(
                    'Rekap barang',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...items.map(
                    (item) => Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_str(item, 'sku_name', 'Barang')} · ${_str(item, 'sku_code', 'SKU tidak tersedia')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Jumlah: ${item['quantity'] ?? 0} ${_str(item, 'unit')}',
                            ),
                            Text('Berat isi: ${item['weight_kg'] ?? 0} kg'),
                            Text(
                              'Batch: ${_str(item, 'batch_no', '-')} · Kemasan: ${_str(item, 'packaging_type', '-')}',
                            ),
                            Text('Diterima: ${_str(item, 'received_at', '-')}'),
                            if (_str(item, 'expiry_date').isNotEmpty)
                              Text('Kedaluwarsa: ${_str(item, 'expiry_date')}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  Text('Total jumlah: $totalQty'),
                  Text(
                    'Total berat isi: ${totalWeight.toStringAsFixed(2)} kg',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InboundPage(
                    palletId: palletId,
                    palletCode: _str(slot, 'pallet_code'),
                  ),
                ),
              );
            },
            child: const Text('Inbound'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OutboundPage(
                    palletId: palletId,
                    palletCode: _str(slot, 'pallet_code'),
                  ),
                ),
              );
            },
            child: const Text('Outbound'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildSlot(Map<String, dynamic> slot) {
    final slotStatus = _str(slot, 'status', 'EMPTY').toUpperCase();
    final occupied = _str(slot, 'pallet_code').isNotEmpty || slotStatus == 'OCCUPIED';
    final blocked = slotStatus == 'UNAVAILABLE' || slotStatus == 'QUARANTINE' || slotStatus == 'MAINTENANCE' || slotStatus == 'MOVING';
    final palletId = _num(slot, 'pallet_id');
    final slotId = _num(slot, 'id');
    final tileColor = slotStatus == 'QUARANTINE'
        ? const Color(0xFFFFE3C2)
        : slotStatus == 'MAINTENANCE'
            ? const Color(0xFFFFE9BD)
            : blocked
                ? const Color(0xFFE0E3E1)
                : occupied
                    ? const Color(0xFF16866C)
                    : const Color(0xFFF0F3F1);
    final tileBorder = slotStatus == 'QUARANTINE'
        ? const Color(0xFFE49A37)
        : slotStatus == 'MAINTENANCE'
            ? const Color(0xFFD6A23A)
            : blocked
                ? const Color(0xFF9CA5A0)
                : occupied
                    ? const Color(0xFF16866C)
                    : const Color(0xFFCDD5D1);
    final slotLabel = occupied && _str(slot, 'pallet_code').isNotEmpty
        ? _str(slot, 'pallet_code')
        : blocked
            ? (slotStatus == 'UNAVAILABLE' ? 'TIDAK TERSEDIA' : slotStatus == 'QUARANTINE' ? 'KARANTINA' : slotStatus == 'MOVING' ? 'SEDANG PINDAH' : 'PEMELIHARAAN')
            : 'S${_num(slot, 'slot_number')}';
    Widget tile = Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(color: tileColor, border: Border.all(color: tileBorder), borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(occupied ? Icons.inventory_2 : blocked ? (slotStatus == 'QUARANTINE' ? Icons.health_and_safety_outlined : slotStatus == 'MAINTENANCE' ? Icons.build_outlined : slotStatus == 'MOVING' ? Icons.sync : Icons.block_outlined) : Icons.add,
            size: 25, color: occupied ? Colors.white : blocked ? const Color(0xFF6B716E) : Colors.grey.shade500),
          const SizedBox(height: 3),
          Text(slotLabel, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(fontSize: occupied && _str(slot, 'pallet_code').isNotEmpty ? 8 : 10, fontWeight: FontWeight.w600,
              color: occupied ? Colors.white : Colors.grey.shade700)),
        ],
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
          message:
              '${_str(slot, 'pallet_code')} · klik untuk detail, seret untuk memindahkan',
          child: InkWell(onTap: () => _showPalletDetail(slot), child: tile),
        ),
      );
    }
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) =>
          !occupied &&
          !blocked &&
          slotStatus == 'EMPTY' &&
          slotId > 0 &&
          _str(widget.rack, 'status', 'ACTIVE') == 'ACTIVE',
      onAcceptWithDetails: (d) => widget.onMove(_num(d.data, 'id'), slotId),
      builder: (context, candidates, rejected) => Container(
        width: 150,
        height: 150,
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
    // Kapasitas per level berasal dari data rack di backend.
    // Batasi 1-4 sesuai desain maksimal slot per level.
    final rackCapacityRaw = _num(widget.rack, 'capacity_pallet', 4);
    final rackCapacity = rackCapacityRaw < 1
        ? 4
        : (rackCapacityRaw > 4 ? 4 : rackCapacityRaw);
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
                    PopupMenuItem(
                      value: 'layout',
                      child: Text('Kelola level & slot'),
                    ),
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
                    } else if (v == 'layout') {
                      widget.onManageLayout();
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
                  '$used/$rackCapacity pallet',
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

class MonitoringPage extends StatefulWidget {
  const MonitoringPage({super.key});
  @override
  State<MonitoringPage> createState() => _MonitoringPageState();
}

class _MonitoringPageState extends State<MonitoringPage> {
  bool loading = true;
  bool recommending = false;
  String? error;
  String? recommendationError;
  String query = '';
  List<Map<String, dynamic>> pallets = [];
  List<Map<String, dynamic>> racks = [];
  List<Map<String, dynamic>> areas = [];
  List<Map<String, dynamic>> fifoRows = [];
  List<Map<String, dynamic>> movements = [];
  List<Map<String, dynamic>> recommendations = [];
  Map<String, dynamic> summary = {};
  int? selectedPalletId;

  int number(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  double decimal(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String value(Map<String, dynamic> m, String key, [String fallback = '-']) {
    final v = m[key];
    return v == null || '$v'.trim().isEmpty ? fallback : '$v';
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw Exception('Format data $path tidak sesuai.');
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/$path'), headers: apiHeaders)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('Format data $path tidak sesuai.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        getList('pallets'),
        getList('racks'),
        getList('warehouse-areas'),
        getList('monitoring/fifo'),
        getList('pallet-movements'),
      ]);
      final actualSummary = await getMap('monitoring/summary');
      if (!mounted) return;
      setState(() {
        pallets = results[0];
        racks = results[1];
        areas = results[2];
        fifoRows = results[3];
        movements = results[4];
        summary = actualSummary;
        final eligible = pallets
            .where((p) => value(p, 'status', '') != 'INACTIVE')
            .toList();
        if (selectedPalletId == null ||
            !eligible.any((p) => number(p, 'id') == selectedPalletId)) {
          selectedPalletId = eligible.isEmpty ? null : number(eligible.first, 'id');
        }
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> loadRecommendations() async {
    final palletId = selectedPalletId;
    if (palletId == null) {
      setState(() {
        recommendations = [];
        recommendationError = 'Pilih pallet terlebih dahulu.';
      });
      return;
    }
    setState(() {
      recommending = true;
      recommendationError = null;
      recommendations = [];
    });
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/slot-recommendations?pallet_id=$palletId'),
            headers: apiHeaders,
          )
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
      if (response.statusCode != 200) {
        final message = decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? response.body)
            : response.body;
        throw Exception('$message');
      }
      if (decoded is! Map) throw Exception('Format rekomendasi tidak sesuai.');
      final data = Map<String, dynamic>.from(decoded);
      final list = data['recommendations'];
      if (!mounted) return;
      setState(() {
        recommendations = list is List
            ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
        recommendationError = recommendations.isEmpty
            ? value(data, 'message', 'Tidak ada slot yang cocok.')
            : null;
        recommending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        recommendationError = '$e'.replaceFirst('Exception: ', '');
        recommending = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    final activeList = pallets.where((p) => value(p, 'status', '') != 'INACTIVE').toList();
    final placed = activeList.where((p) =>
      p['current_slot_id'] != null && value(p, 'status', '') != 'UNPLACED').toList();
    final unplaced = activeList.where((p) =>
      p['current_slot_id'] == null || value(p, 'status', '') == 'UNPLACED').toList();
    final filtered = pallets.where((p) =>
      '${p.values}'.toLowerCase().contains(query.toLowerCase())).toList();
    final usableSlots = number(summary, 'usable_slots');
    final emptySlots = number(summary, 'empty_slots');
    final occupiedSlots = number(summary, 'occupied_slots');
    final utilization = decimal(summary, 'utilization_percent');
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      drawer: const PasataNavigationDrawer(activeMenu: 'Monitoring'),
      appBar: AppBar(
        title: const Text('Monitoring Gudang'),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Gagal memuat monitoring\n$error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: load, child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Ringkasan kondisi gudang', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: wide ? 4 : 2,
                        childAspectRatio: wide ? 2.6 : 2.1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: [
                          _monitorCard('Area gudang', '${areas.length}', Icons.warehouse_outlined, Colors.blue),
                          _monitorCard('Rak terdaftar', '${racks.length}', Icons.view_quilt_outlined, Colors.indigo),
                          _monitorCard('Pallet ditempatkan', '${placed.length}', Icons.inventory_2_outlined, Colors.green),
                          _monitorCard('Belum ditempatkan', '${unplaced.length}', Icons.inventory_outlined, Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Utilisasi dan status slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: wide ? 4 : 2,
                        childAspectRatio: wide ? 2.6 : 2.1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: [
                          _monitorCard('Slot aktif', '$usableSlots', Icons.grid_view_rounded, Colors.teal),
                          _monitorCard('Slot kosong', '$emptySlots', Icons.check_box_outline_blank, Colors.green),
                          _monitorCard('Slot terisi', '$occupiedSlots', Icons.inventory_2_outlined, Colors.indigo),
                          _monitorCard('Utilisasi slot', '${utilization.toStringAsFixed(1)}%', Icons.donut_large, Colors.deepPurple),
                          _monitorCard('Karantina', '${number(summary, 'quarantine_slots')}', Icons.health_and_safety_outlined, Colors.orange),
                          _monitorCard('Pemeliharaan', '${number(summary, 'maintenance_slots')}', Icons.build_outlined, Colors.red),
                          _monitorCard('Sedang dipindahkan', '${number(summary, 'moving_slots')}', Icons.sync, Colors.blueGrey),
                          _monitorCard('Tidak tersedia', '${number(summary, 'unavailable_slots')}', Icons.block_outlined, Colors.grey),
                          _monitorCard('Batas berat tercatat', '${decimal(summary, 'registered_capacity_kg').toStringAsFixed(1)} kg', Icons.scale_outlined, Colors.brown),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4, right: 4),
                        child: Text(
                          'Jumlah slot dihitung dari data slot aktual. Batas berat hanya menjumlahkan slot yang sudah memiliki kapasitas Kg; kapasitas yang belum diisi tidak dianggap nol beban.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Posisi dan status pallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setState(() => query = v),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cari kode pallet atau status', hintText: 'Masukkan kata kunci'),
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Pallet tidak ditemukan.'))),
                      ...filtered.map((p) => Card(
                        child: ListTile(
                          leading: Icon(p['current_slot_id'] == null ? Icons.inventory_outlined : Icons.inventory_2_outlined,
                            color: p['current_slot_id'] == null ? Colors.orange : Colors.green),
                          title: Text(value(p, 'pallet_code', 'Pallet ${number(p, 'id')}')),
                          subtitle: Text('Status: ${value(p, 'status')}\nLokasi: ${value(p, 'rack_code', 'Belum ditempatkan')} · ${value(p, 'slot_code', value(p, 'current_slot_id', '-'))}'),
                          isThreeLine: true,
                        ),
                      )),
                      const SizedBox(height: 16),
                      const Text('Riwayat perpindahan pallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (movements.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada riwayat perpindahan.')))
                      else
                        ...movements.take(10).map((movement) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.swap_horiz, color: Colors.teal),
                            title: Text('${value(movement, 'pallet_code')} · ${value(movement, 'movement_type')}'),
                            subtitle: Text('${value(movement, 'from_slot_code', 'Belum ada slot asal')} → ${value(movement, 'to_slot_code', 'Belum ada slot tujuan')}\n${value(movement, 'moved_at')} · Oleh ${value(movement, 'moved_by_name', 'User tidak tercatat')}\nAlasan: ${value(movement, 'reason', 'Tidak ada alasan')}'),
                            isThreeLine: true,
                          ),
                        )),
                      const SizedBox(height: 16),
                      const Text('Monitoring FIFO & masa inap', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (fifoRows.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Belum ada stok aktif dengan tanggal penerimaan untuk dihitung FIFO.')))
                      else
                        ...fifoRows.take(12).map((item) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${number(item, 'fifo_rank')}')),
                            title: Text('${value(item, 'sku_code')} · ${value(item, 'sku_name')}'),
                            subtitle: Text('Pallet ${value(item, 'pallet_code')} · Batch ${value(item, 'batch_no', '-')}\nDiterima ${value(item, 'received_at')} · Masa inap ${number(item, 'age_days')} hari\nLokasi ${value(item, 'rack_code', 'Belum ditempatkan')} / ${value(item, 'slot_code', '-')} · Sisa ${value(item, 'quantity')} · ${value(item, 'weight_kg')} kg'),
                            isThreeLine: true,
                          ),
                        )),
                      const SizedBox(height: 16),
                      const Text('Rekomendasi penempatan slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: selectedPalletId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pilih pallet', border: OutlineInputBorder()),
                        items: pallets.where((p) => value(p, 'status', '') != 'INACTIVE').map((p) => DropdownMenuItem<int>(value: number(p, 'id'), child: Text('${value(p, 'pallet_code')} · ${value(p, 'status')}'))).toList(),
                        onChanged: recommending ? null : (v) => setState(() { selectedPalletId = v; recommendations = []; recommendationError = null; }),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: recommending ? null : loadRecommendations,
                        icon: recommending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                        label: const Text('Cari slot yang sesuai'),
                      ),
                      if (recommendationError != null)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(recommendationError!)))),
                      ...recommendations.map((rec) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.place_outlined, color: Colors.teal),
                          title: Text('${value(rec, 'rack_code')} · Level ${value(rec, 'level_number')} · ${value(rec, 'slot_code')}'),
                          subtitle: Text('${value(rec, 'area_name')} · Utilisasi area ${decimal(rec, 'area_utilization_percent').toStringAsFixed(1)}%\n${value(rec, 'reason')}'),
                          isThreeLine: true,
                        ),
                      )),
                    ],
                  ),
                ),
    );
  }

  Widget _monitorCard(String title, String count, IconData icon, Color color) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(count, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, height: 1.05, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
