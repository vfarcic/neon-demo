#!/usr/bin/env nu

source  scripts/kubernetes.nu
source  scripts/ingress.nu
source  scripts/common.nu
source  scripts/atlas.nu
source  scripts/image.nu

def main [] {}

def "main setup" [] {

    main create kubernetes kind 

    main apply ingress nginx --hyperscaler kind

    kubectl create namespace a-team

    main apply atlas

    main print source
    
}

def "main run unit_tests" [] {

    go test -v -tags unit

}

def "main update manifests" [
    tag: string # The tag of the image (e.g., 0.0.1)
] {

    sign image $tag

    build helm $tag

    update kustomize $tag

    update kcl $tag

    generate yaml $tag

}

def "main deploy app" [
    neon_conn: string
] {

    main create kubernetes kind

    main apply ingress nginx --hyperscaler kind

    kubectl create namespace a-team

    (
        kubectl --namespace a-team
            create secret generic silly-demo
            --from-literal $"uri=($neon_conn)"
    )

    main apply atlas

    kubectl --namespace a-team apply --filename app.yaml

    (
        kubectl --namespace a-team wait atlasschema silly-demo
            --for=condition=ready --timeout=300s
    )

}

# Signs the image
def "sign image" [
    tag: string                    # The tag of the image (e.g., `0.0.1`)
    --registry_pass: string,       # Registry password. Overwrites environment variable `REGISTRY_PASSWORD`.
    --registry_user = "vfarcic",   # Registry username
    --cosign_private_key: string,  # Cosign private key. Overwrites environment variable `COSIGN_PRIVATE_KEY`.
    --registry = "ghcr.io/vfarcic" # Image registry
    --image = "silly-demo"         # Image name
] {

    mut registry_pass = get_registry_pass $registry_pass

    if $cosign_private_key != null {
        $env.COSIGN_PRIVATE_KEY = $cosign_private_key
    }

    (
        cosign sign --yes --key env://COSIGN_PRIVATE_KEY
            --registry-username $registry_user
            --registry-password $registry_pass
            $"($registry)/($image):($tag)"
    )

}

# Updates Helm files
def "build helm" [
    tag: string                    # The tag of the image (e.g., 0.0.1)
    --push = true                  # Whether to push the chart to the registry
    --registry = "ghcr.io/vfarcic" # Image registry
    --registry_pass: string,       # Registry password. Overwrites environment variable `REGISTRY_PASSWORD`.
    --registry_user = "vfarcic"    # Registry username
] {

    mut registry_pass = get_registry_pass $registry_pass

    open helm/app/Chart.yaml
        | upsert version $tag
        | save helm/app/Chart.yaml --force

    open helm/app/values.yaml
        | upsert image.tag $tag
        | save helm/app/values.yaml --force

    helm package helm/app

    if $push {
        (
            helm registry login
                --username $registry_user
                --password $registry_pass
                $registry
        )
    }

    helm push $"silly-demo-helm-($tag).tgz" $"oci://($registry)"

}

# Updates YAML files
def "generate yaml" [
    tag: string                    # The tag of the image (e.g., 0.0.1)
    --registry = "ghcr.io/vfarcic" # Image registry
    --image = "silly-demo"         # Image name
] {

    kcl run kcl/main.k
    
    kcl run kcl/main.k | save k8s/app.yaml --force

}

# Updates Kustomize files
def "update kustomize" [
    tag: string                    # The tag of the image (e.g., 0.0.1)
    --registry = "ghcr.io/vfarcic" # Image registry
    --image = "silly-demo"         # Image name
] {

    open kustomize/base/deployment.yaml
        | upsert spec.template.spec.containers.0.image $"($registry)/($image):($tag)"
        | save kustomize/base/deployment.yaml --force

}

def "update kcl" [
    tag: string # The tag of the image (e.g., 0.0.1)
] {

    open kcl/values.yaml
        | upsert tag $tag
        | save kcl/values.yaml --force

}
