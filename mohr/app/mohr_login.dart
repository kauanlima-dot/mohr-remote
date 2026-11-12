// Mohr Remote: login dentro do aplicativo (versão TI), lista de computadores do painel
// e o botão "Pedir ajuda" da versão do usuário.
// Usa as contas do painel (técnico: usuário e senha; administrador: também o código). A sessão vale 12 horas.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart' show PageShape;
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

// ---------------------------------------------------------------------------
// Padrão visual Max Mohr v1.0 (tokens do Marketing), claro e escuro.
// ---------------------------------------------------------------------------

class MohrCor {
  final bool escuro;
  MohrCor.of(BuildContext context)
      : escuro = Theme.of(context).brightness == Brightness.dark;

  static const azul = Color(0xFF162D8C); // Azul Max Mohr
  static const azulDestaque = Color(0xFF0539B7);
  static const azulMedio = Color(0xFF2E74D1);
  static const azulClaro = Color(0xFF69ADE5);

  Color get fundo => escuro ? const Color(0xFF0E1224) : const Color(0xFFF0F0EF);
  Color get superficie => escuro ? const Color(0xFF161B33) : Colors.white;
  Color get superficieAlt => escuro ? const Color(0xFF1D2440) : const Color(0xFFF1F4F8);
  Color get titulo => escuro ? const Color(0xFFEEF0F6) : azul;
  Color get texto => escuro ? const Color(0xFFEEF0F6) : const Color(0xFF14182A);
  Color get texto2 => escuro ? const Color(0xFFB4B9C8) : const Color(0xFF5C606A);
  Color get borda => escuro ? const Color(0xFF2A3253) : const Color(0xFFDADCE0);
  Color get link => escuro ? const Color(0xFF8FB0F7) : azulDestaque;
  Color get sucesso => escuro ? const Color(0xFF4CC26A) : const Color(0xFF1A7F37);
  Color get sucessoFundo => escuro ? const Color(0x244CC26A) : const Color(0xFFE6F4EA);
  Color get alerta => escuro ? const Color(0xFFFAB219) : const Color(0xFF8A5A00);
  Color get alertaFundo => escuro ? const Color(0x24FAB219) : const Color(0xFFFEF4DC);
  Color get erro => escuro ? const Color(0xFFF5736C) : const Color(0xFFC2312F);
  Color get erroFundo => escuro ? const Color(0x24F5736C) : const Color(0xFFFBE9E8);

  LinearGradient get gradPrimario => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: escuro
          ? const [Color(0xFF3A4FD0), Color(0xFF4A63E0)]
          : const [azul, azulDestaque]);
  LinearGradient get gradAssinatura => LinearGradient(
      colors: escuro
          ? const [Color(0xFF5060E6), Color(0xFF4F74EA), Color(0xFF3E9ED0), azulClaro]
          : const [azul, azulDestaque, azulMedio, azulClaro],
      stops: const [0, .35, .7, 1]);
}

/// Filete de 3 px com os 4 azuis do símbolo (sob títulos).
class MohrFilete extends StatelessWidget {
  final double largura;
  const MohrFilete({Key? key, this.largura = 72}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        width: largura,
        height: 3,
        decoration: BoxDecoration(
            gradient: MohrCor.of(context).gradAssinatura,
            borderRadius: BorderRadius.circular(2)),
      );
}

/// Botão principal da marca (degradê azul, raio 10).
class MohrBotao extends StatelessWidget {
  final String texto;
  final IconData? icone;
  final VoidCallback? onPressed;
  final double altura;
  final double fonte;
  const MohrBotao(
      {Key? key,
      required this.texto,
      this.icone,
      this.onPressed,
      this.altura = 40,
      this.fonte = 14})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final cor = MohrCor.of(context);
    final ativo = onPressed != null;
    return Opacity(
      opacity: ativo ? 1 : .6,
      child: Container(
        height: altura,
        decoration: BoxDecoration(
          gradient: cor.gradPrimario,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x380539B7), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icone != null) ...[
                    Icon(icone, size: fonte + 4, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(texto,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: fonte,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status sempre com ícone + rótulo.
class MohrStatus extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final Color cor;
  final Color fundo;
  const MohrStatus(
      {Key? key,
      required this.icone,
      required this.rotulo,
      required this.cor,
      required this.fundo})
      : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration:
            BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(rotulo,
              style: TextStyle(
                  color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
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

  // Rótulo sempre visível acima do campo (padrão Max Mohr).
  Widget _field(MohrCor cor, TextEditingController c, String label, IconData icon,
      {bool obscure = false, bool number = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: cor.texto)),
      const SizedBox(height: 6),
      TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLength: number ? 6 : null,
        onSubmitted: (_) => _submit(),
        style: TextStyle(fontSize: 14, color: cor.texto),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20, color: cor.texto2),
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: cor.superficie,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cor.borda, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cor.link, width: 1.5)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cor = MohrCor.of(context);
    return Container(
      color: cor.fundo,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: cor.superficie,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cor.borda),
            boxShadow: const [
              BoxShadow(color: Color(0x1A14182A), blurRadius: 12, offset: Offset(0, 4))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: loadLogo()),
              const SizedBox(height: 20),
              Text('MOHR REMOTE · TI MAX MOHR',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                      color: cor.texto2)),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(
                      text: 'Entrar no ',
                      style: TextStyle(fontWeight: FontWeight.w300)),
                  const TextSpan(
                      text: 'Mohr Remote',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                style: TextStyle(fontSize: 26, color: cor.titulo, height: 1.15),
              ),
              const SizedBox(height: 12),
              const MohrFilete(),
              const SizedBox(height: 12),
              Text('Use sua conta do painel da TI Max Mohr.',
                  style: TextStyle(fontSize: 14, color: cor.texto2)),
              const SizedBox(height: 20),
              _field(cor, _user, 'Usuário', Icons.person_outline),
              const SizedBox(height: 14),
              _field(cor, _pass, 'Senha', Icons.lock_outline, obscure: true),
              const SizedBox(height: 14),
              _field(cor, _code, 'Código do autenticador (só administrador)',
                  Icons.verified_user_outlined,
                  number: true),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cor.erroFundo,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: cor.erro, width: 4)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, size: 18, color: cor.erro),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(fontSize: 14, color: cor.texto))),
                  ]),
                ),
              const SizedBox(height: 22),
              MohrBotao(
                texto: _busy ? 'Entrando...' : 'Entrar',
                altura: 44,
                fonte: 16,
                onPressed: _busy ? null : _submit,
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
              const Icon(Icons.verified_user, size: 16, color: MohrCor.azulMedio),
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
    final color = selected ? MohrCor.of(context).titulo : MohrCor.of(context).texto2;
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
    final cor = MohrCor.of(context);
    final online = _devices.where((d) => d.online == true).length;
    final help = _devices.where((d) => d.help != null).length;
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 14, color: cor.texto),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: cor.superficie,
                  prefixIcon: Icon(Icons.search, size: 20, color: cor.texto2),
                  hintText: 'Buscar por nome, código, usuário ou departamento',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cor.borda, width: 1.5)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cor.link, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Atualizar a lista',
              icon: Icon(Icons.refresh, color: cor.titulo),
              onPressed: () => _load(),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            MohrStatus(
                icone: Icons.check,
                rotulo: '$online de ${_devices.length} online',
                cor: cor.sucesso,
                fundo: cor.sucessoFundo),
            if (help > 0)
              MohrStatus(
                  icone: Icons.support_agent,
                  rotulo: '$help pedido(s) de ajuda',
                  cor: cor.alerta,
                  fundo: cor.alertaFundo),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _onlyOnline = !_onlyOnline),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_onlyOnline ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18, color: cor.titulo),
                  const SizedBox(width: 4),
                  Text('Só online', style: TextStyle(fontSize: 13, color: cor.texto2)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, MohrDevice d) {
    final cor = MohrCor.of(context);
    final details = [d.branch, d.department, d.user].where((s) => s.isNotEmpty).join(' · ');
    final hasHelp = d.help != null;
    final status = d.online == true
        ? MohrStatus(icone: Icons.check, rotulo: 'Online', cor: cor.sucesso, fundo: cor.sucessoFundo)
        : MohrStatus(
            icone: Icons.do_not_disturb_on_outlined,
            rotulo: d.online == false ? 'Offline' : 'Sem status',
            cor: cor.texto2,
            fundo: cor.superficieAlt);
    return Container(
      margin: const EdgeInsets.only(right: 12, bottom: 8),
      decoration: BoxDecoration(
        color: cor.superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasHelp ? cor.alerta : cor.borda),
        boxShadow: const [BoxShadow(color: Color(0x0F14182A), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onDoubleTap: () => _connect(d),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(d.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700, color: cor.titulo)),
                      ),
                      const SizedBox(width: 8),
                      Text(d.rustId, style: TextStyle(fontSize: 13, color: cor.texto2)),
                    ]),
                    if (details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(details,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cor.texto2)),
                      ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      status,
                      if (d.diskAlert)
                        MohrStatus(
                            icone: Icons.storage,
                            rotulo: 'Disco quase cheio · ${d.diskFree!.toStringAsFixed(0)} GB livres',
                            cor: cor.alerta,
                            fundo: cor.alertaFundo),
                    ]),
                    if (hasHelp)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cor.alertaFundo,
                          borderRadius: BorderRadius.circular(6),
                          border: Border(left: BorderSide(color: const Color(0xFFFAB219), width: 3)),
                        ),
                        child: Row(children: [
                          Icon(Icons.support_agent, size: 16, color: cor.alerta),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Pediu ajuda: ${_s(d.help!['message'])}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cor.texto, fontSize: 13)),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: d.favorite ? 'Remover dos favoritos' : 'Favoritar',
                icon: Icon(d.favorite ? Icons.star : Icons.star_border, color: cor.titulo),
                onPressed: () => _post('/api/app/favorite', d),
              ),
              if (hasHelp)
                IconButton(
                  tooltip: 'Marcar o pedido de ajuda como resolvido',
                  icon: Icon(Icons.check_circle_outline, color: cor.sucesso),
                  onPressed: () => _post('/api/app/help/resolve', d,
                      id: (d.help!['id'] as num).toInt()),
                ),
              const SizedBox(width: 4),
              MohrBotao(
                texto: _busy == d.id ? 'Abrindo...' : 'Conectar',
                icone: Icons.open_in_new,
                onPressed: _busy == null ? () => _connect(d) : null,
              ),
            ]),
          ),
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
        child: MohrBotao(
          texto: 'Pedir ajuda à TI',
          icone: Icons.support_agent,
          altura: 52,
          fonte: 16,
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
    // Texto maior, como na tela do usuário.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.25)),
      child: AlertDialog(
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
                    Text(_error!, style: TextStyle(color: MohrCor.of(context).erro)),
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
    ));
  }
}

// ---------------------------------------------------------------------------
// App de celular da TI: aba "Computadores" (mesma lista do app do computador)
// ---------------------------------------------------------------------------

class MohrPaginaComputadores extends StatelessWidget implements PageShape {
  MohrPaginaComputadores({Key? key}) : super(key: key);

  @override
  final String title = 'Computadores';

  @override
  final Widget icon = const Icon(Icons.computer);

  @override
  final List<Widget> appBarActions = [
    IconButton(
      tooltip: 'Sair da conta',
      icon: const Icon(Icons.logout),
      onPressed: () => MohrSession.logout(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cor = MohrCor.of(context);
    return Container(
      color: cor.fundo,
      padding: const EdgeInsets.only(left: 12, top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Obx(() => Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: Row(children: [
                Icon(Icons.verified_user, size: 16, color: cor.titulo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Conectado como ${MohrSession.login.value}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: cor.texto2)),
                ),
              ]),
            )),
        const Expanded(child: MohrDeviceList()),
      ]),
    );
  }
}
