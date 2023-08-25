#!/bin/bash
# 
# Copyright 2020 Shiyghan Navti. Email shiyghan@gmail.com
#
#################################################################################
##############     Install and Configure Anthos GKE Baremetal     ###############
#################################################################################

# User prompt function
function ask_yes_or_no() {
    read -p "$1 ([y]yes to preview, [n]o to create, [d]del to delete): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        n|no)  echo "no" ;;
        d|del) echo "del" ;;
        *)     echo "yes" ;;
    esac
}

function ask_yes_or_no_proj() {
    read -p "$1 ([y]es to change, or any key to skip): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

export vxlan0_ip_count=1 # to set network counter to start from 10.200.0.2/24
function vxlan0_ip_counter {
  export vxlan0_ip_count=$((vxlan0_ip_count+1))
}

clear
MODE=1
export TRAINING_ORG_ID=$(gcloud organizations list --format 'value(ID)' --filter="displayName:techequity.training" 2>/dev/null)
export ORG_ID=$(gcloud projects get-ancestors $GCP_PROJECT --format 'value(ID)' 2>/dev/null | tail -1 )
export GCP_PROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)  

echo
echo
echo -e "                        👋  Welcome to Cloud Sandbox! 💻"
echo 
echo -e "              *** PLEASE WAIT WHILE LAB UTILITIES ARE INSTALLED ***"
sudo apt-get -qq install pv > /dev/null 2>&1
echo 
export SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p `pwd`/gcp-abm-standalone > /dev/null 2>&1
export PROJDIR=`pwd`/gcp-abm-standalone
export SCRIPTNAME=gcp-abm-standalone.sh

if [ -f "$PROJDIR/.env" ]; then
    source $PROJDIR/.env
else
cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT  
export GCP_REGION=us-west1
export GCP_ZONE=us-west1-a
export SERVICEMESH_VERSION=1.18.2-asm.0
export ANTHOS_VERSION=1.15.4
EOF
source $PROJDIR/.env
fi

export VM_PREFIX=abm
export VM_WS=$VM_PREFIX-ws # to set workstation VM name"
export VM_CP1=$VM_PREFIX-cp1 # to set control plane 1 VM name"
export VM_W1=$VM_PREFIX-w1 # to set worker 1 VM name"

declare -a VMs=("$VM_WS" "$VM_CP1" "$VM_W1") # to declare VMs
declare -a IPs=() # to declare IPs

# Display menu options
while :
do
clear
cat<<EOF
==============================================================================
Menu for Configuring Anthos GKE Baremetal 
------------------------------------------------------------------------------
Please enter number to select your choice:
  (1) Enable APIs
  (2) Configure IAM Policy Binding
  (3) Create Virtual Machines
  (4) Connect VMs with Linux vXlan L2 connectivity
  (5) Install gcloud SDK, bmctl and docker tools
  (6) Generate and add admin SSH key public key to VMs
  (7) Create standalone cluster configuration, run the preflight checks and deploy cluster
  (8) Validate cluster nodes
  (9) Setup Connect gateway
 (10) Install Anthos Service Mesh
 (11) Explore Anthos Service Mesh
 (12) Configure Cloud Run
 (13) Deploy a Stateless application to Cloud Run
  (G) Launch user guide
  (Q) Quit
------------------------------------------------------------------------------
EOF
echo "Steps performed${STEP}"
echo
echo "What additional step do you want to perform, e.g. enter 0 to select the execution mode?"
read
clear
case "${REPLY^^}" in

"0")
start=`date +%s`
source $PROJDIR/.env
echo
echo "Do you want to run script in preview mode?"
export ANSWER=$(ask_yes_or_no "Are you sure?")
if [[ ! -z "$TRAINING_ORG_ID" ]]  &&  [[ $ORG_ID == "$TRAINING_ORG_ID" ]]; then
    export STEP="${STEP},0"
    MODE=1
    if [[ "yes" == $ANSWER ]]; then
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    else 
        if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
            echo 
            echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
            echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
        else
            while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                echo 
                echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                gcloud auth login  --brief --quiet
                export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                if [[ $ACCOUNT != "" ]]; then
                    echo
                    echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                    read GCP_PROJECT
                    gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                    sleep 3
                    export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                fi
            done
            gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
            sleep 2
            gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
            gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
            gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
            gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
        fi
        export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
export SERVICEMESH_VERSION=$SERVICEMESH_VERSION
export ANTHOS_VERSION=$ANTHOS_VERSION
EOF
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
        echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
        echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
        echo "*** Anthos Service Mesh version is $SERVICEMESH_VERSION ***" | pv -qL 100
        echo "*** Anthos version is $ANTHOS_VERSION ***" | pv -qL 100
        echo
        echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
        echo "*** $PROJDIR/.env ***" | pv -qL 100
        if [[ "no" == $ANSWER ]]; then
            MODE=2
            echo
            echo "*** Create mode is active ***" | pv -qL 100
        elif [[ "del" == $ANSWER ]]; then
            export STEP="${STEP},0"
            MODE=3
            echo
            echo "*** Resource delete mode is active ***" | pv -qL 100
        fi
    fi
else 
    if [[ "no" == $ANSWER ]] || [[ "del" == $ANSWER ]] ; then
        export STEP="${STEP},0"
        if [[ -f $SCRIPTPATH/.${SCRIPTNAME}.secret ]]; then
            echo
            unset password
            unset pass_var
            echo -n "Enter access code: " | pv -qL 100
            while IFS= read -p "$pass_var" -r -s -n 1 letter
            do
                if [[ $letter == $'\0' ]]
                then
                    break
                fi
                password=$password"$letter"
                pass_var="*"
            done
            while [[ -z "${password// }" ]]; do
                unset password
                unset pass_var
                echo
                echo -n "You must enter an access code to proceed: " | pv -qL 100
                while IFS= read -p "$pass_var" -r -s -n 1 letter
                do
                    if [[ $letter == $'\0' ]]
                    then
                        break
                    fi
                    password=$password"$letter"
                    pass_var="*"
                done
            done
            export PASSCODE=$(cat $SCRIPTPATH/.${SCRIPTNAME}.secret | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:$password 2> /dev/null)
            if [[ $PASSCODE == 'AccessVerified' ]]; then
                MODE=2
                echo && echo
                echo "*** Access code is valid ***" | pv -qL 100
                if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
                    echo 
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
                    echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
                else
                    while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                        echo 
                        echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                        gcloud auth login  --brief --quiet
                        export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                        if [[ $ACCOUNT != "" ]]; then
                            echo
                            echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                            read GCP_PROJECT
                            gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                            sleep 5
                            export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                        fi
                    done
                    gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
                    sleep 2
                    gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
                    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
                    gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
                    gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
                fi
                export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
export SERVICEMESH_VERSION=$SERVICEMESH_VERSION
export ANTHOS_VERSION=$ANTHOS_VERSION
EOF
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
                echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
                echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
                echo "*** Anthos Service Mesh version is $SERVICEMESH_VERSION ***" | pv -qL 100
                echo "*** Anthos version is $ANTHOS_VERSION ***" | pv -qL 100
                echo
                echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
                echo "*** $PROJDIR/.env ***" | pv -qL 100
                if [[ "no" == $ANSWER ]]; then
                    MODE=2
                    echo
                    echo "*** Create mode is active ***" | pv -qL 100
                elif [[ "del" == $ANSWER ]]; then
                    export STEP="${STEP},0"
                    MODE=3
                    echo
                    echo "*** Resource delete mode is active ***" | pv -qL 100
                fi
            else
                echo && echo
                echo "*** Access code is invalid ***" | pv -qL 100
                echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
                echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
                echo
                echo "*** Command preview mode is active ***" | pv -qL 100
            fi
        else
            echo
            echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
            echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
            echo
            echo "*** Command preview mode is active ***" | pv -qL 100
        fi
    else
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    fi
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"1")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},1i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT services enable gkeonprem.googleapis.com anthos.googleapis.com anthosgke.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com serviceusage.googleapis.com stackdriver.googleapis.com monitoring.googleapis.com logging.googleapis.com opsconfigmonitoring.googleapis.com anthosaudit.googleapis.com appdevelopmentexperience.googleapis.com connectgateway.googleapis.com # to enable APIs" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    echo
    echo "$ gcloud --project $GCP_PROJECT services enable gkeonprem.googleapis.com anthos.googleapis.com anthosgke.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com serviceusage.googleapis.com stackdriver.googleapis.com monitoring.googleapis.com logging.googleapis.com opsconfigmonitoring.googleapis.com anthosaudit.googleapis.com appdevelopmentexperience.googleapis.com connectgateway.googleapis.com # to enable APIs" | pv -qL 100
    gcloud --project $GCP_PROJECT services enable anthos.googleapis.com anthosgke.googleapis.com cloudresourcemanager.googleapis.com container.googleapis.com gkeconnect.googleapis.com gkehub.googleapis.com serviceusage.googleapis.com stackdriver.googleapis.com monitoring.googleapis.com logging.googleapis.com opsconfigmonitoring.googleapis.com anthosaudit.googleapis.com appdevelopmentexperience.googleapis.com connectgateway.googleapis.com 
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},1i"
    echo
    echo "1. Enable APIs" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"2")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},2i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT iam service-accounts create baremetal-gcr # to create the service account to download bmctl" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/gkehub.connect\" # to add-iam-policy-binding for remote cluster to connect to GKE Hub" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/gkehub.admin\" # to add-iam-policy-binding to register remote cluster in GKE Hub" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/logging.logWriter\" # to add-iam-policy-binding for stackdriver to log remote cluster data" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/monitoring.metricWriter\" # to add-iam-policy-binding for stackdriver to write remote cluster monitoring metrics" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/monitoring.dashboardEditor\" # to add-iam-policy-binding for monitoring dashboard" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/stackdriver.resourceMetadata.writer\" # to add-iam-policy-binding for stackdriver to write resource metadata" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/opsconfigmonitoring.resourceMetadata.writer\" # to add-iam-policy-binding for opsconfigmonitoring" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"user:\$EMAIL\" --role=\"roles/gkehub.gatewayAdmin\" # to enable user to access the Connect gateway API" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"user:\$EMAIL\" --role=\"roles/container.viewer\" # to enable user to view GKE Clusters" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"user:\$EMAIL\" --role=\"roles/gkehub.viewer\" # to enable user to view clusters outside Google Cloud" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},2"
    echo
    echo "$ gcloud --project $GCP_PROJECT iam service-accounts create baremetal-gcr # to create the service account to download bmctl" | pv -qL 100
    gcloud --project $GCP_PROJECT iam service-accounts create baremetal-gcr
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/gkehub.connect\" # to add-iam-policy-binding for remote cluster to connect to GKE Hub" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/gkehub.connect"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/gkehub.admin\" # to add-iam-policy-binding to register remote cluster in GKE Hub" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/gkehub.admin"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/logging.logWriter\" # to add-iam-policy-binding for stackdriver to log remote cluster data" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/logging.logWriter"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/monitoring.metricWriter\" # to add-iam-policy-binding for stackdriver to write remote cluster monitoring metrics" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/monitoring.dashboardEditor\" # to add-iam-policy-binding for monitoring dashboard" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/monitoring.dashboardEditor"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/stackdriver.resourceMetadata.writer\" # to add-iam-policy-binding for stackdriver to write resource metadata" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/stackdriver.resourceMetadata.writer"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/opsconfigmonitoring.resourceMetadata.writer\" # to add-iam-policy-binding for opsconfigmonitoring" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:baremetal-gcr@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/opsconfigmonitoring.resourceMetadata.writer"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.gatewayAdmin\" # to enable user to access the Connect gateway API" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.gatewayAdmin"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.viewer\" # to enable a user retrieve cluster kubeconfigs" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.viewer"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/container.viewer\" # to enable user to view GKE Clusters" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/container.viewer"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.viewer\" # to enable user to view clusters outside Google Cloud" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.viewer"   
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},2x"
    echo
    echo "$ gcloud --project $GCP_PROJECT iam service-accounts delete baremetal-gcr@${GCP_PROJECT}.iam.gserviceaccount.com # to delete the service account to download bmctl" | pv -qL 100
    gcloud --project $GCP_PROJECT iam service-accounts delete baremetal-gcr@${GCP_PROJECT}.iam.gserviceaccount.com
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.gatewayAdmin\" # to disable ability for user to access the Connect gateway API" | pv -qL 100
    gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.gatewayAdmin"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.viewer\" # to disable ability for a user retrieve cluster kubeconfigs" | pv -qL 100
    gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.viewer"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/container.viewer\" # to disable ability for user to view GKE Clusters" | pv -qL 100
    gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/container.viewer"
    echo
    echo "$ gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member=\"user:$EMAIL\" --role=\"roles/gkehub.viewer\" # to disable ability for user to view clusters outside Google Cloud" | pv -qL 100
    gcloud --project $GCP_PROJECT projects remove-iam-policy-binding $GCP_PROJECT --member="user:$EMAIL" --role="roles/gkehub.viewer"   
else
    export STEP="${STEP},2i"
    echo
    echo "1. Create the service account to download bmctl" | pv -qL 100
    echo "2. Add IAM policy binding for remote cluster to connect to GKE Hub" | pv -qL 100
    echo "3. Add IAM policy binding to register remote cluster in GKE Hub" | pv -qL 100
    echo "4. Add IAM policy binding for stackdriver to log remote cluster data" | pv -qL 100
    echo "5. Add IAM policy binding for stackdriver to write remote cluster monitoring metrics" | pv -qL 100
    echo "6. Add IAM policy binding for monitoring dashboard" | pv -qL 100
    echo "7. Add IAM policy binding for stackdriver to write resource metadata" | pv -qL 100
    echo "8. Add IAM policy binding for opsconfigmonitoring" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"3")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},3i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE # to disable OS login" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=\${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=\${ADMIN_CLUSTER_NAME},bmctl_version=\${BMCTL_VERSION}\" # to create admin workstation VM" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=\${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=\${ADMIN_CLUSTER_NAME},bmctl_version=\${BMCTL_VERSION}\" # to create control plane VM" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute instances create \$VM_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=\${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=\${ADMIN_CLUSTER_NAME},bmctl_version=\${BMCTL_VERSION}\" # to create worker node VM" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},3"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE # to disable OS login" | pv -qL 100
    gcloud --project $GCP_PROJECT compute project-info add-metadata --metadata enable-oslogin=FALSE
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=${ADMIN_CLUSTER_NAME},bmctl_version=${BMCTL_VERSION}\" # to create admin workstation VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_WS --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform "Intel Haswell" --scopes cloud-platform --machine-type n1-standard-4 --metadata "cluster_id=${ADMIN_CLUSTER_NAME},bmctl_version=${BMCTL_VERSION}"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=${ADMIN_CLUSTER_NAME},bmctl_version=${BMCTL_VERSION}\" # to create control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_CP1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform "Intel Haswell" --scopes cloud-platform --machine-type n1-standard-4
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances create $VM_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform \"Intel Haswell\" --scopes cloud-platform --machine-type n1-standard-4 --metadata \"cluster_id=${ADMIN_CLUSTER_NAME},bmctl_version=${BMCTL_VERSION}\" # to create worker node VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances create $VM_W1 --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud --zone=${GCP_ZONE} --boot-disk-size 100G --boot-disk-type pd-ssd --can-ip-forward --network default --tags http-server,https-server --min-cpu-platform "Intel Haswell" --scopes cloud-platform --machine-type n1-standard-4
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},3x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute project-info remove-metadata --keys=enable-oslogin # to disable OS login" | pv -qL 100
    gcloud --project $GCP_PROJECT compute project-info remove-metadata --keys=enable-oslogin
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_WS --zone=${GCP_ZONE} # to delete admin workstation VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_WS --zone=${GCP_ZONE}
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_CP1 --zone=${GCP_ZONE} # to delete control plane VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_CP1 --zone=${GCP_ZONE}
    echo
    echo "$ gcloud --project $GCP_PROJECT compute instances delete $VM_W1 --zone=${GCP_ZONE} # to delete worker node VM" | pv -qL 100
    gcloud --project $GCP_PROJECT compute instances delete $VM_W1 --zone=${GCP_ZONE}
else
    export STEP="${STEP},3i"
    echo
    echo "1. Disable OS login" | pv -qL 100
    echo "2. Create virtual machines" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"4")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},4i"
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    IP=\$(gcloud --project \$GCP_PROJECT compute instances describe \$vm --zone \${GCP_ZONE} --format='get(networkInterfaces[0].networkIP)')
    IPs+=(\"\$IP\")
done # to store VM IPs in array" | pv -qL 100
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    while ! gcloud --project \$GCP_PROJECT compute ssh root@\$vm --zone \${GCP_ZONE} --command \"echo SSH to $vm succeeded\"
    do
        echo \"Trying to SSH into \$vm failed. Sleeping for 5 seconds. zzzZZzzZZ\"
        sleep  5
    done
done # to verify that SSH is ready on all VMs" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.2/24 dev vxlan0
ip link set up dev vxlan0
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_CP1 --zone \${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.3/24 dev vxlan0
ip link set up dev vxlan0
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_W1 --zone \${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.4/24 dev vxlan0
ip link set up dev vxlan0
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},4"
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    IP=\$(gcloud --project $GCP_PROJECT compute instances describe \$vm --zone ${GCP_ZONE} --format='get(networkInterfaces[0].networkIP)')
    IPs+=(\"\$IP\")
done # to store VM IPs in array" | pv -qL 100
for vm in "${VMs[@]}"
do
    IP=$(gcloud --project $GCP_PROJECT compute instances describe $vm --zone ${GCP_ZONE} --format='get(networkInterfaces[0].networkIP)')
    IPs+=("$IP")
done
    echo
    echo "$ for vm in \"\${VMs[@]}\"
do
    while ! gcloud --project $GCP_PROJECT compute ssh root@\$vm --zone ${GCP_ZONE} --command \"echo SSH to $vm succeeded\"
    do
        echo \"Trying to SSH into $vm failed. Sleeping for 5 seconds. zzzZZzzZZ\"
        sleep  5
    done
done # to verify that SSH is ready on all VMs" | pv -qL 100
for vm in "${VMs[@]}"
do
    while ! gcloud --project $GCP_PROJECT compute ssh root@$vm --zone ${GCP_ZONE} --command "echo SSH to $vm succeeded"
    do
        echo "Trying to SSH into $vm failed. Sleeping for 5 seconds. zzzZZzzZZ"
        sleep  5
    done
done
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.2/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in ${IPs[@]}; do
    if [ "\$ip" != "\$current_ip" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
    fi
done
ip addr add 10.200.0.2/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@$VM_CP1 --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.3/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_CP1 --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in ${IPs[@]}; do
    if [ "\$ip" != "\$current_ip" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
    fi
done
ip addr add 10.200.0.3/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@$VM_W1 --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\\\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in \${IPs[@]}; do
    if [ \"\\\$ip\" != \"\\\$current_ip\" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \\\$ip dev vxlan0
    fi
done
ip addr add 10.200.0.4/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_W1 --zone ${GCP_ZONE} << EOF
set -x
apt-get -qq update > /dev/null
apt-get -qq install -y jq > /dev/null
ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
for ip in ${IPs[@]}; do
    if [ "\$ip" != "\$current_ip" ]; then
        bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
    fi
done
ip addr add 10.200.0.4/24 dev vxlan0
ip link set up dev vxlan0
# systemctl stop apparmor.service #Anthos on bare metal does not support apparmor
# systemctl disable apparmor.service
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},4x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},4i"
    echo
    echo "1. Verify that SSH is ready on all virtual machines" | pv -qL 100
    echo "2. Connect VMs with Linux vXlan L2 connectivity" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"5")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},5i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server 
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
gcloud --project PROJECT_ID iam service-accounts keys create bm-gcr.json --iam-account=baremetal-gcr@\${GCP_PROJECT}.iam.gserviceaccount.com
gcloud iam service-accounts keys create installer.json --iam-account=\${GCP_PROJECT}@\${GCP_PROJECT}.iam.gserviceaccount.com # Create keys for a service account with the same permissions
gsutil cp gs://anthos-baremetal-release/bmctl/\${ANTHOS_VERSION}/linux-amd64/bmctl .
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},5"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
sudo snap remove google-cloud-sdk # remove the GCE-specific version of the SDK
sudo curl https://sdk.cloud.google.com | bash # install the SDK as you would on a non-GCE server
sudo snap install kubectl --classic
exec -l \$SHELL # to restart shell
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=\$(gcloud config get-value project)
gcloud --project \$PROJECT_ID iam service-accounts keys create bm-gcr.json --iam-account=baremetal-gcr@\${GCP_PROJECT}.iam.gserviceaccount.com
gcloud iam service-accounts keys create installer.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com # Create keys for a service account with the same permissions
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
mkdir -p baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/${ANTHOS_VERSION}/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/
cd ~
echo \"Installing docker\"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=$(gcloud config get-value project)
gcloud --project \$PROJECT_ID iam service-accounts keys create bm-gcr.json --iam-account=baremetal-gcr@${GCP_PROJECT}.iam.gserviceaccount.com
gcloud iam service-accounts keys create installer.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com # Create keys for a service account with the same permissions
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
mkdir -p baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/${ANTHOS_VERSION}/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/
cd ~
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},5x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},5i"
    echo
    echo "1. Replace GCE-specific version of the SDK" | pv -qL 100
    echo "2. Create service account key" | pv -qL 100
    echo "3. Download kubectl and bmctl" | pv -qL 100
    echo "4. Install docker" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"6")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},6i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
echo \"y\" | ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
for vm in \${VMs[@]}
do
    echo
    gcloud --project \$GCP_PROJECT compute instances add-metadata \\\$vm --zone \${GCP_ZONE} --metadata-from-file ssh-keys=ssh-metadata # to add ssh metadata
done
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},6"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
echo \"y\" | ssh-keygen -t rsa -N \"\" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
for vm in \${VMs[@]}
do
    echo
    gcloud --project $GCP_PROJECT compute instances add-metadata \\\$vm --zone ${GCP_ZONE} --metadata-from-file ssh-keys=ssh-metadata # to add ssh metadata
done
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
echo "y" | ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' /root/.ssh/id_rsa.pub > ssh-metadata
for vm in ${VMs[@]}
do
    echo
    gcloud --project $GCP_PROJECT compute instances add-metadata \$vm --zone ${GCP_ZONE} --metadata-from-file ssh-keys=ssh-metadata # to add ssh metadata
done
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},6x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},6i"
    echo
    echo "1. Add SSH metadata to virtual machines" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"7")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},7i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
bmctl create config -c \\\$clusterid
bash -c \"cat > bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml << 'EOB'
---
gcrKeyPath: /root/bm-gcr.json
sshPrivateKeyPath: /root/.ssh/id_rsa
gkeConnectAgentServiceAccountKeyPath: /root/bm-gcr.json
gkeConnectRegisterServiceAccountKeyPath: /root/bm-gcr.json
cloudOperationsServiceAccountKeyPath: /root/bm-gcr.json
---
apiVersion: v1
kind: Namespace
metadata:
  name: cluster-\\\$clusterid
---
apiVersion: baremetal.cluster.gke.io/v1
kind: Cluster
metadata:
  name: \\\$clusterid
  namespace: cluster-\\\$clusterid
spec:
  type: standalone
  anthosBareMetalVersion: \$ANTHOS_VERSION
  gkeConnect:
    projectID: \\\$PROJECT_ID
  controlPlane:
    nodePoolSpec:
      nodes:
      - address: 10.200.0.3
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 172.26.232.0/24
  loadBalancer:
    mode: bundled
    ports:
      controlPlaneLBPort: 443
    vips:
      controlPlaneVIP: 10.200.0.49
      ingressVIP: 10.200.0.50
    addressPools:
    - name: pool1
      addresses:
      - 10.200.0.50-10.200.0.70
  clusterOperations:
    # might need to be this location
    location: us-central1
    projectID: \\\$PROJECT_ID
    enableApplication: true   
  storage:
    lvpNodeMounts:
      path: /mnt/localpv-disk
      storageClassName: local-disk
    lvpShare:
      numPVUnderSharedPath: 5
      path: /mnt/localpv-share
      storageClassName: local-shared
---
apiVersion: baremetal.cluster.gke.io/v1
kind: NodePool
metadata:
  name: node-pool-1
  namespace: cluster-\\\$clusterid
spec:
  clusterName: \\\$clusterid
  nodes:
  - address: 10.200.0.4
EOB\"

bmctl create cluster -c \\\$clusterid
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},7"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=\$(gcloud config get-value project)
export clusterid=bm-edge-gke-cluster
bmctl create config -c \\\$clusterid
bash -c \"cat > bmctl-workspace/\\\$clusterid/\\\$clusterid.yaml << 'EOB'
---
gcrKeyPath: /root/bm-gcr.json
sshPrivateKeyPath: /root/.ssh/id_rsa
gkeConnectAgentServiceAccountKeyPath: /root/bm-gcr.json
gkeConnectRegisterServiceAccountKeyPath: /root/bm-gcr.json
cloudOperationsServiceAccountKeyPath: /root/bm-gcr.json
---
apiVersion: v1
kind: Namespace
metadata:
  name: cluster-\\\$clusterid
---
apiVersion: baremetal.cluster.gke.io/v1
kind: Cluster
metadata:
  name: \\\$clusterid
  namespace: cluster-\\\$clusterid
spec:
  type: standalone
  profile: default
  anthosBareMetalVersion: $ANTHOS_VERSION
  gkeConnect:
    projectID: \\\$PROJECT_ID
  controlPlane:
    nodePoolSpec:
      nodes:
      - address: 10.200.0.3
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 172.26.232.0/24
  loadBalancer:
    mode: bundled
    ports:
      controlPlaneLBPort: 443
    vips:
      controlPlaneVIP: 10.200.0.49
      ingressVIP: 10.200.0.50
    addressPools:
    - name: pool1
      addresses:
      - 10.200.0.50-10.200.0.70
  clusterOperations:
    # might need to be this location
    location: us-central1
    projectID: \\\$PROJECT_ID
    enableApplication: true   
  storage:
    lvpNodeMounts:
      path: /mnt/localpv-disk
      storageClassName: node-disk
    lvpShare:
      numPVUnderSharedPath: 5
      path: /mnt/localpv-share
      storageClassName: local-shared
---
apiVersion: baremetal.cluster.gke.io/v1
kind: NodePool
metadata:
  name: node-pool-1
  namespace: cluster-\\\$clusterid
spec:
  clusterName: \\\$clusterid
  nodes:
  - address: 10.200.0.4
EOB\"

bmctl create cluster -c \\\$clusterid
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=$(gcloud config get-value project)
export clusterid=bm-edge-gke-cluster
rm -rf bmctl-workspace/\$clusterid/\$clusterid.yaml
bmctl create config -c \$clusterid
bash -c "cat > bmctl-workspace/\$clusterid/\$clusterid.yaml << 'EOB'
---
gcrKeyPath: /root/bm-gcr.json
sshPrivateKeyPath: /root/.ssh/id_rsa
gkeConnectAgentServiceAccountKeyPath: /root/bm-gcr.json
gkeConnectRegisterServiceAccountKeyPath: /root/bm-gcr.json
cloudOperationsServiceAccountKeyPath: /root/bm-gcr.json
---
apiVersion: v1
kind: Namespace
metadata:
  name: cluster-\$clusterid
---
apiVersion: baremetal.cluster.gke.io/v1
kind: Cluster
metadata:
  name: \$clusterid
  namespace: cluster-\$clusterid
spec:
  type: standalone
  profile: default
  anthosBareMetalVersion: $ANTHOS_VERSION
  gkeConnect:
    projectID: \$PROJECT_ID
  controlPlane:
    nodePoolSpec:
      nodes:
      - address: 10.200.0.3
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 172.26.232.0/24
  loadBalancer:
    mode: bundled
    ports:
      controlPlaneLBPort: 443
    vips:
      controlPlaneVIP: 10.200.0.49
      ingressVIP: 10.200.0.50
    addressPools:
    - name: pool1
      addresses:
      - 10.200.0.50-10.200.0.70
  clusterOperations:
    # might need to be this location
    location: us-central1
    projectID: \$PROJECT_ID
    enableApplication: true
  storage:
    lvpNodeMounts:
      path: /mnt/localpv-disk
      storageClassName: local-disk
    lvpShare:
      numPVUnderSharedPath: 5
      path: /mnt/localpv-share
      storageClassName: local-shared
---
apiVersion: baremetal.cluster.gke.io/v1
kind: NodePool
metadata:
  name: node-pool-1
  namespace: cluster-\$clusterid
spec:
  clusterName: \$clusterid
  nodes:
  - address: 10.200.0.4
EOB"

bmctl create cluster -c \$clusterid
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},7x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=\$(gcloud config get-value project)
export clusterid=bm-edge-gke-cluster
bmctl reset --cluster \\\$clusterid
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export PROJECT_ID=$(gcloud config get-value project)
export clusterid=bm-edge-gke-cluster
bmctl reset --cluster \$clusterid
EOF
else
    export STEP="${STEP},7i"
    echo
    echo "1. Create baremetal cluster configuration" | pv -qL 100
    echo "2. Apply baremetal cluster configuration" | pv -qL 100
fi
echo
read -n 1 -s -r -p "$ "
;;

"8")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},8i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
kubectl get nodes # to get nodes
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},8"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl get nodes # to get nodes
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl get nodes # to get nodes
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},8x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},8i"
    echo
    echo "1. Get nodes to verify installation" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"9")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},9i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=\\\$EMAIL --project=\\\$PROJECT_ID --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},9"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export PROJECT_ID=\\\$(gcloud config get-value project) # to set project ID
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\\\$clusterid --role=clusterrole/cluster-admin --users=$EMAIL --project=\\\$PROJECT_ID --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export PROJECT_ID=\$(gcloud config get-value project) # to set project ID
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships generate-gateway-rbac --membership=\$clusterid --role=clusterrole/cluster-admin --users=$EMAIL --project=\$PROJECT_ID --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid --apply # to enable clusters to authorize requests from Google Cloud console
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},9x"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export PROJECT_ID=\\\$(gcloud config get-value project) # to set project ID
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \\\$clusterid --project=\\\$PROJECT_ID --kubeconfig=\\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid # to unregister clusters
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
export PROJECT_ID=\$(gcloud config get-value project) # to set project ID
gcloud container fleet memberships list # to verify that clusters have been registered
gcloud beta container fleet memberships unregister \$clusterid --project=\$PROJECT_ID --kubeconfig=\$KUBECONFIG --context=\$clusterid-admin@\$clusterid # to unregister clusters
EOF
else
    export STEP="${STEP},9i"
    echo
    echo "1. Setup Connect gateway" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"10")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},10i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-\${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-\${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-\${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-\${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem # to create a secret cacerts
/root/istio-\${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},10"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=\$(gcloud config get-value core/account) # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem # to create a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
echo && echo
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for deployment to finish
kubectl get pod -n istio-system # to check control plane Pods
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl create clusterrolebinding cluster-admin --clusterrole=cluster-admin --user=$(gcloud config get-value core/account)  2> /dev/null # to grant cluster admin role to user
curl -LO https://storage.googleapis.com/gke-release/asm/istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to download the Anthos Service Mesh
tar xzf istio-${SERVICEMESH_VERSION}-linux-amd64.tar.gz # to extract the contents of the file to file system
kubectl create namespace istio-system # to create a namespace called istio-system
apt-get update
apt-get -y install make
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk root-ca # to generate a root certificate and key
make -f /root/istio-${SERVICEMESH_VERSION}/tools/certs/Makefile.selfsigned.mk cluster1-cacerts # to generate an intermediate certificate and key
kubectl create secret generic cacerts -n istio-system --from-file=cluster1/ca-cert.pem --from-file=cluster1/ca-key.pem --from-file=cluster1/root-cert.pem --from-file=cluster1/cert-chain.pem 2> /dev/null # to create a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl install --set profile=asm-multicloud -y # to install Anthos Service Mesh
echo && echo
kubectl wait --for=condition=available --timeout=600s deployment --all -n istio-system # to wait for deployment to finish
kubectl get pod -n istio-system # to check control plane Pods
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},10x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl delete clusterrolebinding cluster-admin # to delete cluster admin role
kubectl delete namespace istio-system # to delete a namespace called istio-system
kubectl delete secret cacerts -n istio-system # to delete a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete controlplanerevision -n istio-system 2> /dev/null
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration -l operator.istio.io/component=Pilot 2> /dev/null
kubectl delete namespace istio-system asm-system --ignore-not-found=true 2> /dev/null
kubectl delete clusterrolebinding cluster-admin # to delete cluster admin role
kubectl delete namespace istio-system # to delete a namespace called istio-system
kubectl delete secret cacerts -n istio-system # to delete a secret cacerts
/root/istio-${SERVICEMESH_VERSION}/bin/istioctl x uninstall --purge -y 2> /dev/null
EOF
else
    export STEP="${STEP},10i"
    echo
    echo "1. Grant cluster admin role" | pv -qL 100
    echo "2. Download the Anthos Service Mesh" | pv -qL 100
    echo "3. Generate a root certificate and key" | pv -qL 100
    echo "4. Generate an intermediate certificate and key" | pv -qL 100
    echo "5. Create a secret cacerts" | pv -qL 100
    echo "6. Install Anthos Service Mesh" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"11")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},11i"
    echo
    echo "$ gcloud --project \$GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
kubectl create namespace foo # to create namespace
kubectl label namespace foo istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace bar # to create namespace
kubectl label namespace bar istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace legacy # to create namespace
kubectl -n foo apply -f samples/httpbin/httpbin.yaml # to deploy httpbin
kubectl -n bar apply -f samples/httpbin/httpbin.yaml # to deploy httpbin
kubectl -n legacy apply -f samples/httpbin/httpbin.yaml # to deploy httpbin
kubectl -n foo apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n bar apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n legacy apply -f samples/sleep/sleep.yaml # to deploy sleep
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
cat <<EOB | kubectl apply -n foo -f -
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin-istio-client-mtls
spec:
  host: httpbin.foo.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOB
echo
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: PERMISSIVE
EOB
echo
for from in \"foo\" \"bar\" \"legacy\"; do kubectl exec \\\$(kubectl get pod -l app=sleep -n \\\${from} -o jsonpath={.items..metadata.name}) -c sleep -n \\\${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w \"sleep.\\\${from} to httpbin.foo: %{http_code}, \"; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF" | pv -qL 100
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone \${GCP_ZONE} << EOF
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: STRICT
EOB
echo
for from in \"foo\" \"bar\" \"legacy\"; do kubectl exec \\\$(kubectl get pod -l app=sleep -n \\\${from} -o jsonpath={.items..metadata.name}) -c sleep -n \\\${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w \"sleep.\\\${from} to httpbin.foo: %{http_code}, \"; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},11"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create namespace foo # to create namespace
kubectl label namespace foo istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace bar # to create namespace
kubectl label namespace bar istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace legacy # to create namespace
kubectl -n foo apply -f samples/httpbin/httpbin.yaml # to deploy httpbin
kubectl -n foo apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n bar apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n legacy apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl wait --for=condition=available --timeout=600s deployment --all -n foo # to wait for the deployment to finish
kubectl wait --for=condition=available --timeout=600s deployment --all -n bar # to wait for the deployment to finish
kubectl wait --for=condition=available --timeout=600s deployment --all -n legacy # to wait for the deployment to finish
EOF" | pv -qL 100
gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create namespace foo # to create namespace
kubectl label namespace foo istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace bar # to create namespace
kubectl label namespace bar istio-injection=enabled # to label namespaces for automatic sidecar injection
kubectl create namespace legacy # to create namespace
kubectl -n foo apply -f samples/httpbin/httpbin.yaml # to deploy httpbin
kubectl -n foo apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n bar apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl -n legacy apply -f samples/sleep/sleep.yaml # to deploy sleep
kubectl wait --for=condition=available --timeout=600s deployment --all -n foo # to wait for the deployment to finish
kubectl wait --for=condition=available --timeout=600s deployment --all -n bar # to wait for the deployment to finish
kubectl wait --for=condition=available --timeout=600s deployment --all -n legacy # to wait for the deployment to finish
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -n foo -f -
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin-istio-client-mtls
spec:
  host: httpbin.foo.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOB
echo
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: PERMISSIVE
EOB
echo
for from in \"foo\" \"bar\" \"legacy\"; do kubectl exec \\\$(kubectl get pod -l app=sleep -n \\\${from} -o jsonpath={.items..metadata.name}) -c sleep -n \\\${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w \"sleep.\\\${from} to httpbin.foo: %{http_code}, \"; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF" | pv -qL 100
    echo
    gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -n foo -f -
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin-istio-client-mtls
spec:
  host: httpbin.foo.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOB
echo
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: PERMISSIVE
EOB
echo
for from in "foo" "bar" "legacy"; do kubectl exec \$(kubectl get pod -l app=sleep -n \${from} -o jsonpath={.items..metadata.name}) -c sleep -n \${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w "sleep.\${from} to httpbin.foo: %{http_code}, "; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: STRICT
EOB
echo
for from in \"foo\" \"bar\" \"legacy\"; do kubectl exec \\\$(kubectl get pod -l app=sleep -n \\\${from} -o jsonpath={.items..metadata.name}) -c sleep -n \\\${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w \"sleep.\\\${from} to httpbin.foo: %{http_code}, \"; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF" | pv -qL 100
    echo
    gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
cd /root/istio-${SERVICEMESH_VERSION} # change to istio directory
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
cat <<EOB | kubectl apply -n foo -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: httpbin-authentication
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  mtls:
    mode: STRICT
EOB
echo
for from in "foo" "bar" "legacy"; do kubectl exec \$(kubectl get pod -l app=sleep -n \${from} -o jsonpath={.items..metadata.name}) -c sleep -n \${from} -- curl http://httpbin.foo:8000/ip -s -o /dev/null -w "sleep.\${from} to httpbin.foo: %{http_code}, "; done # to send HTTP request from any sleep pod in foo, bar or legacy namespace to httpbin in foo namespace
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},11x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete namespace foo
kubectl delete namespace bar
kubectl delete namespace legacy
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh root@$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete namespace foo
kubectl delete namespace bar
kubectl delete namespace legacy
EOF
else
    export STEP="${STEP},11i"
    echo
    echo "1. Create namespace" | pv -qL 100
    echo "2. Apply kubernetes configuration" | pv -qL 100
    echo "3. Configure mutual TLS" | pv -qL 100
    echo "4. Enable Permissive and Strict modes" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"12")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},12i"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl create namespace knative-serving # to create native-serving namespace
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/\${GCP_PROJECT}-anthos-baremetal-cloud-ops.json # to create secret for service account with monitoring.metricsWriter permissions
cat > bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: \$GCP_PROJECT
       gcpzone: \$GCP_ZONE
       clustername: bm-edge-gke-cluster
       secretname: gcp-logging-secret
       secretkey: \$GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
gcloud --project \$GCP_PROJECT container fleet cloudrun enable --project=\$GCP_PROJECT # to enable Cloud Run in Anthos fleet
gcloud --project \$GCP_PROJECT container fleet features list --project=\$GCP_PROJECT # to list enabled features
gcloud --project \$GCP_PROJECT container hub cloudrun apply --context \\\$clusterid-admin@\\\$clusterid --kubeconfig=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig --config=bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},12"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
kubectl create namespace knative-serving # to create native-serving namespace
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/${GCP_PROJECT}-anthos-baremetal-cloud-ops.json # to create secret for service account with monitoring.metricsWriter permissions
cat > bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: $GCP_PROJECT
       gcpzone: $GCP_ZONE
       clustername: bm-edge-gke-cluster
       secretname: gcp-logging-secret
       secretkey: $GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
gcloud --project $GCP_PROJECT container fleet cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
sleep 120
gcloud --project $GCP_PROJECT container fleet features list --project=$GCP_PROJECT # to list enabled features
gcloud --project $GCP_PROJECT container hub cloudrun apply --context \\\$clusterid-admin@\\\$clusterid --kubeconfig=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig --config=bmctl-workspace/\\\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
kubectl delete namespace knative-serving > /dev/null 2>&1
kubectl create namespace knative-serving # to create native-serving namespace
kubectl delete secret -n knative-serving gcp-logging-secret > /dev/null 2>&1
kubectl create secret -n knative-serving generic gcp-logging-secret --from-file=bmctl-workspace/.sa-keys/${GCP_PROJECT}-anthos-baremetal-cloud-ops.json
cat > bmctl-workspace/\$clusterid/cloudrunanthos.yaml << 'EOB'
 apiVersion: operator.run.cloud.google.com/v1alpha1
 kind: CloudRun
 metadata:
   name: cloud-run
 spec:
   metricscollector:
     stackdriver:
       projectid: $GCP_PROJECT
       gcpzone: $GCP_ZONE
       clustername: bm-edge-gke-cluster
       secretname: gcp-logging-secret
       secretkey: $GCP_PROJECT-anthos-baremetal-cloud-ops.json
EOB
# gcloud alpha container hub cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
gcloud container fleet cloudrun enable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
sleep 120
gcloud container fleet features list --project=$GCP_PROJECT # to list enabled features
# kubectl apply --filename bmctl-workspace/\$clusterid/cloudrunanthos.yaml # to install Cloud Run
gcloud --project $GCP_PROJECT container hub cloudrun apply --context \$clusterid-admin@\$clusterid --kubeconfig=\$KUBECONFIG --config=bmctl-workspace/\$clusterid/cloudrunanthos.yaml  # to install Cloud Run
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},12x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig
gcloud container fleet cloudrun disable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
kubectl delete secret -n knative-serving gcp-logging-secret 
kubectl delete namespace knative-serving 
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
gcloud container fleet cloudrun disable --project=$GCP_PROJECT # to enable Cloud Run in Anthos fleet
kubectl delete secret -n knative-serving gcp-logging-secret 
kubectl delete namespace knative-serving 
EOF
else
    export STEP="${STEP},12i"
    echo
    echo "1. Create namespace" | pv -qL 100
    echo "2. Create Kubernetes secret" | pv -qL 100
    echo "3. Create Cloud Run operator" | pv -qL 100
    echo "4. Enable Cloud Run in Anthos fleet" | pv -qL 100
    echo "5. Install Cloud Run" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"13")
start=`date +%s`
gcloud --project $GCP_PROJECT container clusters get-credentials $GCP_CLUSTER --zone $GCP_ZONE > /dev/null 2>&1 
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},13i"        
    echo
    echo "$ gcloud --project \$GCP_PROJECT projects add-iam-policy-binding \$GCP_PROJECT --member=\"serviceAccount:\$GCP_PROJECT@\$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/viewer\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password=\"\\\$(cat ~/installer.json)\" --docker-email=\$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{\"imagePullSecrets\": [{\"name\": \"gcrimagepull\"}]}' # to patch the default k8s service account with docker-registry image pull secret
gcloud --project \$GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
EOF" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},13"        
    echo
    echo "$ gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member=\"serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/viewer\" # to add-iam-policy-binding for image pull service account" | pv -qL 100
    gcloud --project $GCP_PROJECT projects add-iam-policy-binding $GCP_PROJECT --member="serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com" --role="roles/viewer"
    echo
    echo "$ export EMAIL=\$(gcloud config get-value core/account) # to set email"| pv -qL 100
    export EMAIL=$(gcloud config get-value core/account)
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh --ssh-flag=\"-A\" root@\$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=bm-edge-gke-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment 
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password=\"\\\$(cat ~/installer.json)\" --docker-email=$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{\"imagePullSecrets\": [{\"name\": \"gcrimagepull\"}]}' # to patch the default k8s service account with docker-registry image pull secret
sleep 10
gcloud --project $GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
sleep 5
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
sleep 15
ps -elf | grep 8080
echo
curl --max-time 5 -H \"Host: hello-app.default.svc.cluster.local\" http://localhost:8080/ # to invoke the service
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=bm-edge-gke-cluster
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment KUBECONFIG environment variable
kubectl delete secret gcrimagepull > /dev/null 2>&1
kubectl create secret docker-registry gcrimagepull --docker-server=gcr.io --docker-username=_json_key --docker-password="\$(cat ~/installer.json)" --docker-email=$EMAIL # to create docker registry secret
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "gcrimagepull"}]}' # to patch the default k8s service account with docker-registry image pull secret
sleep 10
gcloud --project $GCP_PROJECT run deploy hello-app --platform kubernetes --image gcr.io/google-samples/hello-app:1.0 # to deploy appication
sleep 5
kubectl port-forward --namespace istio-system service/knative-local-gateway 8080:80 & # to setup a tunnel to the admin workstation
sleep 15
ps -elf | grep 8080
echo
curl --max-time 5 -H "Host: hello-app.default.svc.cluster.local" http://localhost:8080/ # to invoke the service
echo
echo "*** Enter CTRL C to exit ***"
EOF
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},13x"
    echo
    echo "$ gcloud --project $GCP_PROJECT compute ssh root@\$VM_WS --zone ${GCP_ZONE} << EOF
export clusterid=bm-edge-gke-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\\\$clusterid/\\\$clusterid-kubeconfig # to set the KUBECONFIG environment KUBECONFIG environment variable
kubectl delete secret gcrimagepull
gcloud --project $GCP_PROJECT beta run services delete hello-app --platform kubernetes --kubeconfig \\\$KUBECONFIG --context=\\\$clusterid-admin@\\\$clusterid --quiet # to delete services
EOF" | pv -qL 100
    gcloud --project $GCP_PROJECT compute ssh --ssh-flag="-A" root@$VM_WS --zone $GCP_ZONE --tunnel-through-iap << EOF
export clusterid=bm-edge-gke-cluster
export GOOGLE_APPLICATION_CREDENTIALS=~/installer.json # set the Application Default Credentials
export KUBECONFIG=/root/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig # to set the KUBECONFIG environment variable
kubectl delete secret gcrimagepull
gcloud --project $GCP_PROJECT beta run services delete hello-app --platform kubernetes --kubeconfig \$KUBECONFIG --context=\$clusterid-admin@\$clusterid --quiet
EOF
else
    export STEP="${STEP},13i"        
    echo
    echo "1. Add IAM policy binding for image pull service account" | pv -qL 100
    echo "2. Create docker registry secret" | pv -qL 100
    echo "3. Patch default k8s service account with docker-registry image pull secret" | pv -qL 100
    echo "4. Setup a tunnel to the admin workstation" | pv -qL 100
    echo "5. Invoke the service" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"R")
echo
echo "
  __                      __                              __                               
 /|            /         /              / /              /                 | /             
( |  ___  ___ (___      (___  ___        (___           (___  ___  ___  ___|(___  ___      
  | |___)|    |   )     |    |   )|   )| |    \   )         )|   )|   )|   )|   )|   )(_/_ 
  | |__  |__  |  /      |__  |__/||__/ | |__   \_/       __/ |__/||  / |__/ |__/ |__/  / / 
                                 |              /                                          
"
echo "
We are a group of information technology professionals committed to driving cloud 
adoption. We create cloud skills development assets during our client consulting 
engagements, and use these assets to build cloud skills independently or in partnership 
with training organizations.
 
You can access more resources from our iOS and Android mobile applications.

iOS App: https://apps.apple.com/us/app/tech-equity/id1627029775
Android App: https://play.google.com/store/apps/details?id=com.techequity.app

Email:support@techequity.cloud 
Web: https://techequity.cloud

Ⓒ Tech Equity 2022" | pv -qL 100
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"G")
cloudshell launch-tutorial $SCRIPTPATH/.tutorial.md
;;

"Q")
echo
exit
;;
"q")
echo
exit
;;
* )
echo
echo "Option not available"
;;
esac
sleep 1
done
