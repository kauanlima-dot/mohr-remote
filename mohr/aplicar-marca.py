#!/usr/bin/env python3
"""Aplica a marca Max Mohr (Mohr Remote) numa árvore do RustDesk.

Roda no CI depois do checkout (com submódulos) e antes do build.
Altera só a cópia de trabalho; nada é commitado no submódulo hbb_common.

Uso:  python mohr/aplicar-marca.py [--raiz .]
Falha (exit 1) se algum ponto de patch não for encontrado — melhor quebrar o
build do que gerar um cliente apontando para o servidor público da RustDesk.
"""
import argparse
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

# Valores padrão (o usuário/script ainda pode mudar; para travar, veja OVERWRITE no LEIA-ME)
PADROES = {
    "approve-mode": "click",              # aceite por clique
    "verification-method": "use-temporary-password",
    "allow-websocket": "N",
    "relay-server": SERVIDOR_RELAY,
    "enable-check-update": "N",           # não oferecer o RustDesk oficial
    "allow-auto-update": "N",
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


def patch_config(raiz: Path):
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
    pares = ", ".join(f"({rust_str(k)}.to_owned(), {rust_str(v)}.to_owned())"
                      for k, v in PADROES.items())
    sub_uma(cfg,
            r'pub static ref DEFAULT_SETTINGS: RwLock<HashMap<String, String>> = Default::default\(\);',
            f'pub static ref DEFAULT_SETTINGS: RwLock<HashMap<String, String>> = '
            f'RwLock::new(HashMap::from([{pares}]));',
            "DEFAULT_SETTINGS")


def patch_metadados(raiz: Path):
    rc = raiz / "flutter/windows/runner/Runner.rc"
    sub_uma(rc, r'VALUE "FileDescription", "[^"]*"',
            f'VALUE "FileDescription", "{NOME_EXIBICAO}"', "FileDescription")
    sub_uma(rc, r'VALUE "ProductName", "[^"]*"',
            f'VALUE "ProductName", "{NOME_EXIBICAO}"', "ProductName")
    sub_uma(rc, r'VALUE "CompanyName", "[^"]*"',
            f'VALUE "CompanyName", "{EMPRESA}"', "CompanyName")
    # LegalCopyright fica como está: o código é da Purslane (AGPL-3.0).


def desenhar_simbolo():
    """Símbolo Max Mohr (o "M" de triângulos azuis) sobre círculo branco, 1024x1024."""
    from PIL import Image, ImageDraw
    n = 1024
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((16, 16, n - 16, n - 16), fill=(255, 255, 255, 255))
    # Coordenadas do símbolo no logo original (caixa 132x108), convertidas para o ícone
    ox, oy, esc = 158, 92, 4.6
    dx = (n - 132 * esc) / 2
    dy = (n - 108 * esc) / 2

    def p(pts):
        return [(dx + (x - ox) * esc, dy + (y - oy) * esc) for x, y in pts]

    d.polygon(p([(160, 92), (188, 92), (248, 200), (220, 200)]), fill="#1E2A8A")  # barra
    d.polygon(p([(224, 135), (290, 135), (252, 170)]), fill="#6EA6E6")            # triângulo claro
    d.polygon(p([(160, 158), (160, 200), (200, 200)]), fill="#2F63D4")            # esquerda
    d.polygon(p([(290, 158), (290, 200), (250, 200)]), fill="#1B3FC0")            # direita
    return img


def patch_icones(raiz: Path):
    marca = raiz / "mohr/marca"
    logo = marca / "logo.png"
    from PIL import Image  # pip install pillow

    if logo.exists():
        img = Image.open(logo).convert("RGBA")
        if img.width != img.height or img.width < 256:
            erros.append(f"{logo}: precisa ser quadrado e >= 256 px (ideal 1024x1024); veio {img.size}")
            return
    else:
        print("mohr/marca/logo.png não existe — usando o símbolo Max Mohr desenhado pelo script")
        img = desenhar_simbolo()

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
    horiz = marca / "logo-horizontal.png"
    if horiz.exists():
        (raiz / "flutter/assets/logo.png").write_bytes(horiz.read_bytes())
        print("ok  flutter/assets/logo.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raiz", default=".")
    raiz = Path(ap.parse_args().raiz).resolve()
    patch_config(raiz)
    patch_metadados(raiz)
    patch_icones(raiz)
    if erros:
        print("\nFALHOU:", *erros, sep="\n  ")
        sys.exit(1)
    print(f"\nMarca aplicada: {APP_NAME} -> {SERVIDOR_ID}")


if __name__ == "__main__":
    main()
