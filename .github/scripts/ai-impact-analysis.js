const https = require('https');
const fs = require('fs');

const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;
const CHANGED_FILES = process.env.CHANGED_FILES || '';

  console.log('No Apex files changed. Skipping AI analysis.');
  process.exit(0);
}

function readChangedFiles(fileList) {
  return fileList.split(',')
    .filter(f => f.trim() && fs.existsSync(f.trim()))
    .map(f => {
      const content = fs.readFileSync(f.trim(), 'utf8');
      return 'File: ' + f.trim() + '
' + content;
    }).join('

');
}

const codeContext = readChangedFiles(CHANGED_FILES);

const lines = [
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
  'Org context: Case management org with active assignment rules, Flows for case routing, SLA processes and escalation rules.',
  '',
  'Be specific and concise.'
];

const prompt = lines.join('
');

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
      console.log('
============================================================');
      console.log('   AI IMPACT ANALYSIS - Predictive DevOps (Claude)');
      console.log('============================================================');
      console.log('
Changed files: ' + CHANGED_FILES + '
');
      console.log(analysis);
      console.log('
============================================================');
      const riskMatch = analysis.match(/(HIGH|MEDIUM|LOW)/i);
      const risk = riskMatch ? riskMatch[1].toUpperCase() : 'UNKNOWN';
      console.log('
Risk assessment: ' + risk);
      if (risk === 'HIGH') { console.log('HIGH risk - flagging for manual review'); process.exit(1); }
      else { process.exit(0); }
    } catch(e) { console.error('Parse error:', e.message); process.exit(0); }
  });
});

req.on('error', (e) => { console.error('Request failed:', e.message); process.exit(0); });
req.write(payload);
req.end();
