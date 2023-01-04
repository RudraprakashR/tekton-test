#!/bin/bash
## TC - When UpdateMode set to Initial https://issues.redhat.com/browse/MULTIARCH-1525
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
    updateMode: "Initial"
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

echo "#######################################"
echo "# TC - When UpdateMode set to Initial #"
echo "#######################################"

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

pod1=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | head -n1)
pod2=$(oc get pods -n project-vpa-test -o=jsonpath='{range .items..metadata}{.name}{"\n"}{end}' | tail -n1)

mem_before_vpa1=$(oc describe pod $pod1 -n project-vpa-test | grep memory: | cut -d " " -f12)
mem_before_vpa2=$(oc describe pod $pod2 -n project-vpa-test | grep memory: | cut -d " " -f12)

echo "$pod1 memory before VPA applied is $mem_before_vpa1"
echo "$pod2 memory before VPA applied is $mem_before_vpa2"


echo "Deleting pod to initiate VPAs settings...."
sleep 60
oc delete pod $pod1 -n project-vpa-test
oc delete pod $pod2 -n project-vpa-test
echo " "
echo " "
vpa_mem_recomm=$(oc describe vpa my-vpa -n project-vpa-test | grep Memory | head -n1 | cut -d " " -f11)
echo "Memory of $pod1 should be $vpa_mem_recomm after VPA applied"
echo "Memory of $pod2 should be $vpa_mem_recomm after VPA applied"
echo " "
echo " "


pod1_i=$(oc get pods -n project-vpa-test| cut -d " " -f1 | grep my-auto | head -n1)
pod2_i=$(oc get pods -n project-vpa-test| cut -d " " -f1 | grep my-auto | tail -n1)

mem_after_vpa1=$(oc describe pod $pod1_i -n project-vpa-test | grep memory: | cut -d " " -f12)
mem_after_vpa2=$(oc describe pod $pod2_i -n project-vpa-test | grep memory: | cut -d " " -f12)

echo "Verfying if VPA Auto mode is working ..."
echo " "
echo Memory of pod $pod1_i is $mem_after_vpa1 after applying VPA
echo Memory of pod $pod2_i is $mem_after_vpa2 after applying VPA
echo Memory recommended by VPA is $vpa_mem_recomm

    if [ "$mem_after_vpa1" == "$vpa_mem_recomm" ] && [ "$mem_after_vpa2" == "$vpa_mem_recomm" ]; then
       echo "New pod is updated with VPA reccomendations ..."
       oc describe vpa my-vpa
       oc describe pods -n project-vpa-test
       echo " "
       echo "################################################"
       echo "Passed !!"
       echo "################################################"
       echo " "
    else
     echo " Test Failed "
    fi

echo " "
echo " "

echo " "
echo "Cleaning up....."
oc delete project project-vpa-test
