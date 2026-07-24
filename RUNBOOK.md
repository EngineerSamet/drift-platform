# Runbook — drift-platform

What to do when an alert fires, and what each failure actually looked like when
it happened during development. Every entry here was hit for real, not imagined.

---

## Alert: `SbomdriftNewCriticalFinding`

**Means:** a component gained a CRITICAL vulnerability in the last day. The image
was not necessarily rebuilt — the advisory data moved.

**Do:**
1. Open the Grafana dashboard, *Findings by severity*, and read which artefact.
2. `kubectl logs -n drift -l app.kubernetes.io/name=sbomdrift --tail=100` to see
   the finding: the CVE id and the package it landed on.
3. Decide with the artefact owner: rebuild on a patched base, or accept and
   record why. Accepting is a real answer; pretending it did not appear is not.

**Do not** silence this by widening the threshold. The gate exists for exactly
this event.

---

## Alert: `SbomdriftScanStale`

**Means:** an artefact has not been scanned for two days, on a daily schedule.
Two runs were missed. This is the alert that matters most, because a scan that
stopped shows *no findings*, which looks like good news.

**Do:**
1. `kubectl get cronjob -n drift` — is it suspended? `SUSPEND` should be `False`.
2. `kubectl get jobs -n drift` — did the last job fail, or never get created?
3. If jobs are failing, jump to the failure playbook below.
4. If no job was created at the scheduled time, check the cluster clock and the
   CronJob's `startingDeadlineSeconds`.

**Why the metric never simply disappears:** the Pushgateway holds the last value
forever, so absence is not the signal — *age* is. That is the whole reason
`sbomdrift_last_evaluation_timestamp_seconds` is published.

---

## Alert: `SbomdriftNeverEvaluated`

**Means:** an inventory was ingested but no evaluation ran against it, so the
artefact contributes nothing to the drift picture while appearing on the board.

**Seen for real:** ingesting `busybox:1.36` and skipping `eval` set
`sbomdrift_never_evaluated{artefact="busybox:1.36"} 1`, and the alert moved to
`pending` within one scrape. In normal operation the scan script always ingests
and evaluates together, so this fires when a run died *between* the two steps.

**Do:** re-run the scan for that artefact. If it keeps landing here, the
evaluation step is failing — check OSV reachability (below).

---

## Failure playbook

### Jobs fail with `UNIQUE constraint failed: evaluations.label`

**This actually happened.** The first scan script labelled each evaluation by
date. The second image of the day, and every re-run after a partial failure,
collided on that label and the job crashed with a raw traceback.

**Fixed in two places, both shipped:**
- `sbomdrift` ≥ 0.1.3 raises a named `DuplicateLabelError` and the CLI exits
  cleanly instead of dumping a stack trace.
- The scan script no longer labels scheduled evaluations at all — the metrics
  only read the newest live evaluation, which needs no name, and an unnamed run
  cannot collide.

If you see this, the scan image predates 0.1.3. Bump `image.tag`.

### Jobs fail while OSV.dev is unreachable or throttling

**Symptom:** the `eval` step hangs, then the job hits `activeDeadlineSeconds`
(one hour) and is killed.

**Do:** the run is idempotent — the next scheduled run picks up cleanly, because
ingestion already succeeded and evaluation simply retries. Nothing to unwind. If
it persists, OSV is down; the last good metrics stay on the board and
`SbomdriftScanStale` will fire once they are two days old.

### The history volume is lost

**Symptom:** `sbomdrift_snapshots` drops to a low number; the drift history is
gone.

**Cause:** the PVC was deleted. The chart sets `helm.sh/resource-policy: keep`
precisely so `helm uninstall` does *not* take the history with it — but a manual
`kubectl delete pvc` will.

**Seen for real:** during development a `kubectl delete pvc` hung in
`Terminating` because a pod still held the volume, which then blocked the next
`helm install` from provisioning. Clear it with:

```bash
kubectl delete pod -n drift <holder> --force --grace-period=0
kubectl patch pvc drift-sbomdrift-history -n drift \
  -p '{"metadata":{"finalizers":null}}' --type=merge
```

The history cannot be recovered, but it rebuilds itself: every future run adds a
snapshot, and `--as-of` reconstructs the *time* dimension from OSV's own
publication dates, so the shape of the past returns without the old database.

### Two scans race and corrupt the SQLite file

**Cannot happen by design, but worth knowing why.** The CronJob sets
`concurrencyPolicy: Forbid` and the PVC is `ReadWriteOnce`. SQLite's locking does
not survive two writers, so a slow run delays the next rather than racing it. If
you ever change either setting, you own this failure.
