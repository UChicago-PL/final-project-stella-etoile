# coded using the aid of ChatGPT (because I suck at generating graphs)

import argparse
import itertools
import os
import re
import subprocess
from dataclasses import dataclass
from typing import Dict, List, Tuple

import pandas as pd
import matplotlib.pyplot as plt


DUEL_RE = re.compile(
    r"Duel complete\.\s*X wins=(\d+)\s*O wins=(\d+)\s*draws=(\d+)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Result:
    x_wins: int
    o_wins: int
    draws: int

    @property
    def games(self) -> int:
        return self.x_wins + self.o_wins + self.draws

    @property
    def x_winrate(self) -> float:
        return self.x_wins / self.games if self.games else 0.0

    @property
    def o_winrate(self) -> float:
        return self.o_wins / self.games if self.games else 0.0

    @property
    def drawrate(self) -> float:
        return self.draws / self.games if self.games else 0.0

    @property
    def x_lossrate(self) -> float:
        return self.o_winrate

    @property
    def o_lossrate(self) -> float:
        return self.x_winrate

    @property
    def x_win_or_draw(self) -> float:
        return (self.x_wins + self.draws) / self.games if self.games else 0.0

    @property
    def o_win_or_draw(self) -> float:
        return (self.o_wins + self.draws) / self.games if self.games else 0.0


def label_from_path(p: str) -> str:
    b = os.path.basename(p)
    return b[:-5] if b.lower().endswith(".json") else b


def run_one_duel(
    cabal_project_dir: str,
    menace_exe: str,
    x_json: str,
    o_json: str,
    games: int,
    seed: int,
    symmetry: bool,
    extra_args: List[str],
) -> Tuple[str, Result]:
    cmd = [
        "cabal",
        "run",
        menace_exe,
        "--",
        "duel",
        "--x-load",
        x_json,
        "--o-load",
        o_json,
        "--games",
        str(games),
        "--seed",
        str(seed),
    ]
    if symmetry:
        cmd.append("--symmetry")
    cmd += extra_args

    p = subprocess.run(
        cmd,
        cwd=cabal_project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    out = p.stdout

    m = DUEL_RE.search(out)
    if not m:
        raise RuntimeError(
            "Could not parse duel result.\n"
            f"Command: {' '.join(cmd)}\n"
            "Expected a line like:\n"
            "  Duel complete. X wins=696 O wins=20 draws=284\n"
            "Actual output:\n"
            + out
        )

    xw, ow, dr = map(int, m.groups())
    return out, Result(xw, ow, dr)


def draw_heatmap_on_ax(
    ax,
    df_colors: pd.DataFrame,
    df_text: pd.DataFrame,
    title: str,
    fmt: str = ".3f",
    base_font: int = 12,
):
    nrows, ncols = df_colors.shape
    im = ax.imshow(df_colors.values, aspect="auto")

    ax.set_xticks(range(ncols))
    ax.set_xticklabels(df_colors.columns, rotation=45, ha="right")
    ax.set_yticks(range(nrows))
    ax.set_yticklabels(df_colors.index)
    ax.set_title(title)

    main_font = max(7, min(base_font, int(22 / max(nrows, ncols) * 6)))
    sub_font = max(5, int(main_font * 0.65))

    for i in range(nrows):
        for j in range(ncols):
            vtxt = df_text.iat[i, j]

            if isinstance(vtxt, str) and "\n" in vtxt:
                top, bottom = vtxt.split("\n", 1)

                ax.text(
                    j,
                    i - 0.15,
                    top,
                    ha="center",
                    va="center",
                    fontsize=main_font,
                    fontweight="bold",
                )

                ax.text(
                    j,
                    i + 0.18,
                    bottom,
                    ha="center",
                    va="center",
                    fontsize=sub_font,
                )
            else:
                if pd.isna(vtxt):
                    txt = ""
                elif isinstance(vtxt, (int, float)):
                    txt = format(float(vtxt), fmt)
                else:
                    try:
                        txt = format(float(vtxt), fmt)
                    except Exception:
                        txt = str(vtxt)

                ax.text(
                    j,
                    i,
                    txt,
                    ha="center",
                    va="center",
                    fontsize=main_font,
                )

    return im


def make_wdl_cell_text(rate: float, win: float, draw: float, loss: float) -> str:
    return f"{rate:.3f}\n{win:.3f}/{draw:.3f}/{loss:.3f}"


def make_wd_cell_text(win_draw: float, win: float, draw: float, loss: float) -> str:
    return f"{win_draw:.3f}\n{win:.3f}/{draw:.3f}/{loss:.3f}"


def save_single_heatmap(
    df_colors: pd.DataFrame,
    df_text: pd.DataFrame,
    title: str,
    out_png: str,
    cbar_label: str,
):
    n = max(len(df_colors.index), len(df_colors.columns))
    fig_w = max(10, 1.6 * n)
    fig_h = max(8, 1.3 * n)

    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    im = draw_heatmap_on_ax(
        ax,
        df_colors=df_colors,
        df_text=df_text,
        title=title,
        base_font=12,
    )
    cbar = fig.colorbar(im, ax=ax)
    cbar.set_label(cbar_label)
    fig.tight_layout()
    fig.savefig(out_png, dpi=250)
    plt.close(fig)


def save_four_panel(
    panes: List[Tuple[pd.DataFrame, pd.DataFrame, str, str]],
    out_png: str,
):
    n = max(max(len(p[0].index), len(p[0].columns)) for p in panes)
    fig_w = max(16, 2.2 * n)
    fig_h = max(12, 1.8 * n)

    fig, axes = plt.subplots(2, 2, figsize=(fig_w, fig_h), constrained_layout=True)

    for idx, (dfc, dft, title, cbar_label) in enumerate(panes):
        r = idx // 2
        c = idx % 2
        ax = axes[r][c]
        im = draw_heatmap_on_ax(
            ax,
            df_colors=dfc,
            df_text=dft,
            title=title,
            base_font=11,
        )
        cbar = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        cbar.set_label(cbar_label)

    fig.savefig(out_png, dpi=250)
    plt.close(fig)


def save_two_panel(
    left: Tuple[pd.DataFrame, pd.DataFrame, str, str],
    right: Tuple[pd.DataFrame, pd.DataFrame, str, str],
    out_png: str,
):
    dfc_l, dft_l, title_l, cbar_l = left
    dfc_r, dft_r, title_r, cbar_r = right

    n = max(
        len(dfc_l.index),
        len(dfc_l.columns),
        len(dfc_r.index),
        len(dfc_r.columns),
    )
    fig_w = max(16, 3.0 * n)
    fig_h = max(8, 1.6 * n)

    fig, axes = plt.subplots(1, 2, figsize=(fig_w, fig_h), constrained_layout=True)

    im0 = draw_heatmap_on_ax(
        axes[0],
        df_colors=dfc_l,
        df_text=dft_l,
        title=title_l,
        base_font=12,
    )
    cbar0 = fig.colorbar(im0, ax=axes[0], fraction=0.046, pad=0.04)
    cbar0.set_label(cbar_l)

    im1 = draw_heatmap_on_ax(
        axes[1],
        df_colors=dfc_r,
        df_text=dft_r,
        title=title_r,
        base_font=12,
    )
    cbar1 = fig.colorbar(im1, ax=axes[1], fraction=0.046, pad=0.04)
    cbar1.set_label(cbar_r)

    fig.savefig(out_png, dpi=250)
    plt.close(fig)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        required=True,
        help="Path to the Haskell project directory (contains the .cabal file).",
    )
    ap.add_argument(
        "--exe",
        default="menace-hs",
        help="Cabal executable name (default: menace-hs).",
    )
    ap.add_argument("--games", type=int, default=1000, help="Games per duel (default: 1000).")
    ap.add_argument("--seed", type=int, default=1, help="Seed (default: 1).")
    ap.add_argument("--symmetry", action="store_true", help="Pass --symmetry to the duel command.")
    ap.add_argument(
        "--outname",
        required=True,
        help="Name for this benchmark run. Outputs will go into outdir/outname/.",
    )
    ap.add_argument("--outdir", default="duel_results", help="Base output directory (default: duel_results).")
    ap.add_argument(
        "--extra",
        nargs="*",
        default=[],
        help="Extra args passed to the Haskell command after duel (advanced).",
    )
    ap.add_argument(
        "jsons",
        nargs="+",
        help="MENACE JSON files to include (e.g. trained/menace-1000.json trained/menace-50000-sym.json ...).",
    )
    args = ap.parse_args()

    safe_outname = re.sub(r"[^A-Za-z0-9._-]+", "_", args.outname).strip("_")
    if not safe_outname:
        raise SystemExit("Error: --outname became empty after sanitization. Pick a different name.")

    run_dir = os.path.join(args.outdir, safe_outname)
    os.makedirs(run_dir, exist_ok=True)
    logs_dir = os.path.join(run_dir, "logs")
    os.makedirs(logs_dir, exist_ok=True)

    labels = [label_from_path(p) for p in args.jsons]
    label_to_path = dict(zip(labels, args.jsons))

    results: Dict[Tuple[str, str], Result] = {}

    pairs = list(itertools.product(labels, labels))
    total = len(pairs)

    for idx, (x_lab, o_lab) in enumerate(pairs, 1):
        x_path = label_to_path[x_lab]
        o_path = label_to_path[o_lab]
        print(f"[{idx}/{total}] X={x_lab} vs O={o_lab}", flush=True)

        out, res = run_one_duel(
            cabal_project_dir=args.project_dir,
            menace_exe=args.exe,
            x_json=x_path,
            o_json=o_path,
            games=args.games,
            seed=args.seed,
            symmetry=args.symmetry,
            extra_args=args.extra,
        )
        results[(x_lab, o_lab)] = res

        log_path = os.path.join(logs_dir, f"duel__X={x_lab}__O={o_lab}.log")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(out)

    xwr = pd.DataFrame(index=labels, columns=labels, dtype=float)
    owr = pd.DataFrame(index=labels, columns=labels, dtype=float)
    drw = pd.DataFrame(index=labels, columns=labels, dtype=float)
    xwd = pd.DataFrame(index=labels, columns=labels, dtype=float)
    owd = pd.DataFrame(index=labels, columns=labels, dtype=float)

    xwr_text = pd.DataFrame(index=labels, columns=labels, dtype=object)
    owr_text = pd.DataFrame(index=labels, columns=labels, dtype=object)
    drw_text = pd.DataFrame(index=labels, columns=labels, dtype=object)
    xwd_text = pd.DataFrame(index=labels, columns=labels, dtype=object)
    owd_text = pd.DataFrame(index=labels, columns=labels, dtype=object)

    for x_lab in labels:
        for o_lab in labels:
            r = results[(x_lab, o_lab)]

            xwr.loc[x_lab, o_lab] = r.x_winrate
            owr.loc[x_lab, o_lab] = r.o_winrate
            drw.loc[x_lab, o_lab] = r.drawrate
            xwd.loc[x_lab, o_lab] = r.x_win_or_draw
            owd.loc[x_lab, o_lab] = r.o_win_or_draw

            xwr_text.loc[x_lab, o_lab] = make_wdl_cell_text(r.x_winrate, r.x_winrate, r.drawrate, r.x_lossrate)
            owr_text.loc[x_lab, o_lab] = make_wdl_cell_text(
                r.o_winrate, r.o_winrate, r.drawrate, 1.0 - (r.o_winrate + r.drawrate)
            )
            drw_text.loc[x_lab, o_lab] = make_wdl_cell_text(r.drawrate, r.x_winrate, r.drawrate, r.o_winrate)

            # win+draw tiles: first line is win+draw, second line is W/D/L for that player
            xwd_text.loc[x_lab, o_lab] = make_wd_cell_text(r.x_win_or_draw, r.x_winrate, r.drawrate, r.x_lossrate)
            owd_text.loc[x_lab, o_lab] = make_wd_cell_text(r.o_win_or_draw, r.o_winrate, r.drawrate, r.o_lossrate)

    xwr.to_csv(os.path.join(run_dir, "x_winrate_matrix.csv"))
    owr.to_csv(os.path.join(run_dir, "o_winrate_matrix.csv"))
    drw.to_csv(os.path.join(run_dir, "drawrate_matrix.csv"))
    xwd.to_csv(os.path.join(run_dir, "x_win_or_draw_matrix.csv"))
    owd.to_csv(os.path.join(run_dir, "o_win_or_draw_matrix.csv"))

    xwr_png = os.path.join(run_dir, "x_winrate_heatmap.png")
    owr_png = os.path.join(run_dir, "o_winrate_heatmap.png")
    drw_png = os.path.join(run_dir, "drawrate_heatmap.png")
    xwd_png = os.path.join(run_dir, "x_win_or_draw_heatmap.png")
    owd_png = os.path.join(run_dir, "o_win_or_draw_heatmap.png")
    combined_png = os.path.join(run_dir, "heatmaps_2x2.png")
    wd_side_by_side_png = os.path.join(run_dir, "win_draw_side_by_side.png")

    save_single_heatmap(
        df_colors=xwr,
        df_text=xwr_text,
        title="X win rate",
        out_png=xwr_png,
        cbar_label="X win rate",
    )
    save_single_heatmap(
        df_colors=owr,
        df_text=owr_text,
        title="O win rate",
        out_png=owr_png,
        cbar_label="O win rate",
    )
    save_single_heatmap(
        df_colors=drw,
        df_text=drw_text,
        title="Draw rate",
        out_png=drw_png,
        cbar_label="Draw rate",
    )
    save_single_heatmap(
        df_colors=xwd,
        df_text=xwd_text,
        title="X win+draw",
        out_png=xwd_png,
        cbar_label="X win+draw",
    )
    save_single_heatmap(
        df_colors=owd,
        df_text=owd_text,
        title="O win+draw",
        out_png=owd_png,
        cbar_label="O win+draw",
    )

    save_four_panel(
        panes=[
            (xwr, xwr_text, "X win rate"),
            (owr, owr_text, "O win rate"),
            (drw, drw_text, "Draw rate"),
            (xwd, xwd_text, "X win+draw"),
        ],
        out_png=combined_png,
    )

    save_two_panel(
        left=(xwd, xwd_text, "X win+draw"),
        right=(owd, owd_text, "O win+draw"),
        out_png=wd_side_by_side_png,
    )

    rows = []
    for (x_lab, o_lab), r in results.items():
        rows.append(
            {
                "X": x_lab,
                "O": o_lab,
                "x_wins": r.x_wins,
                "o_wins": r.o_wins,
                "draws": r.draws,
                "games": r.games,
                "x_winrate": r.x_winrate,
                "o_winrate": r.o_winrate,
                "drawrate": r.drawrate,
                "x_win_or_draw": r.x_win_or_draw,
                "o_win_or_draw": r.o_win_or_draw,
            }
        )
    pd.DataFrame(rows).sort_values(["X", "O"]).to_csv(
        os.path.join(run_dir, "duel_counts.csv"), index=False
    )

    meta_path = os.path.join(run_dir, "run_meta.txt")
    with open(meta_path, "w", encoding="utf-8") as f:
        f.write(f"outname={args.outname}\n")
        f.write(f"project_dir={args.project_dir}\n")
        f.write(f"exe={args.exe}\n")
        f.write(f"games={args.games}\n")
        f.write(f"seed={args.seed}\n")
        f.write(f"symmetry={args.symmetry}\n")
        f.write(f"jsons={' '.join(args.jsons)}\n")

    print("\nWrote:")
    print(f"  {os.path.join(run_dir, 'x_winrate_matrix.csv')}")
    print(f"  {os.path.join(run_dir, 'o_winrate_matrix.csv')}")
    print(f"  {os.path.join(run_dir, 'drawrate_matrix.csv')}")
    print(f"  {os.path.join(run_dir, 'x_win_or_draw_matrix.csv')}")
    print(f"  {os.path.join(run_dir, 'o_win_or_draw_matrix.csv')}")
    print(f"  {xwr_png}")
    print(f"  {owr_png}")
    print(f"  {drw_png}")
    print(f"  {xwd_png}")
    print(f"  {owd_png}")
    print(f"  {combined_png}")
    print(f"  {wd_side_by_side_png}")
    print(f"  {os.path.join(run_dir, 'duel_counts.csv')}")
    print(f"  {meta_path}")
    print(f"  logs in {logs_dir}/")


if __name__ == "__main__":
    main()