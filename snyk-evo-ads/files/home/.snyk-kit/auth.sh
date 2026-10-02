#!/bin/sh
# Classifies the supplied credentials without requiring any one of them:
# component selection (resolve-components.sh) decides what's actually required.
# SNYK_TENANT_ID is not required: guard install only needs it for the
# interactive push-key-minting flow, which this kit never uses (it always
# runs headless with a pre-provisioned SNYK_ADS_PUSH_KEY).
if [ -n "${SNYK_ADS_PUSH_KEY:-}" ]; then
  echo enterprise
elif [ -n "${SNYK_TOKEN:-}" ]; then
  echo standalone
else
  echo none
fi
