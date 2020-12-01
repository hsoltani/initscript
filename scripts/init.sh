#!/bin/bash

# creates genesis block and certificates
# and copies them to hlf-kube/ folder
# if version not passed in, default to latest released version
# if version not passed in, default to latest released version
dnf -y install git
VERSION=1.4.0
# if ca version not passed in, default to latest released version
CA_VERSION=1.4.9
ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')")
MARCH=$(uname -m)

printHelp() {
    echo "Usage: bootstrap.sh [version [ca_version]] [options]"
    echo
    echo "options:"
    echo "-h : this help"
    echo "-d : bypass docker image download"
    echo "-s : bypass fabric-samples repo clone"
    echo "-b : bypass download of platform-specific binaries"
    echo
    echo "e.g. bootstrap.sh 2.3.0 1.4.9 -s"
    echo "will download docker images and binaries for Fabric v2.3.0 and Fabric CA v1.4.9"
}

# dockerPull() pulls docker images from fabric and chaincode repositories
# note, if a docker image doesn't exist for a requested release, it will simply
# be skipped, since this script doesn't terminate upon errors.

dockerPull() {
    #three_digit_image_tag is passed in, e.g. "1.4.7"
    three_digit_image_tag=$1
    shift
    #two_digit_image_tag is derived, e.g. "1.4", especially useful as a local tag for two digit references to most recent baseos, ccenv, javaenv, nodeenv patch releases
    two_digit_image_tag=$(echo "$three_digit_image_tag" | cut -d'.' -f1,2)
    while [[ $# -gt 0 ]]
    do
        image_name="$1"
        echo "====> hyperledger/fabric-$image_name:$three_digit_image_tag"
        docker pull "hyperledger/fabric-$image_name:$three_digit_image_tag"
        docker tag "hyperledger/fabric-$image_name:$three_digit_image_tag" "hyperledger/fabric-$image_name"
        docker tag "hyperledger/fabric-$image_name:$three_digit_image_tag" "hyperledger/fabric-$image_name:$two_digit_image_tag"
        shift
    done
}

cloneSamplesRepo() {
    # clone (if needed) hyperledger/fabric-samples and checkout corresponding
    # version to the binaries and docker images to be downloaded
    if [ -d first-network ]; then
        # if we are in the fabric-samples repo, checkout corresponding version
        echo "==> Already in fabric-samples repo"
    elif [ -d fabric-samples ]; then
        # if fabric-samples repo already cloned and in current directory,
        # cd fabric-samples
        echo "===> Changing directory to fabric-samples"
        cd fabric-samples
    else
        echo "===> Cloning hyperledger/fabric-samples repo"
        git clone -b master https://github.com/hyperledger/fabric-samples.git && cd fabric-samples
    fi

    if GIT_DIR=.git git rev-parse v${VERSION} >/dev/null 2>&1; then
        echo "===> Checking out v${VERSION} of hyperledger/fabric-samples"
        git checkout -q v${VERSION}
    else
        echo "fabric-samples v${VERSION} does not exist, defaulting master"
        git checkout -q master
    fi
}

# This will download the .tar.gz
download() {
    local BINARY_FILE=$1
    local URL=$2
    echo "===> Downloading: " "${URL}"
    curl -L --retry 5 --retry-delay 3 "${URL}" | tar xz || rc=$?
    if [ -n "$rc" ]; then
        echo "==> There was an error downloading the binary file."
        return 22
    else
        echo "==> Done."
    fi
}

pullBinaries() {
    echo "===> Downloading version ${FABRIC_TAG} platform specific fabric binaries"
    download "${BINARY_FILE}" "https://github.com/hyperledger/fabric/releases/download/v${VERSION}/${BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${FABRIC_TAG} platform specific fabric binary is not available to download <----"
        echo
        exit
    fi

    echo "===> Downloading version ${CA_TAG} platform specific fabric-ca-client binary"
    download "${CA_BINARY_FILE}" "https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/${CA_BINARY_FILE}"
    if [ $? -eq 22 ]; then
        echo
        echo "------> ${CA_TAG} fabric-ca-client binary is not available to download  (Available from 1.1.0-rc1) <----"
        echo
        exit
    fi
}

pullDockerImages() {
    command -v docker >& /dev/null
    NODOCKER=$?
    if [ "${NODOCKER}" == 0 ]; then
        FABRIC_IMAGES=(peer orderer ccenv tools)
        case "$VERSION" in
        2.*)
            FABRIC_IMAGES+=(baseos)
            shift
            ;;
        esac
        echo "FABRIC_IMAGES:" "${FABRIC_IMAGES[@]}"
        echo "===> Pulling fabric Images"
        dockerPull "${FABRIC_TAG}" "${FABRIC_IMAGES[@]}"
        echo "===> Pulling fabric ca Image"
        CA_IMAGE=(ca)
        dockerPull "${CA_TAG}" "${CA_IMAGE[@]}"
        echo "===> List out hyperledger docker images"
        docker images | grep hyperledger
    else
        echo "========================================================="
        echo "Docker not installed, bypassing download of Fabric images"
        echo "========================================================="
    fi
}

DOCKER=true
SAMPLES=true
BINARIES=true

# Parse commandline args pull out
# version and/or ca-version strings first
if [ -n "$1" ] && [ "${1:0:1}" != "-" ]; then
    VERSION=$1;shift
    if [ -n "$1" ]  && [ "${1:0:1}" != "-" ]; then
        CA_VERSION=$1;shift
        if [ -n  "$1" ] && [ "${1:0:1}" != "-" ]; then
            THIRDPARTY_IMAGE_VERSION=$1;shift
        fi
    fi
fi

# prior to 1.2.0 architecture was determined by uname -m
if [[ $VERSION =~ ^1\.[0-1]\.* ]]; then
    export FABRIC_TAG=${MARCH}-${VERSION}
    export CA_TAG=${MARCH}-${CA_VERSION}
    export THIRDPARTY_TAG=${MARCH}-${THIRDPARTY_IMAGE_VERSION}
else
    # starting with 1.2.0, multi-arch images will be default
    : "${CA_TAG:="$CA_VERSION"}"
    : "${FABRIC_TAG:="$VERSION"}"
    : "${THIRDPARTY_TAG:="$THIRDPARTY_IMAGE_VERSION"}"
fi

BINARY_FILE=hyperledger-fabric-${ARCH}-${VERSION}.tar.gz
CA_BINARY_FILE=hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz

# then parse opts
while getopts "h?dsb" opt; do
    case "$opt" in
        h|\?)
            printHelp
            exit 0
            ;;
        d)  DOCKER=false
            ;;
        s)  SAMPLES=false
            ;;
        b)  BINARIES=false
            ;;
    esac
done

if [ "$SAMPLES" == "true" ]; then
    echo
    echo "Clone hyperledger/fabric-samples repo"
    echo
    cloneSamplesRepo
fi
if [ "$BINARIES" == "true" ]; then
    echo
    echo "Pull Hyperledger Fabric binaries"
    echo
    pullBinaries
fi
if [ "$DOCKER" == "true" ]; then
    echo
    echo "Pull Hyperledger Fabric docker images"
    echo
    pullDockerImages
fi



#dnf install jq
#dnf -y install python-pip
#pip install yq
#curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/v1.4.2/scripts/bootstrap.sh | bash

#yum install git make automake gcc gcc-c++ kernel-devel
#mkdir -p $GOPATH/src/github.com/hyperledger
#cd $GOPATH/src/github.com/hyperledger
#git clone https://github.com/hyperledger/fabric/tree/release-1.4
#cd fabric
#make cryptogen
#make docker
#PATH=$PATH:$GOPATH/src/github.com/hyperledger/fabric/build/bin

config_file=./network.yaml

rm -rf crypto-config
rm -rf channel-artifacts

mkdir -p channel-artifacts

# generate certs
echo "-- creating certificates --"
cryptogen generate --config ./crypto-config.yaml --output crypto-config

# place holder empty folders for external peer orgs
externalPeerOrgs=$(yq '.ExternalPeerOrgs // empty' ./crypto-config.yaml -r -c)
if [ "$externalPeerOrgs" ]; then
    echo "-- creating empty folders for external peer orgs --"
    for peerOrgDomain in $(echo "$externalPeerOrgs" | jq -r '.[].Domain'); do
        echo "$peerOrgDomain"
        mkdir -p "./crypto-config/peerOrganizations/$peerOrgDomain/msp"
    done
fi 

# place holder empty folders for external orderer orgs
externalOrdererOrgs=$(yq '.ExternalOrdererOrgs // empty' ./crypto-config.yaml -r -c)
if [ "$externalOrdererOrgs" ]; then
    echo "-- creating empty folders for external orderer orgs --"
    for ordererOrg in $(echo "$externalOrdererOrgs" | jq -rc '.[]'); do
        # echo "$ordererOrg"
        ordererOrgDomain=$(echo "$ordererOrg" | jq -r '.Domain')
        echo "$ordererOrgDomain"
        mkdir -p "./crypto-config/ordererOrganizations/$ordererOrgDomain/msp/tlscacerts"
        for ordererHostname in $(echo "$ordererOrg" | jq -r '.Specs[].Hostname'); do
            # echo "ordererHostname: $ordererHostname"
            mkdir -p "./crypto-config/ordererOrganizations/$ordererOrgDomain/orderers/$ordererHostname.$ordererOrgDomain/tls"
        done
    done
fi 


if [ "$create_genesis_block" == true ]; then
    # generate genesis block
    echo "-- creating genesis block --"
    genesisProfile=$(yq '.network.genesisProfile' $config_file -r)
    systemChannelID=$(yq '.network.systemChannelID' $config_file -r)
    configtxgen -profile $genesisProfile -channelID $systemChannelID -outputBlock ./channel-artifacts/genesis.block
else
    echo "-- skipping genesis block creation --"
fi

# copy stuff hlf-kube folder (as helm charts cannot access files outside of chart folder)
# see https://github.com/helm/helm/issues/3276#issuecomment-479117753
cd $current_folder

rm -rf hlf-kube/crypto-config
rm -rf hlf-kube/channel-artifacts

cp -r $project_folder/crypto-config hlf-kube/
cp -r $project_folder/channel-artifacts hlf-kube/

cp -r $project_folder/configtx.yaml hlf-kube/

# prepare chaincodes
./prepare_chaincodes.sh $project_folder $chaincode_folder
