#!/bin/bash
# Expose OpenStack services from kind cluster to Azure VNET
# Control Plane Private IP: 10.0.0.4

echo "=================================================="
echo "Exposing OpenStack Services to Azure VNET"
echo "Control Plane IP: 10.0.0.4"
echo "=================================================="
echo ""

# Stop any existing port-forwards
echo "Stopping existing port-forwards..."
pkill -f "kubectl port-forward.*openstack" || true
sleep 2

# Expose RabbitMQ (AMQP)
echo "✓ Starting RabbitMQ port-forward (5672)..."
nohup kubectl port-forward -n openstack svc/openstack-rabbitmq 5672:5672 --address=0.0.0.0 \
  > /tmp/pf-rabbitmq.log 2>&1 &

# Expose MariaDB
echo "✓ Starting MariaDB port-forward (3306)..."
nohup kubectl port-forward -n openstack svc/mariadb-basic 3306:3306 --address=0.0.0.0 \
  > /tmp/pf-mariadb.log 2>&1 &

# Expose Keystone API
echo "✓ Starting Keystone API port-forward (5000)..."
nohup kubectl port-forward -n openstack svc/keystone-api 5000:5000 --address=0.0.0.0 \
  > /tmp/pf-keystone.log 2>&1 &

# Expose Neutron API
echo "✓ Starting Neutron API port-forward (9696)..."
nohup kubectl port-forward -n openstack svc/neutron-server 9696:9696 --address=0.0.0.0 \
  > /tmp/pf-neutron.log 2>&1 &

# Expose Nova API
echo "✓ Starting Nova API port-forward (8774)..."
nohup kubectl port-forward -n openstack svc/nova-api 8774:8774 --address=0.0.0.0 \
  > /tmp/pf-nova.log 2>&1 &

# Expose Placement API
echo "✓ Starting Placement API port-forward (8778)..."
nohup kubectl port-forward -n openstack svc/placement-api 8778:8778 --address=0.0.0.0 \
  > /tmp/pf-placement.log 2>&1 &

# Expose Glance API
echo "✓ Starting Glance API port-forward (9292)..."
nohup kubectl port-forward -n openstack svc/glance-api 9292:9292 --address=0.0.0.0 \
  > /tmp/pf-glance.log 2>&1 &

# Wait for port-forwards to start
sleep 3

echo ""
echo "=================================================="
echo "✓ All services exposed!"
echo "=================================================="
echo ""
echo "Services accessible at: 10.0.0.4"
echo ""
echo "  RabbitMQ:   10.0.0.4:5672"
echo "  MariaDB:    10.0.0.4:3306"
echo "  Keystone:   10.0.0.4:5000"
echo "  Neutron:    10.0.0.4:9696"
echo "  Nova:       10.0.0.4:8774"
echo "  Placement:  10.0.0.4:8778"
echo "  Glance:     10.0.0.4:9292"
echo ""
echo "Verification:"
ss -tlnp | grep -E "5672|3306|5000|9696|8774|8778|9292" | awk '{print "  "$4}'
echo ""
echo "Logs in: /tmp/pf-*.log"
echo ""
echo "Use these IPs in compute/network node values files!"
echo "=================================================="
