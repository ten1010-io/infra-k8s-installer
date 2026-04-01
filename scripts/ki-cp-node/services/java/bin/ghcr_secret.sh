#!/bin/bash

sudo kubectl -n aipub create secret docker-registry ghcr-ten1010 \
    --docker-server=ghcr.io \
    --docker-username=pranludi \
    --docker-password=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 \
    --docker-email=pranludi@gmail.com
