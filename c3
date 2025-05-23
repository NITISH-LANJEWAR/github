name: Promote to UAT

env:
  OPENSHIFT_NAMESPACE: "github-arc"
  IMAGE_REGISTRY_USER: ${{ github.actor }}
  IMAGE_REGISTRY_PASSWORD: ${{ github.token }}

on:
  push:
    branches:
      - dev
  workflow_dispatch:
    inputs:
      APP_NAME:
        description: 'App Name'
        required: true
        default: 'cash-out-management-eapi'
      ARTIFACTORY_PROJECT:
        description: 'Image Registry Project'
        required: true
        default: 'exp-layer-zm-dev'
        type: choice
        options:
          - exp-layer-zm-dev
          - exp-layer-zm-uat
      ENVIRONMENT:
        description: 'Environment to deploy to'
        required: true
        default: 'uat'
        type: choice
        options:
          - dev
          - uat
      OCP_CLUSTER:
        description: 'OpenShift Cluster'
        required: false
        default: 'OCP3-SDC'
        type: choice
        options:
          - OCP3-270
          - OCP3-SDC
      DEPLOYMENT_NAMESPACE:
        description: 'Deployment Namespace'
        required: true
        default: 'experience-layer-zambia-uat'

jobs:
  promote:
    name: Build and Deploy to OpenShift
    runs-on: github-arc-runners
    environment: ${{ github.event.inputs.OCP_CLUSTER }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          repository: absa-group/cash-out-management-eapi
          ref: feature/cashout-redemption
          path: exp-layer-devops
          token: ${{ secrets.PERSONAL_ACCESS_TOKEN }}

      - name: Install OpenShift CLI (oc)
        uses: redhat-actions/openshift-tools-installer@v1
        with:
          oc: 3.11

      - name: Login to OpenShift
        uses: redhat-actions/oc-login@v1
        with:
          openshift_server_url: ${{ secrets.OPENSHIFT_SERVER }}
          openshift_token: ${{ secrets.OPENSHIFT_TOKEN }}
          namespace: ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }}
          insecure_skip_tls_verify: true

      - name: Switch to target OpenShift project
        run: |
          oc project ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }}

      - name: Promote image from dev to uat
        run: |
          oc import-image ${{ github.event.inputs.APP_NAME }}:latest \
            --from=image-registry.openshift-image-registry.svc:5000/experience-layer-zambia-dev/${{ github.event.inputs.APP_NAME }}:latest \
            --confirm \
            -n ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }}

      - name: Promote DeploymentConfig to UAT
        run: |
          oc get dc/${{ github.event.inputs.APP_NAME }} -n experience-layer-zambia-dev -o yaml > dc.yaml
          yq e 'del(.metadata.resourceVersion)' -i dc.yaml
          oc apply -f dc.yaml -n ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }}

      - name: Sync Service and Route
        run: |
          for resource in svc route; do
            oc get $resource -l app=${{ github.event.inputs.APP_NAME }} -n experience-layer-zambia-dev -o yaml > $resource.yaml || true
            oc apply -f $resource.yaml -n ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }} || true
          done

      - name: Check rollout status
        run: |
          oc rollout status dc/${{ github.event.inputs.APP_NAME }} -n ${{ github.event.inputs.DEPLOYMENT_NAMESPACE }}
