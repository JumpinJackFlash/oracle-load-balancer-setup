#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

set -e

# If you set these values the script will drop through the prompts

export CERT_TYPE=
export DOMAIN=
export EMAIL=
COMP_OCID=
SUB_OCID=
SHAPE=
MIN_MBPS=
MAX_MBPS=

clear

if [ ! -f ~/.oci/config ]; then
  echo
  echo -e "${RED}It does not appear as though you have run 'oci setup config' to create your OCI CLI configuration file.${NC}"
  echo
  echo -e "${YELLOW}The OCI CLI can be installed by running 'yum install -y python36-oci-cli' as sudo.${NC}"
  echo
  exit
fi

date
echo "This script will setup an SSL enabled load balancer."
echo
echo "This script is designed to be run from an AsterionDB Marketplace Image"
echo "compute instance.  The instance this script is running from will be placed"
echo "in the backup sets assigned to the load balancer."
echo
echo "This script is limited to only creating a regional load balancer.  The VCN subnet"
echo "that you use must be created as a regional subnet (subnet_type = regional)."
echo
echo "This instance will be used for Let's Encrypt registration and certification maintenance."
echo
echo "You will need to register the public IP address for the load balancer with your DNS provider."
echo
echo "You will need the following information:"
echo 
echo "  -  Your domain name (i.e. your.domain.com)"
echo "  -  An email address to use when registering with Let's Encrypt"
echo "  -  The compartment OCID that the load balancer will be placed to"
echo "  -  The VCN subnet OCID that the load balancer will be placed in"
echo
read -p "Press ENTER to continue..."
echo

while [ "${CERT_TYPE}" == '' ]; do
  read -p "Do you want a production (default) or a test certificate [p|t]?  " CERT_TYPE
  case "${CERT_TYPE}" in
    "")
      CERT_TYPE='production'
      ;;
    [Pp])
      CERT_TYPE='production'
      ;;
    [Tt])
      CERT_TYPE='--test-cert'
      ;;
    *)
      echo "Certificate type must by p or t."
      CERT_TYPE=""
      ;;
  esac
done

echo

if [ "${CERT_TYPE}" == 'production' ]; then
  CERT_TYPE=''
fi

while [ "${DOMAIN}" == '' ]; do
  read -p "Enter your domain name: " DOMAIN
  echo ""
  [ "${DOMAIN}" == '' ] && echo -e "${RED}Your domain name must be specified.${NC}"
done

while [ "${EMAIL}" == '' ]; do
  read -p "Enter your email address: " EMAIL
  echo ""
  [ "${EMAIL}" == '' ] && echo -e "${RED}An email address must be specified.${NC}"
done

while [ "${COMP_OCID}" == '' ]; do
  read -p "Enter the compartment OCID that the load balancer will be placed in: " COMP_OCID
  echo ""
  [ "${COMP_OCID}" == '' ] && echo -e "${RED}A compartment OCID must be specified.${NC}"
done

while [ "${SUB_OCID}" == '' ]; do
  read -p "Enter the VCN subnet OCID that the load balancer will be placed in: " SUB_OCID
  echo ""
  [ "${SUB_OCID}" == '' ] && echo -e "${RED}A VCN subnet OCID must be specified.${NC}"
done

echo "These are the load balancer shapes available:"
echo
echo "  1 - Flexible (default)"
echo "  2 - 10Mbps-Micro (Always Free)"
echo "  3 - 10Mbps"
echo "  4 - 100Mbps"
echo "  5 - 400Mbps"
echo "  6 - 800Mbps"
echo

E_SHAPE=''

while [ "${SHAPE}" == '' ]; do
  read -p "Enter the number of the desired shape [1]: " E_SHAPE
  case "${E_SHAPE}" in
    "")
      SHAPE='flexible'
      ;;
    1)
      SHAPE='flexible'
      ;;
    2)
      SHAPE='10Mbps-Micro'
      ;;
    3)
      SHAPE='10Mbps'
      ;;
    4)
      SHAPE='100Mbps'
      ;;
    5)
      SHAPE='400Mbps'
      ;;
    6)
      SHAPE='800Mbps'
      ;;
    *)
      echo "Load balancer shape ${E_SHAPE} is invalid."
      ;;
  esac
done

if [ "${SHAPE}" == 'flexible' ]; then

  echo
  echo "Flexible shape requires min/max Mbps values..."
  echo

  while [ "${MIN_MBPS}" == '' ]; do
    read -p "Enter the minimum Mbps (10 - 1000) [10]: " MIN_MBPS
    [ "${MIN_MBPS}" == '' ] && MIN_MBPS=10
    [[ $MIN_MBPS =~ ^[0-9]+$ ]] || { echo -e "${RED}Enter a valid number...${NC}"; echo; continue; }
    if ((MIN_MBPS >= 10 && MIN_MBPS <= 1000)); then
      break
    else
      echo -e "${RED}Minimum Mbps must be between 10 and 1000.${NC}"
      echo
    fi
  done

  echo

  while [ "${MAX_MBPS}" == '' ]; do
    read -p "Enter the maximum Mbps (10 - 1000) [10]: " MAX_MBPS
    [ "${MAX_MBPS}" == '' ] && MAX_MBPS=10
    [[ $MAX_MBPS =~ ^[0-9]+$ ]] || { echo -e "${RED}Enter a valid number...${NC}"; echo; continue; }
    if ((MAX_MBPS >= 10 && MAX_MBPS <= 1000 && MIN_MBPS <= MAX_MBPS)); then
      break
    else
      echo -e "${RED}Maximum Mbps must be between 10 and 1000 and less than the minimum Mbps.${NC}"
      echo
    fi
  done

  SHAPE_DETAILS="{\"maximumBandwidthInMbps\": $MAX_MBPS, \"minimumBandwidthInMbps\": $MIN_MBPS}"
  printf "%s" $SHAPE_DETAILS >shapeDetails.json
  SHAPE_DETAILS='--shape-details file://shapeDetails.json'

fi

echo
read -p "Press ENTER to begin the creation process..."
echo
echo -e "${GREEN}Creating the load balancer...${NC}"

Q='"'

printf "[%s%s%s]" $Q $SUB_OCID $Q >subnetDetails.json

oci lb load-balancer create --compartment-id $COMP_OCID --display-name asteriondb_lb --shape-name $SHAPE --subnet-ids file://subnetDetails.json $SHAPE_DETAILS --wait-for-state SUCCEEDED --wait-interval-seconds 2 >output.json

LB_IP=$(jp.py-3 -f output.json data.'"ip-addresses"'[0].'"ip-address"' | tr -d '"')
export LB_OCID=$(jp.py-3 -f output.json data.id | tr -d '"')

SL_OCID=$(oci network subnet get --subnet-id $SUB_OCID --query data.'"security-list-ids"'[0] --raw-output)

echo -e "${GREEN}The load balancer has been created...${NC}"
echo
echo "The public IP address for the load balancer is:" $LB_IP
echo
echo "Register this IP address your DNS provider for domain ${DOMAIN}."
echo
read -p "Verify that the DNS entry is available and then press ENTER to continue..."
echo

echo -e "${GREEN}Installing Certbot and opening port 80...${NC}"
sudo yum install -y certbot 

sudo firewall-cmd  --zone=public --permanent --add-port=80/tcp
sudo firewall-cmd --reload

echo -e "${GREEN}Setting up security list...${NC}"
oci network security-list update --security-list-id $SL_OCID --force --egress-security-rules file://egressRules.json --ingress-security-rules file://ingressRules.json --wait-for-state AVAILABLE

echo -e "${GREEN}Creating certbot_bs backend set...${NC}"
oci lb backend-set create --health-checker-protocol TCP --health-checker-port 22 --load-balancer-id $LB_OCID --name certbot_bs --policy weighted_round_robin --health-checker-url-path '/' --wait-interval-seconds 2 --wait-for-state SUCCEEDED

echo -e "${GREEN}Creating https_bs backend set...${NC}"
oci lb backend-set create --health-checker-protocol HTTP --health-checker-port 8080 --load-balancer-id $LB_OCID --name https_bs --policy weighted_round_robin --health-checker-url-path '/' --wait-interval-seconds 2 --wait-for-state SUCCEEDED

IP=`ip a s ens3 | egrep -o 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d' ' -f2`

echo -e "${GREEN}Creating https backend...${NC}"
oci lb backend create --backend-set-name https_bs --ip-address $IP --load-balancer-id $LB_OCID --port 8080 --wait-interval-seconds 2 --wait-for-state SUCCEEDED

echo -e "${GREEN}Creating certbot backend...${NC}"
oci lb backend create --backend-set-name certbot_bs --ip-address $IP --load-balancer-id $LB_OCID --port 80 --wait-interval-seconds 2 --wait-for-state SUCCEEDED

echo -e "${GREEN}Creating routing policy for certbot...${NC}"
oci lb routing-policy create --condition-language-version V1 --load-balancer-id $LB_OCID --name certbot_route --rules file://routingPolicyRules.json --wait-interval-seconds 2 --wait-for-state SUCCEEDED

echo -e "${GREEN}Creating HTTP redirect rule set...${NC}"
oci lb rule-set create --items file://ruleSetItems.json --load-balancer-id $LB_OCID --name http_redirect --wait-interval-seconds 2 --wait-for-state SUCCEEDED

echo -e "${GREEN}Creating HTTP listener...${NC}"
oci lb listener create --default-backend-set-name certbot_bs --load-balancer-id $LB_OCID --name http_listener --port 80 --protocol HTTP --wait-for-state SUCCEEDED --wait-interval-seconds 2

CERT_PATH=/etc/letsencrypt/live/${DOMAIN}
export CERT_NAME=${DOMAIN}_$(date +"%Y%m%d%H%M%S")
export RENEW_CERT=no

cat > deployHook.sh <<'EOF'
#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

DOMAIN=DOMAIN_VAR

# If we are creating a certificate, do not set the CERT_NAME.
if [ "${RENEW_CERT}" == 'yes' ]; then

  export CERT_NAME=${DOMAIN}_$(date +"%Y%m%d%H%M%S")

fi

sudo -E oci lb certificate create --certificate-name $CERT_NAME --load-balancer-id LB_OCID --private-key-file CERT_PATH/privkey.pem --public-certificate-file CERT_PATH/fullchain.pem --config-file /home/asterion/.oci/config --wait-interval-seconds 2 --wait-for-state SUCCEEDED

if [ "${RENEW_CERT}" == 'yes' ]; then

  oci lb listener update --load-balancer-id LB_OCID --listener-name https_listener --default-backend-set-name https_bs --port 443 --protocol HTTP --routing-policy-name certbot_route --wait-for-state SUCCEEDED --wait-interval-seconds 2 --ssl-certificate-name $CERT_NAME --force --config-file /home/asterion/.oci/config

fi
EOF

chmod 750 deployHook.sh

sed -i "s#DOMAIN_VAR#$DOMAIN#g" deployHook.sh
sed -i "s#CERT_PATH#$CERT_PATH#g" deployHook.sh
sed -i "s#LB_OCID#$LB_OCID#g" deployHook.sh

# This is here to allow the Load Balancer to catch up w/ the route and redirect rules.
sleep 5s

echo -e "${GREEN}Getting letsEncrypt certificate...${NC}"
sudo -E certbot certonly -n --standalone $CERT_TYPE --email $EMAIL --deploy-hook /home/asterion/asterion/oracle/admin/setupLoadBalancer/deployHook.sh -d $DOMAIN --no-eff-email --agree-tos

echo -e "${GREEN}Updating HTTP listener...${NC}"
oci lb listener update --load-balancer-id $LB_OCID --listener-name http_listener --default-backend-set-name certbot_bs --port 80 --protocol HTTP --rule-set-names '["http_redirect"]' --force --wait-for-state SUCCEEDED --wait-interval-seconds 2

echo -e "${GREEN}Creating HTTPS listener...${NC}"
oci lb listener create --default-backend-set-name https_bs --load-balancer-id $LB_OCID --name https_listener --port 443 --protocol HTTP --routing-policy-name certbot_route --wait-for-state SUCCEEDED --wait-interval-seconds 2 --ssl-certificate-name $CERT_NAME

echo -e "${GREEN}Setting up Certbot cron job...${NC}"

SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "export RENEW_CERT=yes && sleep $SLEEPTIME && certbot renew $CERT_TYPE -q" | sudo tee /etc/cron.daily/certbotRenewal > /dev/null
sudo chmod 750 /etc/cron.daily/certbotRenewal

echo
echo -e "${BLUE}Success...!!!  Your AsterionDB installation is now secure and behind an SSL enabled load balancer.${NC}"
echo -e "${BLUE}You can now proceed with installing AsterionDB by running the updateConfig.sh and applyConfig.sh scripts.${NC}"
date
