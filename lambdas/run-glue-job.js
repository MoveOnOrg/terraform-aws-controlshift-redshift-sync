'use strict';

const AWS = require('aws-sdk')
// Set the region
AWS.config.update({region: process.env.AWS_REGION})

const glue = new AWS.Glue()
const jobName = process.env.GLUE_JOB_NAME

exports.handler = async function (event, context) {
  return new Promise((resolve, reject) => {
    glue.startJobRun({ JobName: jobName }, function (error, data) {
      if (error) {
        console.log(error, error.stack)
        reject({
          statusCode: 500,
          body: error
        })
      } else {
        console.log(data)
        resolve({
          statusCode: 200,
          body: data,
        })
      }
    })
  })
}
