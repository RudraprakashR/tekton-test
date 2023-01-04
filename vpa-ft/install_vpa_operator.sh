#!/usr/bin/bash

export VPA_NS=openshift-vertical-pod-autoscaler
export CATALOG_IMAGE=quay.io/openshift-release-dev/ocp-release-nightly:iib-int-index-art-operators-4.12

SSH="ssh -o StrictHostKeyChecking=no"
oc version
$SSH core@$(oc get node | grep master | head -1 | awk '{print $1}') 'cat /etc/*release | grep -w "VERSION="'

oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode |  jq '.auths |= .+ {"brew.registry.redhat.io":{"auth":"fHNoYXJlZC1xZS10ZW1wLnNyYzUuNzViNGQ1OmV5SmhiR2NpT2lKU1V6VXhNaUo5LmV5SnpkV0lpT2lJNU1HRmlOVGMxTlRZME4yWTBOelUyT0RRek56ZG1NR0UwTXpZMFpUTmxaaUo5LlF6YnJsTjQ5TFRIREFKcWFPcEhuVExTRFJfclBLbF9PdjB6VTJWV21OVDRBMUNXZFA3TWR1aDR6azhRbmZUWGtSaXV0UWRIQVJRMUVYMEZpM1pEeDk0aVd2OEpROEc3Ri1Lek1mYm8waTM1c2ROM3kzVXFTekF3QW5DeHVlS3EwZTA5QWRUbFRuS29KOTk3SWVoUnNNMDlSLVNfUlA0MmpIU3pvZWlJcTB2Vml5eUxLSUpNVV9SN1o5cHVqZE1OWHJLcU1hRFk3TnQ1d1c1VURCRm5lcl9Jc3Z5RDVHS2Mtc2FzdzlIdDJvQW5ENlhYajhjc1RKNzlKakFqbjVKOFgyZUE1U3l1elF6UzZSSnc2OXZiZXAyaXFyMl95LVdLeXZpZXNCenlPZzZnNGhvOXE4WXRVRjVKek5KVTRiRmhUSE45Z1BQaEQ5QWZEamx6SnFySjhIcUp4RTcyekpWTnhnM2JXbWV2YkY3NXN1enNMS1VJREJORkpBYXA1eWhEMWxHdUtTN2dhS2M2d3VqNlUtTzRrdmtBaVpRR1NDdUxTaEkxRWk1dEFXcTVEYWhYYlVaZ0l1ZktSZzFfTTBhWmpTU1JRak1JcEZrX1lMYi1HcmwwRDE5TG9vV1gwV1BwUjhDc3VLTFVFTGVFOGNJbEpjUDNlRzJkMV9tTzYzSGJkbEo5QlNaUXh3dWpGd3hwbndReEE3TG1oVXZCdDJOU3V3LVlIVDdkeFN3X3V6YlByX0ZwWmhaQnEzY01XZHhxV0VlOWFtT0xUbnJzbjE4Zms3RWpJd0RWc3hEc1pMRlp6NjhzSlUyRFNFdmdTWEhRcjBWR3lSeHRWcTY2RkJGbEhYaXpjVHY1MXZ2Wk84T0Z5dmxfbXkzamZPUjJOTGdWb09MX3JNRWhyc3JF"}}' | jq -c . > secret.json
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=secret.json


cat << EOF | oc apply -f -
 apiVersion: operator.openshift.io/v1alpha1
 kind: ImageContentSourcePolicy
 metadata:
   name: brew-registry
 spec:
   repositoryDigestMirrors:
   - mirrors:
     - brew.registry.redhat.io
     source: registry.redhat.io
   - mirrors:
     - brew.registry.redhat.io
     source: registry.stage.redhat.io
   - mirrors:
     - brew.registry.redhat.io
     source: registry-proxy.engineering.redhat.com
EOF
sleep 25
cat << EOF | oc apply -f -
 apiVersion: operators.coreos.com/v1alpha1
 kind: CatalogSource
 metadata:
   name: quay-catalog
   namespace: openshift-marketplace
 spec:
   sourceType: grpc
   image: ${CATALOG_IMAGE}
   displayName: quay-catalog
   publisher: redhat
EOF

for index in `seq 1 6`
    do
       status=`oc get pods -n openshift-marketplace | grep "quay-catalog"   | tr -s ' '  | cut -d ' ' -f 2 | cut -d / -f 1,2`
       if [[ ${status} = "1/1" ]]; then
          echo -e "\n quay catalog pods have come up \n"
          oc get pods -n openshift-marketplace | grep "quay catalog"
          break
      else
      echo -e "\n---Wait for quay catalog pod to come up.... \n"
                  sleep 20
      fi
      index=$(( index + 1 ))
      if [[ $index -eq 7 ]]; then
      echo  "quay catalog pod is not ready, please check"
      exit 1
      fi
done

oc create ns ${VPA_NS} -o yaml | oc label -f - security.openshift.io/scc.podSecurityLabelSync=false pod-security.kubernetes.io/enforce=privileged pod-security.kubernetes.io/audit=privileged pod-security.kubernetes.io/warn=privileged --overwrite
sleep 5

cat << EOF | oc apply -f -
 apiVersion: operators.coreos.com/v1
 kind: OperatorGroup
 metadata:
   generateName: openshift-vertical-pod-autoscaler
   name: openshift-vertical-pod-autoscaler
   namespace: ${VPA_NS}
 spec:
   targetNamespaces:
   - ${VPA_NS}
EOF


sleep 5

cat << EOF | oc apply -f -
 apiVersion: operators.coreos.com/v1alpha1
 kind: Subscription
 metadata:
   name: openshift-vertical-pod-autoscaler
   namespace: ${VPA_NS}
 spec:
   channel: "stable"
   installPlanApproval: Automatic
   name: vertical-pod-autoscaler
   source: quay-catalog
   sourceNamespace: openshift-marketplace
EOF

for index in `seq 1 10`
    do
       status=`oc get pods -n ${VPA_NS} | grep vertical-pod-autoscaler-operator | tr -s ' '  | cut -d ' ' -f 2 | cut -d / -f 1,2`

       if [[ ${status} = "1/1" ]]; then
          echo -e "\n VPA controller pod is up and running \n"
          echo -e "\n ------------ All pods and service and deployment and replicaset and jobs running in ${VPA_NS} -------------- \n"
          oc get operator | egrep -i "vertical-pod-autoscaler.openshift-vertical-pod-autoscaler"
          oc get csv -n ${VPA_NS}
          oc get sub -n ${VPA_NS}
          oc get all -n ${VPA_NS}
          break
      else
      echo -e "\n---Waiting for VPA controller pod to come up.... \n"
            sleep 20
      fi
      index=$(( index + 1 ))
      if [[ $index -eq 11 ]]; then
      echo  "VPA controller pod is not ready, please check"
      exit 1
      fi
done
