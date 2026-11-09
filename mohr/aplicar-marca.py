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

# Travadas: o usuário não consegue mudar (aparecem bloqueadas na tela de configurações).
TRAVADAS = {
    "custom-rendezvous-server": SERVIDOR_ID,
    "relay-server": SERVIDOR_RELAY,
    "key": CHAVE,
    "approve-mode": "click",              # aceite por clique
    "allow-websocket": "N",
}
# Padrão: valem até alguém mudar.
PADROES = {
    "verification-method": "use-temporary-password",
    "enable-check-update": "N",           # não oferecer o RustDesk oficial
    "allow-auto-update": "N",
}
# Por variante do build (env MOHR_VARIANTE ou --variante):
#   usuario: só recebe acesso, sem tela de conectar e sem configurações
#   ti:      cliente completo para a equipe de suporte
FIXAS_POR_VARIANTE = {
    "usuario": {"conn-type": "incoming", "disable-settings": "Y"},
    "ti": {},
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

    if logo.exists():
        img = Image.open(logo).convert("RGBA")
        if img.width != img.height or img.width < 256:
            erros.append(f"{logo}: precisa ser quadrado e >= 256 px (ideal 1024x1024); veio {img.size}")
            return
    else:
        print("mohr/marca/logo.png não existe — usando o ícone Mohr Remote desenhado pelo script")
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
    else:
        gerado = desenhar_logo_horizontal(img)
        if gerado:
            gerado.save(raiz / "flutter/assets/logo.png")
            print("ok  flutter/assets/logo.png (gerado)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raiz", default=".")
    ap.add_argument("--variante", default=os.environ.get("MOHR_VARIANTE", "ti"), choices=sorted(FIXAS_POR_VARIANTE))
    args = ap.parse_args()
    raiz = Path(args.raiz).resolve()
    print(f"Variante: {args.variante}")
    patch_config(raiz, args.variante)
    patch_metadados(raiz)
    patch_icones(raiz)
    if erros:
        print("\nFALHOU:", *erros, sep="\n  ")
        sys.exit(1)
    print(f"\nMarca aplicada: {APP_NAME} -> {SERVIDOR_ID}")


if __name__ == "__main__":
    main()
