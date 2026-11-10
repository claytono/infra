# msgvault

msgvault archives the Fastmail account over IMAP and serves keyword and semantic
search at <https://msgvault.k.oneill.net>. Its archive is not backed up; if the
volume is lost, rebuild it from Fastmail with the steps below.

The Fastmail login is in the `msgvault` item in the infra 1Password vault
(`imap-username`, and an app password in `imap-password`). The `msgvault-imap`
Secret puts both into the pod's environment.

## Rebuilding the archive

1. Register the Fastmail account. `add-imap` reads the password from
   `MSGVAULT_IMAP_PASSWORD`, which the pod already has:

   ```bash
   kubectl -n msgvault exec deploy/msgvault -c msgvault -- \
     sh -c 'msgvault add-imap --host imap.fastmail.com --username "$IMAP_USER"'
   ```

2. Wait for the first full sync. The account syncs every 15 minutes; copying
   about 500,000 messages took 11 hours in November 2026. Check progress on the
   web UI's Sources page.

3. Build the semantic index once the sync has finished. Scheduled syncs only add
   to an existing index, so the first one has to be started by hand. Expect it
   to take a day or two:

   ```bash
   kubectl -n msgvault exec deploy/msgvault -c msgvault -- \
     sh -c 'nohup msgvault embeddings build --full-rebuild --yes \
       >/data/tmp/embed-build.log 2>&1 &'
   ```

   Semantic and hybrid search return `index_building` until it finishes.
