#!/bin/bash
## TC - When UpdateMode set to Auto/Recreate https://issues.redhat.com/browse/MULTIARCH-1525
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
  name: my-vpa
  namespace: project-vpa-test
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind:       Deployment
    name:       my-auto-deployment
  updatePolicy:
    updateMode: "Auto"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-auto-deployment
  namespace: project-vpa-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-auto-deployment
  template:
    metadata:
      labels:
        app: my-auto-deployment
    spec:
      containers:
      - name: my-container
        image: sys-loz-test-team-docker-local.artifactory.swg-devops.com/ubuntu:latest
        resources:
          requests:
            cpu: 100m
            memory: 50Mi
        command: ["/bin/sh"]
        args: ["-c", "while true; do timeout 0.5s yes >/dev/null; sleep 0.5s; done"]
EOF

echo "#############################################"
echo "# TC - When UpdateMode set to Auto/Recreate #"
echo "#############################################"

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


while :; do
    oc get pods -n project-vpa-test | grep Running
    if [ $? -eq 0 ]; then
       echo "Application deployed successfully ....."
       echo " "
       oc get pods -n project-vpa-test
       break 
    else
	echo "Checking after 2 seconds"
        sleep 2
    fi
done

echo " "
echo "Verfying if VPA Auto mode is working ..."
echo " "
oc get pods -n project-vpa-test
pod1=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | head -n1)
pod2=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | tail -n1)

while :; do
   # pod1_u=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | head -n1)
   # pod2_u=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | tail -n1)
    oc get pods -n project-vpa-test | grep -e $pod1 -e $pod2 > /dev/null 2>&1
    #if [ "$pod1" == "$pod1_u" ] || [ "$pod2" == "$pod2_u" ]; then
    if [ $? -eq 0 ]; then
       echo "New pods still not rolled out ..., checking after 5 seconds"
       sleep 5
       oc get pods -n project-vpa-test
    else
     echo " "
     echo "New pods rolled....."
     echo "VPA Autoupdate mode is working .... !!"
     echo " "
     oc describe vpa my-vpa
     oc describe pods -n project-vpa-test
     echo " "
     echo "########################################################"
     echo "Passed , VPA Autoupdate mode is working .... !!"
     echo "########################################################"
     echo " "
     break
    fi
done


echo " "
echo "Cleaning up....."
oc delete project project-vpa-test
