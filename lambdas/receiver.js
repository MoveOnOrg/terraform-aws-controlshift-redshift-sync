'use strict';

const AWS = require('aws-sdk');

// Set the region
AWS.config.update({region: process.env.AWS_REGION});

// Create an SQS service object
const sqs = new AWS.SQS();

function enqueueTask(receivedData, kind) {
  console.log("Processing: " + receivedData.url);

  let messageBody = {};
  messageBody['downloadUrl'] = receivedData.url;
  messageBody['table'] = receivedData.table;

  if (receivedData['s3'] !== undefined) {
    messageBody['s3'] = receivedData['s3'];
  }

  messageBody['kind'] =  kind;

  const jsonMessageBody = JSON.stringify(messageBody)

  const loaderQueueParams = {
    MessageBody: jsonMessageBody,
    QueueUrl: process.env.SQS_QUEUE_URL
  };

  const glueQueueParams = {
    MessageBody: jsonMessageBody,
    QueueUrl: process.env.GLUE_SQS_QUEUE_URL
  };

  console.log('Enqueueing ' + JSON.stringify(messageBody) + ' on ' +  process.env.SQS_QUEUE_URL);

  let loaderResp = sqs.sendMessage(loaderQueueParams).promise();
  let glueResp = sqs.sendMessage(glueQueueParams).promise();

  Promise.all([loaderResp, glueResp]).then(
    function(data) {
      console.log("Success " + data.MessageId);
    },
    function(error) {
      console.log("Error", error);
    }
  );
  return resp
}

function sendResponse(body) {
    let response =  {
        isBase64Encoded: false,
        statusCode: 200,
        headers: {'Content-Type': 'application/json', 'x-controlshift-processed': '1'},
        body: JSON.stringify(body)
    };
    console.log("response: " + JSON.stringify(response));
    return response;
}

// Lambda event Handler
exports.handler = async (event) => {
    let receivedJSON = JSON.parse(event.body);
    console.log('Received event:', receivedJSON);
    if(receivedJSON.type === 'data.full_table_exported'){
      await enqueueTask(receivedJSON.data, 'full');
      return sendResponse({"status": "processed"});
    } else if(receivedJSON.type === 'data.incremental_table_exported'){
      await enqueueTask(receivedJSON.data, 'incremental');
      return sendResponse({"status": "processed"});
    } else {
      return Promise.resolve(sendResponse({"status": "skipped", "payload": receivedJSON}));
    }
};
