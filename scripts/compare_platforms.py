#!/usr/bin/env python3
"""Gera uma tabela Markdown comparando os resultados do ORFS entre plataformas.

Uso: python3 scripts/compare_platforms.py <WORK_HOME> <DESIGN_NICKNAME> <plat1> [plat2 ...]

Lê os relatórios finais (6_finish.rpt) e o log do roteamento. Os formatos do
ORFS mudam entre versões; se um valor não for encontrado aparece "?" e deve
ser preenchido à mão a partir dos relatórios.
"""
import re
import sys
from pathlib import Path


def find(pattern, text, group=1, flags=re.IGNORECASE | re.MULTILINE):
    m = re.search(pattern, text, flags)
    return m.group(group) if m else "?"


def read(path):
    try:
        return Path(path).read_text(errors="ignore")
    except OSError:
        return ""


def metrics(work, nick, plat):
    rep = Path(work) / "reports" / plat / nick / "base"
    log = Path(work) / "logs" / plat / nick / "base"
    fin = read(rep / "6_finish.rpt")
    synth = read(rep / "synth_stat.txt")
    return {
        "Área do design (µm²)": find(r"Design area\s+([\d.]+)\s*u\^2", fin),
        "Utilização do core (%)": find(r"Design area\s+[\d.]+\s*u\^2\s+([\d.]+)%", fin),
        "Células (síntese)": find(r"Number of cells:\s*(\d+)", synth),
        "WNS (setup)": find(r"^wns\s+(?:max\s+)?(-?[\d.]+)", fin),
        "TNS (setup)": find(r"^tns\s+(?:max\s+)?(-?[\d.]+)", fin),
        "Pior slack": find(r"worst slack\s+(?:max\s+)?(-?[\d.]+)", fin),
        "Potência total (W)": find(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)", fin),
        "Relatório": str(rep / "6_finish.rpt") if fin else "(não encontrado)",
        "Log final": str(log) if log.exists() else "(não encontrado)",
    }


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    work, nick, plats = sys.argv[1], sys.argv[2], sys.argv[3:]
    data = {p: metrics(work, nick, p) for p in plats}
    keys = list(next(iter(data.values())).keys())

    print("# Comparação entre plataformas\n")
    print("| Métrica | " + " | ".join(plats) + " |")
    print("|---|" + "---|" * len(plats))
    for k in keys:
        print(f"| {k} | " + " | ".join(data[p][k] for p in plats) + " |")
    print("\n> Valores extraídos automaticamente; confira nos relatórios do ORFS.")


if __name__ == "__main__":
    main()
