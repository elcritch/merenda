#!/bin/sh
# vm-bhyve calls this before each boot, including Windows restarts.
set -eu
umask 077
state="$(pwd)/tpm"
mkdir -p "$state"
chmod 700 "$state"
if [ -S "$state/control.sock" ]; then
  swtpm_ioctl --unix "$state/control.sock" -s >/dev/null 2>&1 || true
fi
# swtpm removes its sockets on normal exit. Never unlink a live endpoint.
for n in 1 2 3 4 5; do
  [ ! -S "$state/swtpm.sock" ] && break
  sleep 1
done
if [ -S "$state/swtpm.sock" ]; then
  echo 'Previous swtpm socket remains; refusing to replace it' >&2
  exit 1
fi
rm -f "$state/control.sock"
exec swtpm socket --tpm2 --terminate --daemon \
  --tpmstate "dir=$state,mode=0600,lock" \
  --server "type=unixio,path=$state/swtpm.sock,mode=0600" \
  --ctrl "type=unixio,path=$state/control.sock,mode=0600" \
  --flags not-need-init --log "file=$state/swtpm.log"
