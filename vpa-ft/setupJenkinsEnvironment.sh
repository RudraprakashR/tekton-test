#!/bin/bash
#########################################
## setupjenkinsEnvironment.sh
## This template configures a jenkins pod environment for testing openshift on z
## Script establishes oc connection to $Cluster_IP cluster and creates a new ocp project with pull access to artifactory registry
#########################################

# Check sudo access. Required
if [ "$(sudo whoami)" != "root" ]; then
    echo "need sudo access"
    exit 1
fi

# setup /etc/hosts
if ! echo "$Cluster_IP $etc_hosts" | sudo tee -a /etc/hosts; then
    echo "Fail to add value to /etc/hosts"
    exit 1
fi
#Check values properly written to /etc/hosts
if ! grep --silent "$Cluster_IP $etc_hosts" /etc/hosts  ; then
    echo "Failed to read value from /etc/hosts after it was added"
    exit 1
fi
echo "Added $Cluster_IP $etc_hosts to /etc/hosts"

# Setup BOE Firewall connection if needed
BOE_VPN=${BOE_VPN:-false}
if [[ "$BOE_VPN" == "false" ]]; then
    echo "No BOE sshuttle VPN needed"
else
    echo "BOE sshuttle VPN needed; setting up now"
    if echo "$Cluster_IP" | grep -q "172.18" ; then
        export BOE_GATEWAY=lnxgwne1.boeblingen.de.ibm.com
        if [ -z "$BOE_CONNECT_LNXGWNE_USR" ] || [ -z "$BOE_CONNECT_LNXGWNE_PSW" ]; then
            echo "BOE CONNECT jenkins secrets not available"
            exit 1
        fi
        export BOE_CONNECT_USR="$BOE_CONNECT_LNXGWNE_USR"
        export BOE_CONNECT_PSW="$BOE_CONNECT_LNXGWNE_PSW"
        export SSHUTTLERANGE="172.18.0.0/15"
    elif echo "$Cluster_IP" | grep -q "172.23" ; then
        export BOE_GATEWAY=lnxgwero1.boeblingen.de.ibm.com
        if [ -z "$BOE_CONNECT_LNXGWERO_USR" ] || [ -z "$BOE_CONNECT_LNXGWERO_PSW" ]; then
            echo "BOE CONNECT jenkins secrets not available"
            exit 1
        fi
        export BOE_CONNECT_USR="$BOE_CONNECT_LNXGWERO_USR"
        export BOE_CONNECT_PSW="$BOE_CONNECT_LNXGWERO_PSW"
        export SSHUTTLERANGE="172.23.0.0/15"
    else
        echo "No sshuttle gateway known by workload to allow access to $BOE_GATEWAY."
        exit 1
    fi
    # setup sshpass and sshuttle
    sudo apt-get -qq update
    sudo apt-get -qq install sshpass sshuttle
    # make auto add hosts to config file (so we dont have to interactivly accept)
    echo "StrictHostKeyChecking=no" | sudo tee -a /etc/ssh/ssh_config
    tail /etc/ssh/ssh_config

    # sshuttle into the cluster
    sshpass -p "$BOE_CONNECT_PSW" sshuttle -r "$BOE_CONNECT_USR@$BOE_GATEWAY" $SSHUTTLERANGE > /tmp/sshuttle.log 2>&1 &
      # Now check to see if the sshuttle command has gotten a connection
    sleep 20
    if grep "client: Connected." /tmp/sshuttle.log ; then
        echo 'BOE sshuttle succedded'
    else
        echo 'BOE sshuttle failed'
        exit 1
    fi
fi

# Install oc and kubectl
oc_cli_version=${oc_cli_version:-stable-4.11}
oc_install_url=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$oc_cli_version/openshift-client-linux.tar.gz
if ! wget -nv "$oc_install_url"; then
    echo "wget oc command failed"
    exit 1
fi
if ! tar -xf ./openshift-client-linux.tar.gz; then
    echo "extracting oc archive failed"
    exit 1
fi
chmod +x ./kubectl
chmod +x ./oc
sudo cp -p ./kubectl /usr/local/bin/
sudo cp -p ./oc /usr/local/bin/
if ! oc > /dev/null ; then
    echo "oc failed to be added to path"
    exit 1
fi
if ! kubectl > /dev/null; then
    echo "kubectl failed to be added to path"
    exit 1
fi

#oc_login
if ! oc login -u "$OCP_ADMIN_JENKINS_USR" -p "$OCP_ADMIN_JENKINS_PSW" --server="$Cluster_IP:6443" --insecure-skip-tls-verify=true; then
    echo "Failed to login to OCP cluster for server $Cluster_IP"
    exit 4
fi
#check cluster authentication succeeded
if [ "$(oc whoami)" != "$OCP_ADMIN_JENKINS_USR" ] && [ "$(oc whoami)" != 'kube:admin' ] ; then
   echo "I expected $OCP_ADMIN_JENKINS_USR, instead I am $(oc whoami)"
   exit 5
fi
echo "Logged into cluster succefully with oc"
oc version

# Create the project 
# If individual project and artifactory secret is not needed for jenkins job, delete the rest of this file.
oc new-project "$OCPPRJT" || oc project "$OCPPRJT"

# Add Artifactory pull secret to project
if [[ $(oc get secrets sys-loz-artifactory --ignore-not-found --no-headers | wc -l) -ne 0 ]]; then
    # Secret with the same name is already there, contining without art setup
    echo "There is already a secret by that name"
else
    # Adding art pull secret
    if ! oc create secret docker-registry sys-loz-artifactory --docker-server=sys-loz-test-team-docker-local.artifactory.swg-devops.com --docker-username="$ARTIFACTORY_CREDS_USR" --docker-password="$ARTIFACTORY_CREDS_PSW"; then
        echo "Secret creation failed"
        exit 5
    fi
    if ! oc secrets link default "sys-loz-artifactory" --for=pull; then
        echo "Setting as default pull secret failed"
        exit 6
    fi
    echo "Artifactory pull secret created in $OCPPRJT"
fi
