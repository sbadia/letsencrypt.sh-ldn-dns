#!/bin/bash
#
# Copyright (C) 2016 Sebastien Badia <seb@sebian.fr>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

source ./config/ldn.sh

if [ -z "$PUPPET_REPO" ]; then
  echo "+ PUPPET_REPO variable not set, please edit ./config/ldn.sh"
  exit 1
fi

function update_serial_push() {
  local PUPPET_REPO="${1}" LDN_ZONE="${2}" TYPE="${3}" DOMAIN="${4}"
  local oldserial=$(grep -i Serial "$LDN_ZONE" |awk '{print $1}')
  local date=$(date +%Y%m%d)

  # This function update the serial of a zone. This function make a verification
  # if the serial must be updated or not
  #
  # Parameters:
  # - PUPPET_REPO
  #   The localtion of Puppet LDN repository
  # - LDN_ZONE
  #   The ldn-fai.net bind zone (for serial update)
  pushd "$PUPPET_REPO"
    tests=$(printf $oldserial |grep "^$date")
    ret=$?
    # on teste s'il faut changer ou faire +1
    if [ $ret -eq 1 ]; then
      newserial=${date}01
    elif [ $ret -eq 0 ]; then
      newserial=$(echo "$oldserial + 1" |bc)
    else
      printf "+ Something weird happened… (serial)"
      exit 1
    fi
    sed -i "s/$oldserial/$newserial/" "$LDN_ZONE"
    git add "$LDN_ZONE"
    git commit -m "dns: ${TYPE} - Let's Encrypt DNS challenge for ${DOMAIN}"
    git push
  popd
}

function run_puppet_nsa() {
  ssh "$DNS_MASTER" 'sudo puppet agent --onetime --verbose --ignorecache --no-daemonize --no-usecacheonfailure --no-splay'
}

function deploy_challenge {
  local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

  # This hook is called once for every domain that needs to be
  # validated, including any alternative names you may have listed.
  #
  # Parameters:
  # - DOMAIN
  #   The domain name (CN or subject alternative name) being
  #   validated.
  # - TOKEN_FILENAME
  #   The name of the file containing the token to be served for HTTP
  #   validation. Should be served by your web server as
  #   /.well-known/acme-challenge/${TOKEN_FILENAME}.
  # - TOKEN_VALUE
  #   The token value that needs to be served for validation. For DNS
  #   validation, this is what you want to put in the _acme-challenge
  #   TXT record. For HTTP validation it is the value that is expected
  #   be found in the $TOKEN_FILENAME file.

  local record=$(basename _acme-challenge.${DOMAIN} .ldn-fai.net)

  echo "+ Add: ${record}  IN TXT ${TOKEN_VALUE}"
  pushd "$PUPPET_REPO"
    if ! grep -q "${record} IN TXT ${TOKEN_VALUE}" "$LDN_ZONE" ; then
      echo "${record} IN TXT ${TOKEN_VALUE}" >> "$LDN_ZONE"
      update_serial_push "$PUPPET_REPO" "$LDN_ZONE" "[deploy]" "$DOMAIN"
      run_puppet_nsa
      # Wait for bind
      sleep 5
    fi
  popd
  while [ -z $(dig +short TXT _acme-challenge.${DOMAIN}) ]; do
    echo "+ dns record not yep propagated!"
    sleep 5
  done
}

function clean_challenge {
  local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

  # This hook is called after attempting to validate each domain,
  # whether or not validation was successful. Here you can delete
  # files or DNS records that are no longer needed.
  #
  # The parameters are the same as for deploy_challenge.
  local record=$(basename _acme-challenge.${DOMAIN} .ldn-fai.net)

  echo "+ Clean: ${record}  IN TXT ${TOKEN_VALUE}"
  dns_record="${record} IN TXT ${TOKEN_VALUE}"
  pushd "$PUPPET_REPO"
    if grep -q "${dns_record}" "$LDN_ZONE" ; then
      sed -i /"$dns_record"/d  "$LDN_ZONE"
      update_serial_push "$PUPPET_REPO" "$LDN_ZONE" "[clean]" "$DOMAIN"
      run_puppet_nsa
    fi
  popd
}

function deploy_cert {
  local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

  # This hook is called once for each certificate that has been
  # produced. Here you might, for instance, copy your new certificates
  # to service-specific locations and reload the service.
  #
  # Parameters:
  # - DOMAIN
  #   The primary domain name, i.e. the certificate common
  #   name (CN).
  # - KEYFILE
  #   The path of the file containing the private key.
  # - CERTFILE
  #   The path of the file containing the signed certificate.
  # - FULLCHAINFILE
  #   The path of the file containing the full certificate chain.
  # - CHAINFILE
  #   The path of the file containing the intermediate certificate(s).
  # - TIMESTAMP
  #   Timestamp when the specified certificate was created.
}

function unchanged_cert {
  local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

  # This hook is called once for each certificate that is still
  # valid and therefore wasn't reissued.
  #
  # Parameters:
  # - DOMAIN
  #   The primary domain name, i.e. the certificate common
  #   name (CN).
  # - KEYFILE
  #   The path of the file containing the private key.
  # - CERTFILE
  #   The path of the file containing the signed certificate.
  # - FULLCHAINFILE
  #   The path of the file containing the full certificate chain.
  # - CHAINFILE
  #   The path of the file containing the intermediate certificate(s).
}

HANDLER=$1; shift; $HANDLER $@
