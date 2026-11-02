# Signing and verifying gadgets

Automatic publishing optionally signs gadget images with
[Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/).
Configure the repository secrets before running initialization to sign the first
image, or before a later default-branch push to start signing subsequent images.
Previously published images are not automatically signed.

Without a private key, publishing warns and continues with unsigned images.
With a key configured, a signing error fails publishing rather than falling back
to unsigned images. The commit-SHA tag is pushed first; `latest` is pushed only
after signing succeeds. Signing uses the built image's immutable digest.
Both tags point to the same image, so one recursive
signing operation covers both tags and the image's architecture-specific
manifests. Signatures are stored in GHCR alongside the image. Transparency-log
upload is disabled to avoid publishing private image metadata to a public log.

Local `make build`, `make push`, and `make run-local` do not sign images.

## Configure GitHub Actions

1. Install Cosign (CI uses v3.1.4), then generate a key pair:

   ```bash
   cosign generate-key-pair
   ```

   Choose a password and keep it available for the next step. This creates
   `cosign.key` (the encrypted private key) and `cosign.pub` (the public key).
   Never commit the private key or its password. The default `cosign.key` filename
   is ignored by Git; keep a secure backup outside the repository.

2. In your gadget repository, open **Settings > Secrets and variables > Actions >
   New repository secret** and add:

   | Secret | Value |
   |---|---|
   | `COSIGN_PRIVATE_KEY` | The entire contents of `cosign.key`, including the PEM header/footer |
   | `COSIGN_PASSWORD` | The password chosen during key generation |

   These must be **secrets**, not repository variables. The workflows expose them
   to Cosign as environment variables. Alternatively, with GitHub CLI
   authenticated in the gadget checkout:

   ```bash
   gh secret set COSIGN_PRIVATE_KEY < cosign.key
   gh secret set COSIGN_PASSWORD
   ```

   The second command prompts for the password without putting it in shell
   history. For a key generated with an empty password, omit `COSIGN_PASSWORD`.

3. Commit and publish `cosign.pub` so users can obtain your public key through a
   trusted channel. Run initialization or push a change to the default branch.
   The publishing job reports whether signing was configured.

Replacing the key changes which public key consumers need to trust. Keep the old
public key trusted while consumers still use images signed with it.

## Trust your public key with `ig`

By default, IG trusts the Inspektor Gadget project's key, not your gadget's key.
For persistent configuration, create or edit the default `~/.ig/config.yaml`.
Merge the following settings into any existing configuration, replacing the
first PEM block with the complete contents of `cosign.pub`. The second entry is
the official IG v0.57.0 public key; keep it to continue running official gadgets:

```yaml
operator:
  oci:
    verify-image: true
    public-keys:
      - |
          -----BEGIN PUBLIC KEY-----
          REPLACE WITH THE KEY DATA FROM cosign.pub
          -----END PUBLIC KEY-----
      - |
          -----BEGIN PUBLIC KEY-----
          MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEoDOC0gYSxZTopenGmX3ZFvQ1DSfh
          Ir4EKRt5jC+mXaJ7c7J+oREskYMn/SfZdRHNSOjLTZUMDm60zpXGhkFecg==
          -----END PUBLIC KEY-----
```

Then run with signature verification enabled. With `sudo`, explicitly use your
user's default configuration path so it is not confused with root's home:

```bash
sudo ig --config "$HOME/.ig/config.yaml" run ghcr.io/your-owner/your-gadget:latest
```

Alternatively, configure root's `~/.ig/config.yaml` and use `sudo ig run` without
`--config`.

The `public-keys` list replaces the default trusted keys, so preserve both entries.
Never put `cosign.key` in consumer configuration.

## Trust your public key with `kubectl gadget`

Kubernetes verification is enforced by the gadget daemon, not by the local
`kubectl gadget run` client. Use the deployment method already managing your
cluster; do not mix Helm and `kubectl gadget deploy`.

### Using `kubectl gadget deploy`

A cluster administrator must apply the `operator.oci` settings to the daemon at
deployment time. Using the default configuration file above:

```bash
kubectl gadget deploy --daemon-config="$HOME/.ig/config.yaml"
kubectl gadget run ghcr.io/your-owner/your-gadget:latest
```

For an existing deployment, preserve its other daemon settings when updating the
configuration. Editing the client's file alone does not update the deployed
daemon.

### Using Helm

The chart uses `config.operator.oci` for daemon verification settings. Create
`gadget-values.yaml` with both public keys, replacing the first PEM block with
the contents of `cosign.pub`:

```yaml
config:
  operator:
    oci:
      verify-image: true
      public-keys:
        - |
            -----BEGIN PUBLIC KEY-----
            REPLACE WITH THE KEY DATA FROM cosign.pub
            -----END PUBLIC KEY-----
        - |
            -----BEGIN PUBLIC KEY-----
            MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEoDOC0gYSxZTopenGmX3ZFvQ1DSfh
            Ir4EKRt5jC+mXaJ7c7J+oREskYMn/SfZdRHNSOjLTZUMDm60zpXGhkFecg==
            -----END PUBLIC KEY-----
```

Install or upgrade using the matching IG v0.57.0 chart:

```bash
helm upgrade --install gadget \
  oci://ghcr.io/inspektor-gadget/inspektor-gadget/charts/gadget \
  --namespace gadget --create-namespace --version 0.57.0 \
  -f gadget-values.yaml
kubectl gadget run ghcr.io/your-owner/your-gadget:latest
```

For an existing release, use its release name, namespace, and chart version, and
include your existing values files so other settings are preserved. Keep the
`kubectl gadget` client and deployed IG versions matched.

The Helm key list also replaces the default keys; both PEM entries are included
above so your gadgets and official IG gadgets remain trusted.

Do not disable image verification to use a signed gadget. Private GHCR images
also require registry authentication; trusting the public key does not grant
pull access.

See the upstream [verification guide](https://www.inspektor-gadget.io/docs/latest/reference/verify-gadgets)
for additional configuration options.
