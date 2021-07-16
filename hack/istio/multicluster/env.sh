#!/bin/bash

##############################################################################
# env.sh
#
# Configures the environment to prepare for multi-cluster installations.
# The proper way to use this script is to source it (source env.sh) from
# within other scripts.
#
# See: https://istio.io/latest/docs/tasks/security/cert-management/plugin-ca-cert/
#
# See --help for more details on options to this script.
#
##############################################################################

# If we have already been processed, skip everything
if [ "${HACK_ENV_DONE:-}" == "true" ]; then
  return 0
fi

set -u

SCRIPT_DIR="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"

switch_cluster() {
  local context="${1}"
  local username="${2:-}"
  local password="${3:-}"
  if [ "${IS_OPENSHIFT}" == "true" ]; then
    if ! ${CLIENT_EXE} login --username "${username}" --password "${password}" --server "${context}"; then
      echo "Failed to log into OpenShift cluster. url=[${context}]"
      exit 1
    fi
  else
    if ! ${CLIENT_EXE} config use-context "${context}"; then
      echo "Failed to switch to Kubernetes cluster. context=[${context}]"
      exit 1
    fi
  fi
}

#
# SET UP THE DEFAULTS FOR ALL SETTINGS
#

# CLIENT_EXE_NAME is going to either be "oc" or "kubectl"
# ISTIO_DIR is where the Istio download is installed and thus where the Istio tools are found.
CLIENT_EXE_NAME="kubectl"
ISTIO_DIR=""

# If the scripts need image registry client, this is it (docker or podman)
DORP="${DORP:-docker}"

# The namespace where Istio will be found - this namespace must be the same on both clusters
ISTIO_NAMESPACE="istio-system"

# If you want to override the tag that istioctl will use for the container images it pulls, set this.
# (note: needed this because openshift requires a dev build of istioctl but we still want the released images.
# See: https://github.com/kiali/kiali/pull/3713#issuecomment-809920379)
ISTIO_TAG=""

# Certs directory where you want the generates cert files to be written
CERTS_DIR="/tmp/istio-multicluster-certs"

# The default Mesh and Network identifiers
MESH_ID="mesh-hack"
NETWORK1_ID="network-east"
NETWORK2_ID="network-west"

# If a gateway is required to cross the networks, set this to true and one will be created
# See: https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/
CROSSNETWORK_GATEWAY_REQUIRED="true"

# Under some conditions, manually configuring the mesh network will be required.
MANUAL_MESH_NETWORK_CONFIG=""

# The names of each cluster
CLUSTER1_NAME="east"
CLUSTER2_NAME="west"

# If using Kubernetes, these are the kube context names used to connect to the clusters
# If using OpenShift, these are the URLs to the API login server (e.g. "https://api.server-name.com:6443")
CLUSTER1_CONTEXT=""
CLUSTER2_CONTEXT=""

# if using OpenShift, these are the credentials needed to log on to the clusters
CLUSTER1_USER="kiali"
CLUSTER1_PASS="kiali"
CLUSTER2_USER="kiali"
CLUSTER2_PASS="kiali"

# Should Kiali be installed? This installs the last release of Kiali via the kiali-server helm chart.
# If you want another verison or your own dev build, you must disable this and install what you want manually.
KIALI_ENABLED="true"

# Should Bookinfo demo be installed? If so, where?
BOOKINFO_ENABLED="true"
BOOKINFO_NAMESPACE="bookinfo"

# If true and client exe is kubectl, then two minikube instances will be installed/uninstalled by these scripts
MANAGE_MINIKUBE="true"

# If true and client exe is kubectl, then two kind instances will be installed/uninstalled by these scripts
MANAGE_KIND="false"

# Minikube options - these are ignored if MANAGE_MINIKUBE is false
MINIKUBE_DRIVER="virtualbox"
MINIKUBE_CPU=""
MINIKUBE_DISK=""
MINIKUBE_MEMORY=""

# Some settings that can be configured when helm installing the two Kiali instances.
KIALI1_WEB_FQDN=""
KIALI1_WEB_SCHEMA=""
KIALI2_WEB_FQDN=""
KIALI2_WEB_SCHEMA=""

# process command line args
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -be|--bookinfo-enabled)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--bookinfo-enabled must be 'true' or 'false'" && exit 1
      BOOKINFO_ENABLED="$2"
      shift;shift
      ;;
    -bn|--bookinfo-namespace)
      BOOKINFO_NAMESPACE="$2"
      shift;shift
      ;;
    -c|--client-exe)
      CLIENT_EXE_NAME="$2"
      shift;shift
      ;;
    -c1c|--cluster1-context)
      CLUSTER1_CONTEXT="$2"
      shift;shift
      ;;
    -c1n|--cluster1-name)
      CLUSTER1_NAME="$2"
      shift;shift
      ;;
    -c1p|--cluster1-password)
      CLUSTER1_PASS="$2"
      shift;shift
      ;;
    -c1u|--cluster1-username)
      CLUSTER1_USER="$2"
      shift;shift
      ;;
    -c2c|--cluster2-context)
      CLUSTER2_CONTEXT="$2"
      shift;shift
      ;;
    -c2n|--cluster2-name)
      CLUSTER2_NAME="$2"
      shift;shift
      ;;
    -c2p|--cluster2-password)
      CLUSTER2_PASS="$2"
      shift;shift
      ;;
    -c2u|--cluster2-username)
      CLUSTER2_USER="$2"
      shift;shift
      ;;
    -dorp|--docker-or-podman)
      [ "${2:-}" != "docker" -a "${2:-}" != "podman" ] && echo "-dorp must be 'docker' or 'podman'" && exit 1
      DORP="$2"
      shift;shift
      ;;
    -gr|--gateway-required)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--gateway-required must be 'true' or 'false'" && exit 1
      CROSSNETWORK_GATEWAY_REQUIRED="$2"
      shift;shift
      ;;
    -id|--istio-dir)
      ISTIO_DIR="$2"
      shift;shift
      ;;
    -in|--istio-namespace)
      ISTIO_NAMESPACE="$2"
      shift;shift
      ;;
    -it|--istio-tag)
      ISTIO_TAG="$2"
      shift;shift
      ;;
    -ke|--kiali-enabled)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--kiali-enabled must be 'true' or 'false'" && exit 1
      KIALI_ENABLED="$2"
      shift;shift
      ;;
    -k1wf|--kiali1-web-fqdn)
      KIALI1_WEB_FQDN="$2"
      shift;shift
      ;;
    -k1ws|--kiali1-web-schema)
      KIALI1_WEB_SCHEMA="$2"
      shift;shift
      ;;
    -k2wf|--kiali2-web-fqdn)
      KIALI2_WEB_FQDN="$2"
      shift;shift
      ;;
    -k2ws|--kiali2-web-schema)
      KIALI2_WEB_SCHEMA="$2"
      shift;shift
      ;;
    -mcpu|--minikube-cpu)
      MINIKUBE_CPU="$2"
      shift;shift
      ;;
    -md|--minikube-driver)
      MINIKUBE_DRIVER="$2"
      shift;shift
      ;;
    -mdisk|--minikube-disk)
      MINIKUBE_DISK="$2"
      shift;shift
      ;;
    -mi|--mesh-id)
      MESH_ID="$2"
      shift;shift
      ;;
    -mk|--manage-kind)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--manage-kind must be 'true' or 'false'" && exit 1
      MANAGE_KIND="$2"
      [ "${MANAGE_KIND}" == "true" ] && MANAGE_MINIKUBE="false" # cannot manage minikube if managing kind
      shift;shift
      ;;
    -mm|--manage-minikube)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--manage-minikube must be 'true' or 'false'" && exit 1
      MANAGE_MINIKUBE="$2"
      [ "${MANAGE_MINIKUBE}" == "true" ] && MANAGE_KIND="false" # cannot manage kind if managing minikube
      shift;shift
      ;;
    -mmem|--minikube-memory)
      MINIKUBE_MEMORY="$2"
      shift;shift
      ;;
    -mnc|--manual-network-config)
      [ "${2:-}" != "true" -a "${2:-}" != "false" ] && echo "--manual-network-config must be 'true' or 'false'" && exit 1
      MANUAL_MESH_NETWORK_CONFIG="$2"
      shift;shift
      ;;
    -n1|--network1)
      NETWORK1_ID="$2"
      shift;shift
      ;;
    -n2|--network2)
      NETWORK2_ID="$2"
      shift;shift
      ;;
    -h|--help)
      cat <<HELPMSG
Valid command line arguments:
  -be|--bookinfo-enabled <bool>: If true, install the bookinfo demo spread across the two clusters (Default: true)
  -bn|--bookinfo-namespace: If the bookinfo demo will be installed, this is its namespace (Default: bookinfo)
  -c|--client-exe <name>: Cluster client executable name - valid values are "kubectl" or "oc". If you use
                          kubectl, it is assumed minikube will be used and the cluster names are profile names.
  -c1c|--cluster1-context <name>: If cluster1 is Kubernetes, this is the context used to connect to the cluster
  -c1n|--cluster1-name <name>: The name of cluster1 (Default: east)
  -c1p|--cluster1-password <name>: If cluster1 is OpenShift, this is the password used to log in (Default: kiali)
  -c1u|--cluster1-username <name>: If cluster1 is OpenShift, this is the username used to log in (Default: kiali)
  -c2c|--cluster2-context <name>: If cluster2 is Kubernetes, this is the context used to connect to the cluster
  -c2n|--cluster2-name <name>: The name of cluster2 (Default: west)
  -c2p|--cluster2-password <name>: If cluster2 is OpenShift, this is the password used to log in (Default: kiali)
  -c2u|--cluster2-username <name>: If cluster2 is OpenShift, this is the username used to log in (Default: kiali)
  -dorp|--docker-or-podman <docker|podman>: What image registry client to use (Default: docker)
  -gr|--gateway-required <bool>: If a gateway is required to cross between networks, set this to true
  -id|--istio-dir <dir>: Where Istio has already been downloaded. If not found, this script aborts.
  -in|--istio-namespace <name>: Where the Istio control plane is installed (default: istio-system).
  -it|--istio-tag <tag>: If you want to override the image tag used by istioctl, set this to the tag name.
  -ke|--kiali-enabled <bool>: If "true" the latest release of Kiali will be installed in both clusters. If you want
                              a different version of Kiali installed, you must set this to "false" and install it yourself.
                              (Default: true)
  -k1wf|--kiali1-web-fqdn <fqdn>: If specified, this will be the #1 Kaili setting for spec.server.web_fqdn.
  -k1ws|--kiali1-web-schema <schema>: If specified, this will be the #1 Kaili setting for spec.server.web_schema.
  -k2wf|--kiali2-web-fqdn <fqdn>: If specified, this will be the #2 Kaili setting for spec.server.web_fqdn.
  -k2ws|--kiali2-web-schema <schema>: If specified, this will be the #2 Kaili setting for spec.server.web_schema.
  -mcpu|--minikube-cpu <cpu count>: Number of CPUs to give to each minikube cluster
  -md|--minikube-driver <name>: The driver used by minikube (e.g. virtualbox, kvm2) (Default: virtualbox)
  -mdisk|--minikube-disk <space>: Amount of disk space to give to each minikube cluster
  -mi|--mesh-id <id>: When Istio is installed, it will be part of the mesh with this given name. (Default: mesh-default)
  -mk|--manage-kind <bool>: If "true" and if --client-exe is kubectl, two kind instances will be managed
  -mm|--manage-minikube <bool>: If "true" and if --client-exe is kubectl, two minikube instances will be managed
  -mmem|--minikube-memory <mem>: Amount of memory to give to each minikube cluster
  -mnc|--manual-network-config <bool>: If true, manually configure mesh network. False tells Istio to try to auto-discover things.
                                       (Default: true if on OpenShift, false otherwise)
  -n1|--network1 <id>: When Istio is installed in cluster 1, it will be part of the network with this given name. (Default: network-default)
  -n2|--network2 <id>: When Istio is installed in cluster 2, it will be part of the network with this given name.
                       If this is left as empty string, it will be the same as --network1. (Default: "")
  -h|--help: this message
HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key]. Aborting."
      exit 1
      ;;
  esac
done

if [ "${ISTIO_DIR}" == "" ]; then
  # Go to the main output directory and try to find an Istio there.
  SCRIPT_DIR="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
  OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/../../../_output}"
  ALL_ISTIOS=$(ls -dt1 ${OUTPUT_DIR}/istio-*)
  if [ "$?" != "0" ]; then
    ${OUTPUT_DIR}/../hack/istio/download-istio.sh
    if [ "$?" != "0" ]; then
      echo "ERROR: You do not have Istio installed and it cannot be downloaded"
      exit 1
    fi
  fi
  # use the Istio release that was last downloaded (that's the -t option to ls)
  ISTIO_DIR=$(ls -dt1 ${OUTPUT_DIR}/istio-* | head -n1)
fi

if [ ! -d "${ISTIO_DIR}" ]; then
   echo "ERROR: Istio cannot be found at: ${ISTIO_DIR}"
   exit 1
fi

echo "Istio is found here: ${ISTIO_DIR}"

ISTIOCTL="${ISTIO_DIR}/bin/istioctl"
if [ -x "${ISTIOCTL}" ]; then
  echo "istioctl is found here: ${ISTIOCTL}"
  ${ISTIOCTL} version
else
  echo "ERROR: istioctl is NOT found at ${ISTIOCTL}"
  exit 1
fi

CERT_MAKEFILE="${ISTIO_DIR}/tools/certs/Makefile.selfsigned.mk"
if [ -f "${CERT_MAKEFILE}" ]; then
  echo "Makefile is found here: ${CERT_MAKEFILE}"
else
  echo "ERROR: Makefile is NOT found at ${CERT_MAKEFILE}"
  exit 1
fi

CLIENT_EXE=`which ${CLIENT_EXE_NAME}`
if [ "$?" = "0" ]; then
  echo "The cluster client executable is found here: ${CLIENT_EXE}"
else
  echo "You must install the cluster client ${CLIENT_EXE_NAME} in your PATH before you can continue"
  exit 1
fi

# Are we on OpenShift or Kubernetes - just use the name of the exe for a very simply way to guess
# If you want to explicitly use Kubernetes or OpenShift and you have both clients in PATH,
# then tell the script which one you want to use via the -c option.
if [[ "$CLIENT_EXE" = *"oc" ]]; then
  IS_OPENSHIFT="true"
  echo "Cluster type = OpenShift"
else
  IS_OPENSHIFT="false"
  echo "Cluster type = Kubernetes"
fi

if [ "${IS_OPENSHIFT}" == "true" ]; then
  if [ -z "${CLUSTER1_CONTEXT}" ]; then
    echo "Cluster 1 context is not specified (--cluster1-context)"
    echo "If OpenShift, it should be the api login server URL. If Kubernetes, it should be the kube context."
    exit 1
  fi
  if [ -z "${CLUSTER2_CONTEXT}" ]; then
    echo "Cluster 2 context is not specified (--cluster2-context)"
    echo "If OpenShift, it should be the api login server URL. If Kubernetes, it should be the kube context."
    exit 1
  fi

  # we do not manage minikube or kind when using OpenShift
  MANAGE_MINIKUBE="false"
  MANAGE_KIND="false"

  # By default, we manually configure the mesh network when using OpenShift
  if [ -z "${MANUAL_MESH_NETWORK_CONFIG}" ]; then
    MANUAL_MESH_NETWORK_CONFIG="true"
  fi
else
  if [ "${MANAGE_MINIKUBE}" == "true" -a "${MANAGE_KIND}" == "true" ]; then
    echo "ERROR! Cannot manage both minikube and kind - pick one"
    exit 1
  fi

  # when on Kubenetes (minikube or kind) assume the context name is the same as the cluster name
  # If we know we are on kind, the context names are "kind-<name>"
  if [ -z "${CLUSTER1_CONTEXT}" ]; then
    if [ "${MANAGE_KIND}" == "true" ]; then
      CLUSTER1_CONTEXT="kind-${CLUSTER1_NAME}"
    else
      CLUSTER1_CONTEXT="${CLUSTER1_NAME}"
    fi
  fi
  if [ -z "${CLUSTER2_CONTEXT}" ]; then
    if [ "${MANAGE_KIND}" == "true" ]; then
      CLUSTER2_CONTEXT="kind-${CLUSTER2_NAME}"
    else
      CLUSTER2_CONTEXT="${CLUSTER2_NAME}"
    fi
  fi

  # By default, we do not manually configure the mesh network when using Kubernetes (minikube or kind)
  if [ -z "${MANUAL_MESH_NETWORK_CONFIG}" ]; then
    MANUAL_MESH_NETWORK_CONFIG="false"
  fi
fi

# If network2 is unspecified, assume it is the same as network1
if [ -z "${NETWORK2_ID}" ]; then
  NETWORK2_ID="${NETWORK1_ID}"
fi

# Export all variables so child scripts pick them up
export BOOKINFO_ENABLED \
       BOOKINFO_NAMESPACE \
       CLIENT_EXE_NAME \
       CLUSTER1_CONTEXT \
       CLUSTER1_NAME \
       CLUSTER1_PASS \
       CLUSTER1_USER \
       CLUSTER2_CONTEXT \
       CLUSTER2_NAME \
       CLUSTER2_PASS \
       CLUSTER2_USER \
       CROSSNETWORK_GATEWAY_REQUIRED \
       DORP \
       IS_OPENSHIFT \
       ISTIO_DIR \
       ISTIO_NAMESPACE \
       ISTIO_TAG \
       KIALI_ENABLED \
       MANAGE_KIND \
       MANAGE_MINIKUBE \
       MANUAL_MESH_NETWORK_CONFIG \
       MINIKUBE_CPU \
       MINIKUBE_DISK \
       MINIKUBE_DRIVER \
       MINIKUBE_MEMORY \
       MESH_ID \
       NETWORK1_ID \
       NETWORK2_ID

cat <<EOM
=== SETTINGS ===
BOOKINFO_ENABLED=$BOOKINFO_ENABLED
BOOKINFO_NAMESPACE=$BOOKINFO_NAMESPACE
CLIENT_EXE_NAME=$CLIENT_EXE_NAME
CLUSTER1_CONTEXT=$CLUSTER1_CONTEXT
CLUSTER1_NAME=$CLUSTER1_NAME
CLUSTER1_PASS=$CLUSTER1_PASS
CLUSTER1_USER=$CLUSTER1_USER
CLUSTER2_CONTEXT=$CLUSTER2_CONTEXT
CLUSTER2_NAME=$CLUSTER2_NAME
CLUSTER2_PASS=$CLUSTER2_PASS
CLUSTER2_USER=$CLUSTER2_USER
CROSSNETWORK_GATEWAY_REQUIRED=$CROSSNETWORK_GATEWAY_REQUIRED
DORP=$DORP
IS_OPENSHIFT=$IS_OPENSHIFT
ISTIO_DIR=$ISTIO_DIR
ISTIO_NAMESPACE=$ISTIO_NAMESPACE
ISTIO_TAG=$ISTIO_TAG
KIALI_ENABLED=$KIALI_ENABLED
KIALI1_WEB_FQDN=$KIALI1_WEB_FQDN
KIALI1_WEB_SCHEMA=$KIALI1_WEB_SCHEMA
KIALI2_WEB_FQDN=$KIALI2_WEB_FQDN
KIALI2_WEB_SCHEMA=$KIALI2_WEB_SCHEMA
MANAGE_KIND=$MANAGE_KIND
MANAGE_MINIKUBE=$MANAGE_MINIKUBE
MANUAL_MESH_NETWORK_CONFIG=$MANUAL_MESH_NETWORK_CONFIG
MINIKUBE_CPU=$MINIKUBE_CPU
MINIKUBE_DISK=$MINIKUBE_DISK
MINIKUBE_DRIVER=$MINIKUBE_DRIVER
MINIKUBE_MEMORY=$MINIKUBE_MEMORY
MESH_ID=$MESH_ID
NETWORK1_ID=$NETWORK1_ID
NETWORK2_ID=$NETWORK2_ID
=== SETTINGS ===
EOM

export HACK_ENV_DONE="true"
