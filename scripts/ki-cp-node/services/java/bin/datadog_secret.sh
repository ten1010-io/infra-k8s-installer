#!/bin/bash

sudo kubectl -n aipub create secret generic datadog-api-key \
  --from-literal api-key=d5aa70010467931cb5a8b1b23a115e75 \
  --dry-run=client -o yaml | \
  kubectl apply -f -
