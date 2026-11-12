// Mohr Remote: login dentro do aplicativo (versão TI), lista de computadores do painel
// e o botão "Pedir ajuda" da versão do usuário.
// Usa as contas do painel (técnico: usuário e senha; administrador: também o código). A sessão vale 12 horas.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

const String kMohrPanel = 'https://remoto.maxmohr.com.br';
const String _kToken = 'mohr-app-token';
const String _kLogin = 'mohr-app-login';
const String _kExpires = 'mohr-app-expires';

class MohrSession {
  static final RxBool loggedIn = false.obs;
  static final RxString login = ''.obs;
  static Timer? _timer;
  static bool _started = false;

  static String get token => bind.mainGetLocalOption(key: _kToken);

  static int get _expires =>
      int.tryParse(bind.mainGetLocalOption(key: _kExpires)) ?? 0;

  static void init() {
    if (_started) return;
    _started = true;
    if (token.isNotEmpty && _expires > DateTime.now().millisecondsSinceEpoch) {
      login.value = bind.mainGetLocalOption(key: _kLogin);
      loggedIn.value = true;
      _validate();
    }
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (loggedIn.value && _expires <= DateTime.now().millisecondsSinceEpoch) {
        logout(remote: false);
      }
    });
  }

  static Future<void> _validate() async {
    try {
      final r = await http.get(Uri.parse('$kMohrPanel/api/app/me'),
          headers: {'Authorization': 'Bearer $token'}).timeout(
          const Duration(seconds: 10));
      if (r.statusCode == 401) await logout(remote: false);
    } catch (_) {
      // Sem rede: mantém a sessão até expirar.
    }
  }

  /// Retorna null em caso de sucesso ou a mensagem de erro.
  static Future<String?> signIn(String user, String password, String code) async {
    http.Response r;
    try {
      // O ID deste app vai junto para o painel saber qual técnico fez cada acesso.
      final myId = await bind.mainGetMyId();
      r = await http.post(Uri.parse('$kMohrPanel/api/app/login'), body: {
        'login': user,
        'password': password,
        'code': code,
        'rustdesk': myId
      }).timeout(const Duration(seconds: 20));
    } catch (_) {
      return 'Sem conexão com o painel da Max Mohr.';
    }
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode != 200 || data['token'] == null) {
      if (r.statusCode == 429) return 'Muitas tentativas. Aguarde um pouco.';
      return (data['error'] ?? 'Não foi possível entrar.').toString();
    }
    await bind.mainSetLocalOption(key: _kToken, value: data['token'].toString());
    await bind.mainSetLocalOption(key: _kLogin, value: data['login'].toString());
    await bind.mainSetLocalOption(
        key: _kExpires, value: data['expires'].toString());
    login.value = data['login'].toString();
    loggedIn.value = true;
    return null;
  }

  static Future<void> logout({bool remote = true}) async {
    final t = token;
    if (remote && t.isNotEmpty) {
      try {
        await http.post(Uri.parse('$kMohrPanel/api/app/logout'),
            headers: {'Authorization': 'Bearer $t'}).timeout(
            const Duration(seconds: 5));
      } catch (_) {}
    }
    for (final k in [_kToken, _kLogin, _kExpires]) {
      await bind.mainSetLocalOption(key: k, value: '');
    }
    login.value = '';
    loggedIn.value = false;
  }

  /// Chamada autenticada ao painel. GET sem [body]; POST (formulário) com [body].
  static Future<dynamic> api(String path, {Map<String, String>? body}) async {
    final headers = {'Authorization': 'Bearer $token'};
    final uri = Uri.parse('$kMohrPanel$path');
    http.Response r;
    try {
      r = await (body == null
              ? http.get(uri, headers: headers)
              : http.post(uri, headers: headers, body: body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw MohrApiError('Sem conexão com o painel da Max Mohr.');
    }
    if (r.statusCode == 401) {
      await logout(remote: false);
      throw MohrApiError('Sessão expirada. Entre novamente.');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 400) {
      final message = data is Map ? data['error'] : null;
      throw MohrApiError((message ?? 'Erro ${r.statusCode} no painel.').toString());
    }
    return data;
  }
}

class MohrApiError implements Exception {
  final String message;
  MohrApiError(this.message);
  @override
  String toString() => message;
}

class MohrLoginPage extends StatefulWidget {
  const MohrLoginPage({Key? key}) : super(key: key);

  @override
  State<MohrLoginPage> createState() => _MohrLoginPageState();
}

class _MohrLoginPageState extends State<MohrLoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await MohrSession.signIn(
        _user.text.trim(), _pass.text, _code.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _code.clear();
    });
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool obscure = false, bool number = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      maxLength: number ? 6 : null,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: '',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.colorScheme.background,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: loadLogo()),
              const SizedBox(height: 16),
              Text('Entrar no Mohr Remote',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Use sua conta do painel da TI Max Mohr',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 20),
              _field(_user, 'Usuário', Icons.person_outline),
              const SizedBox(height: 12),
              _field(_pass, 'Senha', Icons.lock_outline, obscure: true),
              const SizedBox(height: 12),
              _field(_code, 'Código do autenticador (só administrador)',
                  Icons.verified_user_outlined,
                  number: true),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Entrar', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra com o técnico logado e o botão Sair (tela inicial da versão TI).
class MohrSessionBar extends StatelessWidget {
  const MohrSessionBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.only(left: 20, right: 12, top: 8),
          child: Row(
            children: [
              const Icon(Icons.verified_user, size: 16, color: MyTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(MohrSession.login.value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                  onPressed: () => MohrSession.logout(),
                  child: const Text('Sair')),
            ],
          ),
        ));
  }
}

// ---------------------------------------------------------------------------
// Lista de computadores do painel (versão TI)
// ---------------------------------------------------------------------------

String _s(dynamic v) => v == null ? '' : v.toString();
double? _d(dynamic v) => v is num ? v.toDouble() : null;

class MohrDevice {
  final int id;
  final String name, rustId, branch, department, user, os, lastTech;
  final bool? online;
  final bool hasSecret, favorite;
  final double? diskFree, diskTotal;
  final Map<String, dynamic>? help;

  MohrDevice.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = _s(j['name']),
        rustId = _s(j['rust_id']),
        branch = _s(j['branch']),
        department = _s(j['department']),
        user = _s(j['user']),
        os = _s(j['os']),
        lastTech = _s(j['last_tech']),
        online = j['online'] is bool ? j['online'] as bool : null,
        hasSecret = j['has_secret'] == true,
        favorite = j['favorite'] == true,
        diskFree = _d(j['disk_free_gb']),
        diskTotal = _d(j['disk_total_gb']),
        help = j['help'] is Map
            ? Map<String, dynamic>.from(j['help'] as Map)
            : null;

  bool get diskAlert =>
      diskFree != null &&
      diskTotal != null &&
      diskTotal! > 0 &&
      (diskFree! < 10 || diskFree! / diskTotal! < 0.1);

  String get searchText =>
      [name, rustId, branch, department, user].join(' ').toLowerCase();
}

/// Painel da direita na versão TI: "Computadores Max Mohr" e a lista original (recentes/favoritos).
class MohrDevicesPanel extends StatefulWidget {
  final Widget recent;
  const MohrDevicesPanel({Key? key, required this.recent}) : super(key: key);

  @override
  State<MohrDevicesPanel> createState() => _MohrDevicesPanelState();
}

class _MohrDevicesPanelState extends State<MohrDevicesPanel> {
  int _tab = 0;

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tab == index;
    final color = selected ? MyTheme.accent : null;
    return TextButton.icon(
      onPressed: () => setState(() => _tab = index),
      icon: Icon(icon, size: 18, color: color),
      label: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 6),
          child: Row(children: [
            _tabButton(0, Icons.computer, 'Computadores Max Mohr'),
            const SizedBox(width: 8),
            _tabButton(1, Icons.history, 'Recentes'),
          ]),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            sizing: StackFit.expand,
            children: [const MohrDeviceList(), widget.recent],
          ),
        ),
      ],
    );
  }
}

class MohrDeviceList extends StatefulWidget {
  const MohrDeviceList({Key? key}) : super(key: key);

  @override
  State<MohrDeviceList> createState() => _MohrDeviceListState();
}

class _MohrDeviceListState extends State<MohrDeviceList> {
  final _search = TextEditingController();
  List<MohrDevice> _devices = [];
  String? _error;
  bool _loading = true;
  bool _onlyOnline = false;
  int? _busy;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Atualiza o status a cada 30 segundos.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!MohrSession.loggedIn.value) return;
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final data = await MohrSession.api('/api/app/devices') as Map;
      final list = (data['devices'] as List)
          .map((e) => MohrDevice.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connect(MohrDevice d) async {
    if (_busy != null) return;
    setState(() => _busy = d.id);
    try {
      final data = await MohrSession.api('/api/app/connect',
          body: {'id': '${d.id}'}) as Map;
      final password = _s(data['password']);
      if (!mounted) return;
      await connect(context, _s(data['rust_id']),
          password: password.isEmpty ? null : password);
    } catch (e) {
      showToast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _post(String path, MohrDevice d, {int? id}) async {
    try {
      await MohrSession.api(path, body: {'id': '${id ?? d.id}'});
      await _load(quiet: true);
    } catch (e) {
      showToast(e.toString());
    }
  }

  List<MohrDevice> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _devices
        .where((d) => q.isEmpty || d.searchText.contains(q))
        .where((d) => !_onlyOnline || d.online == true)
        .toList();
    int rank(MohrDevice d) =>
        (d.help != null ? 0 : 4) + (d.favorite ? 0 : 2) + (d.online == true ? 0 : 1);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Widget _header(BuildContext context) {
    final online = _devices.where((d) => d.online == true).length;
    final help = _devices.where((d) => d.help != null).length;
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Buscar por nome, ID, usuário ou departamento',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('$online de ${_devices.length} online',
                style: Theme.of(context).textTheme.bodySmall),
            if (help > 0) ...[
              const SizedBox(width: 12),
              const Icon(Icons.support_agent, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text('$help pedido(s) de ajuda',
                  style: const TextStyle(color: Colors.orange, fontSize: 12)),
            ],
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _onlyOnline = !_onlyOnline),
              child: Row(children: [
                Icon(_onlyOnline ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18),
                const SizedBox(width: 4),
                Text('Só online', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, MohrDevice d) {
    final theme = Theme.of(context);
    final dot = d.online == true
        ? Colors.green
        : (d.online == false ? Colors.grey : Colors.blueGrey.shade200);
    final details = [d.branch, d.department, d.user].where((s) => s.isNotEmpty).join(' · ');
    final hasHelp = d.help != null;
    return Card(
      margin: const EdgeInsets.only(right: 12, bottom: 6),
      elevation: 0,
      color: hasHelp ? Colors.orange.withOpacity(0.08) : theme.cardColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: hasHelp ? Colors.orange : theme.dividerColor)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onDoubleTap: () => _connect(d),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Tooltip(
              message: d.online == true
                  ? 'Online'
                  : (d.online == false ? 'Offline' : 'Status indisponível'),
              child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(d.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(d.rustId, style: theme.textTheme.bodySmall),
                  ]),
                  if (details.isNotEmpty)
                    Text(details,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  if (d.diskAlert)
                    Text(
                        'Disco quase cheio: ${d.diskFree!.toStringAsFixed(0)} GB livres',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  if (hasHelp)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Icon(Icons.support_agent, size: 16, color: Colors.orange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('Pediu ajuda: ${_s(d.help!['message'])}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.orange, fontSize: 12)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: d.favorite ? 'Remover dos favoritos' : 'Favoritar',
              icon: Icon(d.favorite ? Icons.star : Icons.star_border,
                  color: d.favorite ? Colors.amber : null),
              onPressed: () => _post('/api/app/favorite', d),
            ),
            if (hasHelp)
              IconButton(
                tooltip: 'Marcar o pedido de ajuda como resolvido',
                icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                onPressed: () => _post('/api/app/help/resolve', d,
                    id: (d.help!['id'] as num).toInt()),
              ),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MyTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _busy == null ? () => _connect(d) : null,
              child: Text(_busy == d.id ? 'Abrindo...' : 'Conectar'),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    Widget body;
    if (_loading && _devices.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _devices.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _load(), child: const Text('Tentar de novo')),
        ]),
      );
    } else if (visible.isEmpty) {
      body = Center(
          child: Text(_devices.isEmpty
              ? 'Nenhum computador aprovado no painel para a sua filial.'
              : 'Nenhum computador encontrado.'));
    } else {
      body = ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, i) => _row(context, visible[i]),
      );
    }
    return Column(children: [_header(context), Expanded(child: body)]);
  }
}

// ---------------------------------------------------------------------------
// Botão "Pedir ajuda" (versão do usuário)
// ---------------------------------------------------------------------------

/// Gravado pelo instalador (só administradores alteram; usuários leem).
const String kMohrAgentFile = r'C:\ProgramData\MaxMohr\MohrRemote\agente.json';

String? _agentToken() {
  try {
    final data = jsonDecode(File(kMohrAgentFile).readAsStringSync());
    final token = data is Map ? _s(data['token']) : '';
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ? token : null;
  } catch (_) {
    return null;
  }
}

class MohrHelpButton extends StatelessWidget {
  const MohrHelpButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows || _agentToken() == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: SizedBox(
        width: double.infinity,
        height: 42,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: MyTheme.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.support_agent),
          label: const Text('Pedir ajuda à TI', style: TextStyle(fontSize: 15)),
          onPressed: () => showDialog(
              context: context, builder: (_) => const _MohrHelpDialog()),
        ),
      ),
    );
  }
}

class _MohrHelpDialog extends StatefulWidget {
  const _MohrHelpDialog({Key? key}) : super(key: key);

  @override
  State<_MohrHelpDialog> createState() => _MohrHelpDialogState();
}

class _MohrHelpDialogState extends State<_MohrHelpDialog> {
  final _message = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Escreva em poucas palavras qual é o problema.');
      return;
    }
    final token = _agentToken();
    if (token == null) {
      setState(() => _error = 'Este computador não está cadastrado no painel da TI.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final r = await http.post(Uri.parse('$kMohrPanel/api/agent/help'),
          headers: {'Authorization': 'Bearer $token'},
          body: {'mensagem': text}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 201) {
        dynamic data;
        try {
          data = jsonDecode(utf8.decode(r.bodyBytes));
        } catch (_) {}
        error = _s(data is Map ? data['error'] : null);
        if (error.isEmpty) error = 'Não foi possível enviar o pedido (erro ${r.statusCode}).';
      }
    } catch (_) {
      error = 'Sem conexão com o painel da TI. Verifique a internet e tente de novo.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _sent = error == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pedir ajuda à TI'),
      content: SizedBox(
        width: 380,
        child: _sent
            ? const Text(
                'Pedido enviado! A equipe de TI da Max Mohr já foi avisada e vai '
                'acessar seu computador ou entrar em contato em breve.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Conte em poucas palavras o que está acontecendo:'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _message,
                    autofocus: true,
                    maxLength: 300,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Ex.: a impressora não imprime',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
      ),
      actions: _sent
          ? [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar')),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? 'Enviando...' : 'Enviar'),
              ),
            ],
    );
  }
}
