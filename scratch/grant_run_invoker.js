const fs = require('fs');
const https = require('https');

// 1. firebase-tools.json 읽기
let config;
try {
  config = JSON.parse(fs.readFileSync('C:\\Users\\GEON\\.config\\configstore\\firebase-tools.json', 'utf8'));
} catch (e) {
  const userHome = process.env.USERPROFILE || process.env.HOME;
  try {
    config = JSON.parse(fs.readFileSync(`${userHome}\\.config\\configstore\\firebase-tools.json`, 'utf8'));
  } catch (err) {
    console.error('Failed to read firebase-tools.json:', err);
    process.exit(1);
  }
}

const accessToken = config.tokens?.access_token;
if (!accessToken) {
  console.error('Access token not found in config');
  process.exit(1);
}

// 2. IAM Policy 설정하기
function setIamPolicy(token, serviceName) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({
      policy: {
        bindings: [
          {
            role: 'roles/run.invoker',
            members: ['allUsers']
          }
        ]
      }
    });

    // 전역 Cloud Run API v1 endpoint 경로 사용
    const path = `/v1/projects/releasenote-80bf5/locations/asia-northeast3/services/${serviceName}:setIamPolicy`;

    const req = https.request({
      hostname: 'run.googleapis.com',
      path: path,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(body));
        } else {
          reject(new Error(`Failed to set IAM policy for ${serviceName}: status=${res.statusCode} body=${body}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function main() {
  try {
    console.log('Using cached access token...');
    
    // 모든 서비스 목록 (Cloud Run 서비스 이름은 대소문자 구분하며, Firebase CLI 배포 시 대문자가 모두 소문자로 치환되어 서비스로 등록됩니다.)
    const services = [
      'createtenant',
      'updatetenantstatus',
      'bootstrapplatformadmin',
      'registerdevice',
      'unregisterdevice',
      'releasebotdevice',
      'addtenantmember',
      'removetenantmember',
      'upsertitem',
      'deleteitem',
      'createtenantinvite',
      'accepttenantinvite',
      'listtenantinvites',
      'revoketenantinvite',
      'getbotsnapshot',
      'updatebotsettings',
      'createreservationevent',
      'notifyreservationcreated'
    ];

    for (const service of services) {
      console.log(`Granting run.invoker to allUsers on service: ${service}...`);
      try {
        await setIamPolicy(accessToken, service);
        console.log(`Successfully granted to ${service}`);
      } catch (err) {
        console.error(`Failed for ${service}:`, err.message);
      }
    }
  } catch (err) {
    console.error('Error in main:', err);
  }
}

main();
