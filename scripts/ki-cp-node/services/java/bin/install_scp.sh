#!/bin/bash

DEST_IP=10.10.10.1
DEST_DIR=/root
SSH_PORT=22

scp -P ${SSH_PORT} ./aipub-adapter.tar ${DEST_IP}:${DEST_DIR}/aipub-adapter.tar
scp -P ${SSH_PORT} ./aipub-backend-api.tar ${DEST_IP}:${DEST_DIR}/aipub-backend-api.tar
scp -P ${SSH_PORT} ./aipub-backend-batch.tar ${DEST_IP}:${DEST_DIR}/aipub-backend-batch.tar
scp -P ${SSH_PORT} ./aipub-backend-gateway.tar ${DEST_IP}:${DEST_DIR}/aipub-backend-gateway.tar
scp -P ${SSH_PORT} ./aipub-backend-usage.tar ${DEST_IP}:${DEST_DIR}/aipub-backend-usage.tar
scp -P ${SSH_PORT} ./aipub-web-1_3_4-hotfix_11.tar ${DEST_IP}:${DEST_DIR}/aipub-web-1_3_4-hotfix_11.tar
scp -P ${SSH_PORT} ./project-controller-102-snapshot.tar ${DEST_IP}:${DEST_DIR}/project-controller-102-snapshot.tar
scp -P ${SSH_PORT} ./ubuntu-22.04-util.tar ${DEST_IP}:${DEST_DIR}/ubuntu-22.04-util.tar
