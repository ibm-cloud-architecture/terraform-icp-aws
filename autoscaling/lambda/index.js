console.log('Loading function');

var uuid = require('uuid');
var fs = require('fs');
var yaml = require('js-yaml');
var common = require('./common.js');

var job_tmpl = yaml.safeLoad(fs.readFileSync('./job-tmpl.yaml', 'utf8'));

/* sample event:
{
  "version": "0",
  "id": "52172828-61c2-5465-175b-3eea9f83d58a",
  "detail-type": "EC2 Instance-launch Lifecycle Action",
  "source": "aws.autoscaling",
  "account": "299743145002",
  "time": "2018-03-05T18:27:49Z",
  "region": "us-east-2",
  "resources": [
    "arn:aws:autoscaling:us-east-2:299743145002:autoScalingGroup:5c3812e5-af66-443a-a279-7205c12590b4:autoScalingGroupName/icp-worker-asg-1adb04ca"
  ],
  "detail": {
    "LifecycleActionToken": "230c6086-e66c-4f66-abee-ecfc9d6746b1",
    "AutoScalingGroupName": "icp-worker-asg-1adb04ca",
    "LifecycleHookName": "icp-workernode-added-1adb04ca",
    "EC2InstanceId": "i-0bbed286b7fec6d2b",
    "LifecycleTransition": "autoscaling:EC2_INSTANCE_LAUNCHING",
    "NotificationMetadata": "{\n  \"icp_inception_image\": \"registry.jkwong.cloudns.cx/ibmcom/icp-inception:2.1.0.2-rc1-ee\",\n  \"docker_package_location\": \"s3://icp-2-1-0-2-rc1/icp-docker-17.09_x86_64.bin\",\n  \"image_location\": \"\",\n  \"cluster_backup\": \"icpbackup-1adb04ca\"\n}\n"
  }
}
*/


exports.handler = (event, context, callback) => {
    console.log(JSON.stringify(event, null, 2));
    var instanceId = event.detail.EC2InstanceId;

    var scaleOut = true;
    if (typeof event.detail.LifecycleTransition === "undefined" || event.detail.LifecycleTransition === null) {
        /* not interested in this event */
        return;
    }
    
    var promises = [];

    promises.push(common.get_instance_ip(event.region, instanceId));
    promises.push(common.get_bucket_object(process.env.s3_bucket, "ca.crt"));
    promises.push(common.get_bucket_object(process.env.s3_bucket, "lambda-cert.pem"));
    promises.push(common.get_bucket_object(process.env.s3_bucket, "lambda-key.pem"));

    return Promise.all(promises)
    .then(function(result) {
      /* try to create a batch job in kube */
      if (event.detail.LifecycleTransition === "autoscaling:EC2_INSTANCE_TERMINATING") {
        console.log("scaling down node " + result[0].Reservations[0].Instances[0].PrivateIpAddress);
        return create_delete_node_job(result, event);
      }

      if (event.detail.LifecycleTransition === "autoscaling:EC2_INSTANCE_LAUNCHING") {
        console.log("scaling up cluster using node " + result[0].Reservations[0].Instances[0].PrivateIpAddress);

        return create_add_node_job(result, event);
      }
    }).catch(function(err) {
        console.log("Error: " + err, err.stack);
        common.fail_autoscaling(event);
        return {};
    });

    //callback(null, 'Hello from Lambda');
};

function create_add_node_job(params, event) {
  var privateIp = params[0].Reservations[0].Instances[0].PrivateIpAddress;
  //var jobName = 'add-node-' + privateIp.replace(new RegExp(/\./, 'g'), "-") + "-" + uuid.v4().substring(0, 7);
  var metadataStr = unescape(event.detail.NotificationMetadata);
  var metadata = JSON.parse(metadataStr);
  
  var instance_name = metadata.instance_name + "-" + metadata.cluster_id + "-worker-" + event.detail.EC2InstanceId.replace("i-", "");
  var jobName = 'add-node-' + instance_name + "-" + uuid.v4().substring(0, 7);

  job_tmpl.metadata.name = jobName;
  job_tmpl.metadata.labels.run = jobName;
  job_tmpl.metadata.labels.node_ip = privateIp.replace(new RegExp(/\./, 'g'), "-");

  // use installer image
  job_tmpl.spec.template.spec.containers[0].image = metadata.icp_inception_image;
  job_tmpl.spec.template.spec.containers[0].command = [ "/bin/bash", "-c", "/installer/cluster/add_worker.sh" ];
  job_tmpl.spec.template.spec.containers[0].env = [
    {
      name: "LICENSE",
      value: "accept"
    },
    {
      name: "DOCKER_PACKAGE_LOCATION",
      value: metadata.docker_package_location
    },
    {
      name: "IMAGE_LOCATION",
      value: metadata.image_location
    },
    {
      name: "CLUSTER_BACKUP",
      value: metadata.cluster_backup
    },
    {
      name: "NODE_IP",
      value: privateIp
    },
    {
      name: "LIFECYCLEHOOKNAME",
      value: event.detail.LifecycleHookName
    },
    {
      name: "LIFECYCLEACTIONTOKEN",
      value: event.detail.LifecycleActionToken
    },
    {
      name: "ASGNAME",
      value: event.detail.AutoScalingGroupName
    },
    {
      name: "INSTANCEID",
      value: event.detail.EC2InstanceId
    },
    {
      name: "INSTANCE_NAME",
      value: instance_name
    },
    {
      name: "REGION",
      value: event.region
    },
    {
      name: "ANSIBLE_HOST_KEY_CHECKING",
      value: "false"
    }
  ];
  
  job_tmpl.spec.template.spec.containers[0].volumeMounts = [
    {
      mountPath: "/installer/cluster/add_worker.sh",
      name: "autoscaler-config",
      subPath: "add_worker.sh"
    }
  ];
  
  job_tmpl.spec.template.spec.volumes[0].configMap.defaultMode = 493;
  job_tmpl.spec.template.spec.volumes[0].configMap.items[0].key = "add_worker.sh";
  job_tmpl.spec.template.spec.volumes[0].configMap.items[0].path = "add_worker.sh";
  job_tmpl.spec.template.spec.volumes[0].configMap.name = "autoscaler-config";
  job_tmpl.spec.template.spec.volumes[0].name = "autoscaler-config";

  console.log("Sending job: " + JSON.stringify(job_tmpl, 2));
  console.log("certificate is: " + params[1].Body);
  return common.create_job(params[1].Body, params[2].Body, params[3].Body, job_tmpl);
}

function create_delete_node_job(params, event) {
  var privateIp = params[0].Reservations[0].Instances[0].PrivateIpAddress;
  //var jobName = 'delete-node-' + privateIp.replace(new RegExp(/\./, 'g'), "-") + "-" + uuid.v4().substring(0, 7);
  var metadataStr = unescape(event.detail.NotificationMetadata);
  var metadata = JSON.parse(metadataStr);
  
  var instance_name = metadata.instance_name + "-" + metadata.cluster_id + "-worker-" + event.detail.EC2InstanceId.replace("i-", "");
  var jobName = 'delete-node-' + instance_name + "-" + uuid.v4().substring(0, 7);

  job_tmpl.metadata.name = jobName;
  job_tmpl.metadata.labels.run = jobName;
  job_tmpl.metadata.labels.node_ip = privateIp.replace(new RegExp(/\./, 'g'), "-");

  // use installer image
  job_tmpl.spec.template.spec.containers[0].image = metadata.icp_inception_image;
  job_tmpl.spec.template.spec.containers[0].command = [ "/bin/bash", "-c", "/installer/cluster/remove_worker.sh" ];
  job_tmpl.spec.template.spec.containers[0].env = [
    {
      name: "LICENSE",
      value: "accept"
    },
    {
      name: "DOCKER_PACKAGE_LOCATION",
      value: metadata.docker_package_location
    },
    {
      name: "IMAGE_LOCATION",
      value: metadata.image_location
    },
    {
      name: "CLUSTER_BACKUP",
      value: metadata.cluster_backup
    },
    {
      name: "NODE_IP",
      value: privateIp
    },
    {
      name: "LIFECYCLEHOOKNAME",
      value: event.detail.LifecycleHookName
    },
    {
      name: "LIFECYCLEACTIONTOKEN",
      value: event.detail.LifecycleActionToken
    },
    {
      name: "ASGNAME",
      value: event.detail.AutoScalingGroupName
    },
    {
      name: "INSTANCEID",
      value: event.detail.EC2InstanceId
    },
    {
      name: "REGION",
      value: event.region
    }
  ];

  job_tmpl.spec.template.spec.containers[0].volumeMounts = [
    {
      mountPath: "/installer/cluster/remove_worker.sh",
      name: "autoscaler-config",
      subPath: "remove_worker.sh"
    }
  ];
  
  job_tmpl.spec.template.spec.volumes[0].configMap.defaultMode = 493;
  job_tmpl.spec.template.spec.volumes[0].configMap.items[0].key = "remove_worker.sh";
  job_tmpl.spec.template.spec.volumes[0].configMap.items[0].path = "remove_worker.sh";
  job_tmpl.spec.template.spec.volumes[0].configMap.name = "autoscaler-config";
  job_tmpl.spec.template.spec.volumes[0].name = "autoscaler-config";

  console.log("Sending job: " + JSON.stringify(job_tmpl, 2));
  return common.create_job(params[1].Body, params[2].Body, params[3].Body, job_tmpl);
}

process.on('unhandledRejection', function(error) {
  console.log('Warning: unhandled promise rejection: ', error);
});
/*
var sample_event = {
      "version": "0",
      "id": "c7db91cf-5f64-9509-f033-edff7be73fe1",
      "detail-type": "EC2 Instance-launch Lifecycle Action",
      "source": "aws.autoscaling",
      "account": "299743145002",
      "time": "2018-03-26T19:44:20Z",
      "region": "us-east-2",
      "resources": [
          "arn:aws:autoscaling:us-east-2:299743145002:autoScalingGroup:a9b4e299-d7f3-415e-a750-756e5fd1a3ed:autoScalingGroupName/icp-worker-asg-88e38aae"
      ],
      "detail": {
          "LifecycleActionToken": "82e2f702-919d-4c70-927d-95b410d32d42",
          "AutoScalingGroupName": "icp-worker-asg-88e38aae",
          "LifecycleHookName": "icp-workernode-added-88e38aae",
          "EC2InstanceId": "i-01c8a9d439053b395",
          "LifecycleTransition": "autoscaling:EC2_INSTANCE_LAUNCHING",
          "NotificationMetadata": "{\n  \"icp_inception_image\": \"ibmcom/icp-inception:2.1.0.2-ee\",\n  \"docker_package_location\": \"s3://icp-2-1-0-2-rc1/icp-docker-17.09_x86_64.bin\",\n  \"image_location\": \"\",\n  \"cluster_backup\": \"icpbackup-88e38aae\"\n}\n"
      }
};

exports.handler(sample_event, null, function(err, result) {
  if (err) {
    console.log("error: " + error);
  } else {
    console.log("result: " + result);
  }
});
*/

