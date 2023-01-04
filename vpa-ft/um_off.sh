#!/bin/bash
## TC - When UpdateMode set to Off https://issues.redhat.com/browse/MULTIARCH-1525
## Nishant Chauhan
## nishantchauhan@in.ibm.com
## nichauha@redhat.com
## Using sample application https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/examples/hamster.yaml
## will be using the above application throughout the testing


###echo "Creating sample application deployment file"
cat > vpa_dep.yaml <<EOF
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-rec-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind:       Deployment
    name:       my-rec-deployment
  updatePolicy:
    updateMode: "Off"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-rec-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-rec-deployment
  template:
    metadata:
      labels:
        app: my-rec-deployment
    spec:
      containers:
      - name: my-rec-container
        image: sys-loz-test-team-docker-local.artifactory.swg-devops.com/nginx
EOF

echo "###################################"
echo "# TC - When UpdateMode set to Off #"
echo "###################################"

oc projects | grep project-vpa-test
        if [ $? -eq 0 ]
        then
          echo " "
          echo "Project is already there, Recreating project..."
          echo " "
          oc delete project project-vpa-test
          sleep 60
          oc new-project project-vpa-test
          oc create secret generic secret-jfrog --from-file=.dockerconfigjson=dockerconfigjson --type=kubernetes.io/dockerconfigjson -n project-vpa-test
          oc secrets link default secret-jfrog --for=pull -n project-vpa-test
        else
          echo " "
          echo "Creating Project ...."
          echo " "
          oc new-project project-vpa-test
          oc create secret generic secret-jfrog --from-file=.dockerconfigjson=dockerconfigjson --type=kubernetes.io/dockerconfigjson -n project-vpa-test
          oc secrets link default secret-jfrog --for=pull -n project-vpa-test
          sleep 10
        fi


echo " "
echo "Allowing container to run as root as rqeuired by nginx"
oc adm policy add-scc-to-user anyuid -z default -n project-vpa-test
echo " "
echo " "
echo "Deploying Sample Application and VPA object"
oc apply -f vpa_dep.yaml
echo "Waiting for 1 minute to let application deployed..."
sleep 60

oc get pods -n project-vpa-test | grep my-rec-deployment | grep Running
        if [ $? -eq 0 ]
        then
          echo " "
          echo "Sample Application  deployed succesfully ...."
          echo " "
        else
          echo " "
          echo "Sample application not deployed ..Please check the secret keys, or may be try one more time ..."
          echo " "
          exit 1
        fi

echo " "
echo "Verfying if VPA recommendations are visible"
echo " "
while true; do
    oc get vpa my-rec-vpa --output yaml -n project-vpa-test| grep containerRecommendations
    if [ $? -eq 0 ]; then
        oc describe vpa my-rec-vpa -n project-vpa-test
	echo " "
	echo "####################################################"
	echo "Passed !!!! , VPA recommendations are visible !!"
        echo "####################################################"
	echo " "
        break
    fi
    echo " "
    echo "VPA recommendations are not visible, Checking again after 1 minute"
    echo " "
    sleep 60
done
echo " "
echo "Cleaning up....."
oc delete project project-vpa-test
