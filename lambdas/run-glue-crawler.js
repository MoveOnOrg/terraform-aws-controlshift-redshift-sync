'use strict';

const AWS = require('aws-sdk')
// Set the region
AWS.config.update({region: process.env.AWS_REGION})

const glue = new AWS.Glue()
const crawlerName = process.env.GLUE_CRAWLER_NAME

exports.handler = async (event, context) => {
  const { body } = event.Records[0]
  const parsed_body = JSON.parse(body)

  if (parsed_body.table !== 'signatures' || parsed_body.kind !== 'full') {
    const logMessage = `Ignoring notification for table ${parsed_body.table} and kind ${parsed_body.kind}`

    console.log(logMessage)
    return {
      statusCode: 200,
      body: JSON.stringify(logMessage)
    }
  }

  return new Promise((resolve, reject) => {
    glue.startCrawler({ Name: crawlerName }, function (error, data) {
      if (error) {
        console.log(error, error.stack)
        reject({
          statusCode: 500,
          body: error
        })
      } else {
        resolve({
          statusCode: 200,
          body: data,
        })
      }
    })
  })
}
