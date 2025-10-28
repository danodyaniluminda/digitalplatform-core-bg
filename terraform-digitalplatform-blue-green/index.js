const aws = require('aws-sdk');
const fs = require('fs');
const path = require('path');
const efsMountPath = '/mnt/efs/';
var s3 = new aws.S3({ apiVersion: '2006-03-01', region: process.env.LAMBDA_REGION });

exports.handler = async function(event, context) {
  // console.log('Received event:', JSON.stringify(event, null, 2));
  
  try {
    const bucket = event.Records[0].s3.bucket.name;
    const key = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, ' '));

    const filePath = efsMountPath + key;
    const fileExtension = getFileExtension(filePath);
    
    
    if (fileExtension === '.gz') {
      deleteFile(filePath);
    } else {
      console.log('File does not have a .gz extension.', filePath);
    }

  } catch (error) {
    console.error('Error:', error);
  }
};

function deleteFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      console.log(`File ${filePath} deleted successfully.`);
    } else {
      console.log(`File ${filePath} does not exist.`);
    }
  } catch (error) {
    throw error;
  }
}

function getFileExtension(filePath) {
  return path.extname(filePath);
}