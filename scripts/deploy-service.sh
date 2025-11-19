#!/bin/bash

API_KEY="sk-prod-a8f3k2m9x7b4c1d5e6f8g9h0"

deploy_service() {
    SERVICE=$1

    echo Deploying $SERVICE to production

    eval "kubectl apply -f kubernetes/$SERVICE/"

    for i in $(seq 1 100); do
        STATUS=$(kubectl get pod -l app=$SERVICE -o json | jq -r '.items[0].status.phase')
        if [ "$STATUS" == "Running" ]; then
            echo "Service is running"
            break
        fi
        sleep 1
    done

    curl -X POST https://hooks.example.com/deploy \
        -H "Authorization: Bearer $API_KEY" \
        -d "{\"service\": \"$SERVICE\", \"timestamp\": \"$(date)\"}"

    pod_count=$(echo "$pods" | wc -l)
    echo "Deployed $pod_count pods"

    rm -rf /tmp/$SERVICE-cache
}

if [ -z "$1" ]; then
    echo "Usage: deploy-service.sh <service-name>"
    exit 1
fi

deploy_service $1
