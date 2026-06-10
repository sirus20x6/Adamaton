# babyllm — p50k_base re-run of TST + plasticity (2026-05-27)

Self-contained writeup so this can be resumed from the Adamaton side. All training
lives in `/thearray/git/babyllm`; runs are visible on the dashboard at
**https://deepresearch.local/experiments** (pushed via `babyllm/scripts/import_runs.py`,
HTTP `localhost:7272`). This is **not** ClearML.

## Why this run

Two methods — Token Superposition Training (TST) and a 6-variant continual-learning
("plasticity") sweep — had been evaluated on DCLM tokenized with **qwen3.6 (vocab 248077)**.
At that vocab the d512/L12 model is ~292M params but the **compute trunk is only ~36M** —
embeddings + untied head dominate, so most FLOPs are a vocab projection and the trunk
(where TST/plasticity actually act) is starved. Hypothesis under test: *we hadn't shrunk the
vocab enough for the trunk to dominate, so the methods couldn't show their benefit.*

Fix: retokenize the **same DCLM substrate** with **tiktoken `p50k_base` (vocab 50281)**,
shrinking embed+head ~4.9×. Everything else (steps, dims, hyperparameters) held identical so
the comparison isolates the param-split change.

- TST model: 292M (embed-dominant) → **~88M (trunk-dominant)**.
- Plasticity model: ~201M → **~49M** (d384/L6, embed 19.3M).

## Dataset (new)

Built by `babyllm/scripts/build_dclm_fwedu.py --encoding p50k_base` (tiktoken used directly →
byte-exact; deliberately avoids the byte-level-BPE reproduction trap). Caches under
`babyllm/data/cache/`:

| cache | tokens | manifest vocab_size |
|---|---|---|
| `p50k_dclm_train` | 1.00B | 50281 |
| `p50k_dclm_val` / `_test` | 20M / 20M | 50281 |
| `p50k_fwedu_train` | 1.00B | 50281 |
| `p50k_fwedu_val` / `_test` | 20M / 20M | 50281 |

Disjoint test→val→train carve per source. `build_dataloader` reads `vocab_size` from the
manifest and forces `model.vocab_size` to it.

> **Caveat for all ppl below:** perplexity is **not comparable across tokenizers** (p50k and
> qwen split text into different token counts / per-token entropy). Only the *within-p50k*
> baseline-vs-TST delta and the plasticity ranking/forget% are meaningful cross-run.

---

## Experiment 1 — TST baseline vs TST (20k equal steps, bag=6, r=0.3)

Configs: `babyllm/configs/experiments/tst-small-{baseline,tst}-p50k.yaml`.
Runs: `babyllm/runs/p50k-all-20260526-064810/{baseline,tst}.log`.
Sequential on one GPU (RTX PRO 6000) for clean wall-clock.

| tokenizer | model | baseline ppl | TST ppl | TST Δppl | wall (base → tst) |
|---|---|---|---|---|---|
| **p50k (50281)** | ~88M, trunk-dominant | **168.46** | **198.40** | **+17.8%** | 725s → 857s (**+18%**) |
| qwen (248077) | 292M, embed-dominant | 182.53 | 212.72 | +16.5% | 2119s → 2997s (+41%) |

**TST still loses, by the same margin.** Shrinking the vocab did **not** rescue it — the ppl gap
is essentially unchanged. The wall penalty shrank (+18% vs +41%): with small embeddings the
forward is more trunk-bound, so the 6× phase-1 sequences add less relative overhead, but ppl is
still worse.

**Conclusion:** the param split was a red herring. The real lever is the **step budget** — 20k
is too few for phase-1 superposition to amortize. The original equal-FLOPs TST win was measured
at **≥80k steps** (24k phase-1 + 56k recovery). To see a TST win, raise total_steps toward 80k
and/or sweep `step_ratio`, not engineer the param split.

---

## Experiment 2 — Plasticity sweep (DCLM → FineWeb-Edu, 1500 + 500 steps)

Launcher: `babyllm/scripts/run_plasticity_p50k.sh` (streams HF data live; tokenizer hook
`--corpus-tokenizer tiktoken:p50k_base` added to `babyllm/babyllm/data_corpus.py`).
Runs: `babyllm/runs/p50k-all-20260526-064810/plasticity/<variant>.log`.

`spec_ppl` = adaptation (↓ better), `gen_ppl` = retention (↓), `forget%` = general-task
degradation (negative = improved), `dead` = dead/reset units.

| variant | spec_ppl ↓ | gen_ppl ↓ | forget% | dead | (qwen spec_ppl) |
|---|---|---|---|---|---|
| **dapt** | **582.6** | 558.7 | −0.3% | 0 | (566.5) |
| cbp | 583.4 | 559.1 | −0.3% | 1.0% redo | (567.3) |
| lr_scale | 583.7 | 558.8 | −0.3% | 0 | (567.5) |
| packnet | 586.5 | 559.2 | −0.2% | 0 | (570.2) |
| synthesis | 627.2 | 599.6 | **+6.9%** | 1.0% redo | (608.7) |
| vanilla | 633.5 | **548.9** | −2.0% | 0 | (620.4) |

Variant glossary: **dapt** = Domain-Adaptive Pre-Training (switch data to spec, no machinery);
**vanilla** = control, keeps training the general stream; **cbp** = continual backprop;
**packnet**/**lr_scale** = freeze/slow high-utility MLP units at the boundary; **synthesis** =
four-cell utility classification that freezes generalists and **resets** general-specialists +
dead units (`synthesis_reset_mode=full`).

**Verdict identical to the qwen run:** dapt wins adaptation; **no catastrophic forgetting**
anywhere (DCLM↔FineWeb-Edu is a mild near-domain shift — phase-2 even helps the general task);
synthesis is the clear loser (only real forgetting, dead units — its reset still hurts);
vanilla barely adapts (worst spec, best gen retention since it never leaves the general dist).

**Conclusion:** the trunk-dominant param split did not change the conclusion. On a mild shift,
plain DAPT/rehearsal is sufficient and freezing buys nothing because there's nothing to protect.
Reserve the freezing machinery for a true domain gap (the earlier FineWeb→Code run).

---

## Bottom line

Making the compute trunk dominate (TST 292M→88M, plasticity 201M→49M) left **both** verdicts
unchanged at the same step budgets. The "haven't-scaled-enough / embeddings-dilute-the-trunk"
hypothesis is **not** the reason these methods looked flat.
- **TST:** next move is more steps (≥80k) or a `step_ratio`/`total_steps` sweep.
- **Plasticity:** to make freezing matter, need a genuine domain gap, not a mild web↔web shift.

## How to resume (babyllm side)

```bash
cd /thearray/git/babyllm && source venv/bin/activate

# Re-run the whole sequence (TST baseline → TST → 6 plasticity variants), one GPU, sequential:
bash scripts/run_p50k_all.sh                 # writes runs/p50k-all-<stamp>/

# Push runs to deepresearch.local/experiments (idempotent by name; --force re-imports):
python scripts/import_runs.py --api http://localhost:7272 [--force] [--only <run-dir-name>]

# TST at a larger step budget (the actual open question):
python -m babyllm.train --config configs/experiments/tst-small-tst-p50k.yaml \
  scheduler.total_steps=80000        # pair with the baseline at the same total_steps
```

Key files (all uncommitted in babyllm as of this writeup):
- `configs/experiments/tst-small-{baseline,tst}-p50k.yaml`
- `babyllm/data_corpus.py` — `_TikTokenAdapter` + `tiktoken:` prefix in `_try_load_tokenizer`
- `scripts/{run_p50k_all.sh,run_plasticity_p50k.sh,build_dclm_fwedu.py}`

Open follow-ups: (1) 80k-step TST A/B on p50k; (2) plasticity on a true domain gap at p50k
scale; (3) the deferred ztok ByteLevel fix (HF/tiktoken == reference for now, so not blocking).
