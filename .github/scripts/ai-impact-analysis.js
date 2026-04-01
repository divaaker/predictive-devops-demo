const https = require('https');
const fs = require('fs');

const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;
const SLACK_WEBHOOK = process.env.SLACK_WEBHOOK_URL;
const CHANGED_FILES = process.env.CHANGED_FILES || '';
const REPO = process.env.GITHUB_REPOSITORY || 'unknown/repo';
const COMMIT = process.env.GITHUB_SHA ? process.env.GITHUB_SHA.substring(0, 7) : 'unknown';
const ACTOR = process.env.GITHUB_ACTOR || 'unknown';

if (!CHANGED_FILES) {
  console.log('No Apex files changed. Skipping AI analysis.');
  process.exit(0);
}

function readChangedFiles(fileList) {
  return fileList.split(',')
    .filter(f => f.trim() && fs.existsSync(f.trim()))
    .map(f => {
      const content = fs.readFileSync(f.trim(), 'utf8');
      return 'File: ' + f.trim() + '\n' + content;
    }).join('\n\n');
}

function sendSlack(risk, summary, changedFiles) {
  if (!SLACK_WEBHOOK) { console.log('No Slack webhook configured, skipping.'); return; }

  const color = risk === 'HIGH' ? '#DC2626' : risk === 'MEDIUM' ? '#F59E0B' : '#16A34A';
  const emoji = risk === 'HIGH' ? ':red_circle:' : risk === 'MEDIUM' ? ':yellow_circle:' : ':large_green_circle:';

  const message = {
    attachments: [{
      color: color,
      blocks: [
        {
          type: 'header',
          text: { type: 'plain_text', text: emoji + ' Predictive DevOps — AI Impact Analysis' }
        },
        {
          type: 'section',
          fields: [
          { type: 'mrkdwn', text: '*Repository:*\n' + REPO },
            { type: 'mrkdwn', text: '*Commit:*\n`' + COMMIT + '`' },
            { type: 'mrkdwn', text: '*Pushed by:*\n' + ACTOR },
            { type: 'mrkdwn', text: '*Risk Level:*\n' + emoji + ' *' + risk + '*' }
          ]
        },
        {
          type: 'section',
          text: { type: 'mrkdwn', text: '*Changed files:*\n`' + changedFiles + '`' }
        },
        {
          type: 'section',
          text: { type: 'mrkdwn', text: '*Claude Analysis Summary:*\n' + summary.substring(0, 2800) }
        },
        {
          type: 'context',
          elements: [{
            type: 'mrkdwn',
            text: risk === 'HIGH'
              ? ':warning: *HIGH risk detected — manual review required before deploying*'
              : ':white_check_mark: Risk is ' + risk + ' — review recommended before deploying'
          }]
        }
      ]
    }]
  };

  const payload = JSON.stringify(message);
  const url = new URL(SLACK_WEBHOOK);

  const options = {
    hostname: url.hostname,
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload)
    }
  };

  const req = https.request(options, (res) => {
    console.log('Slack notification sent. Status: ' + res.statusCode);
  });
  req.on('error', (e) => console.error('Slack notification failed:', e.message));
  req.write(payload);
  req.end();
}

const codeContext = readChangedFiles(CHANGED_FILES);

const prompt = [
  'You are a senior Salesforce architect reviewing code changes before deployment.',
  '',
  'Analyze the following changed Apex files and provide:',
  '1. Impacted Components - List Triggers, Flows, Objects, Fields affected',
  '2. Deployment Risks - Specific risks in a Salesforce org',
  '3. Recommended Tests - Test scenarios to validate',
  '4. Risk Level - Score as LOW, MEDIUM, or HIGH with reason',
  '',
  'Changed files:',
  codeContext,
  '',
  'Org context: Salesforce org with active assignment rules, Flows for routing, SLA processes and escalation rules.',
  '',
  'Be specific and concise.'
].join('\n');

const payload = JSON.stringify({
  model: 'claude-sonnet-4-5',
  max_tokens: 1024,
  messages: [{ role: 'user', content: prompt }]
});

const options = {
  hostname: 'api.anthropic.com',
  path: '/v1/messages',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'x-api-key': ANTHROPIC_KEY,
    'anthropic-version': '2023-06-01',
    'Content-Length': Buffer.byteLength(payload)
  }
};

const req = https.request(options, (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    try {
      const json = JSON.parse(data);
      if (json.error) { console.error('Claude API error:', json.error.message); process.exit(0); }
      const analysis = json.content[0].text;

      console.log('\n============================================================');
      console.log('   AI IMPACT ANALYSIS - Predictive DevOps (Claude)');
      console.log('============================================================');
      console.log('\nChanged files: ' + CHANGED_FILES + '\n');
      console.log(analysis);
      console.log('\n============================================================');

      const riskMatch = analysis.match(/risk level[^\n]*(HIGH|MEDIUM|LOW)/i) || analysis.match(/Risk Level[^\n]*(HIGH|MEDIUM|LOW)/i) || analysis.match(/risk level[^\n]*(HIGH|MEDIUM|LOW)/i) || analysis.match(/(HIGH|MEDIUM|LOW)/i);
      const risk = riskMatch ? riskMatch[1].toUpperCase() : 'UNKNOWN';
      console.log('\nRisk assessment: ' + risk);

      sendSlack(risk, analysis, CHANGED_FILES);

      if (risk === 'HIGH') {
        console.log('HIGH risk - flagging for manual review');
        process.exit(1);
      } else {
        process.exit(0);
      }
    } catch(e) { console.error('Parse error:', e.message); process.exit(0); }
  });
});

req.on('error', (e) => { console.error('Request failed:', e.message); process.exit(0); });
req.write(payload);
req.end();
