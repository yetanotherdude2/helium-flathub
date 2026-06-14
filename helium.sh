#!/bin/sh

# Merge the policies with the host ones.
for proot in "etc/chromium/policies" "etc/static/chromium/policies"; do
  for ptype in managed recommended enrollment; do
    if [ -d "/run/host/$proot/$ptype" ]; then
      mkdir -p "/etc/chromium/policies/$ptype"
      ln -sf "/run/host/$proot/$ptype"/*.json "/etc/chromium/policies/$ptype" 2>/dev/null
    fi
  done
done

exec zypak-wrapper /app/lib/helium/helium.real --class=net.imput.helium "$@" --no-default-browser-check
