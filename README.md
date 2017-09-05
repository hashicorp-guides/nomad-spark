# Nomad-spark

## Step-by-Step Walkthrough
**Write this using markdown so you can copy/paste into the README of the guide.**

Download/clone the repo, it must be set up in the correct repo structure to utilize the previous Nomad cluster guide. It should look like this

```bash
/hashicorp-guides/nomad
/hashicorp-guides/nomad-spark
```

Now that we have the necessary repos setup we can launch our control node into the public subnet that houses our Nomad Cluster.

```bash
$ terraform plan -state=aws.tfstate terraform-aws
…
...
+ aws_instance.control
ami:                               "ami-5a5a723a"
associate_public_ip_address:       "<computed>"
availability_zone:                 "<computed>"
…
Plan: 1 to add, 0 to change, 0 to destroy.
```

Looks good, we should be adding one control node to interact with the cluster. Now time to use terraform apply.

```bash
$ terraform apply -state=aws.tfstate terraform-aws/
…
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

…
Outputs:

control_node_public_ip = 52.53.125.87
```

Terraform should output the public IP of the control node. Now let’s SSH into the control node

```bash
$ ssh -i nomad_control_key.pem ec2-user@52.53.125.87
```

You should be logged in to the control node now. The next step is to configure our control node to talk the Nomad Cluster using the “NOMAD_ADDR=http://$Nomad_server_ip:4646” env variable. First we need to leverage the Consul agent installed on our node to see the varioous members of the cluster. NOTE: this command may a few minutes complete successfully as the instances may still be provisioning behind the scenes via terraform.

```bash
[ec2-user@nomad-control-i-0d564e3959ab12525 ~]$ consul members
Node                               Address             Status  Type    Build  Protocol  DC
consul-i-03044c2a6e65a898c         172.19.76.198:8301  alive   server  0.8.3  2         dc1
consul-i-03d8ea5c0225035a5         172.19.76.50:8301   alive   server  0.8.3  2         dc1
consul-i-0473b2557f65e497d         172.19.82.241:8301  alive   server  0.8.3  2         dc1
Nomad-control-i-0d564e3959ab12   172.19.5.182:8301   alive   client  0.8.4  2         dc1
nomad-i-0636d36104f591d7b          172.19.42.206:8301  alive   client  0.8.4  2         dc1
nomad-i-071b63654b239c84c          172.19.44.37:8301   alive   client  0.8.4  2         dc1
nomad-i-09d977cb55ed16172          172.19.27.92:8301   alive   client  0.8.4  2         dc1
```

Set the NOMAD_ADDR env variable to one of the nomad servers IPs (NOT Nomad-control-i-XXXX)

```bash
[ec2-user@nomad-control-i-0d564e3959ab12525 ~]$ export NOMAD_ADDR="http://172.19.42.206:4646"
[ec2-user@nomad-control-i-0d564e3959ab12525 ~]$ nomad server-members
Name                              Address        Port  Status  Leader  Protocol  Build  Datacenter  Region
nomad-i-0636d36104f591d7b.global  172.19.42.206  4648  alive   true    2         0.6.0  dc1         global
nomad-i-071b63654b239c84c.global  172.19.44.37   4648  alive   false   2         0.6.0  dc1         global
nomad-i-09d977cb55ed16172.global  172.19.27.92   4648  alive   false   2         0.6.0  dc1         global
```


You should now be able to launch Spark Jobs against the cluster.

```bash
$ source ~/.bashrc
$ /usr/local/bin/spark/bin/spark-submit   \
--class org.apache.spark.examples.JavaSparkPi \
 --master nomad \
 --deploy-mode cluster \
 --conf spark.executor.instances=4 \
  --conf spark.nomad.cluster.monitorUntil=complete \
  --conf spark.nomad.sparkDistribution=https://s3.amazonaws.com/nomad-spark/spark-2.1.0-bin-nomad.tgz \
  https://s3.amazonaws.com/nomad-spark/spark-examples_2.11-2.1.0-SNAPSHOT.jar 100
```



Now we need to check the allocations to find the driver

```bash
[ec2-user@nomad-control-i-0d564e3959ab12525 ~]$ nomad status org.apache.spark.examples.JavaSparkPi-2017-08-01T20:42:25.482Z
ID            = org.apache.spark.examples.JavaSparkPi-2017-08-01T20:42:25.482Z
Name          = org.apache.spark.examples.JavaSparkPi
Submit Date   = 08/01/17 20:43:29 UTC
Type          = batch
Priority      = 40
Datacenters   = dc1
Status        = dead
Periodic      = false
Parameterized = false

Summary
Task Group  Queued  Starting  Running  Failed  Complete  Lost
driver      0       0         0        0       1         0
executor    0       0         0        0       4         0

Allocations
ID        Node ID   Task Group  Version  Desired  Status    Created At
61208475  425294fc  executor    1        stop     complete  08/01/17 20:42:47 UTC
a31fc217  54939365  executor    1        stop     complete  08/01/17 20:42:47 UTC
cde6c407  3d4799a5  executor    1        stop     complete  08/01/17 20:42:47 UTC
fe37583b  54939365  executor    1        stop     complete  08/01/17 20:42:47 UTC
574c0d77  425294fc  driver      2        run      complete  08/01/17 20:42:27 UTC
```



We can drill on the logs of the spark driver alloocation to see the result.

```bash
[ec2-user@nomad-control-i-0d564e3959ab12525 ~]$ nomad logs 574c0d77
Pi is roughly 3.1412256
```

Done! You now have the output of your spark job running on Nomad.
Continue onto the next section to use HDFS along with Spark on Nomad

### Spark with HDFS Walkthrough
Another common use case is to combine HDFS with Spark for pulling data from a distributed file system.  In the example we will walk through deploying an HDFS cluster on Nomad as well as a spark-history-server. Once done, I’ll show a few more Spark examples like wordcount running with HDFS as the data source.

The Spark history server and several of the sample Spark jobs below require
HDFS. Using the included job file, deploy an HDFS cluster on Nomad:

```bash
$ cd $HOME
$ nomad run hdfs.nomad
$ nomad status hdfs
```

When the allocations are all in the `running` state (as shown by `nomad status
hdfs`), query Consul to verify that the HDFS service has been registered:

```bash
$ dig hdfs.service.consul
```

Next, create directories and files in HDFS for use by the history server and the
sample Spark jobs:

```bash
$ hdfs dfs -mkdir /foo
$ hdfs dfs -put /var/log/apt/history.log /foo
$ hdfs dfs -mkdir /spark-events
$ hdfs dfs -ls /
```

Finally, deploy the Spark history server:

```bash
$ nomad run spark-history-server-hdfs.nomad
```

You can get the private IP for the history server with a Consul DNS lookup:

```bash
$ dig spark-history.service.consul
```

Cross-reference the private IP with the `terraforom apply` output to get the
corresponding public IP. You can access the history server at
`http://PUBLIC_IP:18080`.

## Sample Spark jobs

The sample `spark-submit` commands listed below demonstrate several of the
official Spark examples. Features like `spark-sql`, `spark-shell` and `pyspark`
are included. The commands can be executed from any client or server.

You can monitor the status of a Spark job in a second terminal session with:

```bash
$ nomad status
$ nomad status JOB_ID
$ nomad alloc-status DRIVER_ALLOC_ID
$ nomad logs DRIVER_ALLOC_ID
```

To view the output of the job, run `nomad logs` for the driver's Allocation ID.

### SparkPi (Java)

```bash
spark-submit \
  --class org.apache.spark.examples.JavaSparkPi \
  --master nomad \
  --deploy-mode cluster \
  --conf spark.executor.instances=4 \
  --conf spark.nomad.cluster.monitorUntil=complete \
  --conf spark.eventLog.enabled=true \
  --conf spark.eventLog.dir=hdfs://hdfs.service.consul/spark-events \
  --conf spark.nomad.sparkDistribution=https://s3.amazonaws.com/nomad-spark/spark-2.1.0-bin-nomad.tgz \
  https://s3.amazonaws.com/nomad-spark/spark-examples_2.11-2.1.0-SNAPSHOT.jar 100
```

### Word count (Java)

```bash
spark-submit \
  --class org.apache.spark.examples.JavaWordCount \
  --master nomad \
  --deploy-mode cluster \
  --conf spark.executor.instances=4 \
  --conf spark.nomad.cluster.monitorUntil=complete \
  --conf spark.eventLog.enabled=true \
  --conf spark.eventLog.dir=hdfs://hdfs.service.consul/spark-events \
  --conf spark.nomad.sparkDistribution=https://s3.amazonaws.com/nomad-spark/spark-2.1.0-bin-nomad.tgz \
  https://s3.amazonaws.com/nomad-spark/spark-examples_2.11-2.1.0-SNAPSHOT.jar \
  hdfs://hdfs.service.consul/foo/history.log
```
