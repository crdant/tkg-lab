#!/bin/bash -e 
TKG_LAB_SCRIPTS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${TKG_LAB_SCRIPTS}/set-env.sh

ENVIRONMENT_NAME=$(yq r ${PARAMS_YAML} management-cluster.name)
OKTA_API_KEY=$(yq r ${PARAMS_YAML} okta.api-key)
OKTA_AUTH_SERVER_CN=$(yq r ${PARAMS_YAML} okta.auth-server-fqdn)

function add_application() {
    local name="${1}"
    local uri="${2}"
    local redirect_uri=${3}
    local logout_uri=${4}

    local application="$(jq -n --arg name "${name}" \
                             --arg uri ${uri} \
                             --arg redirect_uri ${redirect_uri} \
                             --arg logout_redirect_uri ${logout_uri} \
                             -f okta/app.json)"

    local client="$(curl --silent --location --request POST "https://${OKTA_AUTH_SERVER_CN}/api/v1/apps" \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/json' \
      --header "Authorization: SSWS ${OKTA_API_KEY}" \
      --data-raw "${application}" |
      jq .credentials.oauthClient)"

    CLIENT_ID=$(echo ${client} | jq -r .client_id)
    CLIENT_SECRET=$(echo ${client} | jq -r .client_secret)
}

function check_group() {
    local name="${1}"
    local first="$(curl --silent --location --get "https://${OKTA_AUTH_SERVER_CN}/api/v1/groups" \
      --header 'Accept: application/json' \
      --header "Authorization: SSWS ${OKTA_API_KEY}" \
      --data "q=${name}" | jq -r ".[0].profile.name")"
    [[ ${first} == ${name}  ]]
}


function add_group() {
    local name="${1}"
    local description="${2}"
    local group="$(jq -n --arg name "${name}" \
                         --arg description "${description}" \
                         -f okta/group.json)"

    curl --silent --location --request POST "https://${OKTA_AUTH_SERVER_CN}/api/v1/groups" \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/json' \
      --header "Authorization: SSWS ${OKTA_API_KEY}" \
      --data-raw "${group}" > /dev/null
 }

DEX_CLIENT_ID=$(yq read $PARAMS_YAML "okta.dex-app-client-id")
if [[ -z ${DEX_CLIENT_ID} ]] ; then
    DEX_CN=$(yq r ${PARAMS_YAML} management-cluster.dex-fqdn)
    DEX_REDIRECT_URI="https://${DEX_CN}/callback"
    DEX_LOGOUT_URI="https://${DEX_CN}/logout"

    add_application "TKG (${ENVIRONMENT_NAME})" "${DEX_REDIRECT_URI}" "${DEX_REDIRECT_URI}" "${DEX_LOGOUT_URI}"
    yq write $PARAMS_YAML -i "okta.dex-app-client-id" "${CLIENT_ID}"
    yq write $PARAMS_YAML -i "okta.dex-app-client-secret" "${CLIENT_SECRET}"
    CLIENT_ID=
    CLIENT_SECRET=
fi

HARBOR_CLIENT_ID=$(yq read $PARAMS_YAML "okta.harbor-app-client-id")
if [[ -z ${HARBOR_CLIENT_ID} ]] ; then
    HARBOR_CN=$(yq r ${PARAMS_YAML} shared-services-cluster.dex-fqdn)
    HARBOR_REDIRECT_URI="https://${DEX_CN}/c/oidc/callback"
    HARBOR_LOGOUT_URI="https://${DEX_CN}/c/oidc/logout"

    add_application "Harbor (${ENVIRONMENT_NAME})" "${HARBOR_REDIRECT_URI}" "${HARBOR_REDIRECT_URI}" "${HARBOR_LOGOUT_URI}"
    yq write $PARAMS_YAML -i "okta.harbor-app-client-id" "${CLIENT_ID}"
    yq write $PARAMS_YAML -i "okta.harbor-app-client-secret" "${CLIENT_SECRET}"
    CLIENT_ID=
    CLIENT_SECRET=
fi

CONCOURSE_CLIENT_ID=$(yq read $PARAMS_YAML "okta.concourse-app-client-id")
if [[ -z ${CONCOURSE_CLIENT_ID} ]] ; then
    CONCOURSE_CN=$(yq r ${PARAMS_YAML} shared-services-cluster.dex-fqdn)
    CONCOURSE_REDIRECT_URI="https://${DEX_CN}/sky/issuer/callback"
    CONCOURSE_LOGOUT_URI="https://${DEX_CN}/sky/issuer/logout"

    add_application "Concourse (${ENVIRONMENT_NAME})" "${CONCOURSE_REDIRECT_URI}" "${CONCOURSE_REDIRECT_URI}" "${CONCOURSE_LOGOUT_URI}"
    yq write $PARAMS_YAML -i "okta.concourse-app-client-id" "${CLIENT_ID}"
    yq write $PARAMS_YAML -i "okta.concourse-app-client-secret" "${CLIENT_SECRET}"
    CLIENT_ID=
    CLIENT_SECRET=
fi

PLATFORM_TEAM="platform-team"
if ! check_group "${PLATFORM_TEAM}" ; then
    add_group "${PLATFORM_TEAM}" "Platform engineering team"
fi
