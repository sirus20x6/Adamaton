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
built and their tags pinned in `image-tags.env`:

1. Copy any existing document blobs into Garage `dr-uploads`, preserving the
   `zotero/<key>.pdf` layout. General uploads move under the `uploads/`
   prefix (new scheme):
   ```bash
   # zotero PDFs keep their key:
   AWS_ACCESS_KEY_ID=$BLOBSTORE_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$BLOBSTORE_SECRET_KEY \
   aws --endpoint-url http://localhost:3900 s3 sync /mnt/pi-uploads/zotero s3://dr-uploads/zotero
   ```
   (Loose UUID staging files are read-once and in-flight only — safe to drop
   rather than migrate.)
2. Add `BLOBSTORE_ENDPOINT=http://garage:3900`, `BLOBSTORE_REGION=us-east-1`,
   `BLOBSTORE_ACCESS_KEY`, `BLOBSTORE_SECRET_KEY` to the `r2g` and
   `plugin-host` service env; give plugin-host a container-local ephemeral
   staging dir in place of the NFS mount.
3. Delete the `dr_uploads:` volume and both `- dr_uploads:/var/lib/dr-uploads`
   mounts from compose.
4. Remove the `/mnt/pi-deepresearch` and `/mnt/pi-uploads` entries from
   `/etc/fstab` on this host (needs sudo); retire the Python `worker-hi`
   service (Phase 4).
