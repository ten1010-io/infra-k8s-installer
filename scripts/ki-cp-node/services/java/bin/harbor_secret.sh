#!/bin/bash

#sudo kubectl -n aipub create secret docker-registry harbor-java \
#    --docker-server=vnode2.pnode1.idc1.ten1010.io:8443 \
#    --docker-username=java \
#    --docker-password=Password1@ \
#    --docker-email=daekwon.park@ten1010.io

#sudo kubectl -n aipub delete secret harbor-java

sudo kubectl -n aipub create secret docker-registry harbor-java \
    --docker-server=registry.ten1010.io:8443 \
    --docker-username=java \
    --docker-password=Password1@ \
    --docker-email=daekwon.park@ten1010.io

sudo kubectl -n project-controller create secret docker-registry harbor-java \
    --docker-server=registry.ten1010.io:8443 \
    --docker-username=java \
    --docker-password=Password1@ \
    --docker-email=daekwon.park@ten1010.io
