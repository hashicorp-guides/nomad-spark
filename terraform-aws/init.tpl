#!/bin/bash

instance_id="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
local_ipv4="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
new_hostname="nomad-$${instance_id}"

# stop consul and nomad so they can be configured correctly
systemctl stop nomad
systemctl stop consul

# clear the consul and nomad data directory ready for a fresh start
rm -rf /opt/consul/data/*
rm -rf /opt/nomad/data/*

# set the hostname (before starting consul and nomad)
hostnamectl set-hostname "$${new_hostname}"

# seeing failed nodes listed  in consul members with their solo config
# try a 2 min sleep to see if it helps with all instances wiping data
# in a similar time window
sleep 120

# add the consul group to the config with jq
jq ".retry_join_ec2 += {\"tag_key\": \"Environment-Name\", \"tag_value\": \"${environment_name}\"}" < /etc/consul.d/consul-default.json > /tmp/consul-default.json.tmp
sed -i -e "s/127.0.0.1/$${local_ipv4}/" /tmp/consul-default.json.tmp
mv /tmp/consul-default.json.tmp /etc/consul.d/consul-default.json
chown consul:consul /etc/consul.d/consul-default.json

if [[ "${consul_as_server}" = "true" ]]; then
  # add the cluster instance count to the config with jq
  jq ".bootstrap_expect = ${cluster_size}" < /etc/consul.d/consul-server.json > /tmp/consul-server.json.tmp
  mv /tmp/consul-server.json.tmp /etc/consul.d/consul-server.json
  chown consul:consul /etc/consul.d/consul-server.json
else
  # remove the consul as server config
  rm /etc/consul.d/consul-server.json
fi

echo "127.0.0.1 $(hostname)" | sudo tee --append /etc/hosts

# start consul and nomad once they are configured correctly
systemctl start consul
#systemctl start nomad
 systemctl start docker

DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null|awk '/inet/ {print $2}'|sed 's/addr://'`)
echo "nameserver $DOCKER_BRIDGE_IP_ADDRESS" | sudo tee /etc/resolv.conf.new
cat /etc/resolv.conf | sudo tee --append /etc/resolv.conf.new
sudo mv /etc/resolv.conf.new /etc/resolv.conf
systemctl restart dnsmasq

#HDFS
export HADOOP_VERSION=2.7.3
wget -O - http://apache.mirror.iphh.net/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz | sudo tar xz -C /usr/local

#Configure Hadoop CLI
HADOOPCONFIGDIR=/usr/local/hadoop-$HADOOP_VERSION/etc/hadoop
sudo bash -c "cat >$HADOOPCONFIGDIR/core-site.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://hdfs.service.consul/</value>
    </property>
</configuration>
EOF

YUM=$(which yum 2>/dev/null)
APT_GET=$(which apt-get 2>/dev/null)
if [[ ! -z $${YUM} ]]; then
  export HOME_DIR=ec2-user
elif [[ ! -z $${APT_GET} ]]; then
  export HOME_DIR=ubuntu
fi

echo "export JAVA_HOME=/usr/"  | sudo tee --append /home/$HOME_DIR/.bashrc
echo "export PATH=$PATH:/usr/local/bin/spark/bin:/usr/local/hadoop-$HADOOP_VERSION/bin" | sudo tee --append /home/$HOME_DIR/.bashrc


echo 'job "hdfs" {

  datacenters = [ "dc1" ]

  group "NameNode" {

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    task "NameNode" {

      driver = "docker"

      config {
        image = "rcgenova/hadoop-2.7.3"
        command = "bash"
        args = [ "-c", "hdfs namenode -format && exec hdfs namenode -D fs.defaultFS=hdfs://$${NOMAD_ADDR_ipc}/ -D dfs.permissions.enabled=false" ]
        network_mode = "host"
        port_map {
          ipc = 8020
          ui = 50070
        }
      }

      resources {
        memory = 500
        network {
          port "ipc" {
            static = "8020"
          }
          port "ui" {
            static = "50070"
          }
        }
      }

      service {
        name = "hdfs"
        port = "ipc"
      }
    }
  }

  group "DataNode" {

    count = 3

    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }
    
    task "DataNode" {

      driver = "docker"

      config {
        network_mode = "host"
        image = "rcgenova/hadoop-2.7.3"
        args = [ "hdfs", "datanode"
          , "-D", "fs.defaultFS=hdfs://hdfs.service.consul/"
          , "-D", "dfs.permissions.enabled=false"
        ]
        port_map {
          data = 50010
          ipc = 50020
          ui = 50075
        }
      }

      resources {
        memory = 500
        network {
          port "data" {
            static = "50010"
          }
          port "ipc" {
            static = "50020"
          }
          port "ui" {
            static = "50075"
          }
        }
      }

    }
  }

}' | tee -a /home/$HOME_DIR/hdfs.nomad

echo 'job "spark-history-server" {
  datacenters = ["dc1"]
  type = "service"

  group "server" {
    count = 1

    task "history-server" {
      driver = "docker"
      
      config {
        image = "barnardb/spark"
        command = "/spark/spark-2.1.0-bin-nomad/bin/spark-class"
        args = [ "org.apache.spark.deploy.history.HistoryServer" ]
        port_map {
          ui = 18080
        }
        network_mode = "host"
      }

      env {
        "SPARK_HISTORY_OPTS" = "-Dspark.history.fs.logDirectory=hdfs://hdfs.service.consul/spark-events/"
        "SPARK_PUBLIC_DNS"   = "spark-history.service.consul"
      }

      resources {
        cpu    = 500
        memory = 500
        network {
          mbits = 250
          port "ui" {
            static = 18080
          }
        }
      }

      service {
        name = "spark-history"
        tags = ["spark", "ui"]
        port = "ui"
      }
    }

  }
}' | tee -a /home/$HOME_DIR/spark-history-server.nomad


