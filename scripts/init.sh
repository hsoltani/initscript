#!/bin/bash

# creates genesis block and certificates
# and copies them to hlf-kube/ folder
#dnf install jq
#dnf -y install python-pip
#pip install yq
#curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/v1.4.2/scripts/bootstrap.sh | bash
yum install git make automake gcc gcc-c++ kernel-devel
mkdir -p $GOPATH/src/github.com/hyperledger
cd $GOPATH/src/github.com/hyperledger
git clone https://github.com/hyperledger/fabric/tree/release-1.4
cd fabric
make cryptogen
make docker
PATH=$PATH:$GOPATH/src/github.com/hyperledger/fabric/build/bin

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
