# oracle-load-balancer-setup
Setup a regional load balancer and a Let's Encrypt SSL Cert. with this script.

The script also sets up automated certificate renewal with a cron job.

Install these files on an OCI compute node.

Take a look at and run the setupLoadBalancer.sh script. It will ask you for:

- Certificate type: production|test
- Domain name: your.domain.com
- Email address (for LE SSL Cert): your.email@address.com
- The compartment ID
- The VCN Subnet ID
- The desired load balancer shape

You must register the IP address of the Load Balancer with your domain provider.

To see an example of how we at AsterionDB utilize this script please refer to this link:

  (https://asteriondb.com/getting-started/)
  
Here's the logged output of setupLoadBalancer.sh:

  (https://asteriondb.com/installation-log/#load-balancer-setup)
