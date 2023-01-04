# Vertical pod autoscaler
https://jsw.ibm.com/browse/OCPONZ-1188

## About Vertical pod autoscaler
The OpenShift Container Platform Vertical Pod Autoscaler Operator (VPA) automatically reviews the historic and current CPU and memory resources for containers in pods and can update the resource limits and requests based on the usage values it learns. The VPA uses individual custom resources (CR) to update all of the pods associated with a workload object, such as a `Deployment, DeploymentConfig, StatefulSet, Job, DaemonSet, ReplicaSet, or ReplicationController` in a project.

To use the Vertical Pod Autoscaler Operator (VPA), we need to create a VPA custom resource (CR) for a workload object in your cluster. The VPA learns and applies the optimal CPU and memory resources for the pods associated with that workload object. You can use a VPA with a `deployment, stateful set, job, daemon set, replica set, or replication controller` workload object. The VPA CR must be in the same project as the pods you want to monitor.

The different modes which is offered by VPA are given below:

The **`Auto or Recreate`** modes automatically apply the VPA CPU and memory recommendations throughout the pod lifetime. The VPA deletes any pods in the project that are out of alignment with its recommendations. When redeployed by the workload object, the VPA updates the new pods with its recommendations.

The **`Initial mode`** automatically applies VPA recommendations only at pod creation.

The **`Off mode`** only provides recommended resource limits and requests, allowing you to manually apply the recommendations. The off mode does not update pods.

## The scripts in this repository can be run manually and also on jenkins pipeline.

**Follow the below steps to execute the test cases Manually**

### Install VPA Operator
`oc apply -f vpa_install.yaml`

make sure to update "channel" and "source" according to your cluster in vpa_install.yaml

details can be found using below command

`oc describe packagemanifests vertical-pod-autoscaler -n openshift-marketplace | grep -e "Default Channel:" -e "Catalog Source:"`

### Please create "dockerconfigjson" file before using any script, you can use below steps:
```
1. copy <jfrog-key> from https://eu.artifactory.swg-devops.com/ui/admin/artifactory/user_profile
2. echo -n '<yourid>@ibm.com:<jfrog-key>' | base64 -w 0
3. Create dockerconfigjson file, sample is below.
{
  "HttpHeaders": {
    "User-Agent": "Docker-Client/19.03.8 (darwin)"
  },
  "auths": {
    "sys-loz-test-team-docker-local.artifactory.swg-devops.com": {
            "auth": "<replace_with_above_base64_key>"
  }
 }
}
4. oc create secret generic secret-jfrog --from-file=.dockerconfigjson=dockerconfigjson --type=kubernetes.io/dockerconfigjson
```
The `Auto`, `initial` and `off` UpdateModes along with container exemption scenario in VPA can be tested by executing the scripts mentioned below respectively

`sh um_auto.sh`

`sh um_initial.sh`

`sh um_off.sh`

`sh c_e.sh`

All the above testcases can be executed form Jenkins pipeline - https://sys-soltest-team-jenkins.swg-devops.com/job/OCP%20DevTest/job/kitchen-sink/job/vertical-pod-autoscaler/. Run a new test after passing in cluster specific parameters.
