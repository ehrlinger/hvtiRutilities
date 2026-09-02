# `dev/specs`

Design notes, implementation plans, findings and meeting handoffs for
`hvtiRutilities`. Not shipped — `dev` is in `.Rbuildignore`.

Each file is written to be self-contained: it assumes no memory of the session
that produced it, and it says what it decided rather than what was discussed.

**Naming:** `YYYY-MM-DD-topic-KIND.md`, where `KIND` is one of

| kind | what it is |
|---|---|
| `design` | what to build and why, with the alternatives and their costs |
| `plan` | how to build it — the steps, the tests, the order |
| `findings` | what was discovered, usually a defect or a defect class |
| `handoff` | what a meeting decided, captured before it evaporates |

A `handoff` is raw material. It becomes a `design` before anything is built.

---

## Index

Newest first. Where a note carries a `**Status:**` line, the status below
condenses it; `plan` files carry none.

| date | note | status |
|---|---|---|
| 2026-09-02 | [Ordinal variables — the representation decision](2026-09-02-ordinal-representation-design.md) | decision note; §7 open, awaiting the statisticians |
| 2026-09-02 | [Handoff — ordinal variables](2026-09-02-ordinal-representation-handoff.md) | step 1 answered by the design note above |
| 2026-09-02 | [Labels — length, fallback, value labels, and what `r_data_types()` is doing wrong](2026-09-02-label-length-and-fallback-design.md) | design; §7 open, `r_data_types()` decision pending |
| 2026-09-02 | [Handoff — label length, the fallback rule, and the exception that is not one](2026-09-02-label-length-and-fallback-handoff.md) | answered by the design note above |
| 2026-08-26 | [Job-type inventory — the level-one corpus sweep](2026-08-26-job-type-inventory-design.md) | implemented here; `hvtiRtemplates` re-export pending |
| 2026-08-26 | [Job-type inventory — plan](2026-08-26-job-type-inventory-plan.md) | plan for the design above |
| 2026-08-25 | [Read layer, dataset manifest, and lazy parquet cache](2026-08-25-read-layer-manifest-parquet-design.md) | approved in outline |
| 2026-08-25 | [Read layer, manifest, parquet — plan](2026-08-25-read-layer-manifest-parquet-plan.md) | plan for the design above |
| 2026-08-17 | [Findings: verification gates that pass without verifying](2026-08-17-verification-gates-findings.md) | one confirmed defect, plus a defect class |
| 2026-08-17 | [Study initialization — `study_init()` and `study_status()`](2026-08-17-study-init-design.md) | approved |
| 2026-08-17 | [Study initialization — plan](2026-08-17-study-init-plan.md) | plan for the design above |
| 2026-08-17 | [Provenance in `hvtiRutilities` — plan](2026-08-17-hvtirutilities-provenance-plan.md) | standalone plan, no design note |
| 2026-08-14 | [Extending `proc_means()` to the `unistats` vocabulary](2026-08-14-proc-means-unistats-design.md) | approved |
| 2026-08-14 | [`proc_means()` unistats — plan](2026-08-14-proc-means-unistats-plan.md) | plan for the design above |
| 2026-08-05 | [Port of SAS `PROC CONTENTS` and `PROC MEANS`](2026-08-05-proc-contents-means-design.md) | approved |
| 2026-08-05 | [`proc_contents()` / `proc_means()` — plan](2026-08-05-proc-contents-means-plan.md) | plan for the design above |
| 2026-07-10 | [SAS macro canonicalization (Phase 0)](2026-07-10-sas-macro-canonicalization-design.md) | shipped in 1.0.4 |
| 2026-07-10 | [SAS macro canonicalization — plan](2026-07-10-sas-macro-canonicalization-plan.md) | plan for the design above |

`artifacts/` holds supporting output referenced by the notes above.
