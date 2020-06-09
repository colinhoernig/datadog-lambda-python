#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019 Datadog, Inc.

# Publish the datadog python lambda layer across regions, using the AWS CLI
# Usage: publish_layer.sh [region] [layer]
# Specifying the region and layer arg will publish the specified layer to the specified region
set -e

# Makes sure any subprocesses will be terminated with this process
trap "pkill -P $$; exit 1;" INT

PYTHON_VERSIONS_FOR_AWS_CLI=("python2.7" "python3.6" "python3.7" "python3.8")
LAYER_PATHS=(".layers/datadog_lambda_py2.7.zip" ".layers/datadog_lambda_py3.6.zip" ".layers/datadog_lambda_py3.7.zip" ".layers/datadog_lambda_py3.8.zip")

# Source the common list of layers and regions
source scripts/all_layers.sh

# Check that the layer files exist
for layer_file in "${LAYER_PATHS[@]}"
do
    if [ ! -f $layer_file  ]; then
        echo "Could not find $layer_file."
        exit 1
    fi
done

# Check region arg
if [ -z "$1" ]; then
    echo "Region parameter not specified, running for all available regions."
    REGIONS=("${AVAILABLE_REGIONS[@]}")
else
    echo "Region parameter specified: $1"
    if [[ ! " ${AVAILABLE_REGIONS[@]} " =~ " ${1} " ]]; then
        echo "Could not find $1 in available regions: ${AVAILABLE_REGIONS[@]}"
        echo ""
        echo "EXITING SCRIPT."
        exit 1
    fi
    REGIONS=($1)
fi

echo "Publishing layers for regions: ${REGIONS[*]}"

# Check layer_name arg
if [ -z "$2" ]; then
    echo "Layer name parameter not specified, running for all layer names."
    LAYER_NAMES=("${AVAILABLE_LAYER_NAMES[@]}")
else
    echo "Layer name parameter specified: $2"
    if [[ ! " ${AVAILABLE_LAYER_NAMES[@]} " =~ " ${2} " ]]; then
        echo "Could not find $2 in available layer names: ${AVAILABLE_LAYER_NAMES[@]}"
        echo ""
        echo "EXITING SCRIPT."
        exit 1
    fi
    LAYER_NAMES=($2)
fi




echo "Publishing layers: ${LAYER_NAMES[*]}"

publish_layer() {
    region=$1
    layer_name=$2
    aws_version_key=$3
    layer_path=$4
    version_nbr=$(aws lambda publish-layer-version --layer-name $layer_name \
        --description "Datadog Lambda Layer for Python" \
        --zip-file "fileb://$layer_path" \
        --region $region \
        --compatible-runtimes $aws_version_key \
                        | jq -r '.Version')

    aws lambda add-layer-version-permission --layer-name $layer_name \
        --version-number $version_nbr \
        --statement-id "release-$version_nbr" \
        --action lambda:GetLayerVersion --principal "*" \
        --region $region

    echo "Published layer for region $region, python version $aws_version_key, layer_name $layer_name, layer_version $version_nbr"
}

BATCH_SIZE=60
PIDS=()

wait_for_processes() {
    for pid in "${PIDS[@]}"; do
        wait $pid
    done
    PIDS=()
}

for region in "${REGIONS[@]}"
do
    echo "Starting publishing layer for region $region..."

    # Publish the layers for each version of python
    i=0
    for layer_name in "${LAYER_NAMES[@]}"; do
        aws_version_key="${PYTHON_VERSIONS_FOR_AWS_CLI[$i]}"
        layer_path="${LAYER_PATHS[$i]}"

        publish_layer $region $layer_name $aws_version_key $layer_path &
        PIDS+=($!)
        if [ ${#PIDS[@]} -eq $BATCH_SIZE ]; then
            wait_for_processes
        fi

        i=$(expr $i + 1)

    done
done

wait_for_processes

echo "Done !"
