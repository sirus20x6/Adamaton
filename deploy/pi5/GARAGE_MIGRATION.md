# MinIO → Garage migration (pi5 storage node)

Garage replaces MinIO as the single S3 storage node for the pi5 stack. It
holds two buckets:

| Bucket       | Consumer                          | Contents                              |
|--------------|-----------------------------------|---------------------------------------|
| `datasets`   | dataset-worker (evolve)           | parquet/jsonl dataset shards          |
| `dr-uploads` | r2g + plugin-host (via blobstore) | document upload staging, zotero PDFs  |

This kills the NFS mounts (`/mnt/pi-deepresearch`, `/mnt/pi-uploads`): every
shared filesystem path becomes an S3 key.

Garage, unlike MinIO, has **no static root credentials** — you must assign a
cluster layout and mint an access key after first boot. These are one-time
manual steps run on pi5; they generate secrets that go into `deploy/pi5/.env`.

---

## Rollout order

The migration is split so nothing breaks mid-flight:

- **Step A–E (deployable now):** stand up Garage, migrate the `datasets`
  bucket, cut `dataset-worker` over. No code change — dataset-manager's S3
  client is plain path-style S3.
- **Step F (gated on Phase 3):** once the blobstore-aware `r2g` and
  `plugin-host` images are built and pinned, repoint them to Garage's
  `dr-uploads` bucket and delete the `dr_uploads` volume + NFS mounts.

---

## A. Generate secrets, add to `.env`

On pi5, in `~/Adamaton-deploy/.env` (the file compose reads):

```bash
echo "GARAGE_RPC_SECRET=$(openssl rand -hex 32)"     >> .env
echo "GARAGE_ADMIN_TOKEN=$(openssl rand -hex 32)"    >> .env
echo "GARAGE_METRICS_TOKEN=$(openssl rand -hex 32)"  >> .env
```

`BLOBSTORE_ACCESS_KEY` / `BLOBSTORE_SECRET_KEY` are filled in at step D once
the key exists.

## B. Boot Garage and apply a single-node layout

```bash
docker compose up -d garage
# Grab the node ID (first column of the "HEALTHY NODES" / unconfigured list):
docker compose exec garage /garage status
# Assign the whole node to one zone with a capacity, then commit:
docker compose exec garage /garage layout assign -z dc1 -c 100G <NODE_ID_PREFIX>
docker compose exec garage /garage layout apply --version 1
```

After `layout apply`, `GET :3903/health` flips to 200 and the compose
healthcheck goes green.

## C. Create buckets

```bash
docker compose exec garage /garage bucket create datasets
docker compose exec garage /garage bucket create dr-uploads
```

## D. Mint one least-privilege key, wire it into `.env`

```bash
docker compose exec garage /garage key create adamaton-blob
# prints:  Key ID: GK....    Secret key: ....
docker compose exec garage /garage bucket allow --read --write --owner datasets   --key adamaton-blob
docker compose exec garage /garage bucket allow --read --write --owner dr-uploads --key adamaton-blob
```

Put the printed pair into `.env`:

```
BLOBSTORE_ACCESS_KEY=GK....
BLOBSTORE_SECRET_KEY=....
```

(`DATASET_S3_ACCESS_KEY` / `DATASET_S3_SECRET_KEY` default to these in the
compose file, so this one key configures datasets + document blobs.)

## E. Copy `datasets` MinIO → Garage, then cut over

With both services up (MinIO not yet removed), from the pi5 host using the
AWS CLI (or `mc`). Garage S3 is on `:3900`, the old MinIO on `:9000`:

```bash
# Pull from MinIO (root creds), push to Garage (new key). Path-style is
# required for both.
export AWS_EC2_METADATA_DISABLED=true
aws --endpoint-url http://localhost:9000 \
    --no-verify-ssl s3 sync s3://datasets /tmp/datasets-stage \
    # creds: MINIO_ROOT_USER / MINIO_ROOT_PASSWORD

AWS_ACCESS_KEY_ID=$BLOBSTORE_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$BLOBSTORE_SECRET_KEY \
aws --endpoint-url http://localhost:3900 s3 sync /tmp/datasets-stage s3://datasets
```

Then bring up the repointed worker and confirm:

```bash
docker compose up -d dataset-worker
docker compose logs -f dataset-worker   # should connect to garage:3900, no errors
```

Once verified, retire MinIO:

```bash
docker compose rm -sf minio          # service already removed from compose
docker volume rm <stack>_minio_data  # only after you trust the copy
```

## F. (Phase 3, gated) Document blobs + drop NFS

Do this **only after** the blobstore-aware `r2g` and `plugin-host` images are
built and their tags pinned in `image-tags.env`.

> **⚠️ STOP — `dr_uploads` is NOT disposable on pi5 (verified 2026-05-24).**
> An earlier draft of this section claimed `dr_uploads` held only "loose,
> read-once, in-flight" staging files safe to drop. That is **wrong** for the
> live pi5 volume. `deepresearch_dr_uploads` is a **local** docker volume
> (not NFS — pi5 has no NFS client mounts, only the `nfsd` kernel module) and
> holds **~782 MB of persistent data** that the blobstore migration does NOT
> touch:
>
> | Path under `/var/lib/dr-uploads/` | What it is | Migrated by new code? |
> |-----------------------------------|------------|------------------------|
> | `cag/<uuid>/<model>/` (930 dirs)  | CAG cache (.md/.txt/.json) | **No** |
> | `plugins/<plugin>/<uuid>/`        | plugin outputs (.md)       | **No** |
> | `wiki-seed/`                      | seed corpus                | **No** |
> | `zotero-sqlite/`                  | 7 sqlite DBs               | **No** |
>
> There are **no `zotero/<key>.pdf` files** in the volume — the PDF-migration
> step below has nothing to copy. The new `r2g`/`plugin-host` blobstore code
> only reroutes the *upload* path (`uploads/<uuid>`) and *plugin-staging* path
> (`plugin/<...>`); it never reads or writes `cag/`, `plugins/`, `wiki-seed/`,
> or `zotero-sqlite/`. So **dropping the volume (step 3) would lose persistent
> data and break whatever still writes those paths.** Reconcile this first:
> decide whether those dirs stay on a retained local volume, move to Garage
> under their own prefixes, or are intentionally abandoned — do NOT blanket-
> delete. Steps 2–4 below are blocked until that decision is made.

1. ~~Copy zotero PDFs into Garage~~ — **no-op on pi5**: no PDFs in the volume.
   General document *uploads* already route to `uploads/<uuid>` via the new
   r2g code; nothing to backfill.
2. ✅ **DONE 2026-05-24.** Added `BLOBSTORE_ENDPOINT=http://garage:3900`,
   `BLOBSTORE_REGION=us-east-1`, `BLOBSTORE_ACCESS_KEY`, `BLOBSTORE_SECRET_KEY`
   to the `r2g` and `plugin-host` service env; gave plugin-host a
   container-local ephemeral staging dir (`PH_STAGE_DIR=/run/ph-stage`) in
   place of the NFS mount, and dropped the `- dr_uploads:/var/lib/dr-uploads`
   mount from both services. Both services now `depends_on: garage:
   service_healthy`. (Additive and safe; the new images fail-soft to 503 if
   the BLOBSTORE_* vars are absent.)

   Required build-infra fixes that landed alongside (workspace-mode Dockerfiles
   so the new `core/blobstore` + `ztok-go` deps resolve in the build context):
   - knowledge `r2g/Dockerfile` → workspace mode (PR #16, pin `e5cd4d8`)
   - platform `plugin-host/Dockerfile` → `COPY ztok` (PR #35, pin `9f535a0`)
   - umbrella `bin/adam` r2g ship-spec context `knowledge` → `.`

   Shipped to pi5 (images `adamaton-r2g:sha-e5cd4d8`,
   `adamaton-plugin-host:sha-9f535a0`; the deploy-agent pull quirk required an
   explicit `docker compose pull + up -d --force-recreate` to converge — see
   memory `adamaton_deploy_agent_pull_quirk`). **Verified end-to-end:** both
   logged `blob store ready (dr-uploads)` against `http://garage:3900`; a
   `POST /platform/sources/upload` round-tripped a 46 B file to
   `uploads/<uuid>.txt` in the Garage `dr-uploads` bucket (confirmed via
   `mc stat`, byte size matched), then cleaned up.
3. **STILL BLOCKED (see STOP box):** the upload/staging *path* is cut over, but
   removing the `dr_uploads:` volume is unsafe until the persistent `cag/` /
   `plugins/` / `wiki-seed/` / `zotero-sqlite/` data is moved into Garage (the
   chosen disposition) and its readers repointed. The volume is still declared
   and untouched as a rollback net; nothing mounts it anymore. This data move
   is the next work item — it requires auditing what code reads those prefixes
   (CAG cache in deepresearch, plugin outputs in plugin-host) before relocating.
4. The `/mnt/pi-deepresearch` / `/mnt/pi-uploads` fstab cleanup is a **no-op on
   pi5** (no such mounts here). Retiring the Python `worker-hi` service is
   tracked separately (Phase 4) and is independent of this volume question.
