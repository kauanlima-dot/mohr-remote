#!/usr/bin/env python3
"""Aplica a marca Max Mohr (Mohr Remote) numa árvore do RustDesk.

Roda no CI depois do checkout (com submódulos) e antes do build.
Altera só a cópia de trabalho; nada é commitado no submódulo hbb_common.

Uso:  python mohr/aplicar-marca.py [--raiz .]
Falha (exit 1) se algum ponto de patch não for encontrado — melhor quebrar o
build do que gerar um cliente apontando para o servidor público da RustDesk.
"""
import argparse
import os
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------- configuração
# Nome interno: vira nome do .exe, do serviço Windows e da pasta em Program Files.
# SEM espaços: o RustDesk monta "sc create {nome}" sem aspas.
APP_NAME = "MohrRemote"
# Nome exibido nos metadados do .exe (Propriedades > Detalhes).
NOME_EXIBICAO = "Mohr Remote"
EMPRESA = "Max Mohr"

SERVIDOR_ID = "143.95.172.62"            # porta 21116 é o padrão
SERVIDOR_RELAY = "143.95.172.62:21117"
CHAVE = "qCsOGI3q3tT5EuSoLJn0GODVRGzKBA2X4uN9497qz8Q="
PAINEL = "https://remoto.maxmohr.com.br"

# Travadas: o usuário não consegue mudar (aparecem bloqueadas na tela de configurações).
TRAVADAS = {
    "custom-rendezvous-server": SERVIDOR_ID,
    "relay-server": SERVIDOR_RELAY,
    "key": CHAVE,
    "approve-mode": "password",           # acesso só com a senha definida na instalação, sem pedir permissão
    "verification-method": "use-permanent-password",
    "allow-websocket": "N",
    # O programa envia ao painel: heartbeat, dados do PC (sysinfo) e cada acesso (histórico de sessões).
    "api-server": PAINEL,
}
# Padrão: valem até alguém mudar.
PADROES = {
    "enable-check-update": "N",           # não oferecer o RustDesk oficial
    "allow-auto-update": "N",
}
# Por variante do build (env MOHR_VARIANTE ou --variante):
#   usuario: só recebe acesso, sem tela de conectar e sem configurações
#   ti:      cliente completo para a equipe de suporte
#   android: app de celular da TI, só conecta nos computadores (sem compartilhar a tela do celular)
FIXAS_POR_VARIANTE = {
    "usuario": {"conn-type": "incoming", "disable-settings": "Y"},
    "ti": {},
    "android": {"conn-type": "outgoing"},
}
# Embutidas (BUILTIN_SETTINGS). Na versão usuário, as configurações ficam escondidas na tela,
# mas o instalador (SYSTEM) ainda precisa usar --set-id / --option pela linha de comando.
EMBUTIDAS_POR_VARIANTE = {
    "usuario": {"allow-command-line-settings-when-settings-disabled": "Y"},
    "ti": {},
    "android": {},
}
# -----------------------------------------------------------------------------

erros = []


def sub_uma(caminho: Path, padrao: str, novo: str, descricao: str):
    texto = caminho.read_text(encoding="utf-8")
    texto_novo, n = re.subn(padrao, lambda _m: novo, texto, count=1)
    if n != 1:
        erros.append(f"{caminho}: não achei {descricao}")
        return
    caminho.write_text(texto_novo, encoding="utf-8", newline="\n")
    print(f"ok  {caminho.name}: {descricao}")


def rust_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def mapa_rust(valores: dict) -> str:
    if not valores:
        return "Default::default()"
    pares = ", ".join(f"({rust_str(k)}.to_owned(), {rust_str(v)}.to_owned())" for k, v in valores.items())
    return f"RwLock::new(HashMap::from([{pares}]))"


def patch_mapa(cfg: Path, nome: str, valores: dict):
    if not valores:
        print(f"ok  config.rs: {nome} sem alteração")
        return
    sub_uma(cfg,
            rf'pub static ref {nome}: RwLock<HashMap<String, String>> = Default::default\(\);',
            f'pub static ref {nome}: RwLock<HashMap<String, String>> = {mapa_rust(valores)};',
            nome)


def patch_config(raiz: Path, variante: str):
    cfg = raiz / "libs/hbb_common/src/config.rs"
    sub_uma(cfg,
            r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];',
            f'pub const RENDEZVOUS_SERVERS: &[&str] = &[{rust_str(SERVIDOR_ID)}];',
            "RENDEZVOUS_SERVERS")
    sub_uma(cfg,
            r'pub const RS_PUB_KEY: &str = "[^"]*";',
            f'pub const RS_PUB_KEY: &str = {rust_str(CHAVE)};',
            "RS_PUB_KEY")
    sub_uma(cfg,
            r'pub static ref APP_NAME: RwLock<String> = RwLock::new\("RustDesk"\.to_owned\(\)\);',
            f'pub static ref APP_NAME: RwLock<String> = RwLock::new({rust_str(APP_NAME)}.to_owned());',
            "APP_NAME")
    patch_mapa(cfg, "DEFAULT_SETTINGS", PADROES)
    patch_mapa(cfg, "OVERWRITE_SETTINGS", TRAVADAS)
    patch_mapa(cfg, "HARD_SETTINGS", FIXAS_POR_VARIANTE[variante])
    patch_mapa(cfg, "BUILTIN_SETTINGS", EMBUTIDAS_POR_VARIANTE[variante])


def patch_codigo(raiz: Path):
    # ID fixo: o servidor OSS responde NOT_SUPPORT à "troca de ID", mas aceita o ID novo no
    # registro normal. Então gravamos o ID local mesmo assim e o cliente se registra com ele.
    sub_uma(raiz / "src/ui_interface.rs",
            r'Ok\(register_pk_response::Result::NOT_SUPPORT\) => \{\s*return "server_not_support";\s*\}',
            'Ok(register_pk_response::Result::NOT_SUPPORT) => {\n'
            '                                // Mohr Remote: servidor OSS não troca ID; o novo ID é registrado em seguida.\n'
            '                                ok = true;\n'
            '                            }',
            "troca de ID com servidor OSS")


def patch_layout(raiz: Path):
    """Paleta Max Mohr, sem "Powered by RustDesk" e tela simplificada na versão usuário
    (bind.isIncomingOnly()). A versão TI mantém a tela completa, só com as cores novas."""
    lib = raiz / "flutter/lib"
    common = lib / "common.dart"
    # Padrão visual Max Mohr v1.0: Azul Max Mohr #162D8C (primário), Azul Médio #2E74D1 (ID).
    for nome, cor in [("accent", "0xFF162D8C"), ("accent50", "0x77162D8C"), ("accent80", "0xAA162D8C"),
                      ("idColor", "0xFF2E74D1"), ("button", "0xFF162D8C"), ("grayBg", "0xFFF0F0EF")]:
        sub_uma(common, rf'static const Color {nome} = Color\(0x[0-9A-Fa-f]{{8}}\);',
                f'static const Color {nome} = Color({cor});', f"cor {nome}")
    # Fonte oficial Rigid Square (instalada nos PCs da empresa; sem ela, o Windows usa a fonte padrão).
    sub_uma(common, r'useMaterial3: false,\s*brightness: Brightness\.light,',
            "useMaterial3: false,\n    brightness: Brightness.light,\n    fontFamily: 'Rigid Square',", "fonte do tema claro")
    sub_uma(common, r'useMaterial3: false,\s*brightness: Brightness\.dark,',
            "useMaterial3: false,\n    brightness: Brightness.dark,\n    fontFamily: 'Rigid Square',", "fonte do tema escuro")

    home = lib / "desktop/pages/desktop_home_page.dart"
    usuario = "bind.isIncomingOnly()"
    sub_uma(home, r'if \(bind\.isCustomClient\(\)\)\s*Align\(\s*alignment: Alignment\.center,\s*child: loadPowered\(context\),\s*\),',
            '', 'remover "Powered by RustDesk"')
    sub_uma(home, r'if \(!isOutgoingOnly\) buildPasswordBoard\(context\),',
            'if (!isOutgoingOnly && !isIncomingOnly) buildPasswordBoard(context),', "esconder senha na versão usuário")
    sub_uma(home, r'translate\("ID"\),',
            f'({usuario} ? "Seu código de acesso" : translate("ID")),', "rótulo do ID")
    sub_uma(home, r'buildPopupMenu\(context\)(?=\s*\],)',
            f'if (!{usuario}) buildPopupMenu(context)', "esconder menu na versão usuário")
    sub_uma(home, r'style: TextStyle\(\s*fontSize: 22,\s*\),',
            f'style: TextStyle(fontSize: {usuario} ? 30 : 22, '
            f'fontWeight: {usuario} ? FontWeight.bold : FontWeight.normal, '
            f'color: {usuario} ? MyTheme.accent : null),', "ID em destaque")
    sub_uma(home, r'margin: const EdgeInsets\.only\(left: 20, right: 11\),\s*height: 57,',
            f'margin: const EdgeInsets.only(left: 20, right: 11),\n      height: {usuario} ? 104 : 57,', "altura do ID")
    # Versão usuário: janela mais larga e todo o texto 30% maior (mais fácil de ler).
    sub_uma(home, r'return ChangeNotifierProvider\.value\(\s*value: gFFI\.serverModel,\s*child: Container\(\s*width: isIncomingOnly \? 280\.0 : 200\.0,',
            "return MediaQuery(\n"
            "      data: isIncomingOnly\n"
            "          ? MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3))\n"
            "          : MediaQuery.of(context),\n"
            "      child: ChangeNotifierProvider.value(\n"
            "      value: gFFI.serverModel,\n"
            "      child: Container(\n"
            "        width: isIncomingOnly ? 400.0 : 200.0,", "tela do usuário maior")
    sub_uma(home, r'\);\s*\}\s*buildRightPane\(',
            "));\n  }\n\n  buildRightPane(", "fecha a escala de texto")
    sub_uma(home, r'translate\("Your Desktop"\)',
            f'({usuario} ? "Suporte remoto Max Mohr" : translate("Your Desktop"))', "título")
    sub_uma(home, r'translate\("desk_tip"\)',
            f'({usuario} ? "Quando precisar de suporte, informe o código abaixo à equipe de TI '
            f'da Max Mohr. O acesso é feito somente pela TI." : translate("desk_tip"))', "instrução")

    server = lib / "desktop/pages/server_page.dart"
    sub_uma(server, re.escape('"${translate("Request access to your device")}...",'),
            f'({usuario} ? "A TI da Max Mohr está acessando seu computador" : '
            '"${translate("Request access to your device")}..."),', "texto do pedido de acesso")


def patch_login(raiz: Path):
    """Login no app (versão TI) com as contas do painel. A tela fica em mohr/app/mohr_login.dart."""
    origem = raiz / "mohr/app/mohr_login.dart"
    if not origem.exists():
        erros.append(f"{origem}: arquivo da tela de login não encontrado")
        return
    (raiz / "flutter/lib/desktop/pages/mohr_login.dart").write_text(origem.read_text(encoding="utf-8"),
                                                                    encoding="utf-8", newline="\n")
    print("ok  flutter/lib/desktop/pages/mohr_login.dart")
    home = raiz / "flutter/lib/desktop/pages/desktop_home_page.dart"
    sub_uma(home, re.escape("import 'package:flutter_hbb/desktop/pages/connection_page.dart';"),
            "import 'package:flutter_hbb/desktop/pages/connection_page.dart';\n"
            "import 'package:flutter_hbb/desktop/pages/mohr_login.dart';", "import da tela de login")
    sub_uma(home, r'@override\s*Widget build\(BuildContext context\) \{\s*super\.build\(context\);',
            "@override\n"
            "  Widget build(BuildContext context) {\n"
            "    super.build(context);\n"
            "    // Mohr Remote: a versão TI exige login com a conta do painel.\n"
            "    if (bind.isIncomingOnly()) return _mohrBuild(context);\n"
            "    MohrSession.init();\n"
            "    return Obx(() => MohrSession.loggedIn.value\n"
            "        ? _mohrBuild(context)\n"
            "        : const MohrLoginPage());\n"
            "  }\n"
            "\n"
            "  Widget _mohrBuild(BuildContext context) {", "trava de login na tela inicial")
    sub_uma(home, r'child: loadLogo\(\),\s*\),',
            "child: loadLogo(),\n      ),\n      if (!isIncomingOnly) const MohrSessionBar(),",
            "barra do técnico logado")
    # Versão do usuário: botão "Pedir ajuda à TI" logo abaixo do código de acesso.
    sub_uma(home, r'if \(!isOutgoingOnly && !isIncomingOnly\) buildPasswordBoard\(context\),',
            "if (!isOutgoingOnly && !isIncomingOnly) buildPasswordBoard(context),\n"
            "      if (isIncomingOnly) const MohrHelpButton(),", "botão Pedir ajuda")
    # Versão TI: lista de computadores do painel no lugar da lista de recentes (que vira uma aba).
    conexao = raiz / "flutter/lib/desktop/pages/connection_page.dart"
    sub_uma(conexao, re.escape("import 'package:flutter_hbb/models/peer_model.dart';"),
            "import 'package:flutter_hbb/models/peer_model.dart';\n"
            "import 'package:flutter_hbb/desktop/pages/mohr_login.dart';", "import da lista de computadores")
    sub_uma(conexao, r'Expanded\(child: PeerTabPage\(\)\),',
            "Expanded(child: MohrDevicesPanel(recent: PeerTabPage())),", "lista de computadores do painel")
    # Celular: login obrigatório e aba "Computadores" (lista do painel) como primeira aba.
    celular = raiz / "flutter/lib/mobile/pages/home_page.dart"
    sub_uma(celular, re.escape("import 'connection_page.dart';"),
            "import 'connection_page.dart';\nimport 'package:flutter_hbb/desktop/pages/mohr_login.dart';",
            "import da tela de login (celular)")
    sub_uma(celular, r'_pages\.clear\(\);\s*if \(!bind\.isIncomingOnly\(\)\) \{',
            "_pages.clear();\n    if (!bind.isIncomingOnly()) {\n      _pages.add(MohrPaginaComputadores());",
            "aba Computadores (celular)")
    sub_uma(celular, r'Widget build\(BuildContext context\) \{\s*return WillPopScope\(',
            "Widget build(BuildContext context) {\n"
            "    // Mohr Remote: o app do celular exige login com a conta do painel.\n"
            "    MohrSession.init();\n"
            "    return Obx(() => !MohrSession.loggedIn.value\n"
            "        ? const Scaffold(body: SafeArea(child: MohrLoginPage()))\n"
            "        : WillPopScope(", "trava de login (celular)")
    sub_uma(celular, r'body: _pages\.elementAt\(_selectedIndex\),\s*\)\);\s*\}',
            "body: _pages.elementAt(_selectedIndex),\n        )));\n  }", "fecha a trava de login (celular)")


def patch_android(raiz: Path):
    """App Android da TI: nome, identificador próprio (não conflita com o RustDesk oficial) e ícones."""
    app = raiz / "flutter/android/app"
    sub_uma(app / "src/main/AndroidManifest.xml", r'android:label="RustDesk"(?=\s*android:roundIcon)',
            f'android:label="{NOME_EXIBICAO}"', "nome do app (manifest)")
    sub_uma(app / "src/main/res/values/strings.xml", r'<string name="app_name">RustDesk</string>',
            f'<string name="app_name">{NOME_EXIBICAO}</string>', "nome do app (strings)")
    sub_uma(app / "build.gradle", r'applicationId "com\.carriez\.flutter_hbb"',
            'applicationId "br.com.maxmohr.mohrremote"', "identificador do app")
    import io
    from PIL import Image
    simbolo = Image.open(io.BytesIO(imagem_marca("icone-1024.png"))).convert("RGBA")
    res = app / "src/main/res"
    for pasta, lado in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        destino = res / f"mipmap-{pasta}"
        # Ícone legado: símbolo sobre fundo branco arredondado.
        fundo = Image.new("RGBA", (lado, lado), (255, 255, 255, 255))
        fundo.alpha_composite(simbolo.resize((lado, lado), Image.LANCZOS))
        fundo.save(destino / "ic_launcher.png")
        fundo.save(destino / "ic_launcher_round.png")
        # Ícone adaptativo (108 dp): símbolo dentro da área segura central.
        grande = round(lado * 108 / 48)
        frente = Image.new("RGBA", (grande, grande), (0, 0, 0, 0))
        miolo = round(grande * 0.72)
        frente.alpha_composite(simbolo.resize((miolo, miolo), Image.LANCZOS), ((grande - miolo) // 2, (grande - miolo) // 2))
        frente.save(destino / "ic_launcher_foreground.png")
        print(f"ok  ícones Android mipmap-{pasta}")


def patch_metadados(raiz: Path):
    rc = raiz / "flutter/windows/runner/Runner.rc"
    sub_uma(rc, r'VALUE "FileDescription", "[^"]*"',
            f'VALUE "FileDescription", "{NOME_EXIBICAO}"', "FileDescription")
    sub_uma(rc, r'VALUE "ProductName", "[^"]*"',
            f'VALUE "ProductName", "{NOME_EXIBICAO}"', "ProductName")
    sub_uma(rc, r'VALUE "CompanyName", "[^"]*"',
            f'VALUE "CompanyName", "{EMPRESA}"', "CompanyName")
    # LegalCopyright fica como está: o código é da Purslane (AGPL-3.0).


AZUL_ESCURO = (20, 33, 110)     # #14216E
AZUL_MEDIO = (47, 99, 212)      # #2F63D4
AZUL_CLARO = (110, 166, 230)    # #6EA6E6


def desenhar_simbolo(n: int = 1024):
    """Ícone Mohr Remote: quadrado arredondado em degradê azul, "M" branco geométrico e,
    no vão do M, o triângulo azul-claro que remete ao símbolo da Max Mohr."""
    from PIL import Image, ImageDraw
    s = n / 1024
    # Degradê diagonal (canto superior esquerdo escuro -> inferior direito médio)
    grad = Image.new("RGBA", (n, n))
    px = grad.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(AZUL_ESCURO, AZUL_MEDIO)) + (255,)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((40 * s, 40 * s, n - 40 * s, n - 40 * s), radius=230 * s, fill=255)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)

    def p(pts):
        return [(x * s, y * s) for x, y in pts]

    # "M" em um único polígono (pernas de 110 px, diagonais encontrando-se no centro)
    d.polygon(p([(262, 742), (262, 282), (382, 282), (512, 486), (642, 282), (762, 282),
                 (762, 742), (652, 742), (652, 478), (512, 694), (372, 478), (372, 742)]), fill="white")
    # Triângulo azul-claro no vão superior do M
    d.polygon(p([(428, 282), (596, 282), (512, 414)]), fill=AZUL_CLARO + (255,))
    return img


def desenhar_logo_horizontal(icone):
    """Logo do cabeçalho do app (600x120): ícone + "Mohr Remote" / "MAX MOHR"."""
    from PIL import Image, ImageDraw, ImageFont

    def fonte(nomes, tamanho):
        for nome in nomes:
            try:
                return ImageFont.truetype(nome, tamanho)
            except OSError:
                continue
        return None

    titulo = fonte(["segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"], 50)
    sub = fonte(["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"], 20)
    if not titulo or not sub:
        print("aviso: nenhuma fonte encontrada — logo horizontal não gerado")
        return None
    img = Image.new("RGBA", (600, 120), (0, 0, 0, 0))
    img.paste(icone.resize((112, 112), Image.LANCZOS), (4, 4))
    d = ImageDraw.Draw(img)
    d.text((132, 20), "Mohr", font=titulo, fill=AZUL_MEDIO + (255,))
    largura = d.textlength("Mohr ", font=titulo)
    d.text((132 + largura, 20), "Remote", font=titulo, fill=AZUL_CLARO + (255,))
    d.text((134, 80), "M A X   M O H R", font=sub, fill=(128, 140, 170, 255))
    return img


def patch_icones(raiz: Path):
    marca = raiz / "mohr/marca"
    logo = marca / "logo.png"
    from PIL import Image  # pip install pillow

    import io
    if logo.exists():
        img = Image.open(logo).convert("RGBA")
        if img.width != img.height or img.width < 256:
            erros.append(f"{logo}: precisa ser quadrado e >= 256 px (ideal 1024x1024); veio {img.size}")
            return
    else:
        # Símbolo oficial Max Mohr (favicon.svg do padrão visual v1.0, renderizado em 1024 px).
        print("usando o símbolo oficial Max Mohr (padrão visual v1.0)")
        img = Image.open(io.BytesIO(imagem_marca("icone-1024.png"))).convert("RGBA")

    def png(dst: Path, lado: int):
        img.resize((lado, lado), Image.LANCZOS).save(dst)
        print(f"ok  {dst.relative_to(raiz)} ({lado}px)")

    def ico(dst: Path, lados):
        img.save(dst, format="ICO", sizes=[(s, s) for s in lados])
        print(f"ok  {dst.relative_to(raiz)}")

    ico(raiz / "res/icon.ico", [16, 24, 32, 48, 64, 128, 256])
    ico(raiz / "res/tray-icon.ico", [16, 20, 24, 32, 48])
    ico(raiz / "flutter/windows/runner/resources/app_icon.ico", [16, 24, 32, 48, 64, 128, 256])
    png(raiz / "res/icon.png", 512)
    png(raiz / "res/32x32.png", 32)
    png(raiz / "res/64x64.png", 64)
    png(raiz / "res/128x128.png", 128)
    png(raiz / "res/128x128@2x.png", 256)
    # O app Flutter prefere assets/icon.png a assets/icon.svg (common.dart: loadIcon)
    png(raiz / "flutter/assets/icon.png", 256)

    # Logo do cabeçalho (máx. 300x60 na tela). Opcional: mohr/marca/logo-horizontal.png
    # Logo horizontal oficial Max Mohr: colorido no tema claro, branco no tema escuro.
    claro = imagem_marca("logo_light.png")
    escuro = imagem_marca("logo_dark.png")
    for nome, dados in [("logo.png", claro), ("logo_light.png", claro), ("logo_dark.png", escuro)]:
        (raiz / "flutter/assets" / nome).write_bytes(dados)
        print(f"ok  flutter/assets/{nome}")


# Imagens oficiais do padrão visual Max Mohr v1.0 (SVG do Marketing renderizados em PNG),
# publicadas no painel. O build baixa e confere o SHA-256: se não bater, o build falha.
IMAGENS_MARCA = {
    "icone-1024.png": "c4ac29be38201ea19f30953a54c8b0a44b8d23573152017eafef26566c904382",
    "logo_light.png": "c64f78bdd9f24ef1ecae9f0a7d9f063f92fb0b74b7c26d77b8def74e03612221",
    "logo_dark.png": "cec5ae407654706580474429eaaaaab6975ef54950f3d77a078c320b8f70c83c",
}


def imagem_marca(nome: str) -> bytes:
    import hashlib
    import urllib.request
    with urllib.request.urlopen(f"{PAINEL}/marca/{nome}", timeout=60) as resposta:
        dados = resposta.read()
    if hashlib.sha256(dados).hexdigest() != IMAGENS_MARCA[nome]:
        raise RuntimeError(f"{nome}: SHA-256 não confere")
    return dados

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raiz", default=".")
    ap.add_argument("--variante", default=os.environ.get("MOHR_VARIANTE", "ti"), choices=sorted(FIXAS_POR_VARIANTE))
    args = ap.parse_args()
    raiz = Path(args.raiz).resolve()
    print(f"Variante: {args.variante}")
    patch_config(raiz, args.variante)
    patch_codigo(raiz)
    patch_layout(raiz)
    patch_login(raiz)
    patch_metadados(raiz)
    patch_icones(raiz)
    if args.variante == "android":
        patch_android(raiz)
    if erros:
        print("\nFALHOU:", *erros, sep="\n  ")
        sys.exit(1)
    print(f"\nMarca aplicada: {APP_NAME} -> {SERVIDOR_ID}")


if __name__ == "__main__":
    main()
