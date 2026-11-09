// Mohr Remote: login dentro do aplicativo (versão TI).
// Usa as contas do painel (usuário, senha e código do autenticador). A sessão vale 12 horas.
import 'dart:async';
import 'dart:convert';

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
      r = await http.post(Uri.parse('$kMohrPanel/api/app/login'), body: {
        'login': user,
        'password': password,
        'code': code
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
              _field(_code, 'Código do autenticador', Icons.verified_user_outlined,
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
