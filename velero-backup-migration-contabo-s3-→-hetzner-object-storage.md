# Velero backup migration: Contabo S3 → Hetzner Object Storage

Moves the entire Velero backup bucket (BSL metadata + kopia repository) from Contabo
Object Storage to Hetzner Object Storage using an in-cluster rclone Job. No VolSync: its
rclone method is PVC↔remote only, so a direct S3→S3 copy is done with rclone instead.

Strategy: two sync passes.

1. Bulk pass while Velero keeps running against Contabo (idempotent, safe to re-run).
2. Short delta pass after Velero schedules are paused, then cut the BSL over to Hetzner.

Contabo egress is capped at 10 MB/s, so the bulk pass takes roughly 14 h for a full
0.5 TB bucket. Hetzner upload is not the bottleneck.

Placeholders to replace everywhere:

| Placeholder                      | Meaning                                              |
| -------------------------------- | ---------------------------------------------------- |
| `SRC_BUCKET`                     | existing Contabo bucket name                         |
| `DST_BUCKET`                     | new Hetzner bucket name                              |
| `CONTABO_KEY` / `CONTABO_SECRET` | Contabo S3 credentials (same keys Velero uses today) |
| `HETZNER_KEY` / `HETZNER_SECRET` | new Hetzner S3 keys                                  |
| `MIG_NS`                         | namespace for the migration (suggested: `velero`)    |

---

## Phase 0 — Prepare the Hetzner side

1. In Hetzner Console: create Object Storage keys (project-scoped, save the secret
   immediately — it is shown once).
2. Create the destination bucket. Pick a German location, e.g. `fsn1` (Falkenstein)
   or `nbg1` (Nuremberg). The endpoint is location-bound:
   `https://fsn1.your-objectstorage.com`.
3. Confirm the Contabo endpoint in the Contabo Control Panel. For the EU region it is
   `https://eu2.contabostorage.com` (path-style addressing required).

Discovery on the cluster (context `${SECRET_DOMAIN}`):

```bash
kubectl --context ${SECRET_DOMAIN} get backupstoragelocations.velero.io -A
kubectl --context ${SECRET_DOMAIN} get secrets -n velero
# note BSL name, bucket, prefix, and the credentials secret key names:
kubectl --context ${SECRET_DOMAIN} get secret -n velero cloud-credentials -o jsonpath='{.data}' | tr ',' '\n'
```

---

## Phase 1 — rclone config Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: s3-migration-rclone
  namespace: MIG_NS
type: Opaque
stringData:
  rclone.conf: |
    [contabo]
    type = s3
    provider = Other
    env_auth = false
    access_key_id = CONTABO_KEY
    secret_access_key = CONTABO_SECRET
    endpoint = https://eu2.contabostorage.com
    region = us-east-1
    force_path_style = true

    [hetzner]
    type = s3
    provider = Other
    env_auth = false
    access_key_id = HETZNER_KEY
    secret_access_key = HETZNER_SECRET
    endpoint = https://fsn1.your-objectstorage.com
    region = us-east-1
    force_path_style = true
```

```bash
kubectl --context ${SECRET_DOMAIN} apply -f s3-migration-secret.yaml
```

Region is required for S3v4 signing only; both providers ignore its value. Mirror the
region string from your working Contabo BSL config if it differs.

## Phase 2 — Bulk sync Job (Velero stays live on Contabo)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: s3-migration-sync
  namespace: MIG_NS
spec:
  backoffLimit: 4
  activeDeadlineSeconds: 172800
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: rclone
          image: rclone/rclone:v1.75.2
          args:
            - sync
            - contabo:SRC_BUCKET
            - hetzner:DST_BUCKET
            - --fast-list
            - --transfers=8
            - --checkers=32
            - --retries=5
            - --low-level-retries=20
            - --s3-upload-concurrency=4
            - --stats-one-line
            - --stats=15m
            - --stats-log-level=NOTICE
          volumeMounts:
            - name: rclone-config
              mountPath: /config/rclone
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: "1", memory: 512Mi }
      volumes:
        - name: rclone-config
          secret:
            secretName: s3-migration-rclone
```

```bash
kubectl --context ${SECRET_DOMAIN} apply -f s3-migration-job.yaml
kubectl --context ${SECRET_DOMAIN} logs -n MIG_NS -f job/s3-migration-sync
```

The copy is byte-identical. The kopia repository (`kopia/` prefix) and Velero metadata
(`velero/` prefix) move as-is; kopia repositories are self-contained, so history,
deduplication and point-in-time state are preserved. `--fast-list` keeps Contabo's
250 req/s limit from throttling listings.

## Phase 3 — Cutover

### 3.1 Pause all Velero schedules

```bash
kubectl --context ${SECRET_DOMAIN} get schedules.velero.io -A
kubectl --context ${SECRET_DOMAIN} patch schedule.velero.io <name> -n velero \
  --type merge -p '{"spec":{"paused":true}}'
# repeat for every schedule
```

### 3.2 Delta sync

Jobs are immutable, so run a second pass with a new name:

```bash
sed 's/s3-migration-sync/s3-migration-delta/' s3-migration-job.yaml \
  | kubectl --context ${SECRET_DOMAIN} apply -f -
kubectl --context ${SECRET_DOMAIN} logs -n MIG_NS -f job/s3-migration-delta
```

Only objects written since the bulk pass are copied; this normally takes minutes.

### 3.3 Verify

ETag/checksums do not survive the provider change, so compare by size:

```bash
kubectl --context ${SECRET_DOMAIN} run s3-verify --rm -it --restart=Never \
  --image=rclone/rclone:v1.75.2 --command -- \
  rclone check contabo:SRC_BUCKET hetzner:DST_BUCKET --size-only --fast-list \
  --config=/dev/null
```

If run with the secret-mounted config instead, drop `--config=/dev/null` and mount
`s3-migration-rclone`. Expect `no differences found`, exit code 0. If not, re-run the
delta job — sync is idempotent.

### 3.4 Repoint Velero

Replace the credentials secret contents (keep the same key names discovered in
Phase 0, e.g. `cloud`):

```bash
kubectl --context ${SECRET_DOMAIN} create secret generic cloud-credentials -n velero \
  --from-file=cloud=<aws-credentials-file-with-hetzner-keys> \
  --dry-run=client -o yaml | kubectl apply -f -
```

Patch the BSL:

```bash
kubectl --context ${SECRET_DOMAIN} patch backupstoragelocation.velero.io default -n velero \
  --type merge -p '{
    "spec": {
      "objectStorage": { "bucket": "DST_BUCKET" },
      "config": {
        "region": "us-east-1",
        "s3ForcePathStyle": "true",
        "s3Url": "https://fsn1.your-objectstorage.com"
      }
    }
  }'
```

Keep the existing `prefix`. Restart the Velero deployment so it picks up the new
credentials:

```bash
kubectl --context ${SECRET_DOMAIN} rollout restart deployment/velero -n velero
```

### 3.5 Validate

```bash
kubectl --context ${SECRET_DOMAIN} get backupstoragelocation.velero.io -A
# phase must be Available
velero --kubecontext ${SECRET_DOMAIN} backup describe <latest-backup>
velero --kubecontext ${SECRET_DOMAIN} backup restore create --from-backup <latest-backup> \
  --namespace-mappings cloud:restore-test --wait
```

Restore into a scratch namespace (`restore-test`) and compare. Only after a successful
test restore: resume schedules, delete the migration Jobs and Secret.

## Phase 4 — Decommission Contabo

Keep the Contabo bucket for one full retention cycle as a cold fallback. Then cancel
the Object Storage line item in the Contabo Customer Control Panel (the VPS M SSD line
is unaffected).

## Caveats

- Contabo download stays capped at 10 MB/s during the whole bulk pass; Hetzner egress
  allowance is 1 TB/month included, so the copy plus normal restores fit comfortably.
- Do not run a third-party "migration service" or bucket-wide encryption change; kopia
  repo objects must be copied unmodified.
- If the bulk Job hits `activeDeadlineSeconds` (48 h), re-apply it with a new name;
  it resumes and only copies what is missing.
- Hetzner bills the base price as long as one bucket exists, even empty; canceling
  Contabo before the first Hetzner restore test saves nothing meaningful and removes
  your fallback.
