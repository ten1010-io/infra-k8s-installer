#!/bin/bash

ctr -n k8s.io images import aipub-adapter.tar
ctr -n k8s.io images import aipub-backend-api.tar
ctr -n k8s.io images import aipub-backend-batch.tar
ctr -n k8s.io images import aipub-backend-gateway.tar
ctr -n k8s.io images import aipub-backend-usage.tar
ctr -n k8s.io images import aipub-web-1_3_4-hotfix_11.tar
ctr -n k8s.io images import project-controller-102-snapshot.tar
ctr -n k8s.io images import ubuntu-22.04-util.tar

