#!/usr/bin/env nu

source  scripts/kubernetes.nu
source  scripts/ingress.nu
source  scripts/common.nu
source  scripts/cnpg.nu

def main [] {}

# Creates a local Kubernetes cluster
def "main setup" [] {

    main create kubernetes kind 

    main apply ingress nginx --hyperscaler kind

    kubectl create namespace a-team

    main apply cnpg

    main print source
    
}
