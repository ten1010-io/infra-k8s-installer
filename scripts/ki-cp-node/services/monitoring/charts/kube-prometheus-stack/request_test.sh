#!/bin/bash

# 사용법 검사
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <base_uri> <requests_for_port_success> <requests_for_port_err>"
    exit 1
fi

# 인자 할당
base_uri=$1
requests_for_port_success=$2
requests_for_port_err=$3

# 숫자 입력 검증
if ! [[ "$requests_for_port_success" =~ ^[0-9]+$ ]] || ! [[ "$requests_for_port_err" =~ ^[0-9]+$ ]]; then
    echo "Error: Please enter valid numbers for both request counts."
    exit 1
fi

# URL 정의
url1="${base_uri}"
url2="${base_uri}/test/test-operation-2222"

# 요청 함수 정의
make_requests() {
    echo "Making $requests_for_port_success requests to $url1"
    for ((i=1; i<=$requests_for_port_success; i++))
    do
        curl -ks "$url1" > /dev/null &
    done

    echo "Making $requests_for_port_err requests to $url2"
    for ((i=1; i<=$requests_for_port_err; i++))
    do
        curl -ks "$url2" > /dev/null &
    done

    wait
    echo "Completed all requests."
}

# 메인 루프
while true
do
    echo "Starting requests..."
    make_requests
    echo "Waiting for 15 seconds before next batch..."
    sleep 15
done
