#!/bin/sh
# Camofox VNC watcher helpers with live socket discovery preferred over lock
# files. /tmp survives container restarts in this deployment, so an Xvfb PID
# can be reused while stale locks for older displays still exist.

find_owned_xvfb_pid() {
  parent_pid="$1"
  resolution="$2"
  awk -v parent="$parent_pid" -v res="$resolution" '
    $2 == parent && $3 ~ /(^|\/)Xvfb$/ && index($0, res) { found=$1 }
    END { if (found) print found }
  '
}

display_for_xvfb_pid() {
  xvfb_pid="$1"
  lock_dir="${2:-/tmp}"
  socket_dir="${3:-/tmp/.X11-unix}"
  proc_root="${4:-/proc}"

  # Map sockets opened by the current Xvfb process first. Lock files can be
  # stale after a container restart because /tmp survives within the pod.
  if [ -d "$proc_root/$xvfb_pid/fd" ] && [ -r "$proc_root/net/unix" ]; then
    for fd in "$proc_root/$xvfb_pid/fd"/*; do
      socket_ref=$(readlink "$fd" 2>/dev/null || true)
      inode=$(printf '%s\n' "$socket_ref" | sed -n 's/^socket:\[\([0-9][0-9]*\)\]$/\1/p')
      [ -n "$inode" ] || continue
      socket_path=$(awk -v inode="$inode" '$7 == inode { print $8; exit }' "$proc_root/net/unix")
      case "$socket_path" in
        "$socket_dir"/X[0-9]*) ;;
        *) continue ;;
      esac
      [ -S "$socket_path" ] || continue
      display_num=${socket_path##*/X}
      case "$display_num" in *[!0-9]*|'') continue ;; esac
      printf ':%s\n' "$display_num"
      return 0
    done
  fi

  # Fall back to traditional lock files where process socket metadata is not
  # available (for example, on a non-Linux runtime).
  for lock in "$lock_dir"/.X*-lock; do
    [ -f "$lock" ] || continue
    lock_pid=$(tr -d '[:space:]' < "$lock" 2>/dev/null || true)
    [ "$lock_pid" = "$xvfb_pid" ] || continue

    display_num=$(basename "$lock" | sed -n 's/^\.X\([0-9][0-9]*\)-lock$/\1/p')
    [ -n "$display_num" ] || continue
    [ -S "$socket_dir/X$display_num" ] || continue
    printf ':%s\n' "$display_num"
    return 0
  done
}

x11vnc_needs_reattach() {
  tracked_pid="$1"
  [ -n "$tracked_pid" ] || return 1
  ! kill -0 "$tracked_pid" 2>/dev/null
}
