#!/bin/sh
# Build each mounted Modelfile as <name>:mine, so the PVC always matches
# git. A tag of our own keeps the build apart from the upstream tag it
# starts FROM: building over the base would inherit the previous build's
# parameters, so a parameter removed from git would stay in effect.
# Ollama reserves :local and :cloud as source suffixes, so :local would
# resolve to :latest. create pulls the base only when it is absent,
# which keeps the weights under existing embeddings from following an
# upstream retag. Never fail, since a failed postStart hook kills the
# container.

# Hook output is discarded unless the hook fails, so log to the stderr
# of ollama serve, which kubectl logs shows.
log() {
  echo "apply-modelfiles: $*" >/proc/1/fd/2 2>/dev/null ||
    echo "apply-modelfiles: $*" >&2
}

ready=0
for _ in $(seq 60); do
  if ollama list >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[ "$ready" = 1 ] || log "ollama not ready after 60s; building anyway"

# Retry, since building from an empty volume pulls the base. Readiness
# waits for the model, so a failure here shows as an unready pod.
for file in /etc/ollama/models/*.Modelfile; do
  name="$(basename "$file" .Modelfile):mine"
  built=0
  for _ in 1 2 3 4 5; do
    if ollama create "$name" -f "$file"; then
      built=1
      break
    fi
    sleep 10
  done
  [ "$built" = 1 ] || log "create $name failed after 5 attempts"
done

exit 0
