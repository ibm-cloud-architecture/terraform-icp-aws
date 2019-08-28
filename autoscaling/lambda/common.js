var aws = require('aws-sdk');
var kubeapi = require('kubernetes-client');
var fs = require('fs');
var region; 
aws.config.update({region: region});
aws.config.setPromisesDependency(Promise);

function get_instance_ip(region, instance_id) {
  var ec2 = new aws.EC2({apiVersion: '2016-11-15'});

  console.log("get_instance_ip: Region: " + region);
  console.log("get_instance_ip: InstanceID: " + instance_id);

  var params = {
    //DryRun: false,
    InstanceIds: [ instance_id ]
  };

  var request = ec2.describeInstances(params);
  
  var promise = request.promise();
  
  // handle promise's fulfilled/rejected states
  promise.then(
    function(data) {
      console.log("get_instance_ip: Instance IP address is: " + data.Reservations[0].Instances[0].PrivateIpAddress);
      console.log("get_instance_ip: " + JSON.stringify(data, null, 2));
      
      //return data.Reservations[0].Instances[0].PrivateIpAddress;
      /* process the data */
    },
    function(err) {
      /* handle the error */
      console.log("get_instance_ip: " + err, err.stack);
      throw err;
    }
  );
  
  return promise;
}

function get_bucket_object(bucketName, key) {
  var s3 = new aws.S3({apiVersion: '2006-03-01'});

  var params = {
    Bucket: bucketName,
    Key: key
  };

  var request = s3.getObject(params);
  
  var promise = request.promise();
  
  // handle promise's fulfilled/rejected states
  promise.then(
    function(data) {
      console.log("get_bucket_object: body is: " + data.Body);
      
      //return data.Reservations[0].Instances[0].PrivateIpAddress;
      /* process the data */
    },
    function(err) {
      /* handle the error */
      console.log("get_bucket_object: " + err, err.stack);
      throw err;
    }
  );
  
  return promise;
}

function create_job(ca_crt, client_cert, client_key, job) {
  var batch = new kubeapi.Batch({
    url: process.env.kube_api_url,
    namespace: process.env.kube_namespace || 'default', // Defaults to 'default'
    ca: ca_crt,
    cert: client_cert,
    key: client_key,
    promises: true
  });

  return batch.namespaces(process.env.kube_namespace).jobs.post({body: job}).then(function(result) {
    console.log("submitted job");
  });
}

function fail_autoscaling(params) {
  const autoscaling = new aws.AutoScaling({apiVersion: '2011-01-01'});

  var autoscaling_params = params.detail;
  autoscaling_params.LifecycleActionResult = 'ABANDON';

  delete autoscaling_params.EC2InstanceId;
  delete autoscaling_params.LifecycleTransition;
  delete autoscaling_params.NotificationMetadata;

  console.log("Sending autoscaling lifecycle params: " + JSON.stringify(autoscaling_params, null, 2));

  return autoscaling.completeLifecycleAction(autoscaling_params).promise()
    .then(function(result) {
        console.log("competed lifecycle action");
    });
}

module.exports.get_instance_ip = get_instance_ip;
module.exports.create_job = create_job;
module.exports.fail_autoscaling = fail_autoscaling;
module.exports.get_bucket_object = get_bucket_object;

